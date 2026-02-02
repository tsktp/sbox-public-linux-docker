# sbox-public-linux-docker
Dockerized s&box linux engine.

## Usage
```
# Build Docker Image
docker build -t tsktp/sbox-public-linux-docker:latest .

# Latest Public Build
docker run tsktp/sbox-public-linux-docker:latest
```

## Steps
```
git clone https://github.com/tsktp/sbox-public-linux-docker.git
cd sbox-public-linux-docker
docker build -t tsktp/sbox-public-linux-docker:latest .
# /host/path is your local path
docker run --mount type=bind,source=/host/path,target=/root/sbox tsktp/sbox-public-linux-docker:latest
```
