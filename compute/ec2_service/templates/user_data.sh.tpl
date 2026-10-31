#!/bin/bash
# Bootstrap for ${name} EC2 service instances.
# Runs at launch, and again after a root volume replacement (Update AMI),
# so every step must be safe to repeat. Deploys are pushed through SSM Run
# Command, so this script prepares the host for either deploy mode.
set -euo pipefail

dnf install -y git jq unzip

%{ if data_volume_creation_enabled ~}
# Data volume: format it only when it is a brand-new blank disk, then mount
# it whenever the mount path is not mounted yet. User data runs again after
# a root volume replacement, which brings back an /etc/fstab without the
# data volume; the volume keeps its filesystem and data and is remounted
# here. A problem is logged and left to the deploy storage guard, which
# refuses to start the app without its data volume.
${data_volume_mount_script}
${data_volume_format_script}
ravion_format_new_data_volume || echo "Data volume: formatting failed" >&2
ravion_mount_data_volume || true
%{ endif ~}

%{ if efs_enabled ~}
# Mount the EFS file system
dnf install -y amazon-efs-utils
mkdir -p ${efs_mount_path}
# Idempotent: user data also runs again after a root volume replacement.
if ! awk -v path="${efs_mount_path}" '$1 !~ /^#/ && $2 == path { found = 1 } END { exit !found }' /etc/fstab; then
%{ if efs_access_point_id != "" ~}
  echo "${efs_file_system_id} ${efs_mount_path} efs _netdev,tls,accesspoint=${efs_access_point_id} 0 0" >> /etc/fstab
%{ else ~}
  echo "${efs_file_system_id} ${efs_mount_path} efs _netdev,tls 0 0" >> /etc/fstab
%{ endif ~}
fi
mount -a -t efs
%{ endif ~}

mkdir -p "$(dirname ${env_file_path})"

# Install both runtime prerequisites so deploy mode can change without
# replacing the instance group. The same idempotent supervisor bootstrap
# also runs during deploys to upgrade existing instances in place.
dnf install -y docker
systemctl enable --now docker
${supervisor_install_script}

# Initialize the app env file. Deploys refresh it before running either mode.
${env_file_script}

dnf install -y amazon-cloudwatch-agent

%{ if additional_user_data != "" ~}
# Additional user data
${additional_user_data}
%{ endif ~}
