#!/usr/bin/env bash
# flash.sh — flash a built balena-image-revpi-core-se onto the Core SE's
# internal eMMC over `rpiboot` / USB mass-storage mode.
#
# Usage:
#   ./scripts/flash.sh dev          # uses the dev image
#   ./scripts/flash.sh prod
#   ./scripts/flash.sh <path-to.img>
#
# Note: `./scripts/flash.sh flasher` is intentionally refused. A flasher
# image is meant to boot from an SD card and write the embedded prod image
# to internal eMMC; writing it to the internal eMMC directly does not do
# what users expect. Burn the flasher image to an SD card with a generic
# tool (balenaEtcher, `dd`) and boot the device from the SD.
#
# This script REFUSES to write without an interactive confirmation, and
# does its best to identify the correct USB mass-storage device. You are
# still responsible for not nuking your host system. Read the prompts.

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
MACHINE="revpi-core-se"

die() { printf '[flash] ERROR: %s\n' "$*" >&2; exit 1; }

arg="${1:-dev}"
case "$arg" in
	dev|prod)
		IMG="${UPSTREAM_DIR}/build/tmp/deploy/images/${MACHINE}/balena-image-${MACHINE}.balenaos-img"
		;;
	flasher)
		cat >&2 <<EOF
[flash] ERROR: 'flash.sh flasher' is intentionally refused.

  A flasher image must be written to an SD card (or USB stick), then
  booted by the Core SE. The device boots from the SD, writes the
  embedded prod image to internal eMMC, then reboots.

  To flash the flasher image to an SD card:
    sudo dd if=upstream/build/tmp/deploy/images/${MACHINE}/balena-image-flasher-${MACHINE}.balenaos-img \\
            of=/dev/sdX bs=4M conv=fsync status=progress

  Then insert the SD into the Core SE and apply 24 V.
EOF
		exit 64
		;;
	*)
		IMG="$arg"
		;;
esac

if [[ ! -f "$IMG" ]]; then
	die "image not found: $IMG"
fi

printf '[flash] image: %s (%s bytes)\n' "$IMG" "$(stat -c%s "$IMG" 2>/dev/null || stat -f%z "$IMG")"

# ---------------------------------------------------------------------------
# Step 0: keep sudo credentials warm for the whole flow
# ---------------------------------------------------------------------------
sudo -v
# Background refresher so a slow rpiboot doesn't time out our credential.
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &
SUDO_REFRESHER_PID=$!
trap 'kill "$SUDO_REFRESHER_PID" 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Step 1: locate rpiboot
# ---------------------------------------------------------------------------
if command -v rpiboot >/dev/null 2>&1; then
	RPIBOOT="$(command -v rpiboot)"
elif [[ -x "./usbboot/rpiboot" ]]; then
	RPIBOOT="$(pwd)/usbboot/rpiboot"
else
	cat >&2 <<EOF
[flash] rpiboot not found. Install it:
        git clone --depth 1 https://github.com/raspberrypi/usbboot.git
        cd usbboot && make && sudo make install
EOF
	exit 3
fi

cat <<EOF

[flash] 1. Power OFF the Revolution Pi Core SE (disconnect 24 V).
[flash] 2. Plug a USB DATA cable (not power-only!) from the Core SE's
           Console/Service micro-USB port to this host.
[flash] 3. Press ENTER to start rpiboot, then apply 24 V to the Core SE.
           Order matters: rpiboot must be listening BEFORE the device
           powers on, otherwise the bootrom won't fall into mass-storage
           mode.

EOF
read -r _

sudo "$RPIBOOT"

# ---------------------------------------------------------------------------
# Step 2: wait for the eMMC to enumerate; identify the block device
# ---------------------------------------------------------------------------
case "$(uname -s)" in
	Linux)
		printf '\n[flash] waiting up to 30 s for USB enumeration...\n'
		for _ in $(seq 1 30); do
			if lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN -nr 2>/dev/null | grep -qiE 'rpi|usb'; then
				break
			fi
			sleep 1
		done

		printf '\n[flash] block devices (TRAN=usb or model contains RPi):\n'
		lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN | awk 'NR==1 || $5=="usb" || tolower($3) ~ /rpi/'

		printf '\n[flash] enter the target block device (e.g. /dev/sdb) — NO PARTITION SUFFIX:\n'
		read -r TARGET
		[[ -b "$TARGET" ]] || die "not a block device: $TARGET"

		# Detect zero-byte enumeration (known CM4 firmware quirk).
		size_bytes="$(sudo blockdev --getsize64 "$TARGET" 2>/dev/null || echo 0)"
		if (( size_bytes < 1000000000 )); then
			die "target $TARGET reports < 1 GB ($size_bytes bytes). This is a known CM4S rpiboot quirk. Power-cycle the Core SE (24 V off, USB unplug, then redo from step 1) and try again."
		fi
		printf '[flash] target %s capacity: %s bytes\n' "$TARGET" "$size_bytes"

		printf '\n[flash] CONFIRM: write %s to %s ? type the device path again to proceed:\n' "$IMG" "$TARGET"
		read -r CONFIRM
		[[ "$CONFIRM" == "$TARGET" ]] || die "confirmation mismatch; aborting."

		# Wipe partition signatures so the kernel doesn't auto-mount during the write.
		sudo wipefs -af "$TARGET" >/dev/null || true

		sudo dd if="$IMG" of="$TARGET" bs=4M conv=fsync iflag=fullblock status=progress
		sudo sync
		;;

	Darwin)
		printf '\n[flash] waiting up to 30 s for USB enumeration...\n'
		for _ in $(seq 1 30); do
			if diskutil list | grep -qE 'RPi[- ]MSD'; then
				break
			fi
			sleep 1
		done

		diskutil list | grep -E '^/dev/disk|RPi MSD|RPi-MSD'

		printf '\n[flash] enter the target RAW disk (e.g. /dev/rdisk5) — NOTE the "r" prefix:\n'
		read -r TARGET
		[[ "$TARGET" == /dev/rdisk* ]] || die "expected a /dev/rdiskN target (raw device for speed)"

		# macOS doesn't expose blockdev; use diskutil to read size.
		PARENT="${TARGET/rdisk/disk}"
		size_bytes="$(diskutil info "$PARENT" 2>/dev/null | awk -F'\\(' '/Disk Size/{gsub(/[^0-9]/,"",$2); print $2; exit}')"
		if [[ -z "$size_bytes" || "$size_bytes" -lt 1000000000 ]]; then
			die "target $TARGET reports < 1 GB. This is a known CM4S rpiboot quirk. Power-cycle the Core SE (24 V off, USB unplug, then redo from step 1) and try again."
		fi
		printf '[flash] target %s capacity: %s bytes\n' "$TARGET" "$size_bytes"

		printf '\n[flash] CONFIRM: write %s to %s ? type the device path again to proceed:\n' "$IMG" "$TARGET"
		read -r CONFIRM
		[[ "$CONFIRM" == "$TARGET" ]] || die "confirmation mismatch; aborting."

		diskutil unmountDisk "$PARENT" || true

		sudo dd if="$IMG" of="$TARGET" bs=4m
		sudo sync
		diskutil eject "$PARENT" || true
		;;

	*)
		die "unsupported host OS: $(uname -s)"
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
