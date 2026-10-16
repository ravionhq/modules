#!/usr/bin/env bash
# Runs the router's boot script for real, in a throwaway Debian container.
#
# The script is rendered from user_data.sh.tftpl with OpenTofu's own
# templatefile, then run as root in the container with systemctl replaced by a
# stand-in that records what it was asked. Each scenario starts from the state
# of a fresh image: with the preview router it carries, without one, or with
# one that cannot run.
#
# Needs tofu and docker. Usage: tests/user_data_test.sh
set -euo pipefail

module_dir=$(cd "$(dirname "$0")/.." && pwd)
image=${USER_DATA_TEST_IMAGE:-debian:13-slim}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# tofu console prints the base64 text as one quoted string.
rendered=$(cd "$work" && tofu console <<EOF | tr -d '"'
base64encode(templatefile("$module_dir/user_data.sh.tftpl", {
  ravion_api_url     = "https://api.example.test"
  module_instance_id = "minst_test"
  router_ports       = { traffic = 8080, redirect = 8081, health = 8082 }
}))
EOF
)

docker run --rm -i -e USER_DATA_B64="$rendered" "$image" bash -s <<'CONTAINER'
set -uo pipefail

echo "$USER_DATA_B64" | base64 -d > /root/user_data.sh
bash -n /root/user_data.sh || { echo "FAIL: the boot script is not valid bash"; exit 1; }

# The stand-in lives where the boot script's PATH looks first.
cat > /usr/local/bin/systemctl <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> /var/log/systemctl.args
STUB
chmod 0755 /usr/local/bin/systemctl

router=/usr/local/bin/preview-router
unit=/etc/systemd/system/ravion-preview-router.service
failures=0

check() {
	if "${@:2}" > /dev/null 2>&1; then
		echo "  ok    $1"
	else
		echo "  FAIL  $1"
		failures=$((failures + 1))
	fi
}

# reset puts back what a fresh image holds: a preview router reporting $1,
# or none when $1 is empty.
reset() {
	rm -rf /etc/ravion /var/lib/ravion "$unit" "$router" /var/log/systemctl.args /root/out
	mkdir -p /etc/systemd/system
	if [ -n "${1:-}" ]; then
		printf '#!/bin/sh\n[ "$1" = --version ] && echo "preview-router version %s"\n' "$1" > "$router"
		chmod 0755 "$router"
	fi
}

boot() {
	bash /root/user_data.sh > /root/out 2>&1
}

never_started() {
	[ ! -e "$unit" ] && [ ! -e /var/log/systemctl.args ]
}

echo "the image's router is started"
reset v9.9.9
check "the boot script succeeds" boot
check "the environment names the control plane" grep -qx 'RAVION_API_URL=https://api.example.test' /etc/ravion/preview-router.env
check "the environment names the module instance" grep -qx 'RAVION_PREVIEW_ROUTER_MODULE_INSTANCE_ID=minst_test' /etc/ravion/preview-router.env
check "the work directory is root only" test "$(stat -c %a /var/lib/ravion/preview-router)" = 700
check "the unit starts the router on its three ports" grep -qx 'ExecStart=/usr/local/bin/preview-router --listen :8080 --listen-redirect :8081 --listen-health :8082' "$unit"
check "the unit is reloaded, then enabled and started" diff <(printf 'daemon-reload\nenable --now ravion-preview-router.service\n') /var/log/systemctl.args
check "the router's release is logged" grep -q 'preview-router version v9.9.9' /root/out

echo "an image without a router stops the boot"
reset
check "the boot script fails" bash -c '! bash /root/user_data.sh > /root/out 2>&1'
check "the failure names the missing router" grep -q 'the image carries no preview router at /usr/local/bin/preview-router' /root/out
check "the router is never started" never_started

echo "a router that cannot run here stops the boot"
reset v9.9.9
printf '#!/bin/sh\nexit 126\n' > "$router"
check "the boot script fails" bash -c '! bash /root/user_data.sh > /root/out 2>&1'
check "the failure is reported" grep -q 'preview router setup: FAILED' /root/out
check "the router is never started" never_started

echo
if [ "$failures" -gt 0 ]; then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
CONTAINER
