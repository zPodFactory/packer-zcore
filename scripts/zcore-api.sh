#!/bin/bash -eux

##
## zBoxAPI setup
## API to configure zCore features + Traefik reverse proxy
##
## The FQDN-dependent configuration (TLS certificate, Traefik dynamic
## routers) is generated at first boot by zcore-init.sh.
##

echo '> Installing zBoxAPI...'

# Install pipx for self-contained, non-system Python packages
apt-get install -y pipx

# Install zboxapi (lands in /root/.local/bin/zboxapi, matching zboxapi.service)
pipx install zboxapi

##
## Install Traefik
##

echo '> Installing Traefik...'

TRAEFIK_VERSION="v3.4.3"
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
