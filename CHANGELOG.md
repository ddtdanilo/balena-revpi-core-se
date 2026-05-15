# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial public scaffold of a balenaOS BSP for the Revolution Pi Core SE family
  (8 / 16 / 32 GB eMMC variants) based on Kunbus' CM4S industrial PLC.
- Overlay files and patches against `balena-os/balena-raspberrypi` (pinned to
  `v6.12.3+rev4`) reproducing the closed upstream PR #1285 with corrections.
- Reproducible bootstrap (`scripts/bootstrap.sh`), build (`scripts/build.sh`),
  and flash (`scripts/flash.sh`) scripts.
- Sento Spec-Driven Development artifacts: `todo/balena-revpi-core-se.md` and
  `docs/spec/balena-revpi-core-se.md`.
- Documentation:
  - `docs/flashing.md` — `rpiboot` procedure for blank CM4S eMMC.
  - `docs/piControl-in-containers.md` — canonical Docker passthrough pattern
    and supervisor LED workaround (`LED_FILE=/dev/null`).
  - `docs/cds-handoff.md` — package for Kunbus to engage Balena Custom Device
    Support (CDS) and land `revpi-core-se` in the balenaCloud catalog.
- Vendored device-type contract under `docs/contracts/revpi-core-se/`.
