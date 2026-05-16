# balena-revpi-core-se

Open-source **balenaOS Board Support Package (BSP) for the Kunbus
Revolution Pi Core SE** (8 / 16 / 32 GB eMMC variants).

Produces flashable balenaOS images for the CM4S-based industrial PLC, with
`piControl`, `PREEMPT_RT`, and the full Kunbus kernel stack inherited from
upstream's `linux-kunbus` recipe.

> **Status:** scaffolding published. Build and on-device validation pending —
> see [Roadmap](#roadmap) below.

> **Note:** This is an unofficial, community-maintained BSP. The Revolution
> Pi Core SE is **not** currently in the balenaCloud device catalog. See
> [Relationship to upstream Balena](#relationship-to-upstream-balena).

---

## Why this exists

Kunbus' Revolution Pi family is a popular Raspberry Pi-based industrial PLC.
balenaOS supports `revpi-connect-s` and `revpi-connect-4` upstream, but **the
Core SE has no machine entry** in the current
[`balena-os/balena-raspberrypi`](https://github.com/balena-os/balena-raspberrypi)
repository. Two community PRs (`#1272`, `#1285`) attempted to add it and were
closed without merge, in line with Balena's published policy of routing new
hardware through their paid Custom Device Support (CDS) program.

This repository:

1. Reproduces the closed PR diff against the **current** `balena-raspberrypi`
   master, with corrections and full documentation.
2. Produces a flashable image that works **standalone** (without balenaCloud).
3. Bundles a Kunbus → Balena CDS handoff package
   ([`docs/cds-handoff.md`](docs/cds-handoff.md)) so an officially supported
   `revpi-core-se` device type can eventually land in the balenaCloud catalog.

---

## Hardware support matrix

| Variant | SoM | Article (Kunbus) | eMMC | RAM | Validated |
|---------|------|------------------|------|------|-----------|
| Core SE 8 GB | CM4S | (TBD) | 8 GB | 1 GB LPDDR4 | not yet |
| Core SE 16 GB | CM4S | 100366 | 16 GB | 1 GB LPDDR4 | not yet |
| Core SE 32 GB | CM4S | (TBD) | 32 GB | 1 GB LPDDR4 | not yet |

A single `MACHINE = "revpi-core-se"` covers all three; only the image-size
budget changes per variant (smallest, 8 GB, governs the build).

### What's onboard (Core SE family)

- Raspberry Pi **CM4S** (BCM2711, SO-DIMM, eMMC-only, **no WiFi/BT/PCIe**),
  1 GB LPDDR4.
- 24 V DC input (10.8 – 28.8 V), ≤ 10 W.
- 1 × RJ45 Ethernet (USB-attached LAN95xx, **10/100 only**).
- NXP **PCF85063A** RTC @ I²C-0x51, supercap-backed.
- HAT EEPROM (24Cxx) with article number / serial / MAC.
- 3 × bi-color status LEDs (A1 / A2 / A3) driven through `piControl`.
- BCM2711 internal watchdog (`bcm2835_wdt`).
- 2 × USB 2.0 host, 1 × micro-USB OTG (used for `rpiboot` provisioning).
- **No** onboard DIO, RS-485, or Gateway. PiBridge L+R for expansion only.

### What's not on the Core SE (vs. Connect / Connect 4)

- No WiFi, no Bluetooth.
- No cellular modem.
- No onboard digital I/O or RS-485 — those live on `RevPi DIO` / `RevPi RO` /
  `RevPi AIO` PiBridge expansion modules and are managed by `piControl` if
  attached.

---

## Quick start

### 1. Build a balenaOS image (requires x86_64 Linux host)

Yocto needs an x86_64 Linux build host with **cgroups v1**. macOS is not
supported by balena-yocto-scripts. See [Build host](#build-host) below for
options including AWS EC2.

```bash
git clone https://github.com/ddtdanilo/balena-revpi-core-se.git
cd balena-revpi-core-se

# Clone upstream balena-raspberrypi @ v6.12.3+rev4, apply our overlay/patches
./scripts/bootstrap.sh

# Build the development image (dev: SSH on :22222, debug enabled)
./scripts/build.sh dev

# Output: upstream/build/tmp/deploy/images/revpi-core-se/
#   balena-image-revpi-core-se.balenaos-img
```

Build flavors: `dev` (default), `prod`, `flasher`. First clean build on a
modern 16 vCPU x86_64 host with no `sstate-cache` typically takes
**4 – 8 hours**. Warm-cache incremental rebuilds drop to **15 – 45 min**.
Slower hosts (or 8 vCPU) can take significantly longer.

### 2. Flash the Core SE (requires the hardware + a host with `rpiboot`)

```bash
./scripts/flash.sh dev   # walks through rpiboot eMMC mode, writes image, reboots
```

Full procedure in [`docs/flashing.md`](docs/flashing.md).

### 3. First boot

After flashing, the dev image boots to balenaOS:

- SSH: `ssh -p 22222 root@<device-ip>` (host key prompt on first connect)
- Check kernel: `uname -r` → expect `6.6.84-rt52-revpi9` (or current pin) and
  `/sys/kernel/realtime` → `1`
- Check piControl: `ls -l /dev/piControl0` → owned by `root:picontrol`, mode `0660`

---

## Running `piControl` from a container

`/dev/piControl0` can be passed to a container without `--privileged`. See
[`docs/piControl-in-containers.md`](docs/piControl-in-containers.md) for the
canonical compose pattern, the supervisor LED conflict workaround
(`LED_FILE=/dev/null`), and `config.rsc` deployment.

Minimal example:

```yaml
services:
  picontrol-test:
    image: debian:bookworm-slim
    devices:
      - /dev/piControl0:/dev/piControl0
    group_add:
      - picontrol
    volumes:
      - /etc/revpi:/etc/revpi:ro
    command: piTest -d
```

---

## Build host

Yocto needs an x86_64 Linux host (Ubuntu 22.04 recommended), booted with
`systemd.unified_cgroup_hierarchy=0` for cgroups v1. Recommended sizing:

- 16+ vCPU, 32+ GB RAM, 150+ GB free disk (build dir + sstate cache).
- First clean build: 4 – 8 h (modern 16 vCPU x86_64 host). Warm sstate
  incremental rebuilds: 15 – 45 min.
- cgroups v1 required: boot the host kernel with
  `systemd.unified_cgroup_hierarchy=0` (Ubuntu 22.04 LTS supports this).
  `scripts/build.sh` enforces this by default; set `ALLOW_CGROUPS_V2=1`
  in the environment to override the check at your own risk.

Reasonable AWS EC2 spec: `c6i.4xlarge` or `m6i.4xlarge` (Ubuntu 22.04 AMI),
150 GB gp3 EBS. Terminate when done; mount a separate EBS for `sstate-cache`
if you plan to rebuild often.

See [`docs/spec/balena-revpi-core-se.md`](docs/spec/balena-revpi-core-se.md)
§ Build environment for the full recipe.

---

## Relationship to upstream Balena

This BSP is built as a downstream overlay on top of
[`balena-os/balena-raspberrypi`](https://github.com/balena-os/balena-raspberrypi)
pinned to `v6.12.3+rev4`. The license is Apache-2.0 (inherited).

- `revpi-core-se` is **not** in the balenaCloud device catalog. The official
  catalog is curated by Balena Inc., not the community; new device types are
  added through their paid Custom Device Support (CDS) program.
- Images built with this repo flash and run **standalone** (SSH'able dev or
  prod image) and integrate with **openBalena** (self-hosted fleet API).
- Path to balenaCloud catalog inclusion is documented in
  [`docs/cds-handoff.md`](docs/cds-handoff.md) — built so Kunbus or another
  partner can engage Balena CDS with this repo as the technical reference.

### Why we don't submit a PR

`balena-os/balena-raspberrypi` closed prior community device-type
submissions (`#1272`, `#1285`) without merge, in line with Balena's policy
documented at <https://docs.balena.io/reference/os/customer-board-support>.
A working public fork serves users today; CDS is the path to upstream.

---

## Repository layout

```
.
├── README.md
├── LICENSE                       # Apache-2.0 (inherited from upstream)
├── CHANGELOG.md
├── todo/
│   └── balena-revpi-core-se.md   # SDD execution checklist
├── docs/
│   ├── spec/balena-revpi-core-se.md   # SDD specification
│   ├── flashing.md
│   ├── piControl-in-containers.md
│   ├── cds-handoff.md
│   ├── contracts/revpi-core-se/       # Vendored device-type contract
│   └── examples/piControl-test/       # Reference compose + Dockerfile
├── overlay/                      # Drop-in files copied into upstream tree
│   ├── revpi-core-se.coffee
│   └── layers/meta-balena-raspberrypi/conf/machine/revpi-core-se.conf
├── patches/                      # Patches applied on top of upstream
│   ├── 0001-layer-conf-revpi-core-se.patch
│   ├── 0002-local-conf-sample-revpi-core-se.patch
│   └── 0003-image-budgets-revpi-core-se.patch
└── scripts/
    ├── bootstrap.sh              # Clone upstream + apply overlay + patches
    ├── build.sh                  # Run balena-yocto-scripts build
    └── flash.sh                  # rpiboot eMMC flash
```

---

## Roadmap

- [x] Public scaffold + documentation + reproducible overlay/patches
- [x] First clean build of `dev` image on Linux x86_64 host —
      **[`v0.1.0-rc1`](https://github.com/ddtdanilo/balena-revpi-core-se/releases/tag/v0.1.0-rc1)**
      (2026-05-16, 1 h 19 min on AWS EC2 c6i.4xlarge)
- [ ] Flash + on-device validation on Core SE 16 GB (full 13-item acceptance
      checklist in [`docs/spec/balena-revpi-core-se.md`](docs/spec/balena-revpi-core-se.md))
- [ ] Build `prod` and `flasher` flavors
- [ ] First stable release (`v0.1.0`) with `.img.xz` artifacts attached
- [ ] Validate 8 GB and 32 GB eMMC variants
- [ ] Engage Kunbus for the Balena CDS handoff

---

## Contributing

Issues and PRs welcome. Conventions:

- All artifacts in **English**.
- Commits authored solely by the contributor; no AI/co-authored-by tags.
- Follow Sento's Spec-Driven Development for non-trivial changes: update
  `todo/` and `docs/spec/` before implementation.
- Avoid hardcoded secrets, backwards-compat shims for unfinished features,
  and dead code.

---

## License

Apache License 2.0, inherited from
[`balena-os/balena-raspberrypi`](https://github.com/balena-os/balena-raspberrypi).
See [`LICENSE`](LICENSE).

---

## Acknowledgements

- [Kunbus GmbH](https://revolutionpi.com/) for the Revolution Pi hardware,
  the [`linux-kunbus`](https://gitlab.com/revolutionpi/linux) kernel,
  [`piControl`](https://github.com/RevolutionPi/piControl), and the open
  documentation that made this work possible.
- [Balena](https://balena.io/) for `meta-balena`, `balena-raspberrypi`, and
  the open Yocto layers this BSP builds on top of.
- The community contributors on PRs
  [#1272](https://github.com/balena-os/balena-raspberrypi/pull/1272) and
  [#1285](https://github.com/balena-os/balena-raspberrypi/pull/1285) — their
  closed work is the starting point reproduced here.
