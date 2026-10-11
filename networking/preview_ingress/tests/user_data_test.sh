#!/usr/bin/env bash
# Runs the router's boot script for real, in a throwaway Debian container.
#
# The script is rendered from user_data.sh.tftpl with OpenTofu's own
# templatefile, then run as root in the container with curl and systemctl
# replaced by stand-ins: curl serves a release from fixture files (or answers
# 404), systemctl records what it was asked. Each scenario starts from the
# state of a fresh image that already carries an older runner.
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
  release_path       = "/sandbox-host/v1/releases/current"
  platform           = "linux-amd64"
  router_ports       = { traffic = 8080, redirect = 8081, health = 8082 }
}))
EOF
)

docker run --rm -i -e USER_DATA_B64="$rendered" "$image" bash -s <<'CONTAINER'
set -uo pipefail

echo "$USER_DATA_B64" | base64 -d > /root/user_data.sh
bash -n /root/user_data.sh || { echo "FAIL: the boot script is not valid bash"; exit 1; }

# The stand-ins live outside the boot script's PATH order only by name: the
# script puts /usr/local/bin first, which is where they are.
cat > /usr/local/bin/curl <<'STUB'
#!/bin/bash
# Stand-in for curl: serves /fixtures/<file>, where <file> is the file= query
# parameter of the URL, to the --output path. A missing fixture is a 404.
printf '%s\n' "$*" >> /var/log/curl.args
output="" url=""
while [ $# -gt 0 ]; do
	case "$1" in
		--output) output=$2; shift ;;
		--proto | --proto-redir | --retry | --retry-delay | --max-time) shift ;;
		--*) ;;
		*) url=$1 ;;
	esac
	shift
done
file=${url##*file=}
if [ ! -f "/fixtures/$file" ]; then
	echo "curl: (22) The requested URL returned error: 404" >&2
	exit 22
fi
cp "/fixtures/$file" "$output"
STUB
cat > /usr/local/bin/systemctl <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> /var/log/systemctl.args
STUB
chmod 0755 /usr/local/bin/curl /usr/local/bin/systemctl

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

# reset puts back what a fresh image holds: an older runner and nothing else.
reset() {
	rm -rf /etc/ravion /var/lib/ravion /fixtures "$unit" /var/log/curl.args /var/log/systemctl.args /root/out
	mkdir -p /fixtures /etc/systemd/system
	printf '#!/bin/sh\necho v0.0.1\n' > /usr/local/bin/runner
	chmod 0755 /usr/local/bin/runner
}

# release writes a runner that reports itself as $1 and its checksum line.
release() {
	printf '#!/bin/sh\n[ "$1 $2" = "version --release" ] && echo %s\n' "$1" > /fixtures/binary
	printf '%s  runner-linux-amd64\n' "$(sha256sum /fixtures/binary | cut -d' ' -f1)" > /fixtures/checksum
}

boot() {
	bash /root/user_data.sh > /root/out 2>&1
}

never_started() {
	[ ! -e "$unit" ] && [ ! -e /var/log/systemctl.args ]
}

echo "a release that verifies is installed and started"
reset
release v9.9.9
check "the boot script succeeds" boot
check "the new runner replaces the image's" grep -q v9.9.9 /usr/local/bin/runner
check "the runner is executable" test -x /usr/local/bin/runner
check "the environment names the control plane" grep -qx 'RAVION_API_URL=https://api.example.test' /etc/ravion/preview-router.env
check "the environment names the module instance" grep -qx 'RAVION_PREVIEW_ROUTER_MODULE_INSTANCE_ID=minst_test' /etc/ravion/preview-router.env
check "the work directory is root only" test "$(stat -c %a /var/lib/ravion/preview-router)" = 700
check "the unit starts the router on its three ports" grep -qx 'ExecStart=/usr/local/bin/runner preview-router --listen :8080 --listen-redirect :8081 --listen-health :8082' "$unit"
check "the unit is reloaded, then enabled and started" diff <(printf 'daemon-reload\nenable --now ravion-preview-router.service\n') /var/log/systemctl.args
check "the binary comes from the release endpoint" grep -q 'https://api.example.test/sandbox-host/v1/releases/current?platform=linux-amd64&file=binary$' /var/log/curl.args
check "the checksum comes from the release endpoint" grep -q 'https://api.example.test/sandbox-host/v1/releases/current?platform=linux-amd64&file=checksum$' /var/log/curl.args
check "every download fails on an HTTP error and stays on HTTPS" test "$(grep -c -e '--fail .*--proto =https --proto-redir =https' /var/log/curl.args)" = 2
check "the release it installed is logged" grep -q 'runner release v9.9.9' /root/out
check "no download is left behind" test -z "$(find /tmp -name runner -o -name runner.sha256)"

echo "a download that does not match its checksum is refused"
reset
release v9.9.9
echo tampered >> /fixtures/binary
check "the boot script fails" bash -c '! bash /root/user_data.sh > /root/out 2>&1'
check "the failure is reported" grep -q 'preview router setup: FAILED' /root/out
check "the image's runner is untouched" grep -q v0.0.1 /usr/local/bin/runner
check "the router is never started" never_started

echo "a release the control plane does not offer stops the boot"
reset
check "the boot script fails" bash -c '! bash /root/user_data.sh > /root/out 2>&1'
check "the failure is reported" grep -q 'preview router setup: FAILED' /root/out
check "the image's runner is untouched" grep -q v0.0.1 /usr/local/bin/runner
check "the router is never started" never_started

echo "a checksum that is not a digest is refused"
reset
release v9.9.9
echo '<html>Service Unavailable</html>' > /fixtures/checksum
check "the boot script fails" bash -c '! bash /root/user_data.sh > /root/out 2>&1'
check "the failure names the checksum" grep -q 'the release checksum is not a sha256 digest' /root/out
check "the image's runner is untouched" grep -q v0.0.1 /usr/local/bin/runner
check "the router is never started" never_started

echo "a runner that cannot run here stops the boot"
reset
printf '#!/bin/sh\nexit 126\n' > /fixtures/binary
printf '%s  runner-linux-amd64\n' "$(sha256sum /fixtures/binary | cut -d' ' -f1)" > /fixtures/checksum
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
