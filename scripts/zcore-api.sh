#!/bin/bash -eux

##
## zBoxAPI setup
## API to configure zCore features + Traefik reverse proxy
##
## The FQDN-dependent configuration (TLS certificate, Traefik dynamic
## routers) is generated at first boot by zcore-init.sh.
##

echo '> Installing zBoxAPI...'

# zboxapi is a uv project (uv_build backend, uv.lock); the appliance installs it the
# same way, as an isolated uv tool. The shim lands in /root/.local/bin/zboxapi, which
# is what zboxapi.service runs, exactly where pipx used to put it.
#
# ZBOXAPI_PYTHON: zboxapi >= 0.1.1 requires Python 3.14; Debian trixie ships 3.13, so uv
# fetches a stripped standalone CPython 3.14 (~36 MB download) and runs zboxapi on it.
# ZBOXAPI_SPEC: the >=0.1.1 floor keeps a stale index from handing back an older release
# (0.1.0 still allowed Python 3.10, 0.0.7 does not even build on 3.14).
ZBOXAPI_PYTHON="${ZBOXAPI_PYTHON:-3.14}"
ZBOXAPI_SPEC="${ZBOXAPI_SPEC:-zboxapi>=0.1.1}"   # or an exact pin: zboxapi==0.1.1

# uv stays in the image (single ~40 MB binary) so the operator can
# `uv tool upgrade zboxapi` later. zcore-system.sh's zBoxTUI install removed its
# own copy, hence the re-install here.
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
fi

uv tool install --python "$ZBOXAPI_PYTHON" "$ZBOXAPI_SPEC"
test -x /root/.local/bin/zboxapi
uv cache clean

##
## Install Traefik
##

echo '> Installing Traefik...'

TRAEFIK_VERSION="v3.7.13"
TRAEFIK_URL="https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz"
INSTALL_DIR="/usr/local/bin"

# Download & install the Traefik binary from a temporary directory
TEMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

curl -fsSL -o "$TEMP_DIR/traefik.tar.gz" "$TRAEFIK_URL"
tar -xzf "$TEMP_DIR/traefik.tar.gz" -C "$TEMP_DIR" traefik
install -o root -g root -m 0755 "$TEMP_DIR/traefik" "$INSTALL_DIR/traefik"

# Prepare the Traefik configuration directories
mkdir -vp /etc/traefik/{certificates,dynamic}

echo '> Done'
