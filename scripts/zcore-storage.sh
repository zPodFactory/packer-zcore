#!/bin/bash -eux

##
## Debian Storage
## Install Storage utilities
##
## The zCore appliance acts as an NFS server, so the
## nfs-kernel-server package is installed here. Exports are configured
## at first boot by zcore-init.sh.
##
## lvm2 is for zboxapi's /storage endpoints (a new data disk may be set up
## as one VG per disk and grown later). Partitioning uses sfdisk from the
## fdisk package, growing uses growpart from cloud-guest-utils.
##

echo '> Installing Storage utilities...'

apt-get install -y \
  gdu \
  lftp \
  lvm2 \
  nfs-kernel-server

#
# Install cull (disk usage TUI)
# https://github.com/legostin/cull
#
curl -fsSL https://github.com/legostin/cull/releases/latest/download/cull_linux_amd64.tar.gz \
 | tar -xz -C /tmp \
 && install -o root -g root -m 0755 /tmp/cull /usr/local/bin/cull \
 && rm -f /tmp/cull

echo '> Done'
