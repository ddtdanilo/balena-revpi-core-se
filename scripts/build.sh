#!/usr/bin/env bash
# build.sh — wrap balena-yocto-scripts/build/balena-build.sh for revpi-core-se
#
# Usage:
#   ./scripts/build.sh dev          # development image (SSH on 22222)
#   ./scripts/build.sh prod         # production image (no SSH, supervisor only)
#   ./scripts/build.sh flasher      # flasher image (SD -> writes eMMC)
#
# Output:
#   upstream/build/tmp/deploy/images/revpi-core-se/balena-image-revpi-core-se.balenaos-img
#
# Requirements:
#   - x86_64 Linux host (Ubuntu 22.04 LTS recommended)
#   - Booted with `systemd.unified_cgroup_hierarchy=0` (cgroups v1)
#   - ~150 GB free disk for build/ + sstate-cache/ + downloads/
#   - Docker available (balena-build.sh runs the toolchain in a container)
#   - Or: a fully-prepared native Yocto host with all build deps installed

set -Eeuo pipefail

MACHINE="revpi-core-se"
FLAVOUR="${1:-dev}"

case "$FLAVOUR" in
	dev|prod|flasher) ;;
	*)
		printf 'usage: %s {dev|prod|flasher}\n' "$0" >&2
		exit 64
		;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
SHARED_DIR="${BALENA_SHARED_DIR:-/var/balena-shared}"

if [[ ! -d "$UPSTREAM_DIR" ]]; then
	printf '[build] upstream/ is missing. Run ./scripts/bootstrap.sh first.\n' >&2
	exit 2
fi

if [[ ! -x "${UPSTREAM_DIR}/balena-yocto-scripts/build/balena-build.sh" ]]; then
	printf '[build] %s not found or not executable. Did bootstrap complete?\n' \
		"${UPSTREAM_DIR}/balena-yocto-scripts/build/balena-build.sh" >&2
	exit 3
fi

if [[ "$(uname -s)" != "Linux" ]]; then
	printf '[build] ERROR: Yocto builds require Linux x86_64. Detected: %s\n' "$(uname -s)" >&2
	exit 1
fi

# cgroups v1 sanity check (best-effort; warn rather than fail in case of newer
# host configurations that work without the legacy flag).
if [[ -f /proc/cmdline ]]; then
	if ! grep -q 'systemd.unified_cgroup_hierarchy=0' /proc/cmdline; then
		printf '[build] WARNING: kernel cmdline does not include systemd.unified_cgroup_hierarchy=0\n'
		printf '[build] WARNING: balena-yocto-scripts requires cgroups v1; build may fail.\n'
		printf '[build] WARNING: continue anyway? [y/N] '
		read -r reply
		if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
			exit 1
		fi
	fi
fi

mkdir -p "$SHARED_DIR"

cd "$UPSTREAM_DIR"

cat <<EOF

[build] machine:   $MACHINE
[build] flavour:   $FLAVOUR
[build] upstream:  $UPSTREAM_DIR
[build] shared:    $SHARED_DIR  (sstate-cache + downloads will live here)

[build] invoking balena-yocto-scripts/build/balena-build.sh
EOF

# The balena-build.sh runner accepts -d <device-slug> and -s <shared-dir>.
# The flavour is selected via the underlying barys driver. balena-build.sh
# forwards positional args after -- to barys.
case "$FLAVOUR" in
	dev)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR"
		;;
	prod)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR" \
			-g "--development-image=no"
		;;
	flasher)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR" \
			-g "--flasher-image=yes"
		;;
esac

DEPLOY_DIR="${UPSTREAM_DIR}/build/tmp/deploy/images/${MACHINE}"
ART="${DEPLOY_DIR}/balena-image-${MACHINE}.balenaos-img"

if [[ -f "$ART" ]]; then
	printf '\n[build] DONE: %s (%s bytes)\n' "$ART" "$(stat -c%s "$ART" 2>/dev/null || stat -f%z "$ART")"
else
	printf '\n[build] WARNING: expected artifact not found at %s\n' "$ART" >&2
	printf '[build] Inspect %s/ manually.\n' "$DEPLOY_DIR" >&2
	exit 4
fi
