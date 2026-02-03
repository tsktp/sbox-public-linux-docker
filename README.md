# sbox-public-linux-docker

## Prerequisites

- **Docker** or **Podman** (either works)
- **Git**
- Arch users may need to install `docker-buildx` separately

## Quick Start

```bash
# Clone this repository
git clone https://github.com/tsktp/sbox-public-linux-docker.git
cd sbox-public-linux-docker

# Build the Docker image (first time only, takes 10-15 minutes)
docker build -t sbox-public-builder .

# Compile s&box from source to a directory
./sbox-install.sh compile /path/to/sbox-public
```

## Usage

### Main Commands

```bash
# Compile s&box from source (first run: 10-20 minutes, subsequent: 1-2 minutes)
./sbox-install.sh compile /path/to/sbox-public

# Open a debugging shell in the build environment
./sbox-install.sh shell /path/to/sbox-public

# Rebuild the container image (update dependencies)
./sbox-install.sh update

# Show help
./sbox-install.sh help
```

### Manual Docker Usage

If you prefer to use Docker directly without the helper script:

```bash
# Build the image
docker build -t sbox-public-builder .

# Run interactive shell
docker run -it --rm -v /path/to/sbox-public:/root/sbox sbox-public-builder

# Inside container, run builds manually:
cd /root/sbox
export WINEDEBUG=-all
xvfb-run -a -s "-screen 0 1024x768x24" wine dotnet run --project ./engine/Tools/SboxBuild/SboxBuild.csproj -- build --config Developer
```
