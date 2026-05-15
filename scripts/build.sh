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
#   - x86_64 Linux host (Ubuntu 22.04 LTS recommended).
#   - Booted with `systemd.unified_cgroup_hierarchy=0` (cgroups v1). To
#     override the check explicitly (knowing the build may fail), set
#     `ALLOW_CGROUPS_V2=1` in the environment.
#   - ~150 GB free disk for build/ + sstate-cache/ + downloads/.
#   - Docker available (balena-build.sh runs the toolchain in a container).
#   - Or: a fully-prepared native Yocto host with all build deps installed.

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
SHARED_DIR_DEFAULT="${HOME}/.cache/balena-shared"
SHARED_DIR="${BALENA_SHARED_DIR:-$SHARED_DIR_DEFAULT}"

die() { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }

if [[ ! -d "$UPSTREAM_DIR" ]]; then
	die "upstream/ is missing. Run ./scripts/bootstrap.sh first."
fi

if [[ ! -x "${UPSTREAM_DIR}/balena-yocto-scripts/build/balena-build.sh" ]]; then
	die "${UPSTREAM_DIR}/balena-yocto-scripts/build/balena-build.sh not found or not executable. Did bootstrap complete?"
fi

if [[ "$(uname -s)" != "Linux" ]]; then
	cat >&2 <<EOF
[build] ERROR: Yocto builds require an x86_64 Linux host. Detected: $(uname -s).
[build] Use one of:
[build]   - A native Ubuntu 22.04 LTS workstation or server.
[build]   - An x86_64 Linux VM (e.g. AWS EC2 c6i.4xlarge with 150 GB EBS).
[build]   - A local QEMU/KVM/UTM Ubuntu VM (slow but viable).
EOF
	exit 1
fi

# cgroups v1 is a hard requirement of balena-yocto-scripts. Fail by default
# unless the user explicitly opts in via ALLOW_CGROUPS_V2=1.
if [[ -f /proc/cmdline ]] && ! grep -q 'systemd.unified_cgroup_hierarchy=0' /proc/cmdline; then
	if [[ "${ALLOW_CGROUPS_V2:-0}" != "1" ]]; then
		cat >&2 <<EOF
[build] ERROR: kernel cmdline does not include systemd.unified_cgroup_hierarchy=0.
[build]        balena-yocto-scripts requires cgroups v1; cgroups-v2 hosts will
[build]        usually fail late in the build with opaque cgroup errors.
[build]
[build]        Either reboot with that kernel parameter, or set
[build]        ALLOW_CGROUPS_V2=1 to override this check (build may still fail).
EOF
		exit 1
	fi
	printf '[build] WARNING: ALLOW_CGROUPS_V2=1 set; build may fail late.\n' >&2
fi

mkdir -p "$SHARED_DIR"
if [[ ! -w "$SHARED_DIR" ]]; then
	die "shared dir is not writable: $SHARED_DIR (override with BALENA_SHARED_DIR)"
fi

LOG_DIR="${REPO_ROOT}/build-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-${MACHINE}-${FLAVOUR}-$(date -u +%Y%m%dT%H%M%SZ).log"

cd "$UPSTREAM_DIR"

cat <<EOF | tee -a "$LOG_FILE"

[build] machine:   $MACHINE
[build] flavour:   $FLAVOUR
[build] upstream:  $UPSTREAM_DIR
[build] shared:    $SHARED_DIR
[build] log:       $LOG_FILE

[build] invoking balena-yocto-scripts/build/balena-build.sh
EOF

# balena-build.sh forwards positional args after -- to barys.
# Flag-set for the underlying barys driver:
#   dev:     (no extra flag — default development image)
#   prod:    --development-image=no
#   flasher: --flasher-image=yes
# These flag names match meta-balena `master` in v6.12.3+rev4. If the
# submodule is bumped, re-verify against balena-yocto-scripts/build/barys.
set -o pipefail
case "$FLAVOUR" in
	dev)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR" 2>&1 | tee -a "$LOG_FILE"
		;;
	prod)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR" \
			-g "--development-image=no" 2>&1 | tee -a "$LOG_FILE"
		;;
	flasher)
		./balena-yocto-scripts/build/balena-build.sh \
			-d "$MACHINE" \
			-s "$SHARED_DIR" \
			-g "--flasher-image=yes" 2>&1 | tee -a "$LOG_FILE"
		;;
esac

DEPLOY_DIR="${UPSTREAM_DIR}/build/tmp/deploy/images/${MACHINE}"
ART="${DEPLOY_DIR}/balena-image-${MACHINE}.balenaos-img"

if [[ -f "$ART" ]]; then
	size_bytes="$(stat -c%s "$ART" 2>/dev/null || stat -f%z "$ART")"
	printf '\n[build] DONE: %s (%s bytes)\n' "$ART" "$size_bytes" | tee -a "$LOG_FILE"
else
	printf '\n[build] WARNING: expected artifact not found at %s\n' "$ART" | tee -a "$LOG_FILE" >&2
	printf '[build] Inspect %s/ manually; full log: %s\n' "$DEPLOY_DIR" "$LOG_FILE" >&2
	exit 4
fi
