#!/usr/bin/env bash
# flash.sh — flash a built balena-image-revpi-core-se onto the Core SE's
# internal eMMC over `rpiboot` / USB mass-storage mode.
#
# Usage:
#   ./scripts/flash.sh dev          # uses the dev image
#   ./scripts/flash.sh prod
#   ./scripts/flash.sh flasher
#   ./scripts/flash.sh <path-to.img>
#
# This script REFUSES to write without an interactive confirmation, and
# does its best to identify the correct USB mass-storage device. You are
# still responsible for not nuking your host system. Read the prompts.

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
MACHINE="revpi-core-se"

arg="${1:-dev}"
case "$arg" in
	dev|prod|flasher)
		IMG="${UPSTREAM_DIR}/build/tmp/deploy/images/${MACHINE}/balena-image-${MACHINE}.balenaos-img"
		;;
	*)
		IMG="$arg"
		;;
esac

if [[ ! -f "$IMG" ]]; then
	printf '[flash] image not found: %s\n' "$IMG" >&2
	exit 2
fi

printf '[flash] image: %s (%s bytes)\n' "$IMG" "$(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG")"

# ---------------------------------------------------------------------------
# Step 1: rpiboot
# ---------------------------------------------------------------------------
if ! command -v rpiboot >/dev/null 2>&1; then
	if [[ -x "./usbboot/rpiboot" ]]; then
		RPIBOOT="$(pwd)/usbboot/rpiboot"
	else
		printf '[flash] rpiboot not found. Install it:\n' >&2
		printf '        git clone --depth 1 https://github.com/raspberrypi/usbboot.git\n' >&2
		printf '        cd usbboot && make && sudo make install\n' >&2
		exit 3
	fi
else
	RPIBOOT="$(command -v rpiboot)"
fi

cat <<EOF

[flash] 1. Power OFF the Revolution Pi Core SE.
[flash] 2. Plug a micro-USB cable from the Core SE's Console/Service port to this host.
[flash] 3. Press ENTER to start rpiboot, then apply 24 V to the Core SE.

EOF
read -r _

sudo "$RPIBOOT"

# ---------------------------------------------------------------------------
# Step 2: identify the eMMC block device
# ---------------------------------------------------------------------------
case "$(uname -s)" in
	Linux)
		printf '\n[flash] waiting 3 s for USB enumeration...\n'
		sleep 3

		printf '\n[flash] USB block devices currently attached:\n'
		lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN | awk 'NR==1 || $5=="usb"'

		printf '\n[flash] enter the target block device (e.g. /dev/sdb) — NO PARTITION SUFFIX:\n'
		read -r TARGET
		if [[ ! -b "$TARGET" ]]; then
			printf '[flash] not a block device: %s\n' "$TARGET" >&2
			exit 4
		fi

		printf '\n[flash] CONFIRM: write %s to %s ? type the device path again:\n' "$IMG" "$TARGET"
		read -r CONFIRM
		if [[ "$CONFIRM" != "$TARGET" ]]; then
			printf '[flash] confirmation mismatch; aborting.\n' >&2
			exit 5
		fi

		sudo dd if="$IMG" of="$TARGET" bs=4M conv=fsync status=progress
		sudo sync
		;;

	Darwin)
		printf '\n[flash] waiting 3 s for USB enumeration...\n'
		sleep 3

		diskutil list | grep -E '^/dev/disk|RPi MSD|RPi-MSD'

		printf '\n[flash] enter the target raw disk (e.g. /dev/rdisk5) — NOTE the "r" prefix:\n'
		read -r TARGET
		if [[ "$TARGET" != /dev/rdisk* ]]; then
			printf '[flash] expected a /dev/rdiskN target (the raw device for speed)\n' >&2
			exit 4
		fi

		printf '\n[flash] CONFIRM: write %s to %s ? type the device path again:\n' "$IMG" "$TARGET"
		read -r CONFIRM
		if [[ "$CONFIRM" != "$TARGET" ]]; then
			printf '[flash] confirmation mismatch; aborting.\n' >&2
			exit 5
		fi

		# Unmount any auto-mounted volumes on the parent disk
		PARENT="${TARGET/rdisk/disk}"
		diskutil unmountDisk "$PARENT" || true

		sudo dd if="$IMG" of="$TARGET" bs=4m
		sudo sync
		;;

	*)
		printf '[flash] unsupported host OS: %s\n' "$(uname -s)" >&2
		exit 1
		;;
esac

cat <<EOF

[flash] DONE.
  1. Power off the Core SE (disconnect 24 V).
  2. Unplug the micro-USB cable.
  3. Connect Ethernet to X1.
  4. Apply 24 V to boot from internal eMMC.

  Dev image: SSH on TCP/22222.
EOF
