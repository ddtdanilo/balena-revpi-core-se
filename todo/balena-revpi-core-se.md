# TODO — `balena-revpi-core-se` v0.1.0

Execution checklist for the open-source balenaOS BSP for the Revolution Pi
Core SE family. Companion to
[`docs/spec/balena-revpi-core-se.md`](../docs/spec/balena-revpi-core-se.md).

Mark items as you go. Do **not** check items off optimistically — only when
they have actually been completed and validated.

---

## Phase 0 — Scaffold (in repo, no hardware needed)

- [x] Initialize `ddtdanilo/balena-revpi-core-se` (Apache-2.0).
- [x] Write `README.md` (English), `LICENSE`, `CHANGELOG.md`, `.gitignore`.
- [x] Author Sento SDD spec under `docs/spec/`.
- [x] Author this TODO.
- [x] Write `docs/flashing.md`.
- [x] Write `docs/piControl-in-containers.md`.
- [x] Write `docs/cds-handoff.md`.
- [x] Author `overlay/revpi-core-se.coffee`.
- [x] Author `overlay/layers/meta-balena-raspberrypi/conf/machine/revpi-core-se.conf`.
- [x] Author `patches/0001-layer-conf-revpi-core-se.patch`.
- [x] Author `patches/0002-local-conf-sample-revpi-core-se.patch`.
- [x] Author `patches/0003-image-budgets-revpi-core-se.patch`.
- [x] Vendor `docs/contracts/revpi-core-se/contract.json`.
- [x] Author `docs/examples/piControl-test/` reference compose.
- [x] Author `scripts/bootstrap.sh`.
- [x] Author `scripts/build.sh`.
- [x] Author `scripts/flash.sh`.
- [x] Initial commit (no AI co-author tags).
- [x] Push to `github.com/ddtdanilo/balena-revpi-core-se` (public).

## Phase 1 — Build host setup (Linux x86_64)

- [ ] Provision build host (Ubuntu 22.04 LTS, ≥ 16 vCPU, ≥ 32 GB RAM, ≥ 150 GB disk).
- [ ] Boot kernel with `systemd.unified_cgroup_hierarchy=0` (cgroups v1).
- [ ] Install build deps: `git build-essential chrpath cpio diffstat file gawk lz4 zstd python3 python3-pip python3-pexpect socat texinfo unzip xz-utils wget`.
- [ ] Install `docker` (for `balena-build.sh` containerized driver) or Yocto host deps if going native.
- [ ] Verify host with `./scripts/bootstrap.sh --dry-run`.

## Phase 2 — First build

- [ ] Clone upstream pin via `./scripts/bootstrap.sh` (creates `upstream/` with submodules initialized).
- [ ] Confirm `upstream/balena-yocto-scripts/build/barys --help` runs.
- [ ] Run `./scripts/build.sh dev`. Capture full bitbake log to `build-dev.log`.
- [ ] Resolve any kernel-overlay name drift (R1 in spec); if `revpi-core-se-2022-overlay.dtb` is renamed, update the machine `.conf` accordingly.
- [ ] Confirm output file exists: `upstream/build/tmp/deploy/images/revpi-core-se/balena-image-revpi-core-se.balenaos-img`.
- [ ] Record build time, peak RAM, peak disk in CHANGELOG notes.

## Phase 3 — On-device validation (Core SE 16 GB)

For each item, append the result + brief evidence under
`docs/spec/balena-revpi-core-se.md` § 13 "Validation Results".

- [ ] **A1.** Build succeeds.
- [ ] **A2.** Flashed `dev` image boots; SSH on 22222 reachable within 90 s.
- [ ] **A3.** Kernel: `uname -r` shows `linux-kunbus` tag; `/sys/kernel/realtime` = `1`.
- [ ] **A4.** `/dev/piControl0` present with `root:picontrol` 0660.
- [ ] **A5.** `piTest -d` host-side succeeds with no PiBridge modules.
- [ ] **A6.** RTC `hwclock -r/-w` round-trip; ≥ 30 s power cycle preserves time.
- [ ] **A7.** HAT EEPROM article number readable and matches the unit label.
- [ ] **A8.** RJ45 DHCP + ≥ 90 Mbit/s `iperf3` both directions.
- [ ] **A9.** `wdctl` shows `bcm2835-wdt`; supervisor heartbeats it.
- [ ] **A10.** Container with `devices: [/dev/piControl0]` + `group_add: [picontrol]` runs `piTest -d` without `--privileged`.
- [ ] **A11.** `cyclictest` under stress: max latency < 250 µs at 25 °C.
- [ ] **A12.** `flasher` image writes `prod` to internal eMMC and reboots cleanly.
- [ ] **A13.** `prod` `.img` size < 7 GB.

## Phase 4 — Release

- [ ] Build `prod` and `flasher` flavors.
- [ ] Zip artifacts: `balena-revpi-core-se-{dev,prod,flasher}-v0.1.0.img.zip`.
- [ ] Tag `v0.1.0`.
- [ ] Publish GitHub Release with artifacts + release notes referencing the spec.
- [ ] Update README "Status" badge from "scaffolding" to "validated on Core SE 16 GB" with date.

## Phase 5 — Kunbus / CDS handoff

- [ ] Finalize `docs/cds-handoff.md` with measured numbers from Phase 3.
- [ ] Email Kunbus partner contact with the repo URL and offer Sento as integration partner for the CDS submission.
- [ ] Open a community thread on revolutionpi.com/forum announcing the BSP.
- [ ] (Optional, depending on Kunbus response) Engage Balena CDS jointly with Kunbus.

## Phase 6 — Stretch (deferred)

- [ ] Validate 8 GB eMMC variant.
- [ ] Validate 32 GB eMMC variant.
- [ ] Add `revpi-core-s` and `revpi-core-4` machines (if hardware available).
- [ ] Set up a GitHub Action for automated `barys --shared-downloads --shared-sstate-cache` builds on tag.
