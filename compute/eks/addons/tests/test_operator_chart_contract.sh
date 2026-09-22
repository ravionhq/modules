#!/usr/bin/env bash
# Verifies the cross-repository Operator chart contract that Terraform tests
# cannot see: executor resources come only from runtime policy, even when an
# upgrade carries obsolete resource fields in its stored Helm values.
#
# Usage:
#   OPERATOR_CHART_PATH=/path/to/ravion/packages/operator/chart/operator \
#     ./tests/test_operator_chart_contract.sh
set -euo pipefail

: "${OPERATOR_CHART_PATH:?Set OPERATOR_CHART_PATH to the Operator 0.5.11 chart directory}"

for tool in helm yq python3; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: ${tool} is required" >&2
    exit 1
  }
done

if [[ ! -f "${OPERATOR_CHART_PATH}/Chart.yaml" ]]; then
  echo "error: OPERATOR_CHART_PATH does not contain Chart.yaml: ${OPERATOR_CHART_PATH}" >&2
  exit 1
fi

chart_version="$(yq eval '.version' "${OPERATOR_CHART_PATH}/Chart.yaml")"
if [[ "${chart_version}" != "0.5.11" ]]; then
  echo "error: expected Operator chart 0.5.11, found ${chart_version}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cat >"${work_dir}/base.yaml" <<'YAML'
cluster:
  installationId: opagt_contract_test
  arn: arn:aws:eks:us-east-2:123456789012:cluster/contract-test
  name: contract-test
  region: us-east-2
deploy:
  enabled: true
executionJobs:
  enabled: true
  fullManagement: true
  image: public.ecr.aws/a8z1i1r2/operator@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
YAML

# Older releases documented these raw Helm fields. Chart 0.5.11 must accept
# stored upgrade values but omit them from the runtime JSON. Capacity ownership
# remains independent and must still reach the Operator.
cat >"${work_dir}/obsolete.yaml" <<'YAML'
executionJobs:
  maxConcurrent: 7
  settingsSource: local
  resourcesSource: local
  resources:
    requests:
      cpu: 375m
      memory: 640Mi
      ephemeral-storage: 2Gi
    limits:
      cpu: "3"
      memory: 4Gi
      ephemeral-storage: 24Gi
YAML

rendered="${work_dir}/rendered.yaml"
if ! helm template ravion-operator "${OPERATOR_CHART_PATH}" \
  --namespace ravion-operator \
  --values "${work_dir}/base.yaml" \
  --values "${work_dir}/obsolete.yaml" >"${rendered}"; then
  echo "error: failed to render Operator values with obsolete resource fields" >&2
  exit 1
fi

execution_json="$(yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "RVN_OPERATOR_EXECUTION_JOBS") | .value' "${rendered}")"
if [[ -z "${execution_json}" || "${execution_json}" == "null" ]]; then
  echo "error: render omitted RVN_OPERATOR_EXECUTION_JOBS" >&2
  exit 1
fi

python3 - "${execution_json}" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
obsolete_keys = [key for key in ("resources", "resourcesSource") if key in value]
if obsolete_keys:
    raise SystemExit(
        "RVN_OPERATOR_EXECUTION_JOBS retained obsolete resource fields: "
        + ", ".join(obsolete_keys)
    )
if value.get("maxConcurrent") != 7 or value.get("settingsSource") != "local":
    raise SystemExit(
        "capacity configuration changed while removing resource configuration\n"
        f"actual: {value!r}"
    )

print("ok: runtime JSON omits obsolete resources while preserving capacity configuration")
PY
