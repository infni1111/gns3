# GNS3 Server in Docker

A containerised GNS3 server with the browser-based GNS3 Web UI, packaged so a network lab can be started with one `make` or `docker compose` command instead of installing GNS3, QEMU, Dynamips and their dependencies on the host. The image runs `gns3-server`, an nginx front-end for the Web UI, and a nested Docker daemon (for Docker-based GNS3 nodes) under supervisord. An optional second image seeds a MikroTik CHR disk image and registers ready-to-use appliance templates on first boot.

## Features

- **Multi-stage build**: stage 1 compiles [gns3-web-ui](https://github.com/GNS3/gns3-web-ui) (Angular) from source on `node:18`; stage 2 is an `ubuntu:22.04` runtime with `gns3-server` from the official GNS3 PPA.
- **Emulators included**: Dynamips, VPCS, IOU support (`gns3-iou` + i386 libraries), uBridge, and QEMU for x86/ARM/MIPS/PPC with OVMF and swtpm.
- **Single-origin Web UI**: nginx serves the Web UI on port 8080 and reverse-proxies `/v2/` and `/v3/` (including WebSockets) to the server on port 3080, which avoids CORS issues.
- **Docker nodes inside GNS3**: a nested `dockerd` runs with the `fuse-overlayfs` storage driver (`daemon.json`) to work around overlayfs-on-overlayfs.
- **Persistent data**: projects, images, configs and symbols live under a single `/data` volume.
- **KVM when available**: `/dev/kvm` is passed through when present on the host (`enable_kvm = True`, `require_kvm = False`), so QEMU falls back to software emulation otherwise.
- **Optional "full" image** (`Dockerfile.full`): downloads MikroTik CHR 7.22.1 and checks its MD5, copies it into `/data` on first boot without overwriting existing files, pulls `kalilinux/kali-rolling`, and registers the *MikroTik CHR 7.22.1* (QEMU) and *Kali Linux* (Docker) templates through the GNS3 REST API. The bootstrap script is idempotent.

## Architecture

```
                host
  ┌───────────────────────────────────────────────────────┐
  │  :8080 ──► nginx ──► /var/www/gns3-web-ui (static SPA)│
  │               │                                       │
  │               └─ /v2/, /v3/ (HTTP + WS) ─┐            │
  │  :3080 ─────────────────────────────► gns3-server     │
  │                                          │            │
  │                        QEMU / Dynamips / VPCS / IOU   │
  │                        dockerd (fuse-overlayfs)       │
  │                        bootstrap.sh (full image only) │
  │                                                       │
  │  supervisord manages all processes     /data (volume) │
  └───────────────────────────────────────────────────────┘
```

`entrypoint.sh` prepares `/dev/net/tun`, makes `/dev/kvm` accessible, creates the `/data` tree, copies seed content, then hands off to supervisord.

## Tech stack

Docker (multi-stage), Ubuntu 22.04, GNS3 server (PPA) and gns3-web-ui, QEMU/KVM, Dynamips, nginx, supervisord, Bash, `curl` + `jq` against the GNS3 REST API v2.

## Getting started

Requirements: a Linux host (or WSL2) with Docker. The container runs **privileged** because it needs TUN devices, raw networking and a nested Docker daemon.

### With Make

```bash
make build        # docker build -t gns3:latest .
make run          # start container "gns3-server" (adds /dev/kvm automatically if present)
make logs         # follow logs
make shell        # bash inside the container
make ps           # container status
make restart      # stop + run
make stop         # stop and remove the container
make clean        # stop + delete the gns3-data volume
make rebuild      # clean, rebuild without cache, run
```

`IMAGE` and `NAME` can be overridden, e.g. `make run IMAGE=gns3:full NAME=lab`.

### With Docker Compose

```bash
docker compose up -d --build
```

Uncomment the `/dev/kvm` device line in `docker-compose.yml` if the host supports KVM.

### Building the full image

`Dockerfile.full` is built on top of `gns3:latest`, so build the base image first:

```bash
make build
docker build -f Dockerfile.full -t gns3:full .
make run IMAGE=gns3:full
```

### Access

- Web UI: `http://localhost:8080`
- REST API / GNS3 desktop client: `http://localhost:3080` (e.g. `curl http://localhost:3080/v2/version`)

The Web UI version can be pinned with `--build-arg GNS3_WEBUI_REF=<tag>` (default: `master`).

## Project layout

```
Dockerfile          multi-stage build: web UI + runtime
Dockerfile.full     extends gns3:latest with CHR image, extra tools, bootstrap
bootstrap.sh        first-boot: pull Kali image, register templates via REST API
entrypoint.sh       device setup, /data tree, first-boot seeding
supervisord.conf    dockerd, gns3-server, nginx, bootstrap
nginx.conf          static Web UI + reverse proxy to :3080
gns3_server.conf    server paths, KVM and IOU settings
daemon.json         nested dockerd config (fuse-overlayfs, no default bridge)
docker-compose.yml  compose equivalent of `make run`
Makefile            build/run helpers
```

## Known limitations

- **Lab use only**: API authentication is disabled (`auth = False`) and the container is privileged. Do not expose ports 3080/8080 on an untrusted network.
- `supervisord.conf` always declares the `bootstrap` program, but only `Dockerfile.full` copies `bootstrap.sh`. In the base image that program fails once at startup. This is harmless but shows up in the logs.
- Both `make run` and Compose bind-mount the host's `/var/run/docker.sock` while also starting an internal `dockerd` that uses the same socket path. Which daemon GNS3 ends up talking to depends on startup order. Removing one of the two is advisable.
- The Web UI is built from the `master` branch by default, which may not match the PPA server version. Pinning a tag is recommended for reproducible builds.
- IOU images and licences are not included. MikroTik CHR is downloaded from the vendor at build time, subject to its licence.
- No automated tests or CI.
