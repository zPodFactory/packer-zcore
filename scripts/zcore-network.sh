#!/bin/bash -eux

##
## Debian Network
## Install Network utilities
##


echo '> Installing Network utilities...'

apt-get install -y \
  frr \
  gping \
  rsync \
  chrony \
  ipcalc \
  telnet \
  dnsmasq \
  dnsutils \
  tcpdump \
  mtr-tiny \
  wireguard \
  traceroute \
  speedometer \
  bridge-utils \
  netcat-traditional \
  nftables


# Install Doggo fancy DNS Client (json output possible, great with jq)
curl -sS https://raw.githubusercontent.com/mr-karan/doggo/main/install.sh | /bin/sh && chown root:root /usr/local/bin/doggo

#
# Install snitch (a prettier way to inspect network connections)
# https://github.com/karol-broda/snitch
#
curl -sSL https://raw.githubusercontent.com/karol-broda/snitch/master/install.sh | sh

#
# Install witr (Why is this running? )
# https://github.com/pranshuparmar/witr
#
curl -fsSL https://raw.githubusercontent.com/pranshuparmar/witr/main/install.sh | bash


#
# Install ttl (Fast, modern traceroute with real-time TUI)
# https://github.com/lance0/ttl
#
sh -c "$(curl -fsSL https://raw.githubusercontent.com/lance0/ttl/master/install.sh)" <<<'Y' \
&& chown root:root /usr/local/bin/ttl

#
# Install xfr (A modern iperf3 alternative with a live TUI, multi-client server, and QUIC support)
# https://github.com/lance0/xfr
#
curl -fsSL https://github.com/lance0/xfr/releases/latest/download/xfr-x86_64-unknown-linux-musl.tar.gz \
 | tar -xz -C /usr/local/bin xfr \
 && chown root:root /usr/local/bin/xfr

#
# Install surge (fast download manager)
# https://github.com/surge-downloader/surge
#
curl -fsSL -o /dev/null -w "%{url_effective}" -L https://github.com/surge-downloader/Surge/releases/latest \
| sed 's#.*/tag/v##' \
| xargs -I T sh -c 'curl -fsSL https://github.com/surge-downloader/Surge/releases/download/vT/Surge_T_linux_amd64.tar.gz \
  | tar -xzO surge > /usr/local/bin/surge' \
&& chmod 0755 /usr/local/bin/surge

#
# nftables: zBoxAPI's VLAN masquerade feature writes one file under /etc/nftables.d/
# (its own table, one rule per masqueraded VLAN) and loads it live with `nft -f`; the
# service re-loads it at boot so the rules survive a reboot. Nothing is shipped under
# /etc/nftables.d/: an include glob that matches no file is fine for nft, and until the
# first masquerade call there is no table, no NAT hook and no connection tracking, so a
# fresh zCore routes exactly as before. `flush ruleset` at boot is harmless: nothing else
# on zCore defines nftables tables (FRR is disabled, no firewall). The package was
# already on the image through Debian's Priority: important; it is in the apt list
# above so a priority change upstream can never drop it silently.
#
mkdir -p /etc/nftables.d
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.nft"
EOF
chmod 0644 /etc/nftables.conf
nft -c -f /etc/nftables.conf      # syntax check at build time; fails the build if wrong
systemctl enable nftables

# zCore routes between the zPod VLANs; FRR is installed but left disabled
# and enabled on demand by the operator / zBoxAPI.
systemctl disable frr

echo '> Done'
