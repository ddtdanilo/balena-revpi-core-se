#!/usr/bin/env bash
# launch.sh — provision a fresh AWS EC2 build host for the Yocto compile.
#
# Idempotent within reason: if the security group or key pair already exist,
# they are reused. The instance itself is always launched fresh (the per-run
# state we want is "one new instance, one new public IP").
#
# Outputs the new instance ID and public IP to stdout. Sensitive values
# (instance ID, IP) are NOT committed to git — they live in this script's
# stdout / your local notes / the Obsidian runbook.
#
# Usage:
#   ./infrastructure/aws/launch.sh                     # default region us-east-1
#   AWS_REGION=us-west-2 ./infrastructure/aws/launch.sh
#
# Required tools: aws (CLI v2 authenticated), curl
# Required env (or default): AWS_REGION, INSTANCE_TYPE, ROOT_VOLUME_GB

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Config (env-overridable)
# ---------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c6i.4xlarge}"   # 16 vCPU x86_64, 32 GiB
ROOT_VOLUME_GB="${ROOT_VOLUME_GB:-150}"
KEY_NAME="${KEY_NAME:-balena-build-key}"
SG_NAME="${SG_NAME:-balena-build-sg}"
PUBKEY_PATH="${PUBKEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
USER_DATA="${REPO_ROOT}/infrastructure/aws/cloud-init.sh"

log() { printf '[launch] %s\n' "$*"; }
die() { printf '[launch] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$PUBKEY_PATH" ]] || die "public key not found: $PUBKEY_PATH"
[[ -f "$USER_DATA" ]]   || die "cloud-init script not found: $USER_DATA"
command -v aws >/dev/null  || die "aws CLI not installed"
command -v curl >/dev/null || die "curl not installed"

export AWS_DEFAULT_REGION="$AWS_REGION"

# ---------------------------------------------------------------------------
# Step 1: key pair (import if missing; reuse if already present with same fp)
# ---------------------------------------------------------------------------
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    log "key pair $KEY_NAME already exists; reusing"
else
    log "importing $PUBKEY_PATH as key pair $KEY_NAME"
    aws ec2 import-key-pair \
        --key-name "$KEY_NAME" \
        --public-key-material "fileb://$PUBKEY_PATH" >/dev/null
fi

# ---------------------------------------------------------------------------
# Step 2: security group + ingress rule for current public IP
# ---------------------------------------------------------------------------
MY_IP="$(curl -sS https://api.ipify.org)"
[[ -n "$MY_IP" ]] || die "failed to look up current public IP"
log "current public IP: $MY_IP"

SG_ID="$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
    DEFAULT_VPC="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
        --query 'Vpcs[0].VpcId' --output text)"
    log "creating security group $SG_NAME in $DEFAULT_VPC"
    SG_ID="$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "SSH from launch.sh for Yocto builds" \
        --vpc-id "$DEFAULT_VPC" \
        --query 'GroupId' --output text)"
fi
log "security group: $SG_ID"

# Add the current IP if not already present (idempotent)
if aws ec2 describe-security-groups --group-ids "$SG_ID" \
    --query "SecurityGroups[0].IpPermissions[?ToPort==\`22\`].IpRanges[].CidrIp" \
    --output text | grep -qw "${MY_IP}/32"; then
    log "SSH rule for ${MY_IP}/32 already present"
else
    log "authorizing SSH from ${MY_IP}/32"
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 \
        --cidr "${MY_IP}/32" >/dev/null
fi

# ---------------------------------------------------------------------------
# Step 3: pick the latest Ubuntu 22.04 amd64 AMI
# ---------------------------------------------------------------------------
AMI_ID="$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters \
        "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*" \
        "Name=state,Values=available" \
        "Name=architecture,Values=x86_64" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
[[ -n "$AMI_ID" && "$AMI_ID" != "None" ]] || die "could not resolve Ubuntu 22.04 AMI"
log "AMI: $AMI_ID"

# ---------------------------------------------------------------------------
# Step 4: run the instance
# ---------------------------------------------------------------------------
log "launching $INSTANCE_TYPE in $AWS_REGION with ${ROOT_VOLUME_GB} GB root..."
INSTANCE_ID="$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${ROOT_VOLUME_GB},VolumeType=gp3,DeleteOnTermination=true}" \
    --user-data "file://$USER_DATA" \
    --metadata-options 'HttpTokens=required' \
    --tag-specifications \
        'ResourceType=instance,Tags=[{Key=Name,Value=balena-revpi-build},{Key=project,Value=balena-revpi-core-se}]' \
        'ResourceType=volume,Tags=[{Key=Name,Value=balena-revpi-build-root}]' \
    --query 'Instances[0].InstanceId' --output text)"
log "instance: $INSTANCE_ID"

# ---------------------------------------------------------------------------
# Step 5: wait for SSH-able (cloud-init reboots once, so we may have to wait
# through that reboot)
# ---------------------------------------------------------------------------
log "waiting for instance to enter running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
log "public IP: $PUBLIC_IP"

log "waiting for SSH (will survive the cloud-init reboot)..."
# poll up to 12 minutes
deadline=$(( $(date +%s) + 720 ))
while (( $(date +%s) < deadline )); do
    if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
           -o BatchMode=yes ubuntu@"$PUBLIC_IP" 'true' 2>/dev/null; then
        # Confirm cgroups v1 is active
        if ssh -o BatchMode=yes ubuntu@"$PUBLIC_IP" \
           'grep -q systemd.unified_cgroup_hierarchy=0 /proc/cmdline' 2>/dev/null; then
            break
        fi
    fi
    sleep 10
done

cat <<EOF

[launch] ready.
  Instance:  $INSTANCE_ID
  Public IP: $PUBLIC_IP
  Type:      $INSTANCE_TYPE   Region: $AWS_REGION   Disk: ${ROOT_VOLUME_GB} GB gp3

Next steps:
  ssh ubuntu@$PUBLIC_IP                                 # connect
  ./infrastructure/aws/teardown.sh $INSTANCE_ID         # terminate when done
EOF
