#!/usr/bin/env bash
# First-boot bootstrap: pulls the Kali Docker image and registers the
# MikroTik CHR + Kali Linux templates through the GNS3 REST API.
# Idempotent — skips anything that is already in place.
set -euo pipefail

log() { printf '[bootstrap %s] %s\n' "$(date +%T)" "$*"; }

# ---- wait for dockerd -------------------------------------------------------
log "waiting for dockerd"
for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then break; fi
    sleep 2
done
docker info >/dev/null 2>&1 || { log "dockerd never came up"; exit 1; }
log "dockerd ready"

# ---- pull Kali image --------------------------------------------------------
if docker image inspect kalilinux/kali-rolling:latest >/dev/null 2>&1; then
    log "kali image already present"
else
    log "pulling kalilinux/kali-rolling"
    docker pull kalilinux/kali-rolling:latest
fi

# ---- wait for gns3-server ---------------------------------------------------
log "waiting for gns3-server on :3080"
for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:3080/v2/version >/dev/null 2>&1; then break; fi
    sleep 2
done
curl -fsS http://127.0.0.1:3080/v2/version >/dev/null 2>&1 \
    || { log "gns3-server never came up"; exit 1; }
log "gns3-server ready"

# ---- register templates (idempotent) ----------------------------------------
has_template() {
    curl -fsS http://127.0.0.1:3080/v2/templates \
      | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null
}

register() {
    local name="$1" payload="$2"
    if has_template "$name"; then
        log "template '$name' already registered"
    else
        log "registering template '$name'"
        curl -fsS -X POST http://127.0.0.1:3080/v2/templates \
             -H 'Content-Type: application/json' \
             -d "$payload" >/dev/null
    fi
}

register "MikroTik CHR 7.22.1" '{
  "name": "MikroTik CHR 7.22.1",
  "template_type": "qemu",
  "compute_id": "local",
  "category": "router",
  "symbol": ":/symbols/router_firewall.svg",
  "platform": "x86_64",
  "qemu_path": "/usr/bin/qemu-system-x86_64",
  "hda_disk_image": "chr-7.22.1.img",
  "hda_disk_interface": "virtio",
  "adapters": 8,
  "adapter_type": "virtio-net-pci",
  "ram": 384,
  "cpus": 1,
  "boot_priority": "c",
  "console_type": "telnet",
  "options": "-nographic",
  "on_close": "power_off",
  "port_name_format": "ether{port1}"
}'

register "Kali Linux" '{
  "name": "Kali Linux",
  "template_type": "docker",
  "compute_id": "local",
  "category": "guest",
  "symbol": ":/symbols/affinity/circle/gray/linux.svg",
  "image": "kalilinux/kali-rolling:latest",
  "adapters": 1,
  "console_type": "telnet",
  "console_resolution": "1024x768",
  "start_command": "",
  "environment": "",
  "usage": "Default shell. Install tools on demand: apt update && apt install -y <tool>"
}'

log "done"
