# Specification — `balena-revpi-core-se`

Spec-Driven Development specification for the open-source balenaOS Board
Support Package for the Revolution Pi Core SE family.

| Field | Value |
|---|---|
| Author | Danilo Diaz (`@ddtdanilo`) |
| Status | Draft v0.1 — implementation pending hardware validation |
| Last updated | 2026-05-14 |
| Repository | `github.com/ddtdanilo/balena-revpi-core-se` |
| License | Apache-2.0 |

---

## 1. Objective

Produce a reproducible, publicly maintained balenaOS BSP that builds
flashable images for the **Kunbus Revolution Pi Core SE** (CM4S, 8 / 16 /
32 GB eMMC) with:

- `piControl` kernel module and userspace tools (`piTest`) baked in.
- `PREEMPT_RT` kernel (`linux-kunbus` 6.6.84 + `v6.6.84-rt52-revpi9`).
- Working RTC (PCF85063A), HAT EEPROM, status LEDs, watchdog, and Ethernet.
- Three image flavors: `dev`, `prod`, `flasher`.
- Standalone use (SSH'able image) and **openBalena** compatibility.
- A CDS handoff package suitable for Kunbus to take to Balena Inc.

## 2. Scope

In scope for v0.1.0:

- `MACHINE = "revpi-core-se"` machine config covering all eMMC sizes.
- Overlay files + patches against `balena-os/balena-raspberrypi @ v6.12.3+rev4`.
- Bootstrap, build, and flash scripts wrapping `balena-yocto-scripts`.
- Reference compose for `piControl` in containers.
- SDD artifacts (this spec + execution TODO).
- GitHub Releases of `.img.zip` artifacts (dev / prod / flasher) once validated.

## 3. Out of scope

- `revpi-core-s` and `revpi-core-4` device types (no hardware available to validate; deferred to follow-up releases).
- `revpi-connect-s` and `revpi-connect-4` (already merged upstream).
- balenaCloud catalog integration (paid CDS path; outside this repository).
- A managed openBalena server deployment (a self-hosted fleet is the user's responsibility; we only document compatibility).
- Closed-source proprietary tools (`PiCtory` GUI configurator). Users bake a `config.rsc` into their app or rely on `piControl` defaults.
- Custom HMI / dashboard images.

## 4. Assumptions

- Build host is x86_64 Linux (Ubuntu 22.04 LTS recommended) booted with `systemd.unified_cgroup_hierarchy=0` to satisfy `balena-yocto-scripts`' cgroups v1 requirement.
- Build host has ≥ 16 vCPU, ≥ 32 GB RAM, ≥ 150 GB free disk for `build/`, `sstate-cache/`, and `downloads/`.
- Target device is a Revolution Pi Core SE with a CM4S SoM (article 100366 verified for 16 GB; 8 GB and 32 GB SKUs share the same SoM and PCB).
- Flashing host has `usbboot` (`rpi-rpiboot`) installed (Linux or macOS) plus root/admin access for raw block device writes.
- Network connectivity on the device: standard 10/100 Ethernet on the X1 RJ45 with DHCP available, used for first-boot SSH access in `dev` mode and for application updates in `prod` mode.
- Upstream `balena-os/balena-raspberrypi @ v6.12.3+rev4` is the pin. Subsequent upstream releases are tracked in `CHANGELOG.md` when this repo bumps.

## 5. Requirements

### 5.1 Functional

- F1. `MACHINE = "revpi-core-se"` resolves under `balena-yocto-scripts/build/balena-build.sh`.
- F2. Three image flavors selectable: `dev`, `prod`, `flasher`.
- F3. `dev` image has SSH on TCP/22222, no application required.
- F4. `prod` image has no SSH, no shell access, supervisor-managed only.
- F5. `flasher` image boots from external storage and writes the embedded `prod` image to internal eMMC, then reboots.
- F6. `/dev/piControl0` is present after first boot, owned by `root:picontrol`, mode `0660`.
- F7. `piTest -d` from the host (and from a container with the device mapped) lists at least the base RevPi device entry with zero PiBridge modules attached.
- F8. RTC (PCF85063A) is probed by the kernel; `hwclock -r/-w` round-trips correctly; the supercap holds the clock across a ≥ 30 s power-off (full validation of the ≥ 24 h supercap soak is informational, not a build gate — see § 13).
- F9. The HAT EEPROM article number and MAC are readable (e.g. via `piSerial` or direct I²C read on bus 10, address 0x50).
- F10. Ethernet (`lan95xx` on USB) enumerates, obtains a DHCP lease on X1.
- F11. The BCM2711 internal watchdog is exposed (`/dev/watchdog`) and heartbeated by the supervisor.
- F12. The kernel reports `PREEMPT_RT`: `cat /sys/kernel/realtime` → `1` and `uname -v` contains `PREEMPT_RT`.

### 5.2 Non-functional

- N1. First-boot to SSH-ready under 90 s on a 16 GB eMMC unit.
- N2. `dev` image footprint ≤ 7 GB after first boot (fits 8 GB eMMC with margin for both A/B slots + state partition).
- N3. `cyclictest -l 1000000 -m -n -p99 -i 200` under stress-ng load completes with max latency < 250 µs on a Core SE 16 GB at 25 °C ambient (documented; treated as informational, not a regression gate).

### 5.3 Operational

- O1. Build reproducible from a clean checkout via `./scripts/bootstrap.sh && ./scripts/build.sh dev`.
- O2. Flash reproducible from a clean download via `./scripts/flash.sh dev` with the device in `rpiboot` mode.
- O3. Release artifacts (`.img.zip`) attached to each GitHub Release tag.

## 6. Interfaces

### 6.1 BalenaOS machine

- Slug: `revpi-core-se`.
- Yocto `MACHINE` name: `revpi-core-se`.
- Architecture: `aarch64`.
- Inherits: `conf/machine/include/revpi4.inc` → `conf/machine/raspberrypi4-64.conf` (`MACHINEOVERRIDES =. "raspberrypi4-64:"`).
- Kernel provider: `linux-kunbus`.
- Kernel `defconfig`: `revpi-v8_defconfig`.
- Required kernel device-tree files appended via `KERNEL_DEVICETREE:append`:
  - `overlays/revpi-core.dtbo`
  - `overlays/revpi-core-dt-blob-overlay.dtb`
  - `overlays/revpi-core-se-2022-overlay.dtb`
- Boot partition file mapping: `revpi-core-dt-blob-overlay.dtb:/dt-blob.bin`.

### 6.2 Device contract (vendored)

`docs/contracts/revpi-core-se/contract.json` mirrors `balena-io/contracts`
hardware contract format for the eventual CDS submission. Key fields:

- `slug: "revpi-core-se"`, `arch: "aarch64"`.
- `data.flashProtocol: "RPIBOOT"`.
- `data.media.defaultBoot: "internal"`.
- Connectivity: `[wired]` (no WiFi/BT/cellular).

### 6.3 Filesystem layout on the device

| Path | Purpose |
|---|---|
| `/dev/piControl0` | piControl character device |
| `/dev/i2c-10` | I²C bus carrying RTC + HAT EEPROM |
| `/dev/watchdog` | BCM2711 watchdog |
| `/etc/revpi/config.rsc` | Process-image topology (PiCtory output) |
| `/etc/modules-load.d/picontrol.conf` | Autoloads `piControl` |
| `/sys/firmware/devicetree/base/compatible` | Carries `kunbus,revpi-core-se-2022` |

### 6.4 Container interface (`piControl` passthrough)

Container must:

- Map `/dev/piControl0` via `devices:` (not `--privileged`).
- Add the `picontrol` GID via `group_add:`.
- Mount `/etc/revpi:/etc/revpi:ro` (or just `config.rsc`) if the application reads the topology.
- Not write to the supervisor-owned LED sysfs entries (set `LED_FILE=/dev/null` on the supervisor side if the application controls LEDs through `piControl` directly).

## 7. Data model / payloads

This BSP does not define application-level payloads; it provides the OS
substrate. The only "payload" surfaces are:

- Process image bytes via `read(2)`/`write(2)`/`ioctl(2)` on `/dev/piControl0`. Format defined by `piControl` upstream (`piControl/piControlMain.c` + `piControl.h`).
- HAT EEPROM contents — Kunbus standard format (article, serial, MAC).
- `/etc/revpi/config.rsc` — binary PiCtory output. Treated as opaque by this BSP.

## 8. Edge cases

- **Missing `dt-blob.bin`.** If the boot partition lacks `dt-blob.bin`, GPIOs are mis-routed and `piControl` cannot bind. Recovery: re-flash. Acceptance: build must include `revpi-core-dt-blob-overlay.dtb` mapped to `/dt-blob.bin`.
- **No PiBridge modules attached.** `piControl` must still load and expose the base device. `piTest -d` should succeed and list only the base entry.
- **`config.rsc` topology mismatch.** Writes to non-existent modules silently no-op. Documented in `docs/piControl-in-containers.md`. Acceptance: dev image ships a minimal default `config.rsc` declaring only the base unit.
- **Supervisor grabs `/sys/class/leds/*` entries.** The Balena supervisor takes ownership of LED files for status indication, conflicting with `piControl`-driven A1/A2/A3 LED control. Workaround: set `LED_FILE=/dev/null` on the supervisor (documented). Acceptance: workaround verified in `docs/piControl-in-containers.md`.
- **RTC battery / supercap empty.** On first boot from a fully discharged unit the RTC reads garbage. The supervisor's NTP sync must succeed before any `hwclock -w` runs. Acceptance: documented.
- **eMMC near-full on 8 GB variant.** `IMAGE_ROOTFS_SIZE` is tuned for the 8 GB SKU. Acceptance: `prod` image size < 372 MiB and total slot A + slot B + state partition < 7 GB.
- **Failed `rpiboot`.** Some host USB controllers don't enumerate the CM4S in mass-storage mode reliably. Documented in `docs/flashing.md` with a USB 2.0 hub workaround.
- **Zero-byte eMMC enumeration after `rpiboot`.** Known CM4S bootrom quirk: rpiboot loads but the eMMC controller fails to initialize, exposing a 0-byte (or sub-1 GB) block device. `scripts/flash.sh` detects this and refuses to write; recovery is a power-cycle of the device.
- **Mid-write power loss during `flasher` install.** The flasher image must leave the eMMC in a recoverable state (re-runnable). Acceptance: power-cycle during flashing returns the device to its prior state (still SD-bootable into the flasher).
- **`flash.sh flasher` misuse.** A flasher image is meant to be SD-booted, not eMMC-written. `scripts/flash.sh` refuses this combination and points the user at the SD-card workflow.

## 9. Acceptance criteria

Each item is pass/fail and must be verified on a real Core SE 16 GB unit
before tagging v0.1.0:

1. Clean build from `./scripts/bootstrap.sh && ./scripts/build.sh dev` produces `balena-image-revpi-core-se.balenaos-img` without errors.
2. Flashed `dev` image boots; SSH on TCP/22222 reachable within 90 s of power-on.
3. `uname -r` reports a `linux-kunbus`-tagged kernel (e.g. `6.6.84-rt52-revpi9`); `cat /sys/kernel/realtime` → `1`.
4. `lsmod | grep piControl` shows the module loaded; `ls -l /dev/piControl0` matches `crw-rw---- 1 root picontrol …`.
5. `piTest -d` from the host succeeds with no PiBridge modules attached; lists at least the base device.
6. `dmesg | grep pcf85063` shows successful probe; `hwclock -r` returns a sensible time after `hwclock -w` from NTP; a > 30 s power cycle preserves the clock.
7. The HAT EEPROM article number is readable and matches the unit's printed label.
8. The 10/100 RJ45 obtains a DHCP lease and sustains ≥ 90 Mbit/s `iperf3` throughput in both directions.
9. `wdctl` lists `bcm2835-wdt`; the supervisor is observed to keep it heartbeated.
10. From a non-`--privileged` container with `devices: [/dev/piControl0]` and `group_add: [picontrol]`, `piTest -d` succeeds.
11. `cyclictest -l 1000000 -m -n -p99 -i 200 -h 100` under `stress-ng --cpu 4 --io 2 --vm 2` completes with max latency < 250 µs at 25 °C ambient.
12. `flasher` image written to an SD card boots the device, writes the embedded `prod` image to internal eMMC, and reboots cleanly into balenaOS prod.
13. Final `.img` for `prod` is < 7 GB.

## 10. Validation plan

1. Build all three flavors on the chosen Linux build host. Capture build logs as artifacts.
2. Flash `dev` via `scripts/flash.sh dev` on the Core SE 16 GB unit on the bench.
3. Execute the 13 acceptance items above; record results in this file under § 13 ("Validation Results").
4. If any fail, log GitHub issues with the exact failing acceptance item, dmesg excerpts, and `journalctl -b` output; do not tag the release.
5. Once all items pass on 16 GB hardware, tag `v0.1.0` and publish GitHub Release with `.img.zip` artifacts for the three flavors.
6. (Deferred) Repeat steps 2–5 on an 8 GB and a 32 GB unit when available; otherwise mark those variants as "untested" in `README.md`.

## 11. Rollout plan

- v0.0.x development tags (no published binaries) — scaffold + iterative
  build fixes.
- v0.1.0 — first publicly downloadable images, validated on 16 GB.
- v0.1.x — bug fixes from real-world use.
- v0.2.0 — once 8 GB and 32 GB validated.
- v0.3.0 — pin bump to next `balena-raspberrypi` release.
- (External) Engage Kunbus on the CDS handoff once v0.1.0 is published.

## 12. Observability

- Build: bitbake logs in `upstream/build/tmp/log/cooker/<machine>/`. CI to capture and upload as Action artifacts.
- Runtime: balenaOS standard journald; supervisor logs at `journalctl -u balena.service`.
- piControl: kernel ring buffer (`dmesg | grep -i picontrol`).
- A reference health-check container under `docs/examples/piControl-test/` exits non-zero if `/dev/piControl0` is missing or `piTest -d` fails.

## 13. Validation results

(Empty until v0.1.0 hardware validation.)

## 14. Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | Overlay names in `linux-kunbus` 6.6.84 differ from PR #1285's expectations. | **Validated 2026-05-15:** `revpi-6.6` branch of `RevolutionPi/linux` carries `revpi-core-overlay.dts`, `revpi-core-dt-blob-overlay.dts`, and `revpi-core-se-2022-overlay.dts` (`arch/arm/boot/dts/overlays/`). The `*-overlay.dtb` naming convention used in our machine `.conf` matches the working `revpi-core-3.conf` and `revpi-connect-s.conf` in upstream master. Risk closed; document the validation in `CHANGELOG.md`. |
| R2 | `dt-blob.bin` not required on CM4S (Connect S doesn't ship one). | Build twice, with and without, and validate `piControl` binding both ways. Adjust `BALENA_BOOT_PARTITION_FILES` if not needed. |
| R3 | 8 GB image budget too tight after A/B + state partitions. | Profile actual image size on the 16 GB unit before claiming 8 GB support. Trim `IMAGE_INSTALL` if needed. |
| R4 | Balena supervisor LED conflict more invasive than the documented workaround. | Verify on the bench. Worst case: ship a small systemd unit that nulls `LED_FILE` at boot. |
| R5 | Upstream `balena-raspberrypi` bumps in a breaking way before validation. | Pin to `v6.12.3+rev4` in `scripts/bootstrap.sh`; only bump intentionally. |
| R6 | Closed-source proprietary tools (PiCtory) needed by some users. | Out of scope by design; users baking a `config.rsc` into their app is the documented path. |
| R7 | `rpiboot` unreliability on some USB controllers. | Document USB 2.0 hub workaround; reference Kunbus support article. |

## 15. Open questions

- Q1. Does CM4S Core SE in fact need `dt-blob.bin` (Core 1/3 yes, Connect S no — Core SE empirical)?
- Q2. Is `kunbus,revpi-core-se-2022` the only DT compatible string in the field, or are there units shipping with `kunbus,revpi-core-se` (no year suffix) or with a "2023" / "2024" variant?
- Q3. Does the 8 GB SKU actually exist in production (revolutionpi.com lists 16 / 32 GB)?
- Q4. What's the optimal `IMAGE_ROOTFS_SIZE` for the 8 GB variant, accounting for two slots plus state?
- Q5. License of the device-type SVG icon for the CDS submission — Kunbus-licensed or Sento-drawn clean-room?

## 16. Implementation plan

1. **Scaffold + docs** (this commit).
2. **Overlay + patches** (this commit) — reproduce PR #1285's 5-file diff against `v6.12.3+rev4`.
3. **Bootstrap script** (this commit) — clone, submodule init, copy overlay, apply patches.
4. **Build script** (this commit) — wrap `balena-yocto-scripts/build/balena-build.sh -d revpi-core-se`.
5. **Flash script** (this commit) — wrap `rpiboot` workflow.
6. **Hardware validation** (separate, requires Core SE on bench).
7. **Tag v0.1.0** when § 9 acceptance items all pass.
