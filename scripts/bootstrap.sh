#!/usr/bin/env bash
# bootstrap.sh — clone upstream balena-raspberrypi at a pinned tag,
# initialize submodules, install this repo's overlay files, apply patches.
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

# Known overlay files installed into upstream. Keep in sync with overlay/.
OVERLAY_FILES=(
	"revpi-core-se.coffee"
	"layers/meta-balena-raspberrypi/conf/machine/revpi-core-se.conf"
)

DRY_RUN="false"
RESET="false"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[bootstrap] %s\n' "$*"; }
die() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

# run COMMAND ARGS... — execute or echo. NO eval; args stay as a real argv.
run() {
	if [[ "$DRY_RUN" == "true" ]]; then
		printf '[bootstrap] DRY-RUN:'
		printf ' %q' "$@"
		printf '\n'
	else
		"$@"
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
submodules, installs files from overlay/, and applies patches/*.patch.
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
require_tool install

# ---------------------------------------------------------------------------
# Reset if requested
# ---------------------------------------------------------------------------
if [[ "$RESET" == "true" && -e "$UPSTREAM_DIR" ]]; then
	log "--reset specified; removing $UPSTREAM_DIR"
	run rm -rf -- "$UPSTREAM_DIR"
fi

# ---------------------------------------------------------------------------
# Clone upstream if missing OR partially populated
# ---------------------------------------------------------------------------
if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
	# Partial dir from interrupted rm/clone — clear it before clone.
	if [[ -e "$UPSTREAM_DIR" ]]; then
		log "upstream/ exists but is not a git repo; removing before clone"
		run rm -rf -- "$UPSTREAM_DIR"
	fi
	log "cloning $UPSTREAM_REPO @ $UPSTREAM_TAG into $UPSTREAM_DIR"
	run git clone --branch "$UPSTREAM_TAG" --depth 1 "$UPSTREAM_REPO" "$UPSTREAM_DIR"
else
	log "upstream already cloned; verifying pin"
	run git -C "$UPSTREAM_DIR" fetch --depth 1 origin "refs/tags/$UPSTREAM_TAG:refs/tags/$UPSTREAM_TAG"
	run git -C "$UPSTREAM_DIR" checkout -q "tags/$UPSTREAM_TAG"
fi

# ---------------------------------------------------------------------------
# Init submodules.
#
# NOTE: full clone (no --depth 1) on submodules. balena-yocto-scripts and
# meta-balena use `git describe` against the submodule history for version
# strings; a shallow submodule clone breaks those version embeddings.
# ---------------------------------------------------------------------------
log "initializing submodules (this may take several minutes; full history)"
run git -C "$UPSTREAM_DIR" submodule update --init --recursive

# ---------------------------------------------------------------------------
# Refuse to clobber uncommitted local changes
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" != "true" ]]; then
	dirty="$(git -C "$UPSTREAM_DIR" status --porcelain 2>/dev/null || true)"
	if [[ -n "$dirty" ]]; then
		# Acceptable iff the only dirty files are the ones we own (overlay + patch targets)
		expected="^(.. )?(revpi-core-se\.coffee|layers/meta-balena-raspberrypi/(conf/(layer\.conf|machine/revpi-core-se\.conf|samples/local\.conf\.sample)|recipes-core/images/balena-image\.inc))$"
		if echo "$dirty" | grep -qvE "$expected"; then
			die "upstream/ has unexpected uncommitted changes:
$dirty
Re-run with --reset to discard, or commit them first."
		else
			log "upstream tree only carries this BSP's own overlay/patches — proceeding"
		fi
	else
		log "upstream tree is clean"
	fi
fi

# ---------------------------------------------------------------------------
# Install overlay files (explicit list — no blanket rsync that could clobber
# upstream files that happen to share a name)
# ---------------------------------------------------------------------------
log "installing overlay files into $UPSTREAM_DIR"
for rel in "${OVERLAY_FILES[@]}"; do
	src="${OVERLAY_DIR}/${rel}"
	dst="${UPSTREAM_DIR}/${rel}"
	if [[ ! -f "$src" ]]; then
		die "overlay source missing: $src"
	fi
	run install -D -m 0644 "$src" "$dst"
done

# ---------------------------------------------------------------------------
# Apply patches.
# Skipped under --dry-run if upstream/ wasn't actually cloned this run.
# ---------------------------------------------------------------------------
shopt -s nullglob
if [[ "$DRY_RUN" == "true" && ! -d "$UPSTREAM_DIR/.git" ]]; then
	for p in "$PATCHES_DIR"/*.patch; do
		log "DRY-RUN: would apply patch: $(basename "$p")"
	done
else
	for p in "$PATCHES_DIR"/*.patch; do
		log "applying patch: $(basename "$p")"
		# `git apply --check` first so a partial state is impossible.
		if ! git -C "$UPSTREAM_DIR" apply --check "$p" 2>/dev/null; then
			# Reverse-applies cleanly? → patch already applied.
			if git -C "$UPSTREAM_DIR" apply -R --check "$p" 2>/dev/null; then
				log "  already applied — skipping"
				continue
			fi
			die "patch fails --check on $p — try './scripts/bootstrap.sh --reset' to restart from a clean upstream tree"
		fi
		run git -C "$UPSTREAM_DIR" apply "$p"
	done
fi
shopt -u nullglob

# ---------------------------------------------------------------------------
# Append local.conf overrides to upstream's local.conf.sample.
# barys reads the sample to seed build/conf/local.conf, so these overrides
# take effect on every build. Idempotent (won't re-append if a marker is
# already present).
# ---------------------------------------------------------------------------
LOCAL_CONF_OVERRIDES="${REPO_ROOT}/infrastructure/yocto/local.conf-overrides.txt"
LOCAL_CONF_SAMPLE="${UPSTREAM_DIR}/layers/meta-balena-raspberrypi/conf/samples/local.conf.sample"
LOCAL_CONF_MARKER="# === balena-revpi-core-se overrides start ==="

if [[ -f "$LOCAL_CONF_OVERRIDES" && -f "$LOCAL_CONF_SAMPLE" ]]; then
	if grep -qF "$LOCAL_CONF_MARKER" "$LOCAL_CONF_SAMPLE" 2>/dev/null; then
		log "local.conf overrides already appended; skipping"
	else
		log "appending local.conf overrides from $LOCAL_CONF_OVERRIDES"
		if [[ "$DRY_RUN" == "true" ]]; then
			printf '[bootstrap] DRY-RUN: would append %s into %s\n' \
				"$LOCAL_CONF_OVERRIDES" "$LOCAL_CONF_SAMPLE"
		else
			{
				printf '\n%s\n' "$LOCAL_CONF_MARKER"
				cat "$LOCAL_CONF_OVERRIDES"
				printf '# === balena-revpi-core-se overrides end ===\n'
			} >> "$LOCAL_CONF_SAMPLE"
		fi
	fi
elif [[ -f "$LOCAL_CONF_OVERRIDES" && ! -f "$LOCAL_CONF_SAMPLE" && "$DRY_RUN" != "true" ]]; then
	die "local.conf.sample missing — bootstrap is incomplete: $LOCAL_CONF_SAMPLE"
fi

# ---------------------------------------------------------------------------
# Sanity check the result
# ---------------------------------------------------------------------------
for rel in "${OVERLAY_FILES[@]}"; do
	if [[ ! -f "${UPSTREAM_DIR}/${rel}" && "$DRY_RUN" != "true" ]]; then
		die "expected file missing after bootstrap: ${UPSTREAM_DIR}/${rel}"
	fi
done

cat <<EOF

[bootstrap] DONE.
  Upstream: $UPSTREAM_DIR (@ $UPSTREAM_TAG, with overlay + patches applied)
  Next:     ./scripts/build.sh dev   (requires x86_64 Linux build host with cgroups v1)
EOF
