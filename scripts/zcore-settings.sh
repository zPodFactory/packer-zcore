#!/bin/bash -eux

##
## Debian Settings
## Misc configuration
##

echo '> zCore Settings...'

echo '> Installing resolvconf...'
apt-get install -y resolvconf-admin
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo ""

echo '> SSH directory'
mkdir -vp $HOME/.ssh

echo '> zCore acts as a Router now'
# Configure via sysctl.d drop-in (Debian may not ship /etc/sysctl.conf by default)
cat > /etc/sysctl.d/99-zcore.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
EOF
# Reload sysctl rules; ignore non-zero to avoid failing the build
sysctl --system || true

echo '> Setup Appliance Banner for /etc/issue & /etc/issue.net'
echo ">>" | tee /etc/issue /etc/issue.net > /dev/null
echo ">> zCore $(cat /etc/debian_version)" | tee -a /etc/issue /etc/issue.net > /dev/null
echo ">>" | tee -a /etc/issue /etc/issue.net > /dev/null
sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config

# Setup zcore-init.service for early first boot initialization.
# zcore-init.sh configures the appliance from OVF properties on first boot
# (network, dnsmasq, chrony, NFS, credentials, Traefik & zBoxAPI).
systemctl daemon-reload
systemctl enable zcore-init.service

echo '> Done'
