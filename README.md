# sbox-public-linux-docker

## Prerequisites

- **Docker** or **Podman** (either works)
- **Git**
- Arch users may need to install `docker-buildx`

## Quick Start

```bash
# Clone this repository
git clone https://github.com/tsktp/sbox-public-linux-docker.git
cd sbox-public-linux-docker

# Compile sbox-public from folder
./sbox-install.sh compile /path/to/sbox-public
```

## Usage

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
