# packer-zcore

[Packer](https://www.packer.io/) build for the **zCore Appliance** —
a Debian-based OVA that provides the shared infrastructure services for a zPod
environment.

- **OS:** Debian 13.7 "Trixie"
- **Format:** OVF/OVA (built on a remote ESXi host via `vmware-iso`)
- **First-boot config:** driven by VMware OVF properties
- **System disk:** LVM (`/boot` partition, `vg/swap` 8 GB, `vg/root` on the rest); first boot
  grows `root` to the disk, `zcore-init.sh --extend-disk` does it again after a vSphere resize

## Downloads

Latest builds are available here:
- https://cloud.tsugliani.fr/ova/zcore-13.7.ova

What changed in each version: [GitHub releases](https://github.com/zPodFactory/packer-zcore/releases)
(one per Debian point release, `v13.7` is the zCore built on Debian 13.7) or [CHANGELOG.md](CHANGELOG.md).

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

## Console (zBoxTUI)

[zBoxTUI](https://github.com/zPodFactory/zBoxTUI) is baked into the image at build
time but **not wired to any console by default**: every VT boots on the stock
Debian getty. The `guestinfo.zboxtui` OVF property (boolean, default `false`)
decides at first boot:

- `True` → `/sbin/zcore-zboxtui-setup.sh --enable` wires **tty1** to the zBoxTUI
  dashboard (kmscon) and **tty2** to a truecolor kmscon login shell, then switches
  the active VT to tty1.
- anything else → `--disable` purges kmscon and the zBoxTUI venv to reclaim the
  space the build baked in. tty1–tty6 stay on stock getty.

Toggle later on a running appliance with `--enable` / `--disable`. See the
[zBoxTUI INSTALL.md](https://github.com/zPodFactory/zBoxTUI/blob/main/INSTALL.md)
for operator and security notes.

## Networking

- **eth0** — management interface (static from OVF properties, or DHCP fallback)
- **eth1** — zPod VLAN trunk (MTU 1700 for VXLAN/Geneve):
  - internal non-routed VLANs `10 / 20 / 30` → `172.16.10/20/30.1/24`
  - routed `/26` public subnets on VLANs `64 / 128 / 192`

## Building

Requirements: `packer`, VMware `ovftool`, and a reachable ESXi build host.

1. Copy `zcore-builder.json.sample` to `zcore-builder.json` and fill in your
   ESXi build host details. (The real `zcore-builder.json` is `.gitignore`d so
   credentials are never committed.)
2. Run the build:

   ```sh
   ./build-zcore.sh
   ```

This runs `packer build` against `zcore.json` with the `zcore-13.7.json` version
file, then exports the OVA. The result lands in
`output-zcore-13.7/zcore-13.7.ova` (mode `644`).

## Releasing

```sh
python3 tools/release.py 13.8 --push
```

Create `zcore-13.8.json` and build the OVA first. The cut moves `[Unreleased]` in
`CHANGELOG.md` under a `[13.8]` heading, points `build-zcore.sh` at the new var file,
commits, tags `v13.8` and pushes; the tag publishes the section as the GitHub release.
`python3 tools/release.py --check` is what CI runs on every push. See
[tools/README.md](tools/README.md).

## Deploying

This should only be used through zPodFactory.

