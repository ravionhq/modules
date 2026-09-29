#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# The mock apply seeds state without AWS. The next run plans with the real AWS
# provider schema (refresh disabled), so ForceNew and create-before-destroy
# ordering appear in its verbose plan. HCL test assertions cannot inspect
# planned resource actions directly.
plan=$(tofu test -filter=tests/replacement_plan.tftest.hcl -verbose -no-color)

grep -Fq 'module.group.aws_autoscaling_group.this must be replaced' <<< "$plan"
grep -Fq '+/- create replacement and then destroy' <<< "$plan"
grep -Fq -- '-> "my-service-" # forces replacement' <<< "$plan"
grep -Fq 'Plan: 1 to add, 0 to change, 1 to destroy.' <<< "$plan"

echo 'ASG fixed-to-generated replacement plan passed.'
