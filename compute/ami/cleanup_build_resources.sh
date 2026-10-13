#!/usr/bin/env bash
set -euo pipefail

log() { printf 'AMI build cleanup: %s\n' "$*"; }
fail() { log "$*" >&2; exit 1; }

if [[ -z "${MODULE_INSTANCE_ID:-}" ]]; then
  log "No module_instance_id; retained build resources require manual cleanup."
  exit 0
fi

: "${AWS_REGION:?Build region is required}"
: "${AWS_ACCOUNT_ID:?AWS account is required}"
for tool in aws jq; do
  command -v "$tool" >/dev/null || fail "$tool is required on the destroy runner"
done
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

account=$(aws sts get-caller-identity --region "$AWS_REGION" --output json | jq -er '.Account')
[[ "$account" == "$AWS_ACCOUNT_ID" ]] || fail "CLI account $account does not match state account $AWS_ACCOUNT_ID"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ib() { aws imagebuilder "$@" --region "$AWS_REGION" --output json; }

# AWS CLI JSON output aggregates all pages. Discover everything before deleting.
ib list-images --owner Self --include-deprecated > "$work/images.json"
jq -r '.imageVersionList[].arn' "$work/images.json" > "$work/image-versions"
: > "$work/images"
while IFS= read -r arn; do
  ib list-image-build-versions --image-version-arn "$arn" > "$work/builds.json"
  jq --arg id "$MODULE_INSTANCE_ID" '[.imageSummaryList[] | select(.tags.ModuleId == $id)]' \
    "$work/builds.json" > "$work/owned-builds.json"
  if ! jq -e 'all(.[]; .state.status as $s | ["AVAILABLE", "FAILED", "CANCELLED", "DEPRECATED", "DISABLED", "DELETED"] | index($s) != null)' \
    "$work/owned-builds.json" >/dev/null; then
    jq -r '.[] | "\(.arn): \(.state.status)"' "$work/owned-builds.json" >&2
    fail "A build is active or has an unknown status. Stop deployments and retry after builds finish."
  fi
  jq -r '.[].arn' "$work/owned-builds.json" >> "$work/images"
done < "$work/image-versions"

ib list-image-recipes --owner Self > "$work/recipes.json"
jq -r --arg id "$MODULE_INSTANCE_ID" '.imageRecipeSummaryList[] | select(.tags.ModuleId == $id) | .arn' \
  "$work/recipes.json" > "$work/recipes"

ib list-components --owner Self > "$work/components.json"
jq -r '.componentVersionList[].arn' "$work/components.json" > "$work/component-versions"
: > "$work/components"
while IFS= read -r arn; do
  ib list-component-build-versions --component-version-arn "$arn" > "$work/builds.json"
  jq -r --arg id "$MODULE_INSTANCE_ID" '.componentSummaryList[] |
    select(.tags.ModuleId == $id and .tags.Module == "compute/ami" and .tags.ManagedBy == "terraform") | .arn' \
    "$work/builds.json" >> "$work/components"
done < "$work/component-versions"

delete_resource() {
  local operation=$1 flag=$2 arn=$3
  log "$operation $arn"
  if ib "$operation" "$flag" "$arn" > /dev/null 2> "$work/error"; then
    return
  fi
  # A retried, partially completed destroy may find an object already gone.
  if grep -q 'ResourceNotFoundException' "$work/error"; then
    return
  fi
  cat "$work/error" >&2
  fail "Could not delete $arn. Resolve its dependency or permission error, then retry destroy."
}

# DeleteImage removes only Image Builder metadata, never EC2 AMIs or snapshots.
while IFS= read -r arn; do
  delete_resource delete-image --image-build-version-arn "$arn"
done < "$work/images"
while IFS= read -r arn; do
  delete_resource delete-image-recipe --image-recipe-arn "$arn"
done < "$work/recipes"
while IFS= read -r arn; do
  delete_resource delete-component --component-build-version-arn "$arn"
done < "$work/components"
log "Finished; EC2 AMIs, snapshots, and running instances were not deleted."
