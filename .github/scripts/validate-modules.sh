#!/usr/bin/env bash
# Runs `tofu init` and `tofu validate` on one shard of the modules, several at
# a time. Each module's output is printed in one block once it finishes, so
# parallel runs do not interleave, and the script fails if any module fails.
#
# Usage: validate-modules.sh <shard> <shards> [jobs]
#   validate-modules.sh 0 1 8   validates every module, 8 at a time
set -euo pipefail

shard="$1"
shards="$2"
jobs="${3:-4}"

validate() {
  local module="$1" output
  if output=$(tofu -chdir="${module}" init -backend=false -input=false -no-color 2>&1 &&
    tofu -chdir="${module}" validate -no-color 2>&1); then
    echo "ok      ${module}"
  else
    echo "::group::FAILED  ${module}"
    echo "${output}"
    echo "::endgroup::"
    echo "::error::${module} failed tofu init or validate"
    return 1
  fi
}
export -f validate

find . -mindepth 3 -maxdepth 3 -name versions.tf -exec dirname {} \; | sort |
  awk -v shard="${shard}" -v shards="${shards}" '(NR - 1) % shards == shard' |
  xargs -P "${jobs}" -I{} bash -c 'validate "$1"' _ {}
