# syntax=docker/dockerfile:1
# Follow melle2/scum-ds' tested SCUM Wine runtime. Its image contains a
# build-time initialized /home/scum/.wine prefix with vcrun2017,
# d3dcompiler_47 and native crypt32. DepotDownloader remains the ONLY game
# downloader in this project; inherited SteamCMD is never invoked.
FROM --platform=linux/amd64 melle2/scum-dedicated-server:latest

LABEL org.opencontainers.image.title="SCUM Dedicated Server"
LABEL org.opencontainers.image.description="SCUM server using the melle2 Wine prefix and DepotDownloader"
LABEL org.opencontainers.image.source="https://github.com/melle2/scum-ds"

ARG DEPOT_DOWNLOADER_VERSION=3.4.0

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    DOTNET_ROOT=/usr/share/dotnet \
    PATH=/usr/share/dotnet:/depotdownloader:${PATH} \
    WINEARCH=win64 \
    WINEDEBUG=fixme-all,err+all \
    WINEPREFIX=/home/scum/.wine \
    XDG_RUNTIME_DIR=/tmp/runtime-scum

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip gosu tini python3 procps psmisc \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && chmod +x /tmp/dotnet-install.sh \
 && /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet \
 && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
 && rm -f /tmp/dotnet-install.sh

RUN curl -fsSL --retry 3 \
      "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" \
      -o /tmp/depotdownloader.zip \
 && mkdir -p /depotdownloader \
 && unzip -q /tmp/depotdownloader.zip -d /depotdownloader \
 && chmod +x /depotdownloader/DepotDownloader \
 && rm -f /tmp/depotdownloader.zip \
 && /depotdownloader/DepotDownloader --version

# melle2's initialized prefix belongs to user scum. Keep its name, map it to
# the required host identity, then repair prefix ownership before runtime.
RUN groupmod -o -g 1000 scum \
 && usermod -o -u 1000 -g 1000 -d /home/scum -s /bin/bash scum \
 && mkdir -p /data/server /data/depotdownloader /tmp/runtime-scum \
 && chown -R scum:scum /data /home/scum /tmp/runtime-scum \
 && chmod 700 /tmp/runtime-scum

COPY --chmod=0755 scripts/init.sh scripts/start.sh scripts/functions.sh /opt/scum/scripts/
COPY --chmod=0755 scripts/send-log.py /opt/scum/scripts/send-log.py

WORKDIR /data/server
EXPOSE 7777/udp 7777/tcp 7778/udp 7778/tcp 7779/udp 7779/tcp 27015/udp 27015/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=15m --retries=3 \
  CMD pgrep -f 'SCUMServer.exe' >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/scum/scripts/init.sh"]
