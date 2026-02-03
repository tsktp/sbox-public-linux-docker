FROM ubuntu:noble

LABEL maintainer="sbox-linux-builder"

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

WORKDIR /root/sbox

# Set the working directory and use bash as default
CMD ["/bin/bash"]
