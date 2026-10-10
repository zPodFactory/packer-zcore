# Changelog

Notable changes to the zCore appliance, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow the **Debian point
release** the appliance is built on: `13.7` is the zCore built from `zcore-13.7.json`, and its
git tag is `v13.7`. A rebuild of the same Debian release with appliance-only changes may take a
third digit (`v13.7.1`); it still reads `zcore-13.7.json`.

Entries describe what changed for the person deploying the appliance: services, tools added or
removed, first-boot behaviour, OVF properties, disk layout. The commit history has the reasoning.

**Cutting a release.** Changes land under `[Unreleased]` as they are made. When a new Debian
point release is out: create `zcore-X.Y.json` (ISO URL and sha256), build the OVA with
`./build-zcore.sh`, publish it, then `python3 tools/release.py X.Y --push` does the rest:
`[Unreleased]` becomes `[X.Y] — date`, `build-zcore.sh` is pointed at the new var file, the
commit is tagged `vX.Y` and pushed, and the tag publishes this file's section as the GitHub
release note, with the ISO, its checksum and the OVA link above it
(`.github/workflows/release.yml`, `tools/release_notes.py`). The script refuses a dirty tree, an
empty `[Unreleased]` (`--from-commits` fills it from the commits), a version not above the last
tag, a var file that does not exist yet, and any string from the local `.release-denylist`;
`--check` runs the same rules, and CI runs it on every push. Preview a note with
`python3 tools/release_notes.py X.Y`.

## [Unreleased]

### Added
- **nftables enabled, with `/etc/nftables.d/` included from `/etc/nftables.conf`**, so the VLAN
  masquerade feature of zBoxAPI 0.2.0 keeps its rules across reboots. Nothing is shipped in that
  directory: until the first masquerade call there is no table and no NAT hook, and routing is
  untouched. The package was already on the image by Debian default; it is explicit now.
- **zBoxTUI on tty1 is opt-in per deployment** via the `guestinfo.zboxtui` OVF property
  (default `False`), the same mechanism as the zBox appliance. kmscon and
  [zBoxTUI](https://github.com/zPodFactory/zBoxTUI) are baked into the image at build time with
  `/sbin/zcore-zboxtui-setup.sh --install` while every VT stays on stock getty; `True` runs
  `--enable` at first boot (tty1 dashboard, tty2 truecolor shell, no network needed), anything
  else runs `--disable`, which purges kmscon and the zBoxTUI venv to reclaim the space.
- `dnsutils` (`dig`, `nslookup`) next to dnsmasq.
- `lvm2`, for the zboxapi storage endpoints that set up a data disk as one volume group per
  disk and grow it later (partitioning via `sfdisk`, growing via `growpart`).
- **lvm2**, for zBoxAPI's upcoming `/storage` endpoints (a new data disk as one VG per disk,
  grown online later). The installer brings it for the root layout; the storage script keeps it
  explicit. Partitioning and growing use `fdisk` and `cloud-guest-utils`, already in the image.
- Var files for Debian 13.6 and 13.7.
- Releases follow the shared zPodFactory standard: `CHANGELOG.md`, `tools/release.py` (cut,
  `--check`, `--draft`, `--from-commits`), `tools/release_notes.py`, and the `release` and `checks`
  GitHub workflows. The tag is created by the cut, on the workstation, never by a workflow.

### Changed
- Built on **Debian 13.7**.
- **System disk on LVM**, the zBox layout: `/boot` partition, then a volume group `vg` with an
  8 GB `swap` volume and `root` on the rest. First boot grows `root` to the disk size, and
  `zcore-init.sh --extend-disk` repeats that after the virtual disk is enlarged in vSphere.
  The previous single-partition layout could not grow at all, swap sat behind it.
- Kernel is `linux-image-cloud-amd64`, as on zBox (VLAN and NFS server verified).
- Disk controller switched from LSI Logic to **PVSCSI**; the installer kernel already ships
  `vmw_pvscsi`, so the preseed is unchanged.
- **Traefik** `v3.4.3` → `v3.7.13`. Both entry points set `aliasHeadersStrategy: keep`
  explicitly: Traefik ≥ 3.7.12 warns at startup when it is unset, and `delete`, the hardening
  it suggests, would drop zboxapi's `access_token` header (its name carries an underscore).
- **zBoxAPI** is installed with `uv tool install` instead of pipx, matching the zboxapi
  project's own tooling (uv build backend and lockfile). zboxapi `>= 0.1.1` requires
  **Python 3.14**, so it runs on a uv-managed CPython 3.14 (Debian trixie ships 3.13);
  `ZBOXAPI_PYTHON` and `ZBOXAPI_SPEC` in `scripts/zcore-api.sh` override the interpreter
  and the version. `uv` stays in the image for `uv tool upgrade zboxapi`.
- Nerd Fonts `3.3.0` → `3.5.1` for the kmscon console; catppuccin tmux `v2.1.3` → `v2.3.1`.
- The fancy oh-my-posh prompt and `eza` aliases also load on kmscon sessions, not only over SSH.
- kmscon runs with the software renderer (`no-hwaccel`): on the VMware virtual GPU the GL
  renderer fails every glyph upload and floods syslog and the journal with `text_gltex`
  warnings while burning a CPU.
- `zcore-13.5.json` points at the Debian archive, where the 13.5 ISO moved.

### Fixed
- **zboxapi through Traefik answered 403 `Invalid access_token`** on the first builds of this
  version: `aliasHeadersStrategy: delete` silently removed the `access_token` request header (an
  underscore is not a letter, digit or dash). The entry points use `keep`, safe since zboxapi
  never aliases header names.
- **syslog-ng runs at boot.** Debian 13's `syslog-ng-core` package registers only its sysvinit
  script and never enables the systemd unit, so the appliance came up with the unit
  `disabled` and no `/var/log/syslog`. The system script now enables it explicitly.

### Removed
- `btop`, `mise` (its apt repo stays configured, `apt install mise` is one command away),
  `wakey` and `pure-ftpd`, as on zBox 13.7.
- `dstat`: on Debian 13 it is a virtual package provided by **Performance Co-Pilot**, which
  brought twelve `pcp` packages and three always-on daemons (`pmcd`, `pmlogger`, `pmie`) writing
  metric archives to `/var/log/pcp`. Nothing on the appliance used them.

## [13.5] — 2026-06-15

### Added
- **Debian 13.5 (trixie)**: `zcore-13.5.json`.
- First boot moved from `rc.local` to the `zcore-init` systemd unit, which requires
  open-vm-tools and dbus.
- Global shell setup (oh-my-zsh, oh-my-posh, tmux with catppuccin, zoxide, atuin) aligned with
  the zBox appliance.

### Changed
- **Rebranded** from zBox Core Services to **zCore**: scripts, files, services, var files and
  the OVF product metadata. The ESXi builder config is `zcore-builder.json.sample`; the real
  file is git-ignored.
- First-boot script rewritten from Python (`debian-init.py`) to zsh (`zcore-init.sh`): network
  (eth0 management + eth1 zPod VLAN trunk), hostname, dnsmasq, chrony, NFS exports, credentials,
  TLS certificate, Traefik routers and zBoxAPI.
- VMware guest customization through tools is disabled; OVF properties configure the appliance.
- dnsmasq configuration fixes.

### Removed
- Debian 12.5, 12.7 and 12.11 var files.
