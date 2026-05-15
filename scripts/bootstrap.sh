#!/usr/bin/env bash
# bootstrap.sh — clone upstream balena-raspberrypi at a pinned tag,
# initialize submodules, apply this repo's overlay files and patches.
#
# Idempotent: re-running on an existing upstream/ tree is safe; it will
# refuse to overwrite uncommitted changes and re-apply only missing patches.
#
# Usage:
#   ./scripts/bootstrap.sh             # full bootstrap
#   ./scripts/bootstrap.sh --dry-run   # print actions without doing them
#   ./scripts/bootstrap.sh --reset     # blow away upstream/ and start over

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
UPSTREAM_REPO="https://github.com/balena-os/balena-raspberrypi.git"
UPSTREAM_TAG="v6.12.3+rev4"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
OVERLAY_DIR="${REPO_ROOT}/overlay"
PATCHES_DIR="${REPO_ROOT}/patches"

DRY_RUN="false"
RESET="false"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[bootstrap] %s\n' "$*"; }
die() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

run() {
	if [[ "$DRY_RUN" == "true" ]]; then
		printf '[bootstrap] DRY-RUN: %s\n' "$*"
	else
		eval "$@"
	fi
}

require_tool() {
	command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN="true" ;;
		--reset)   RESET="true" ;;
		-h|--help)
			cat <<EOF
Usage: $0 [--dry-run] [--reset]

  --dry-run    print actions without executing
  --reset      remove existing upstream/ tree first

Clones $UPSTREAM_REPO @ $UPSTREAM_TAG into upstream/, initializes
submodules, copies files from overlay/, and applies patches/*.patch.
EOF
			exit 0
			;;
		*) die "unknown argument: $arg (try --help)" ;;
	esac
done

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
require_tool git
require_tool patch
require_tool rsync

# ---------------------------------------------------------------------------
# Reset if requested
# ---------------------------------------------------------------------------
if [[ "$RESET" == "true" && -d "$UPSTREAM_DIR" ]]; then
	log "--reset specified; removing $UPSTREAM_DIR"
	run "rm -rf '$UPSTREAM_DIR'"
fi

# ---------------------------------------------------------------------------
# Clone upstream if missing
# ---------------------------------------------------------------------------
if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
	log "cloning $UPSTREAM_REPO @ $UPSTREAM_TAG into $UPSTREAM_DIR"
	run "git clone --branch '$UPSTREAM_TAG' --depth 1 '$UPSTREAM_REPO' '$UPSTREAM_DIR'"
else
	log "upstream already cloned; checking pin"
	run "git -C '$UPSTREAM_DIR' fetch --depth 1 origin tag '$UPSTREAM_TAG' --no-tags"
	run "git -C '$UPSTREAM_DIR' checkout -q 'tags/$UPSTREAM_TAG'"
fi

# ---------------------------------------------------------------------------
# Init submodules (this is the big download — meta-balena, poky, etc.)
# ---------------------------------------------------------------------------
log "initializing submodules (this may take several minutes)"
run "git -C '$UPSTREAM_DIR' submodule update --init --recursive --depth 1"

# ---------------------------------------------------------------------------
# Refuse to clobber uncommitted local changes
# ---------------------------------------------------------------------------
if [[ -z "$(git -C "$UPSTREAM_DIR" status --porcelain 2>/dev/null || true)" ]]; then
	log "upstream tree is clean"
else
	if [[ "$DRY_RUN" != "true" ]]; then
		die "upstream/ has uncommitted changes; re-run with --reset to discard, or commit them"
	fi
fi

# ---------------------------------------------------------------------------
# Copy overlay files
# ---------------------------------------------------------------------------
log "copying overlay files from $OVERLAY_DIR into $UPSTREAM_DIR"
run "rsync -a --info=NAME '$OVERLAY_DIR/' '$UPSTREAM_DIR/'"

# ---------------------------------------------------------------------------
# Apply patches
# ---------------------------------------------------------------------------
shopt -s nullglob
for p in "$PATCHES_DIR"/*.patch; do
	log "applying patch: $(basename "$p")"
	# `git apply --check` first so a partial state is impossible
	if ! git -C "$UPSTREAM_DIR" apply --check "$p" 2>/dev/null; then
		# Try `git apply -R --check` — if reverse applies cleanly, patch is already applied
		if git -C "$UPSTREAM_DIR" apply -R --check "$p" 2>/dev/null; then
			log "  already applied — skipping"
			continue
		fi
		die "patch fails --check; upstream may have drifted: $p"
	fi
	run "git -C '$UPSTREAM_DIR' apply '$p'"
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# Sanity check the result
# ---------------------------------------------------------------------------
expected_files=(
	"$UPSTREAM_DIR/revpi-core-se.coffee"
	"$UPSTREAM_DIR/layers/meta-balena-raspberrypi/conf/machine/revpi-core-se.conf"
)
for f in "${expected_files[@]}"; do
	if [[ ! -f "$f" && "$DRY_RUN" != "true" ]]; then
		die "expected file missing after bootstrap: $f"
	fi
done

cat <<EOF

[bootstrap] DONE.
  Upstream: $UPSTREAM_DIR (@ $UPSTREAM_TAG, with overlay + patches applied)
  Next:     ./scripts/build.sh dev   (requires x86_64 Linux build host with cgroups v1)
EOF
