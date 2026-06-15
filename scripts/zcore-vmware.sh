#!/bin/bash -eux

##
## VMware related stuff
## Install VMware related tools
##

echo '> Installing VMware Related/Virtualization packages...'

apt-get install -y \
  cloud-guest-utils \
  open-vm-tools

# Disable VMware guest tools customization of the VM
# The appliance is configured from OVF properties at first boot.
cat >> /etc/vmware-tools/tools.conf << 'EOF'
[deployPkg]
enable-customization=false
EOF


echo '> Done'
