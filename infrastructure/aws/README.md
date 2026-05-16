# `infrastructure/aws/` — reproducible build host on AWS EC2

Scripts to spin up a one-shot Yocto build host on AWS EC2 for the
`balena-revpi-core-se` BSP, run the build, and tear everything down
cleanly when done. Designed for a single confident run — not for a
persistent build farm.

## Files

| File | Purpose |
|---|---|
| `cloud-init.sh` | User-data passed to the instance on first boot. Installs Docker + Yocto build deps, writes the cgroups v1 GRUB drop-in, clones this repo, reboots. |
| `launch.sh` | Idempotent CLI wrapper around `aws ec2`: imports the SSH key, creates the security group with the current public IP, picks the latest Ubuntu 22.04 LTS amd64 AMI, runs the instance with the `cloud-init.sh` user-data, waits for SSH. |
| `teardown.sh` | Idempotent CLI wrapper: terminates the instance, deletes the security group, deletes the key pair. |

## Prerequisites

- AWS CLI v2 authenticated (`aws sts get-caller-identity` works).
- An SSH key pair on the operator's machine; default path `~/.ssh/id_ed25519.pub`.
- The IAM principal must have EC2 read/write permissions: `RunInstances`,
  `TerminateInstances`, `DescribeInstances`, `CreateSecurityGroup`,
  `AuthorizeSecurityGroupIngress`, `DeleteSecurityGroup`, `ImportKeyPair`,
  `DeleteKeyPair`, `DescribeImages`, `DescribeVpcs`.
- `curl` available for the public-IP lookup.

## Usage

End-to-end for one build:

```bash
# 1) Provision a host. Output ends with "Instance: i-..." and "Public IP: ...".
./infrastructure/aws/launch.sh

# 2) SSH in and start the build. Use a tmux session so detaching doesn't
#    kill the build.
ssh ubuntu@<public-ip>
tmux new-session -s build
cd ~/balena-revpi-core-se
./scripts/bootstrap.sh
./scripts/build.sh dev
# Ctrl-b d to detach. Re-attach later with `tmux attach -t build`.

# 3) When the .img is ready, copy it back to your workstation.
scp ubuntu@<public-ip>:~/balena-revpi-core-se/upstream/build/tmp/deploy/images/revpi-core-se/balena-image-revpi-core-se.balenaos-img \
    ~/Downloads/

# 4) Tear the host down completely.
./infrastructure/aws/teardown.sh <instance-id>
```

## Defaults

| Variable | Default | Override |
|---|---|---|
| `AWS_REGION` | `us-east-1` | env |
| `INSTANCE_TYPE` | `c6i.4xlarge` (16 vCPU x86_64, 32 GiB) | env |
| `ROOT_VOLUME_GB` | `150` | env |
| `KEY_NAME` | `balena-build-key` | env |
| `SG_NAME` | `balena-build-sg` | env |
| `PUBKEY_PATH` | `~/.ssh/id_ed25519.pub` | env |

## Cost expectations

Approximate, on-demand pricing in `us-east-1` (verify at
[aws.amazon.com/ec2/pricing/on-demand](https://aws.amazon.com/ec2/pricing/on-demand/)):

- `c6i.4xlarge`: ~$0.68/h while running.
- 150 GB gp3 EBS: ~$0.02 prorated for a 6 h build.
- Data transfer out: a few cents per `.img` artifact.

A clean first build typically costs **~$4–5 in total**. The instance is
terminated by `teardown.sh`, so no ongoing infra remains.

## Why cgroups v1?

`balena-yocto-scripts/build/balena-build.sh` runs the toolchain in a
container that requires the legacy cgroups v1 hierarchy. Ubuntu 22.04
ships with cgroups v2 by default.

**Common pitfall:** editing `/etc/default/grub` directly does not stick on
Ubuntu cloud images, because `/etc/default/grub.d/50-cloudimg-settings.cfg`
is loaded later and overrides `GRUB_CMDLINE_LINUX_DEFAULT`. The reliable
fix used here is a higher-priority drop-in at
`/etc/default/grub.d/99-cgroups-v1.cfg` that re-asserts the kernel cmdline
with the `systemd.unified_cgroup_hierarchy=0` flag included. The
cloud-init script then runs `update-grub` and reboots.

## What is NOT in these files

By design, this directory contains **no sensitive identifiers**: no AWS
account ID, no IP addresses, no instance IDs, no access keys. The
`launch.sh` script looks up the current public IP at runtime and prints
the new instance ID to stdout; the operator captures those in their own
notes (or in their private Obsidian / 1Password / wherever) rather than
committing them.

If you need to extend this for a more permanent deployment (Elastic IP,
named DNS, multiple regions, GitHub Actions integration), do it via env
vars / CLI args, not by hardcoding values here.
