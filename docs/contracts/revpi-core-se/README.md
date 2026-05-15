# Device-type contract — `revpi-core-se`

This is a **vendored** copy of the hardware contract intended to live
upstream at `balena-io/contracts/contracts/hw.device-type/revpi-core-se/`.

It is shipped here so the CDS handoff package (`docs/cds-handoff.md`) is
self-contained and reviewers don't need to invent the contract from
scratch.

Pattern: derived from `balena-io/contracts/contracts/hw.device-type/revpi-connect-s/`
with WiFi / Bluetooth / cellular disabled (the Core SE has none of those).

Missing from this directory: `revpi-core-se.svg` (the device icon). The
SVG must be either:

- Provided by Kunbus (preferred — official branding), or
- Drawn clean-room by Sento or a third party and dual-licensed for both
  this repo and the eventual `balena-io/contracts` submission.

Until that asset exists, the `assets.logo.url` field above points at a
file that will 404. This is intentional — the CDS submission will
include the SVG before catalog publication.
