# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial public scaffold of a balenaOS BSP for the Revolution Pi Core SE
  family (8 / 16 / 32 GB eMMC variants) based on Kunbus' CM4S industrial PLC.
- Overlay files and patches against `balena-os/balena-raspberrypi` (pinned
  to `v6.12.3+rev4`) reproducing the closed upstream PR #1285 against the
  current upstream layout.
- Reproducible bootstrap (`scripts/bootstrap.sh`), build (`scripts/build.sh`),
  and flash (`scripts/flash.sh`) scripts.
- Sento Spec-Driven Development artifacts: `todo/balena-revpi-core-se.md`
  and `docs/spec/balena-revpi-core-se.md`.
- Documentation:
  - `docs/flashing.md` — `rpiboot` procedure for blank CM4S eMMC, with a
    troubleshooting entry for the known 0-byte enumeration quirk.
  - `docs/piControl-in-containers.md` — canonical Docker passthrough pattern
    and supervisor LED workaround (`LED_FILE=/dev/null`). Explicitly notes
    that name-based `group_add` is balenaOS-specific.
  - `docs/cds-handoff.md` — pre-validation proposal package for Kunbus to
    engage Balena Custom Device Support (CDS).
- Vendored device-type contract under `docs/contracts/revpi-core-se/`.
- Reference `docker-compose.yml` + `Dockerfile` under
  `docs/examples/piControl-test/`.

### Verified (2026-05-15)
- Overlay naming convention (`*-overlay.dtb` for the dt-blob entries, plain
  `.dtbo` for the rest) matches the working `revpi-core-3.conf` and
  `revpi-connect-s.conf` machine configs in upstream master, and the
  matching `*-overlay.dts` source files exist in `RevolutionPi/linux`
  branch `revpi-6.6` (`arch/arm/boot/dts/overlays/`). Risk R1 in the spec
  is closed.
- All three patches `git apply --check` cleanly against
  `balena-os/balena-raspberrypi @ v6.12.3+rev4`.

### Audit follow-ups applied
Independent functionality + stability audit by a senior-Yocto-engineer
reviewer agent flagged several stability and accuracy improvements,
applied in this commit:
- `scripts/bootstrap.sh`: removed `eval "$@"` in favor of array-based
  command invocation; explicit `install` of overlay files instead of
  blanket `rsync`; submodule init now uses full history (no `--depth 1`)
  so `balena-yocto-scripts` version detection works; safer handling of
  partially-removed upstream/ directory; permissive "dirty tree" check
  that allows our own overlay files to pre-exist.
- `scripts/build.sh`: cgroups v1 check is now hard-fail by default,
  overridable via `ALLOW_CGROUPS_V2=1`; `SHARED_DIR` default is
  `${HOME}/.cache/balena-shared` (writable without sudo); macOS detection
  error now suggests EC2 / VM workarounds; full build log tee'd into
  `build-logs/build-<machine>-<flavour>-<UTC>.log`.
- `scripts/flash.sh`: refuses `flasher` mode (with directions for the
  correct SD-card workflow); detects 0-byte / sub-1 GB target after
  `rpiboot` and aborts; wipes partition signatures before `dd` so the host
  kernel doesn't auto-mount mid-write; persistent sudo credential
  refresher; macOS uses `diskutil eject` after sync.
- `docs/spec/balena-revpi-core-se.md`: reconciled F8 (RTC) with the 30 s
  acceptance check in § 9; added "zero-byte eMMC enumeration" and
  "flash.sh flasher misuse" to the edge-case list; closed risk R1.
- `docs/cds-handoff.md`: now explicitly labels itself a pre-validation
  proposal.
- `README.md`: build-time estimate widened from "1 – 4 hours" to
  "4 – 8 hours first clean build, 15 – 45 min warm" and the cgroups v1
  requirement made explicit.

### Notes
- The auditor's P0 finding ("device-tree overlay filenames are wrong, will
  fail Phase 2 build") was investigated and **does not apply**: the
  `*-overlay.dtb` convention used in our machine `.conf` is the same one
  used by `revpi-core-3.conf` and `revpi-connect-s.conf` already in
  upstream master, and the corresponding `*-overlay.dts` sources are
  present in the kunbus kernel. The auditor mistook the Makefile's
  `.dtbo` targets for the only build outputs, but the RPi kernel also
  emits `*-overlay.dtb` from `*-overlay.dts`. See the "Verified" entry
  above.
