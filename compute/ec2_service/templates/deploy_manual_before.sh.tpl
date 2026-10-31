#!/bin/bash
set -euo pipefail

DEPLOY_ID="{{ deployId }}"
if [ -z "$DEPLOY_ID" ]; then DEPLOY_ID=$(date +%s); fi

# SSM runs this script as root but with the agent's bare environment (no
# HOME, TERM=dumb). Restore normal root-shell semantics so release tooling
# that resolves `~` or queries terminal capabilities does not abort.
export HOME="$${HOME:-/root}"
if [ "$${TERM:-dumb}" = "dumb" ]; then export TERM=xterm; fi

${deployment_log_script}
exec > >(tee -a "$LOG_PATH") 2> >(tee -a "$LOG_PATH" >&2)

echo "Preparing manual deploy $DEPLOY_ID"

# Check storage before touching the running app: a failure here leaves the
# current app running.
${storage_guard_script}

${supervisor_install_script}
${env_file_script}

# Stop the previous supervised app before release preparation. Removing a
# same-named container also makes Container -> Manual switches deterministic.
/usr/local/bin/supervisorctl -c /etc/supervisord.conf stop "${supervisor_program}" >/dev/null 2>&1 || true
docker rm -f ${name} >/dev/null 2>&1 || true

set -a
. "${env_file_path}"
set +a

${git_source_checkout_script}
