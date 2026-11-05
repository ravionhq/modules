#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=0.38.0
source=github.com/terraform-linters/tflint-ruleset-aws
config=$(awk '/^plugin "aws" *\{/ { in_aws=1; next } in_aws && /^}/ { exit } in_aws { print }' "$root/.tflint.hcl")
configured_version=$(printf '%s\n' "$config" | awk '$1 == "version" { gsub(/"/, "", $3); print $3 }')
configured_source=$(printf '%s\n' "$config" | awk '$1 == "source" { gsub(/"/, "", $3); print $3 }')
if [[ "$configured_version" != "$version" || "$configured_source" != "$source" ]]; then
  echo "Update tools/install-tflint-aws.sh checksums to match .tflint.hcl before installing." >&2
  exit 1
fi

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    platform=linux_amd64
    archive_sha=e81212eef130a2bacd537e9159a65de6a6a1ab8b5cdbd1a5e919b60bee46b120
    binary_sha=bdea6c87e9962b80eb674d7d8e7bfab89ea72295664fa4fb83b371d4799beb2d ;;
  Linux/aarch64|Linux/arm64)
    platform=linux_arm64
    archive_sha=152fa903b84a39492070bec6f6f4b01490b9615a748064b393ab13fb65d8f9bf
    binary_sha=e2967af87e47fe589b2fe78666e92c0d9f5becc4f5b6bb0f8a6a480ef1ca82d8 ;;
  Darwin/x86_64)
    platform=darwin_amd64
    archive_sha=227fade2cc294f61c2234ac9d16993b3d291465228b221a6349db5a429a9fe4d
    binary_sha=55c88081059b9ee2e18e0bbd27ca11ac81085883f61cb98f19cb740e54432c47 ;;
  Darwin/arm64)
    platform=darwin_arm64
    archive_sha=d2e023494e20814a806d442365d37e0b4f856de4c3f85211321abb883e126ff2
    binary_sha=fa8e3a5751511227354fe23f06a2923525b86061fea35fe8b457285b75d4c507 ;;
  *) echo "Unsupported platform; use authenticated tflint --init." >&2; exit 1 ;;
esac

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

plugin_root=${TFLINT_PLUGIN_DIR:-$HOME/.tflint.d/plugins}
if [[ -z "${TFLINT_PLUGIN_DIR:-}" && -d "$root/.tflint.d/plugins" ]]; then
  plugin_root="$root/.tflint.d/plugins"
fi
destination="$plugin_root/$source/$version/tflint-ruleset-aws"
if [[ -x "$destination" && "$(sha "$destination")" == "$binary_sha" ]]; then
  echo "AWS TFLint plugin $version is cached and verified."
  exit 0
fi

# Pinned release checksums avoid GitHub's unauthenticated release-metadata API.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
curl --fail --silent --show-error --location --retry 3 --max-time 120 \
  "https://$source/releases/download/v$version/tflint-ruleset-aws_$platform.zip" \
  --output "$scratch/plugin.zip"
if [[ "$(sha "$scratch/plugin.zip")" != "$archive_sha" ]]; then
  echo "TFLint plugin archive checksum mismatch; nothing installed." >&2
  exit 1
fi
unzip -p "$scratch/plugin.zip" tflint-ruleset-aws > "$scratch/plugin"
if [[ "$(sha "$scratch/plugin")" != "$binary_sha" ]]; then
  echo "TFLint plugin binary checksum mismatch; nothing installed." >&2
  exit 1
fi
mkdir -p "$(dirname "$destination")"
staging=$(mktemp "$(dirname "$destination")/.install-XXXXXX")
trap 'rm -rf "$scratch"; rm -f "$staging"' EXIT
install -m 0755 "$scratch/plugin" "$staging"
mv -f "$staging" "$destination"
echo "Installed verified AWS TFLint plugin $version."
