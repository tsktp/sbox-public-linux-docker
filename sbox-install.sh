#!/bin/bash

# sbox-tool: Distro-agnostic builder for s&box public
# Based on https://github.com/tsktp/sbox-public-linux-docker

set -e

IMAGE_NAME="sbox-public-builder"
DEFAULT_BUILD_DIR="$HOME/sbox-build"

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

get_dockerfile() {
    cat <<'EOF'
FROM ubuntu:noble

LABEL maintainer="tsktp"

ENV WINEPREFIX=/root/.wine64
ENV WINEARCH=win64
ENV DISPLAY=:0
ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386

RUN apt-get update -qq && \
	apt-get install -qq curl wget git xvfb winbind wine64 wine32:i386 cabextract bzip2 ca-certificates libvulkan1 libvulkan1:i386 && \
	apt-get clean -qq all
	
RUN wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
	chmod +x winetricks && \
	mv winetricks /usr/bin/
	
RUN wget https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.102/dotnet-sdk-10.0.102-win-x64.exe && \
    xvfb-run -a -s "-screen 0 1024x768x24" wine dotnet-sdk-10.0.102-win-x64.exe /install /quiet; \
    wineserver -w && \
    rm dotnet-sdk-10.0.102-win-x64.exe

RUN wget https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.102/dotnet-sdk-10.0.102-win-x86.exe && \
    xvfb-run -a -s "-screen 0 1024x768x24" wine dotnet-sdk-10.0.102-win-x86.exe /install /quiet; \
    wineserver -w && \
    rm dotnet-sdk-10.0.102-win-x86.exe
	
RUN wget --no-check-certificate https://symantec.tbs-certificats.com/vsign-universal-root.crt && \
	mkdir -p /usr/local/share/ca-certificates/extra && \
	cp vsign-universal-root.crt /usr/local/share/ca-certificates/extra/vsign-universal-root.crt && \
	update-ca-certificates && \
	rm vsign-universal-root.crt

RUN xvfb-run -a -s "-screen 0 1024x768x24" winetricks -q powershell cmake mingw 7zip cabinet; \
    wineserver -w

RUN xvfb-run -a -s "-screen 0 1024x768x24" winetricks -q d3dxof dxdiag dxvk dxvk_async dxvk_nvapi; \
    wineserver -w

RUN wget https://github.com/git-for-windows/git/releases/download/v2.52.0.windows.1/Git-2.52.0-64-bit.tar.bz2 && \
	mkdir -p /root/.wine64/drive_c/Git && \
	tar xjvf Git-2.52.0-64-bit.tar.bz2 -C /root/.wine64/drive_c/Git && \
	rm Git-2.52.0-64-bit.tar.bz2 && \
	mkdir -p /root/.wine64/drive_c/MinGW/bin && \
	ln -s /root/.wine64/drive_c/Git/bin/git.exe /root/.wine64/drive_c/MinGW/bin/git.exe

# Configure git to trust the mounted repository
RUN /root/.wine64/drive_c/Git/bin/git.exe config --global --add safe.directory '*'
RUN /root/.wine64/drive_c/Git/bin/git.exe config --global --add safe.directory 'Z:/root/sbox'

WORKDIR /root/sbox

# Set the working directory and use bash as default
CMD ["/bin/bash"]
EOF
}

ENGINE=$(detect_engine)
if [ -z "$ENGINE" ]; then
    echo "Error: Neither docker nor podman found."
    exit 1
fi

COMMAND=$1
shift || true

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

# Configure git to trust the repository (fix ownership issues in wine)
echo "Configuring git safe directories..."
if [ -f /root/.wine64/drive_c/Git/bin/git.exe ]; then
    /root/.wine64/drive_c/Git/bin/git.exe config --global --add safe.directory '*' 2>/dev/null || true
    /root/.wine64/drive_c/Git/bin/git.exe config --global --add safe.directory 'Z:/root/sbox' 2>/dev/null || true
fi

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
            echo "Building container image (this may take 10-15 minutes)..."
            get_dockerfile | $ENGINE build -t "$IMAGE_NAME" -f - .
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
        get_dockerfile | $ENGINE build --no-cache -t "$IMAGE_NAME" -f - .
        ;;
    help|*)
        show_help
        ;;
esac
