# packer-zbox-core-services

[Packer](https://www.packer.io/) build for the **zBox Core Services Appliance** —
a Debian-based OVA that provides the shared infrastructure services for a zPod
environment.

- **OS:** Debian 13.5 "Trixie"
- **Format:** OVF/OVA (built on a remote ESXi host via `vmware-iso`)
- **First-boot config:** driven by VMware OVF properties

## Services

The appliance bundles the core services a zPod relies on:

| Service        | Role                                                                  |
| -------------- | --------------------------------------------------------------------- |
| **dnsmasq**    | DNS resolver + DHCP for the zPod management subnet                    |
| **chrony**     | NTP server (serves time to all zPod subnets / VLANs)                  |
| **NFS**        | `nfs-kernel-server` — exports `/FILER/STORAGE01/*` from a data disk   |
| **Traefik**    | TLS reverse proxy for the dashboard and zBoxAPI                       |
| **zBoxAPI**    | API to manage zPod VLANs (`/zboxapi`)                                 |
| **FRR**        | Routing daemon (installed, disabled — enabled on demand)              |

IP forwarding is enabled, so the appliance also routes between the zPod VLANs.

## Networking

- **eth0** — management interface (static from OVF properties, or DHCP fallback)
- **eth1** — zPod VLAN trunk (MTU 1700 for VXLAN/Geneve):
  - internal non-routed VLANs `10 / 20 / 30` → `172.16.10/20/30.1/24`
  - routed `/26` public subnets on VLANs `64 / 128 / 192`

## Building

Requirements: `packer`, VMware `ovftool`, and a reachable ESXi build host.

1. Set your ESXi build host details in `zbox-builder.json`.
2. Run the build:

   ```sh
   ./build-zbox.sh
   ```

This runs `packer build` against `zbox.json` with the `zbox-13.5.json` version
file, then exports the OVA. The result lands in
`output-zbox-core-services-13.5/zbox-core-services-13.5.ova` (mode `644`).

## Deploying

This should only be used through zPodFactory.

