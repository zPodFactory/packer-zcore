# zCore — Debian 13 "Trixie" update

Branch: `debian-trixie-wip`

This document describes the migration of the **zCore** appliance
from Debian 12.11 "Bookworm" to Debian 13.5 "Trixie", and the realignment of
its build pipeline with the upstream
[`packer-zbox`](https://github.com/zPodFactory/packer-zbox) reference repository.

---

## 1. Goals

1. Build the appliance on **Debian 13.5 (Trixie)**.
2. Replace the Python first-boot script (`files/debian-init.py`) with a clean
   shell implementation (`files/zcore-init.sh`) — no feature change, just no
   Python runtime dependency.
3. Replace the legacy **`rc.local`** first-boot hook with a proper **systemd
   unit** (`zcore-init.service`), matching `packer-zbox`.
4. Realign the provisioning scripts (packages / APT sources / shell setup)
   with `packer-zbox`, while keeping the Core Services specifics:
   **NFS server, FRR, NTP server, Traefik + zBoxAPI**.

---

## 2. Version bump

| Item            | Before (Bookworm / "zBox Core Services") | After (Trixie / "zCore")            |
| --------------- | ----------------------------------------- | ----------------------------------- |
| Var file        | `zbox-12.11.json`                         | `zcore-13.5.json` *(new)*           |
| Debian release  | 12.11.0                                   | 13.5.0                              |
| Packer template | `zbox.json`                               | `zcore.json`                        |
| `vm_name`       | `zbox-core-services-12.11`                | `zcore-13.5`                        |
| Appliance name  | "zBox Core Services Appliance"            | "zCore Appliance"                   |
| ISO             | `debian-12.11.0-amd64-netinst`            | `debian-13.5.0-amd64-netinst`       |
| Build entry     | `build-zbox.sh`                           | `build-zcore.sh` → uses `zcore-13.5.json` |

The obsolete `zbox-12.*.json` var files (Bookworm builds under the old name)
were removed in this branch.

`zcore-13.5.json` drops the unused `guest_os_type` field (it is not referenced
by `zcore.json`), matching the upstream `packer-zbox` var file.

---

## 3. First-boot init: `debian-init.py` → `zcore-init.sh`

`files/debian-init.py` (Python) is replaced by `files/zcore-init.sh` (zsh), a
**1:1 feature port**. Python added no value here — every function only shelled
out to system commands.

### Trigger change

| Before                                          | After                                       |
| ------------------------------------------------ | -------------------------------------------- |
| `/etc/rc.local` calls `/sbin/debian-init.py`     | `zcore-init.service` runs `/sbin/zcore-init.sh` |
| run-once guard written by `rc.local`             | run-once guard is `/etc/zcore.config` itself   |

`zcore-init.service` is copied to `/etc/systemd/system/` and enabled by
`scripts/zcore-settings.sh`. It is a `oneshot` unit ordered `After=` /
`Requires=` `open-vm-tools.service` + `dbus.socket`, so VMware Tools is
guaranteed available before OVF properties are read.

### Feature parity (kept identical)

| Function                       | Behaviour                                                            |
| ------------------------------- | -------------------------------------------------------------------- |
| `appliance_config_ovf_settings` | Reads `guestinfo.ovfEnv`, parses the **first** `PropertySection`      |
| `appliance_config_network`      | `eth0` static + `eth1` zPod VLANs `.10/.20/.30` & routed `.64/.128/.192` |
| `appliance_config_host`         | `/etc/hosts` + `hostnamectl set-hostname`                            |
| `appliance_config_dnsmasq`      | DNS + DHCP for the zPod management subnet                            |
| `appliance_config_nfs`          | Formats the first extra disk, exports `/FILER/STORAGE01/*`           |
| `appliance_config_credentials`  | root password + SSH public key                                      |
| `appliance_config_certificates` | Self-signed TLS cert for `zcore.<domain>`                             |
| `appliance_config_traefik`      | Generates Traefik dynamic routers, starts Traefik + zBoxAPI          |

The zPod subnet maths previously done with Python `ipaddress` is reproduced in
shell: the mgmt `/24` is split into `/26`s, giving gateways `.65 / .129 / .193`.
A small `prefix_to_netmask()` helper replaces `IPv4Network.netmask`.

### Intentional small improvements

* **DHCP fallback** — if no `guestinfo.ipaddress` is supplied, `eth0` is
  configured for DHCP and the zPod-specific services are skipped (the Python
  version simply crashed). zCore is still expected to be deployed with
  a static IP.
* The OVF parser uses the same robust `awk`/`sed` approach as `packer-zbox`
  instead of `xml.dom.minidom`.
* NFS disk preparation uses `udevadm settle` instead of a fixed `sleep 30`.

### NTP: `ntp` → `chrony`

Debian 13 **removed the `ntp` package**. zCore advertises itself as an NTP
server to the zPod VLAN clients (via the dnsmasq `ntp-server` DHCP option), so
a real serving daemon is required. **`chrony`** was chosen (over `openntpd` /
`ntpsec`) for its solid server-side support:

* `allow all` — serve time to any client (all zPod subnets / VLANs).
* `local stratum 10` — keep serving even with no reachable upstream source.

---

## 4. Provisioning scripts realigned with `packer-zbox`

All `scripts/zcore-*.sh` were brought in line with the upstream `packer-zbox`
versions ("full adoption"), **re-adding only the Core Services extras**.

| Script             | Change                                                                                       |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `zcore-update.sh`    | Unchanged (already identical).                                                                |
| `zcore-apt.sh`       | Codename-based repos; **+ Netbird, Cloudflared, Mise**; **− Microsoft/PowerShell, gierens/eza**. |
| `zcore-system.sh`    | Upstream tool set; **+ `mise`, `ripgrep`**; **− `exa`** (dropped from Trixie, replaced by the `eza` apt package), **− `cloud-init`** (not used by this appliance). |
| `zcore-network.sh`   | Upstream tool set; **− `openntpd`**; **+ `chrony`, `frr`** (FRR installed, left disabled).     |
| `zcore-storage.sh`   | Upstream tool set; **+ `nfs-kernel-server`** (zCore is an NFS server).                 |
| `zcore-settings.sh`  | `sysctl.d` drop-in for routing/IPv6; enables **`zcore-init.service`** instead of `rc.local`.    |
| `zcore-shell.sh`     | Global oh-my-zsh / oh-my-posh / tmux plugins in `/usr/share`, seeded via `/etc/skel`.          |
| `zcore-vmware.sh`    | `cloud-guest-utils` + `open-vm-tools`; **− `govc`** (no longer used).                          |
| `zcore-cleanup.sh`   | Upstream cleanup (kernel/locale purge, log cleanup, free-space zeroing); cloud-init steps dropped. |
| `zcore-api.sh`       | **Kept (zCore only).** Cleaned up: `pipx install zboxapi` + Traefik binary install.    |

### New `files/`

* `files/zcore-init.sh` / `files/zcore-init.service` — first-boot init (see §3).
* `files/zshrc` / `files/tmux.conf` — shell config consumed by the global
  `/etc/skel` setup from `zcore-shell.sh`.

### `zcore.json` provisioner changes

* Copy `zcore-init.service` → `/etc/systemd/system/` and `zcore-init.sh` →
  `/sbin/` (replaces the `debian-init.py` copy).
* `zcore.omp.json` now installs to `/usr/share/poshthemes/` (global), and
  `zshrc` / `tmux.conf` are copied to both `/etc/skel/` and root's home.
* Traefik / zBoxAPI file copies (`zboxapi.conf`, `traefik.service`,
  `zboxapi.service`, `traefik.yml`, `certificates.yml`) are unchanged.

---

## 5. Validation / testing checklist

Static checks already performed:

- [x] `zcore.json` and `zcore-13.5.json` are valid JSON.
- [x] `bash -n` passes on every `scripts/*.sh` and `build-zcore.sh`.
- [x] `zsh -n` passes on `files/zcore-init.sh`.

To validate end-to-end:

1. `./build-zcore.sh` — builds the OVA against an ESXi builder host.
2. Deploy the OVA with OVF properties (see `test-zcore.json` for an example) and
   confirm on first boot:
   - `eth0` static + `eth1.{10,20,30,64,128,192}` VLAN interfaces are up.
   - `dnsmasq`, `chrony`, `nfs-server`, `traefik`, `zboxapi` are `active`.
   - `chronyc clients` shows zPod clients can reach the NTP server.
   - `showmount -e localhost` lists the `/FILER/STORAGE01/*` exports.
   - `https://zcore.<domain>/dashboard` and `/zboxapi` are reachable.
   - `/etc/zcore.config` exists and the script does **not** re-run on reboot.

---

## 6. Known risks / follow-ups

* **`http/preseed.cfg`** was intentionally left untouched. The Debian-Installer
  preseed format is broadly compatible with Trixie, but it should be smoke
  tested; the `mirror/http/hostname http.debian.net` entry is a legacy host and
  may warrant switching to `deb.debian.org`.
* **Third-party APT repos on Trixie** — Docker / HashiCorp / Tailscale are
  pulled by the `trixie` codename. If an upstream has no `trixie` suite yet,
  `apt-get update` may warn or fail; a `bookworm` fallback may be needed
  (this is inherited as-is from `packer-zbox`).
* **No cloud-init.** This appliance is configured exclusively from OVF
  properties by `zcore-init.sh`. The `cloud-init` package and the cloud-init
  cleanup/disable steps present in upstream `packer-zbox` were intentionally
  left out — this keeps feature parity with the former `debian-init.py`.
* The appliance still expects a **second data disk** for NFS storage, attached
  at deploy time — the OS disk is left on the existing partition layout
  (no LVM root-grow logic, unlike `packer-zbox`).

---

## 7. Rebrand: zBox Core Services → zCore

The appliance was also renamed in this branch — the long form "zBox Core
Services Appliance" (which also collided with the standalone `zBox` toolbox
appliance) became simply **zCore**.

### Identity renames applied

| Concern                    | Before                                       | After                                |
| -------------------------- | -------------------------------------------- | ------------------------------------ |
| Repo (suggested)           | `packer-zbox-core-services`                  | `packer-zcore`                       |
| Packer template            | `zbox.json`                                  | `zcore.json`                         |
| Version var file           | `zbox-13.5.json`                             | `zcore-13.5.json`                    |
| Builder config             | `zbox-builder.json`                          | `zcore-builder.json`                 |
| Build script               | `build-zbox.sh`                              | `build-zcore.sh`                     |
| Provisioning scripts       | `scripts/zbox-*.sh`                          | `scripts/zcore-*.sh`                 |
| First-boot script          | `files/zbox-init.sh` → `/sbin/zbox-init.sh`  | `files/zcore-init.sh` → `/sbin/zcore-init.sh` |
| First-boot systemd unit    | `zbox-init.service`                          | `zcore-init.service`                 |
| Run-once marker            | `/etc/zbox.config`                           | `/etc/zcore.config`                  |
| sysctl drop-in             | `/etc/sysctl.d/99-zbox.conf`                 | `/etc/sysctl.d/99-zcore.conf`        |
| TLS cert CN / Traefik host | `zbox.<domain>`                              | `zcore.<domain>`                     |
| Default `hostname` in OVA  | `zbox`                                       | `zcore`                              |
| Preseed install domain     | `zbox.lab`                                   | `zcore.lab`                          |
| Prompt theme file          | `zbox.omp.json`                              | `zcore.omp.json`                     |
| OVF `<Product>`            | "zBox Core Services Appliance"               | "zCore Appliance"                    |
| OVF `<ProductUrl>`         | `.../packer-zbox-core-services`              | `.../packer-zcore`                   |
| `/etc/issue` banner        | `>> zBox <debian-version>`                   | `>> zCore <debian-version>`          |

### Intentionally **not** renamed

* `zBoxAPI` / `zboxapi.service` / `zboxapi.conf` / `/zboxapi` URL prefix /
  `ZBOXAPI_ROOT_PATH` — a **separate product** (the API package). The appliance
  hosts it but doesn't own its name.
* References to **`packer-zbox`** in this doc — that's the sibling upstream
  repo used as the alignment reference, unchanged.
* Generic shell config (`zshrc`, `tmux.conf`), Traefik config files, OVF
  property keys (`guestinfo.*`) — not name-tied.

### Behavioural changes for deployers

* The dashboard and API are now served at **`https://zcore.<domain>/dashboard`**
  and **`https://zcore.<domain>/zboxapi`** (TLS cert CN follows the new name).
* The default hostname baked into the OVA is **`zcore`**; if `guestinfo.hostname`
  is supplied it overrides this as before.
* The obsolete `zbox-12.{5,7,11}.json` var files were removed.
