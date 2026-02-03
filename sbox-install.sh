#!/bin/bash

# sbox-tool: Distro-agnostic builder for s&box public
# Based on https://github.com/tsktp/sbox-public-linux-docker

set -e

IMAGE_NAME="sbox-public-builder"
DEFAULT_BUILD_DIR="$HOME/sbox-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    echo "sbox-tool - Distro-agnostic s&box Linux Builder"
    echo ""
    echo "Usage:"
    echo "  $0 compile [dir]    Compile s&box from source into [dir] (default: $DEFAULT_BUILD_DIR)"
    echo "  $0 update           Update the build environment image"
    echo "  $0 shell [dir]      Open a shell in the build environment for debugging"
    echo "  $0 help             Show this help"
    echo ""
    echo "This tool uses Docker/Podman to create a Windows-like environment (Wine + .NET 10)"
    echo "to compile the s&box engine from the facepunch/sbox-public repository."
    echo ""
    echo "NOTE: The first compile can take 1-3 hours due to wine/dotnet initialization."
    echo "Subsequent compiles will be much faster."
}

detect_engine() {
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
    elif command -v podman >/dev/null 2>&1; then
        echo "podman"
    else
        echo ""
    fi
}

ENGINE=$(detect_engine)
if [ -z "$ENGINE" ]; then
    echo "Error: Neither docker nor podman found."
    exit 1
fi

run_build_step() {
    local step_name="$1"
    local build_args="$2"
    local build_dir="$3"
    local log_file="step_${step_name// /_}.log"
    
    echo ""
    echo "=========================================="
    echo "$step_name"
    echo "=========================================="
    echo "This step may take 30-90 minutes on first run..."
    echo "Build command: wine dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- $build_args"
    echo "Log file: $log_file"
    echo ""
    echo "Starting at $(date)"
    echo "(Press Ctrl+C to cancel, but this will abort the build)"
    echo ""
    
    # Create a script to run inside the container
    local tmp_script=$(mktemp)
    cat > "$tmp_script" <<'SCRIPT'
#!/bin/bash
set -x
cd /root/sbox
export WINEDEBUG=-all
export DISPLAY=:99

# Fix case-sensitive folder issues (merge lowercase 'code' into 'Code')
echo "Checking for case-sensitive folder conflicts..."
if [ -d "/root/sbox/game/addons/menu/code" ] && [ -d "/root/sbox/game/addons/menu/Code" ]; then
    echo "Found both 'code' and 'Code' folders in menu addon. Merging..."
    # Copy contents from lowercase to capitalized, overwriting any duplicates
    cp -rf /root/sbox/game/addons/menu/code/* /root/sbox/game/addons/menu/Code/
    # Verify copy succeeded, then remove lowercase folder
    if [ $? -eq 0 ]; then
        rm -rf /root/sbox/game/addons/menu/code
        echo "Merged 'code' into 'Code' (overwrote duplicates) and removed lowercase folder."
    else
        echo "Warning: Failed to merge folders completely."
    fi
fi

echo "=== Starting build at $(date) ==="
echo "Working directory: $(pwd)"
echo "Command: wine dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- $@"
echo ""
xvfb-run -a -s "-screen 0 1024x768x24" wine dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- "$@" 2>&1
EXIT_CODE=$?

echo ""
echo "Build process exited with code $EXIT_CODE"
echo "Shutting down Wine processes..."

# Kill lingering dotnet/MSBuild processes that prevent wineserver from exiting
wine taskkill /F /IM dotnet.exe 2>/dev/null || true
wine taskkill /F /IM VBCSCompiler.exe 2>/dev/null || true
wine taskkill /F /IM MSBuild.exe 2>/dev/null || true

# Wait a moment for processes to terminate
sleep 2

# Now wait for wineserver with timeout
wineserver -w &
WINEPID=$!
(sleep 60 && kill $WINEPID 2>/dev/null) &
wait $WINEPID 2>/dev/null || echo "Wineserver wait completed or timed out"

echo ""
echo "=== Completed at $(date) with exit code $EXIT_CODE ==="
exit $EXIT_CODE
SCRIPT
    chmod +x "$tmp_script"
    
    # Run the build step with timeout of 3 hours per step
    timeout 10800 $ENGINE run --rm \
        -v "$build_dir:/root/sbox" \
        -v "$tmp_script:/tmp/build_step.sh" \
        -e WINEDEBUG=-all \
        "$IMAGE_NAME" \
        /tmp/build_step.sh $build_args 2>&1 | tee "$log_file"
    
    local exit_code=${PIPESTATUS[0]}
    rm -f "$tmp_script"
    
    echo ""
    echo "Completed at $(date)"
    
    if [ $exit_code -ne 0 ]; then
        if [ $exit_code -eq 124 ]; then
            echo "ERROR: $step_name timed out after 3 hours!"
        else
            echo "ERROR: $step_name failed with exit code $exit_code"
        fi
        echo "Check $log_file for details"
        exit $exit_code
    fi
    
    echo ""
    echo "$step_name completed successfully!"
    echo ""
}

COMMAND=$1
shift || true

case "$COMMAND" in
    compile)
        BUILD_DIR="${1:-$DEFAULT_BUILD_DIR}"
        # Handle ~ expansion properly
        if [[ "$BUILD_DIR" == ~* ]]; then
            BUILD_DIR="${BUILD_DIR/\~/$HOME}"
        fi
        if [ ! -d "$BUILD_DIR" ]; then
            echo "Error: Directory does not exist: $BUILD_DIR"
            echo "Current HOME: $HOME"
            echo "Please provide a full path"
            exit 1
        fi
        BUILD_DIR=$(cd "$BUILD_DIR" && pwd)
        
        echo "Ensuring build environment image exists..."
        if ! $ENGINE image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
            echo "Building container image from Dockerfile (this may take 10-15 minutes)..."
            $ENGINE build -t "$IMAGE_NAME" "$SCRIPT_DIR"
            echo "Image build complete!"
        else
            echo "Using existing container image."
        fi

        echo "Checking source in $BUILD_DIR..."
        if [ ! -d "$BUILD_DIR" ]; then
            echo "Directory does not exist. Cloning from GitHub..."
            mkdir -p "$BUILD_DIR"
            git clone --depth 1 https://github.com/Facepunch/sbox-public.git "$BUILD_DIR"
        else
            echo "Source found at $BUILD_DIR. Proceeding with build..."
        fi

        # Fix case-sensitive folder issues (merge lowercase 'code' into 'Code')
        echo "Checking for case-sensitive folder conflicts..."
        if [ -d "$BUILD_DIR/game/addons/menu/code" ] && [ -d "$BUILD_DIR/game/addons/menu/Code" ]; then
            echo "Found both 'code' and 'Code' folders in menu addon. Merging..."
            # Copy contents from lowercase to capitalized, overwriting any duplicates
            cp -rf "$BUILD_DIR/game/addons/menu/code/"* "$BUILD_DIR/game/addons/menu/Code/"
            # Verify copy succeeded, then remove lowercase folder
            if [ $? -eq 0 ]; then
                rm -rf "$BUILD_DIR/game/addons/menu/code"
                echo "✓ Merged 'code' into 'Code' (overwrote duplicates) and removed lowercase folder."
            else
                echo "Warning: Failed to merge folders completely."
            fi
        fi

        echo ""
        echo "Starting compilation (expect 1-3 hours total on first run)..."
        echo "Logs will be saved to: $(pwd)/step_*.log"
        echo ""
        
        # Run the three build steps
        run_build_step "Step_1_Building_engine" "build --config Developer" "$BUILD_DIR"
        run_build_step "Step_2_Building_shaders" "build-shaders" "$BUILD_DIR"
        run_build_step "Step_3_Building_content" "build-content" "$BUILD_DIR"

        echo ""
        echo "=========================================="
        echo "✓ All compilation steps completed!"
        echo "The compiled engine is available in: $BUILD_DIR/game/bin"
        echo "=========================================="
        ;;
    shell)
        BUILD_DIR="${1:-$DEFAULT_BUILD_DIR}"
        if [[ "$BUILD_DIR" == ~* ]]; then
            BUILD_DIR="${BUILD_DIR/\~/$HOME}"
        fi
        BUILD_DIR=$(cd "$BUILD_DIR" && pwd)
        
        echo "Opening shell in build environment..."
        echo "Source mounted at: /root/sbox"
        $ENGINE run -it --rm \
            -v "$BUILD_DIR:/root/sbox" \
            -e WINEDEBUG=-all \
            "$IMAGE_NAME" \
            /bin/bash
        ;;
    update)
        echo "Updating build environment (rebuilding image)..."
        $ENGINE build --no-cache -t "$IMAGE_NAME" "$SCRIPT_DIR"
        ;;
    help|*)
        show_help
        ;;
esac
