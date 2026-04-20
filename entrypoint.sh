#!/usr/bin/env bash
set -euo pipefail

# /dev/net/tun is required by several emulators.
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 || true
    chmod 0666 /dev/net/tun || true
fi

# Let the gns3 user open /dev/kvm if present.
if [ -e /dev/kvm ]; then
    chmod 0666 /dev/kvm || true
fi

# Ensure the data tree exists — /data is a volume, so this runs every boot.
mkdir -p /data/projects /data/images/{IOU,QEMU,IOS,DOCKER} \
         /data/configs /data/symbols /data/appliances

# First-boot seeding: populate /data from /opt/gns3-seed without overwriting
# anything that already exists (preserves user images/projects across upgrades).
if [ -d /opt/gns3-seed ]; then
    cp -rn /opt/gns3-seed/. /data/ 2>/dev/null || true
fi

chown -R gns3:gns3 /data || true

exec "$@"
