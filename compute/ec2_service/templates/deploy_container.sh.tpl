#!/bin/bash
# In-place container deploy for ${name}. Runs on each instance via the
# SSM deploy document; {{ }} placeholders are SSM parameter substitutions.
set -euo pipefail

IMAGE_URI="{{ imageUri }}"
DEPLOY_ID="{{ deployId }}"
if [ -z "$DEPLOY_ID" ]; then DEPLOY_ID=$(date +%s); fi

# SSM runs this script as root but with the agent's bare environment (no
# HOME, TERM=dumb). Restore normal root-shell semantics so release tooling
# that resolves `~` or queries terminal capabilities does not abort.
export HOME="$${HOME:-/root}"
if [ "$${TERM:-dumb}" = "dumb" ]; then export TERM=xterm; fi

${deployment_log_script}
exec > >(tee -a "$LOG_PATH") 2> >(tee -a "$LOG_PATH" >&2)

echo "Deploying image $IMAGE_URI (deploy $DEPLOY_ID)"

# Check storage before touching the running app: a failure here leaves the
# current container serving.
${storage_guard_script}

TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Make supervisord available on both newly launched and existing instances.
${supervisor_install_script}

# Rebuild the app env file on every deploy.
${env_file_script}

# Log in to ECR when pulling from an ECR registry
case "$IMAGE_URI" in
  *.dkr.ecr.*.amazonaws.com/*)
    ECR_REGISTRY="$${IMAGE_URI%%/*}"
    aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    ;;
esac

docker pull "$IMAGE_URI"

%{ if target_group_arn != "" ~}
# Drain this instance from the target group before swapping the container.
# Skipped when this instance is the only registered target: there is
# nothing to shift traffic to, and skipping the deregistration delay and
# in-service wait shortens the outage the swap causes anyway.
REGISTERED_TARGETS=$(aws elbv2 describe-target-health --region ${region} --target-group-arn "${target_group_arn}" --query 'length(TargetHealthDescriptions)' --output text)
DRAIN=0
if [ "$REGISTERED_TARGETS" -gt 1 ]; then
  DRAIN=1
  echo "Deregistering $INSTANCE_ID from the target group"
  aws elbv2 deregister-targets --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
  aws elbv2 wait target-deregistered --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
else
  echo "Only registered target in the target group; skipping drain"
fi
%{ endif ~}

# Stop the old supervised process after draining. The runner removes any
# stale same-named container before starting the requested image.
/usr/local/bin/supervisorctl -c /etc/supervisord.conf stop "${supervisor_program}" >/dev/null 2>&1 || true
docker rm -f ${name} >/dev/null 2>&1 || true
printf '%s\n' "$IMAGE_URI" > "${image_ref_path}"

cat > "${app_runner_path}" <<'APP_RUNNER'
#!/bin/bash
set -euo pipefail
# Supervisord starts the runner without a login environment; docker reads
# credential config from $HOME.
export HOME="$${HOME:-/root}"
IMAGE_URI=$(cat "${image_ref_path}")
docker rm -f ${name} >/dev/null 2>&1 || true

RUN_ARGS=(--rm --name ${name} --env-file "${env_file_path}")
%{ if app_port != null ~}
RUN_ARGS+=(-p ${app_port}:${app_port})
%{ endif ~}
%{ if data_volume_mount_path != "" ~}
RUN_ARGS+=(-v ${data_volume_mount_path}:${data_volume_mount_path})
%{ endif ~}
%{ if efs_mount_path != "" ~}
RUN_ARGS+=(-v ${efs_mount_path}:${efs_mount_path})
%{ endif ~}
%{ if docker_socket_mount_enabled ~}
DOCKER_GROUP_GID=$(getent group docker | awk -F: 'NR==1 {print $3}' || true)
if [ -z "$DOCKER_GROUP_GID" ]; then
  echo "The host docker group could not be found; refusing to start the container" >&2
  exit 1
fi
RUN_ARGS+=(--group-add "$DOCKER_GROUP_GID" -v /var/run/docker.sock:/var/run/docker.sock)
%{ endif ~}
exec docker run "$${RUN_ARGS[@]}" "$IMAGE_URI" ${start_command}
APP_RUNNER
chmod 755 "${app_runner_path}"

${supervisor_program_script}

%{ if deploy_health_check_path != "" && app_port != null ~}
# Gate deploy success on the local health check
HEALTHY=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:${app_port}${deploy_health_check_path}"; then
    HEALTHY=1
    break
  fi
  sleep 5
done
if [ "$HEALTHY" -ne 1 ]; then
  echo "App failed the local health check on port ${app_port}${deploy_health_check_path}" >&2
  tail -n 100 "$LOG_PATH" >&2 || true
  exit 1
fi
%{ endif ~}

%{ if target_group_arn != "" ~}
if [ "$DRAIN" -eq 1 ]; then
  echo "Re-registering $INSTANCE_ID with the target group"
  aws elbv2 register-targets --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
  aws elbv2 wait target-in-service --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
fi
%{ endif ~}

docker image prune -f >/dev/null 2>&1 || true
echo "Deploy $DEPLOY_ID complete"
