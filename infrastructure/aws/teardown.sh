#!/usr/bin/env bash
# teardown.sh — destroy a build host launched by launch.sh.
#
# Usage:
#   ./infrastructure/aws/teardown.sh <instance-id>
#   ./infrastructure/aws/teardown.sh <instance-id> --keep-sg --keep-key
#
# Idempotent: safe to re-run. By default deletes the SG and key pair
# too, since launch.sh re-creates them on demand.

set -Eeuo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
KEY_NAME="${KEY_NAME:-balena-build-key}"
SG_NAME="${SG_NAME:-balena-build-sg}"

INSTANCE_ID=""
KEEP_SG="false"
KEEP_KEY="false"

for arg in "$@"; do
    case "$arg" in
        --keep-sg)  KEEP_SG="true" ;;
        --keep-key) KEEP_KEY="true" ;;
        i-*)        INSTANCE_ID="$arg" ;;
        *)
            printf 'usage: %s <instance-id> [--keep-sg] [--keep-key]\n' "$0" >&2
            exit 64
            ;;
    esac
done

[[ -n "$INSTANCE_ID" ]] || {
    printf '[teardown] ERROR: instance id missing.\n' >&2
    exit 64
}

export AWS_DEFAULT_REGION="$AWS_REGION"

log() { printf '[teardown] %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Terminate instance
# ---------------------------------------------------------------------------
state="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "missing")"
if [[ "$state" == "terminated" ]]; then
    log "$INSTANCE_ID already terminated"
elif [[ "$state" == "missing" ]]; then
    log "$INSTANCE_ID not found; assuming already removed"
else
    log "terminating $INSTANCE_ID (current state: $state)"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" \
        --query 'TerminatingInstances[0].CurrentState.Name' --output text
    log "waiting for terminated state..."
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
fi

# ---------------------------------------------------------------------------
# Delete security group (unless --keep-sg)
# ---------------------------------------------------------------------------
if [[ "$KEEP_SG" == "true" ]]; then
    log "--keep-sg: leaving $SG_NAME in place"
else
    SG_ID="$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        log "deleting security group $SG_NAME ($SG_ID)"
        aws ec2 delete-security-group --group-id "$SG_ID" >/dev/null || true
    fi
fi

# ---------------------------------------------------------------------------
# Delete key pair (unless --keep-key)
# ---------------------------------------------------------------------------
if [[ "$KEEP_KEY" == "true" ]]; then
    log "--keep-key: leaving $KEY_NAME in place"
else
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
        log "deleting key pair $KEY_NAME"
        aws ec2 delete-key-pair --key-name "$KEY_NAME"
    fi
fi

log "DONE. Verify no residual resources with:"
log "  aws ec2 describe-instances --filters Name=tag:project,Values=balena-revpi-core-se Name=instance-state-name,Values=running,stopped"
