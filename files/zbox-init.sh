#!/bin/zsh

##
## zBox Core Services - first boot initialization
##
## Configures the appliance from VMware OVF properties on first boot:
##   1. Network        - mgmt interface (eth0) + zPod VLANs (eth1)
##   2. Hostname        - hostname & /etc/hosts
##   3. dnsmasq         - DNS + DHCP for the zPod management subnet
##   4. chrony          - NTP server for the zPod subnets
##   5. NFS             - export any extra data disk as /FILER storage
##   6. Credentials     - root password & SSH public key
##   7. Certificates    - TLS certificate for Traefik / zBoxAPI
##   8. Traefik         - dynamic routers for the dashboard & zBoxAPI
##
## Driven by the zbox-init.service systemd unit. Runs exactly once,
## guarded by the presence of $ZBOX_CONFIG_FILE.
##
## This is a faithful shell rewrite of the former files/debian-init.py.
##

# Path to the temporary OVF environment file
ZBOX_OVFENV_FILE="/tmp/ovfenv.xml"
# Path to the configuration file (also acts as the run-once marker)
ZBOX_CONFIG_FILE="/etc/zbox.config"


log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$message"
    # Append the timestamp and message to the config / marker file
    echo "[$timestamp] $message" >>"$ZBOX_CONFIG_FILE"
}


# Convert a CIDR prefix length (e.g. 24) into a dotted netmask (255.255.255.0)
prefix_to_netmask() {
    local prefix="$1"
    local mask=$(( 0xffffffff ^ ((1 << (32 - prefix)) - 1) ))

    printf "%d.%d.%d.%d" \
        $(( (mask >> 24) & 255 )) \
        $(( (mask >> 16) & 255 )) \
        $(( (mask >> 8) & 255 )) \
        $(( mask & 255 ))
}


# Fetch the OVF properties from the VMware guestinfo environment
appliance_config_ovf_settings() {
    log "Fetching OVF settings..."

    # Save the OVF environment to a file
    vmtoolsd --cmd 'info-get guestinfo.ovfEnv' >"$ZBOX_OVFENV_FILE"

    # Extract only the first PropertySection (direct child of Environment).
    # When deployed inside a vApp the OVF environment contains one
    # PropertySection per VM; the first one belongs to this VM.
    FIRST_PROP_SECTION=$(awk '/<PropertySection>/,/<\/PropertySection>/{print; if(/<\/PropertySection>/) exit}' "$ZBOX_OVFENV_FILE")

    # Parse the OVF properties from the extracted section
    OVF_HOSTNAME=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.hostname" oe:value="\([^"]*\).*/\1/p')
    OVF_DNS=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.dns" oe:value="\([^"]*\).*/\1/p')
    OVF_DOMAIN=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.domain" oe:value="\([^"]*\).*/\1/p')
    OVF_GATEWAY=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.gateway" oe:value="\([^"]*\).*/\1/p')
    OVF_IPADDRESS=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.ipaddress" oe:value="\([^"]*\).*/\1/p')
    OVF_NETPREFIX=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.netprefix" oe:value="\([^"]*\).*/\1/p')
    OVF_PASSWORD=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.password" oe:value="\([^"]*\).*/\1/p')
    OVF_SSHKEY=$(echo "$FIRST_PROP_SECTION" | sed -n 's/.*Property oe:key="guestinfo.sshkey" oe:value="\([^"]*\).*/\1/p')

    # Derive the zPod network values from the management IP address.
    # All zPod subnets are carved out of the /24 the mgmt IP belongs to.
    if [[ -n "$OVF_IPADDRESS" ]]; then
        OVF_ZPODNET=$(echo "$OVF_IPADDRESS" | cut -d. -f1-3)
        OVF_NETMASK=$(prefix_to_netmask "$OVF_NETPREFIX")
        OVF_ZPODSUBNET="${OVF_ZPODNET}.0/${OVF_NETPREFIX}"

        # Reverse DNS zone for the zPod /24
        OVF_REVERSE_ZONE=$(echo "$OVF_ZPODNET" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')

        # Gateways for the 3 routed /26 zPod subnets (.64 / .128 / .192)
        OVF_GW_64="${OVF_ZPODNET}.65"
        OVF_GW_128="${OVF_ZPODNET}.129"
        OVF_GW_192="${OVF_ZPODNET}.193"
    fi

    log "=========================================="
    log "ZBOX CORE SERVICES DEPLOYMENT"
    log "=========================================="
    log "FQDN: $OVF_HOSTNAME.$OVF_DOMAIN"
    log "DNS: $OVF_DNS"
    log "Network: $OVF_IPADDRESS/$OVF_NETPREFIX"
    log "Gateway: $OVF_GATEWAY"
    log "zPod subnet: $OVF_ZPODSUBNET"
    log "=========================================="
}


# Configure /etc/network/interfaces and restart networking
appliance_config_network() {
    log "Configuring network..."

    systemctl stop networking

    if [[ -z "$OVF_IPADDRESS" ]]; then
        # No static IP provided: fall back to DHCP on the mgmt interface
        cat <<EOF >/etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).
# Managed by zbox-init.sh

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary (management) network interface
auto eth0
iface eth0 inet dhcp
EOF
        systemctl start networking
        log "No static IP in OVF properties, eth0 configured for DHCP."
        return
    fi

    # Static management interface + zPod VLANs on the eth1 trunk
    cat <<EOF >/etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).
# Managed by zbox-init.sh

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary (management) network interface
auto eth0
iface eth0 inet static
    address $OVF_IPADDRESS/$OVF_NETPREFIX
    gateway $OVF_GATEWAY
    dns-nameservers $OVF_DNS

# zPod VLAN trunk
auto eth1
iface eth1 inet manual
    mtu 1700

# Internal non-routed zPod VLANs
# - VLAN 10 (172.16.10.1/24)
# - VLAN 20 (172.16.20.1/24)
# - VLAN 30 (172.16.30.1/24)
auto eth1.10
iface eth1.10 inet static
    address 172.16.10.1/24
    mtu 1700

auto eth1.20
iface eth1.20 inet static
    address 172.16.20.1/24
    mtu 1700

auto eth1.30
iface eth1.30 inet static
    address 172.16.30.1/24
    mtu 1700

# zPod 3 x public /26 routed subnets
# Routed through NSX T1 / static routes
auto eth1.64
iface eth1.64 inet static
    address $OVF_GW_64/$OVF_NETPREFIX
    mtu 1700

auto eth1.128
iface eth1.128 inet static
    address $OVF_GW_128/$OVF_NETPREFIX
    mtu 1700

auto eth1.192
iface eth1.192 inet static
    address $OVF_GW_192/$OVF_NETPREFIX
    mtu 1700
EOF

    systemctl start networking
    log "Network configured (management interface + zPod VLANs)."
}


# Configure the hostname and /etc/hosts
appliance_config_host() {
    log "Configuring hostname..."

    if [[ -n "$OVF_HOSTNAME" && -n "$OVF_IPADDRESS" && -n "$OVF_DOMAIN" ]]; then
        # /etc/hosts feeds the dnsmasq expand-hosts directive
        cat <<EOF >/etc/hosts
127.0.0.1       localhost
$OVF_IPADDRESS  $OVF_HOSTNAME.$OVF_DOMAIN    $OVF_HOSTNAME
EOF
        hostnamectl set-hostname "$OVF_HOSTNAME.$OVF_DOMAIN"
        log "Hostname and /etc/hosts configured."
    else
        log "Warning: missing hostname, IP address or domain, skipping host config."
    fi
}


# Configure dnsmasq (DNS + DHCP for the zPod management subnet)
appliance_config_dnsmasq() {
    log "Configuring dnsmasq..."

    cat <<EOF >/etc/dnsmasq.conf
listen-address=127.0.0.1,$OVF_IPADDRESS
interface=lo,eth0
bind-interfaces
expand-hosts
cache-size=10000
domain=$OVF_DOMAIN
local=/$OVF_DOMAIN/
local=/$OVF_REVERSE_ZONE/
server=$OVF_DNS
no-dhcp-interface=lo,eth1,eth2,eth3
dhcp-range=$OVF_ZPODNET.50,$OVF_ZPODNET.60,$OVF_NETMASK,5m
dhcp-option=option:router,$OVF_GATEWAY
dhcp-option=option:ntp-server,$OVF_IPADDRESS
dhcp-option=option:domain-search,$OVF_DOMAIN
EOF

    systemctl enable dnsmasq
    systemctl restart dnsmasq
    log "dnsmasq configured."
}


# Configure chrony as an NTP server for the zPod subnets
appliance_config_chrony() {
    log "Configuring chrony (NTP server)..."

    cat <<EOF >/etc/chrony/chrony.conf
# Managed by zbox-init.sh
pool 0.debian.pool.ntp.org iburst
pool 1.debian.pool.ntp.org iburst
pool 2.debian.pool.ntp.org iburst
pool 3.debian.pool.ntp.org iburst

driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
makestep 1.0 3
rtcsync
leapsectz right/UTC

# Serve time to any client
allow all

# Keep serving time to clients even when no upstream source is reachable
local stratum 10
EOF

    systemctl enable chrony
    systemctl restart chrony
    log "chrony configured."
}


# Configure NFS exports on the first extra (unformatted) data disk
appliance_config_nfs() {
    log "Configuring NFS exports..."

    local disks disk uuid
    # List whole disks, excluding CD-ROM devices (major 11)
    disks=$(lsblk -dn -o NAME -e 11)

    for disk in ${(f)disks}; do
        # Skip disks that already carry a filesystem or partition table
        if blkid "/dev/$disk" >/dev/null 2>&1; then
            continue
        fi

        log "Preparing data disk /dev/$disk for NFS storage..."

        # Create a GPT label with a single partition spanning the disk
        fdisk "/dev/$disk" <<'FDISK'
g
n



w
FDISK

        udevadm settle

        # Format with a pre-generated UUID. Reading the UUID back with
        # lsblk/blkid right after mkfs races with udev and can return an
        # empty value, which would produce a broken /etc/fstab entry.
        uuid=$(cat /proc/sys/kernel/random/uuid)
        mkfs.ext4 -F -U "$uuid" "/dev/${disk}1"
        sync
        udevadm settle

        echo "UUID=$uuid" >>/etc/uuid.storage
        echo "UUID=$uuid /FILER/STORAGE01 ext4 defaults 1 1" >>/etc/fstab

        # Mount now by device path (robust on first boot); the fstab entry
        # above handles mounting by UUID on subsequent boots.
        mkdir -vp /FILER/STORAGE01
        mount "/dev/${disk}1" /FILER/STORAGE01
        mkdir -vp /FILER/STORAGE01/NFS-01
        mkdir -vp /FILER/STORAGE01/NFS-VCD
        mkdir -vp /FILER/STORAGE01/VCF-BACKUPS
        chmod -R 777 /FILER

        cat <<EOF >/etc/exports
/FILER/STORAGE01/NFS-01     $OVF_ZPODSUBNET(rw,no_subtree_check)
/FILER/STORAGE01/NFS-VCD    $OVF_ZPODSUBNET(rw,no_subtree_check,no_root_squash)
EOF

        # RPCMOUNTDOPTS pins mountd to a fixed port; comment it out
        sed -i '/^RPCMOUNTDOPTS.*$/s/^/#/' /etc/default/nfs-kernel-server

        systemctl enable nfs-server
        systemctl restart nfs-server
        log "NFS storage configured on /dev/$disk."

        # Only the first usable data disk is provisioned
        break
    done
}


# Update the root password & SSH public key
appliance_config_credentials() {
    log "Configuring credentials..."

    if [[ -n "$OVF_PASSWORD" ]]; then
        echo "root:$OVF_PASSWORD" | chpasswd
        log "Root password updated."
    else
        log "Warning: no password provided in OVF properties."
    fi

    if [[ -n "$OVF_SSHKEY" ]]; then
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        echo "$OVF_SSHKEY" >>/root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        log "SSH key added to /root/.ssh/authorized_keys."
    else
        log "Warning: no SSH key provided in OVF properties."
    fi
}


# Generate the self-signed TLS certificate used by Traefik / zBoxAPI
appliance_config_certificates() {
    log "Generating TLS certificate for Traefik / zBoxAPI..."

    mkdir -p /etc/traefik/certificates
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
        -keyout /etc/traefik/certificates/cert.key \
        -out /etc/traefik/certificates/cert.crt \
        -subj "/C=US/O=zPodFactory/CN=zbox.$OVF_DOMAIN" \
        -addext "subjectAltName = DNS:zbox.$OVF_DOMAIN"
    log "Certificate generated."
}


# Generate the Traefik dynamic configuration and start Traefik & zBoxAPI
appliance_config_traefik() {
    log "Configuring Traefik & zBoxAPI..."

    # Traefik dashboard / API router
    cat <<EOF >/etc/traefik/dynamic/internal.yml
http:
  routers:
    dashboard-router:
      rule: "Host(\`zbox.$OVF_DOMAIN\`) && PathPrefix(\`/dashboard\`) || PathPrefix(\`/api\`)"
      entryPoints: ["websecure"]
      service: api@internal
      tls: true
EOF

    # zBoxAPI router / service
    cat <<EOF >/etc/traefik/dynamic/zboxapi.yml
http:
  routers:
    zboxapi-router:
      rule: "Host(\`zbox.$OVF_DOMAIN\`) && PathPrefix(\`/zboxapi\`)"
      entryPoints: ["websecure"]
      middlewares:
        - "prefix-api@file"
      service: zboxapi
      tls: true

  services:
    zboxapi:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8000"

  middlewares:
    prefix-api:
      stripPrefix:
        prefixes:
          - "/zboxapi"
        forceSlash: false
EOF

    systemctl daemon-reload
    systemctl enable zboxapi traefik
    systemctl restart zboxapi traefik
    log "Traefik & zBoxAPI configured."
}


# Appliance configuration flow
main() {
    # Run exactly once: the config file is created by the first log() call
    if [[ -f "$ZBOX_CONFIG_FILE" ]]; then
        echo "$ZBOX_CONFIG_FILE exists, zbox-init has already run. Exiting..."
        exit 0
    fi

    appliance_config_ovf_settings
    appliance_config_network
    appliance_config_credentials

    if [[ -n "$OVF_IPADDRESS" ]]; then
        appliance_config_host
        appliance_config_dnsmasq
        appliance_config_chrony
        appliance_config_nfs
        appliance_config_certificates
        appliance_config_traefik
    else
        log "No management IP in OVF properties; skipped DNS/NTP/NFS/Traefik configuration."
    fi

    # Clean up the temporary OVF environment file
    if [[ -f "$ZBOX_OVFENV_FILE" ]]; then
        rm -vf "$ZBOX_OVFENV_FILE"
    fi

    log "zBox Core Services setup complete."
}

main "$@"
