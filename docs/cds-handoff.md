# Balena Custom Device Support (CDS) Handoff Package

This document is a self-contained brief intended for **Kunbus GmbH** and
**Balena Inc.** for engaging Balena's [Custom Device Support
program](https://docs.balena.io/reference/os/customer-board-support/) to
land the **Revolution Pi Core SE** in the official balenaCloud device
catalog.

---

## Why CDS, not a community PR

Balena's published policy refuses self-service device bring-up. Two
community PRs against `balena-os/balena-raspberrypi` adding
`revpi-core-se` were closed without merge:

- [PR #1272](https://github.com/balena-os/balena-raspberrypi/pull/1272) — closed.
- [PR #1285](https://github.com/balena-os/balena-raspberrypi/pull/1285) — closed.

Both proposals carried valid technical content; the closure reason is
process / policy, not technical. CDS is Balena's documented path forward.

---

## What this repository provides (the "Sento reference implementation")

`github.com/ddtdanilo/balena-revpi-core-se` is a public Apache-2.0 fork of
the upstream layout that ships:

- Machine config: `MACHINE = "revpi-core-se"` inheriting `revpi4.inc` (so
  the full RevPi kernel stack — `linux-kunbus` 6.6.84 with
  `v6.6.84-rt52-revpi9`, `piControl 2.3.7`, RT patches, AUFS-on-RT, RevPi
  udev rules — is reused unchanged).
- Device-type `.coffee` contract (slug `revpi-core-se`, `aarch64`,
  `RPIBOOT` flash protocol, `internal` default boot media).
- Image-size budgets tuned for the 8 GB eMMC variant.
- A vendored hardware contract under `docs/contracts/revpi-core-se/` ready
  to drop into [`balena-io/contracts`](https://github.com/balena-io/contracts).
- Hardware validation results (see § Validation below).
- Reproducible build + flash + on-device test scripts.
- Documentation including the canonical `piControl` container pattern.

This means a CDS engagement starts from a working public reference
implementation rather than from scratch.

---

## Diff against current upstream master

Five files, ~61 net additions (smaller than the original PR #1285 because
upstream has since consolidated the per-machine image-budget block):

| File | Add | Del | Status |
|---|---:|---:|---|
| `revpi-core-se.coffee` | 45 | 0 | New |
| `layers/meta-balena-raspberrypi/conf/machine/revpi-core-se.conf` | 11 | 0 | New |
| `layers/meta-balena-raspberrypi/conf/layer.conf` | 1 | 0 | Modified |
| `layers/meta-balena-raspberrypi/conf/samples/local.conf.sample` | 1 | 0 | Modified |
| `layers/meta-balena-raspberrypi/recipes-core/images/balena-image.inc` | 3 | 0 | Modified |

`overlay/` and `patches/` directories in this repo carry the full diff.
The `50-revpi.rules` udev file already covers `kunbus,revpi-core-se-2022`
so no rules changes are required.

---

## Hardware specification

| Item | Value |
|---|---|
| Slug | `revpi-core-se` |
| Architecture | `aarch64` |
| SoM | Raspberry Pi **CM4S** (BCM2711, SO-DIMM, eMMC-only) |
| RAM | 1 GB LPDDR4 |
| eMMC variants | 8 / 16 / 32 GB |
| DT compatible | `kunbus,revpi-core-se-2022` |
| Flash protocol | `rpiboot` (USB device mode, then `dd` to mass-storage) |
| Default boot media | Internal eMMC |
| Power | 24 V DC, 10.8 – 28.8 V, ≤ 10 W |
| Networking | 1 × RJ45 10/100 (USB-attached LAN95xx) |
| Real-time | `PREEMPT_RT` enabled in Kunbus kernel |

What the Core SE does **not** have:

- No WiFi, no Bluetooth.
- No cellular modem.
- No onboard digital I/O or RS-485 (Core SE is the lean SKU — those live
  on PiBridge expansion modules).
- No PCIe (CM4S lacks it).

---

## What CDS engineering work would own

This list defines the boundary between what Sento has done in the public
repo and what Balena would deliver under CDS:

1. **balenaCloud catalog entry.** Merge the hardware contract into
   [`balena-io/contracts`](https://github.com/balena-io/contracts) with
   officially-licensed SVG iconography.
2. **Image hosting.** Build, sign, and serve `revpi-core-se` images from
   `balena.io/os/` so customers can download official releases.
3. **Upstream merge.** Land the 5-file diff in
   `balena-os/balena-raspberrypi` master under Balena's CI gates
   (Versionbot, `tests/autohat`).
4. **Supervisor integration.** Decide whether to ship a default
   `SUPERVISOR_LED_FILE=/dev/null` per-machine override to resolve the
   well-known LED conflict (see `docs/piControl-in-containers.md`).
5. **End-to-end test fixtures.** Add `revpi-core-se` to the
   `tests/autohat` rig if Balena owns a unit, or accept a Kunbus-loaned
   unit hosted at Balena's lab.
6. **Documentation.** Publish a `revpi-core-se/getting-started` page on
   `docs.balena.io` (the `.coffee` contract's `gettingStartedLink` field
   already points at the expected URL).
7. **Release engineering.** Tag and publish initial `v0.1.0` images for
   the new machine through the balenaCloud release pipeline.

---

## Validation results (Sento reference unit)

> Populated when the Sento bench validation (`docs/spec/balena-revpi-core-se.md`
> § 13) is complete. Currently a placeholder.

| Acceptance item | Result | Evidence |
|---|---|---|
| A1. Clean build | pending | |
| A2. SSH < 90 s | pending | |
| A3. `linux-kunbus` RT kernel | pending | |
| A4. `/dev/piControl0` | pending | |
| A5. `piTest -d` host-side | pending | |
| A6. RTC round-trip | pending | |
| A7. HAT EEPROM | pending | |
| A8. Ethernet ≥ 90 Mbit/s | pending | |
| A9. Watchdog | pending | |
| A10. `piTest -d` in non-privileged container | pending | |
| A11. `cyclictest` max < 250 µs | pending | |
| A12. Flasher round-trip | pending | |
| A13. `prod` image < 7 GB | pending | |

Validation hardware: Core SE 16 GB (Kunbus article 100366).

---

## Contacts

| Role | Party | Contact |
|---|---|---|
| Reference implementation owner | Sento Tech Labs (Medellín, CO) | Danilo Diaz — `@ddtdanilo` |
| Hardware vendor | Kunbus GmbH | (to be filled by partner contact) |
| Balena CDS intake | Balena Inc. | <https://balena.io/contact/> |

---

## Suggested next steps for the partner conversation

1. Kunbus confirms the SVG icon and the marketing name ("Revolution Pi
   Core SE") for the device catalog entry.
2. Kunbus engages Balena CDS, referencing this repository as the technical
   starting point.
3. Sento provides validation evidence (§ Validation above) and a working
   demo image for Balena's CDS engineers to reproduce.
4. Balena's CDS team performs items 1 – 7 in § What CDS engineering work
   would own.
5. Public release announced jointly (Kunbus blog + Balena blog +
   ddtdanilo's repo points to the official catalog entry).

---

## License + attribution

This repository is Apache-2.0 (inherited from upstream
`balena-os/balena-raspberrypi`). The diff content reproduces community
work originally submitted in closed PRs #1272 and #1285, with corrections.
Sento's contribution is the public maintenance, documentation, and
hardware validation.
