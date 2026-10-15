#!/usr/bin/env bash
# Runs `tofu init` and `tofu validate` on one shard of the modules, so CI can
# validate the shards in parallel jobs. Modules within a shard run one at a
# time: concurrent inits sharing a plugin cache can hang on its lock.
#
# Usage: validate-modules.sh <shard> <shards>
#   validate-modules.sh 0 1   validates every module
set -euo pipefail

shard="$1"
shards="$2"

modules=$(find . -mindepth 3 -maxdepth 3 -name versions.tf -exec dirname {} \; | sort |
  awk -v shard="${shard}" -v shards="${shards}" '(NR - 1) % shards == shard')

for module in ${modules}; do
  echo "Validating ${module}"
  tofu -chdir="${module}" init -backend=false -input=false
  tofu -chdir="${module}" validate
done
