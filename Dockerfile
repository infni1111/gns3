###############################################################################
# Stage 1 — build gns3-web-ui (Angular) from source
###############################################################################
FROM node:18-bullseye AS webui

ARG GNS3_WEBUI_REF=master
WORKDIR /src

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git clone --depth 1 --branch ${GNS3_WEBUI_REF} \
      https://github.com/GNS3/gns3-web-ui.git /src

ENV NODE_OPTIONS=--openssl-legacy-provider

RUN npm ci --legacy-peer-deps || npm install --legacy-peer-deps
RUN npx ng build --configuration=production --output-path=/out \
 || npm run build -- --output-path=/out \
 || npx ng build --prod --output-path=/out

###############################################################################
# Stage 2 — runtime: gns3-server + emulators + nginx
###############################################################################
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates curl wget gnupg \
 && add-apt-repository -y ppa:gns3/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        gns3-server \
        gns3-iou \
        dynamips \
        vpcs \
        ubridge \
        qemu-system-x86 qemu-system-arm qemu-system-mips qemu-system-ppc \
        qemu-utils qemu-kvm ovmf swtpm \
        libvirt-clients \
        iproute2 iptables net-tools bridge-utils ebtables \
        tcpdump iputils-ping telnet socat \
        docker.io fuse-overlayfs \
        supervisor nginx \
        python3 python3-pip \
        unzip p7zip-full xz-utils genisoimage \
        jq less nano procps cpu-checker \
        libc6:i386 libcrypt1:i386 libstdc++6:i386 zlib1g:i386 \
        xauth xterm \
 && setcap cap_net_admin,cap_net_raw=ep /usr/bin/ubridge || true \
 && rm -rf /var/lib/apt/lists/*

COPY --from=webui /out /var/www/gns3-web-ui

COPY gns3_server.conf /etc/gns3/gns3_server.conf
COPY nginx.conf       /etc/nginx/sites-available/default
COPY supervisord.conf /etc/supervisor/conf.d/gns3.conf
COPY daemon.json      /etc/docker/daemon.json
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /data/projects /data/images/IOU /data/images/QEMU \
             /data/images/IOS /data/images/DOCKER /data/configs /data/symbols \
 && useradd -m -u 1000 gns3 || true \
 && chown -R gns3:gns3 /data /etc/gns3

EXPOSE 3080 8080

VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
