#!/bin/bash
# cloud-init user-data for the balena-revpi-core-se Yocto build host.
#
# Runs once on first boot as root, installs Docker + Yocto deps, configures
# the kernel cmdline for cgroups v1 (required by balena-yocto-scripts), and
# reboots once so the cgroups change takes effect.
#
# Tested on Ubuntu 22.04 LTS amd64 (Canonical AMI).

set -eux

exec > >(tee -a /var/log/balena-build-setup.log) 2>&1
echo "[setup] $(date -u) — starting balena-build host bootstrap"

# Base update
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade

# Yocto + balena-build runtime deps
apt-get -y install \
    git build-essential chrpath cpio diffstat file gawk lz4 zstd \
    python3 python3-pip python3-pexpect socat texinfo unzip xz-utils wget \
    curl ca-certificates gnupg lsb-release tmux htop iotop \
    rsync jq tree

# Docker Engine (balena-build.sh runs the toolchain in a container)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu

# Cgroups v1 — REQUIRED by balena-yocto-scripts.
#
# IMPORTANT: editing /etc/default/grub directly does NOT work on Ubuntu
# cloud images, because /etc/default/grub.d/50-cloudimg-settings.cfg is
# applied AFTER and clobbers GRUB_CMDLINE_LINUX_DEFAULT. The reliable fix
# is a higher-priority drop-in that re-sets the variable with the cgroups
# v1 flag appended.
cat > /etc/default/grub.d/99-cgroups-v1.cfg <<'GRUBCFG'
GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0 nvme_core.io_timeout=4294967295 systemd.unified_cgroup_hierarchy=0"
GRUBCFG
update-grub

# Friendly MOTD pointing at the project
cat > /etc/update-motd.d/99-balena-build <<'MOTD'
#!/bin/sh
echo
echo "=============================================================="
echo "  balena-revpi-core-se BUILD HOST"
echo "  Repo:     https://github.com/ddtdanilo/balena-revpi-core-se"
echo "  Build:    cd ~/balena-revpi-core-se && ./scripts/bootstrap.sh"
echo "            ./scripts/build.sh dev"
echo "  Monitor:  tmux attach -t build"
echo "  Logs:     ~/balena-revpi-core-se/build-logs/"
echo "  Shutdown: sudo shutdown -h now"
echo "=============================================================="
echo
MOTD
chmod +x /etc/update-motd.d/99-balena-build

# Clone the public repo as the ubuntu user
su - ubuntu -c "git clone https://github.com/ddtdanilo/balena-revpi-core-se.git ~/balena-revpi-core-se"

echo "[setup] $(date -u) — bootstrap done; rebooting to apply cgroups v1"
sleep 15
reboot
