#!/usr/bin/env bash
# Verifies the cross-repository Operator chart contract that Terraform tests
# cannot see: values must survive the chart's RVN_OPERATOR_EXECUTION_JOBS JSON.
#
# Usage:
#   OPERATOR_CHART_PATH=/path/to/ravion/packages/operator/chart/operator \
#     ./tests/test_operator_chart_contract.sh
set -euo pipefail

: "${OPERATOR_CHART_PATH:?Set OPERATOR_CHART_PATH to the Operator 0.5.10 chart directory}"

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
if [[ "${chart_version}" != "0.5.10" ]]; then
  echo "error: expected Operator chart 0.5.10, found ${chart_version}" >&2
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

# This is the shape emitted by ravion_operator_execution_resources.
cat >"${work_dir}/typed.yaml" <<'YAML'
executionJobs:
  resourcesSource: local
  resources:
    requests:
      cpu: 250m
      memory: 384Mi
      ephemeral-storage: 1Gi
    limits:
      cpu: "2"
      memory: 3Gi
      ephemeral-storage: 20Gi
YAML

# This is an independent raw ravion_operator_helm_values override. Different
# quantities ensure the assertion is checking the override, not chart defaults.
cat >"${work_dir}/raw.yaml" <<'YAML'
executionJobs:
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

render_execution_json() {
  local case_name="$1"
  local values_file="$2"
  local rendered="${work_dir}/${case_name}-rendered.yaml"

  if ! helm template ravion-operator "${OPERATOR_CHART_PATH}" \
    --namespace ravion-operator \
    --values "${work_dir}/base.yaml" \
    --values "${values_file}" >"${rendered}"; then
    echo "error: failed to render ${case_name} Operator values" >&2
    return 1
  fi

  local execution_json
  execution_json="$(yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "RVN_OPERATOR_EXECUTION_JOBS") | .value' "${rendered}")"
  if [[ -z "${execution_json}" || "${execution_json}" == "null" ]]; then
    echo "error: ${case_name} render omitted RVN_OPERATOR_EXECUTION_JOBS" >&2
    return 1
  fi
  printf '%s\n' "${execution_json}"
}

assert_execution_json() {
  local case_name="$1"
  local execution_json="$2"
  local request_cpu="$3"
  local request_memory="$4"
  local request_storage="$5"
  local limit_cpu="$6"
  local limit_memory="$7"
  local limit_storage="$8"

  python3 - "${case_name}" "${execution_json}" \
    "${request_cpu}" "${request_memory}" "${request_storage}" \
    "${limit_cpu}" "${limit_memory}" "${limit_storage}" <<'PY'
import json
import sys

case_name, raw, request_cpu, request_memory, request_storage, limit_cpu, limit_memory, limit_storage = sys.argv[1:]
value = json.loads(raw)
expected = {
    "resourcesSource": "local",
    "resources": {
        "requests": {
            "cpu": request_cpu,
            "memory": request_memory,
            "ephemeral-storage": request_storage,
        },
        "limits": {
            "cpu": limit_cpu,
            "memory": limit_memory,
            "ephemeral-storage": limit_storage,
        },
    },
}

for key, expected_value in expected.items():
    if value.get(key) != expected_value:
        raise SystemExit(
            f"{case_name}: RVN_OPERATOR_EXECUTION_JOBS {key} mismatch\n"
            f"expected: {expected_value!r}\nactual:   {value.get(key)!r}"
        )

print(f"ok: {case_name} resourcesSource and resources reach RVN_OPERATOR_EXECUTION_JOBS")
PY
}

typed_json="$(render_execution_json typed "${work_dir}/typed.yaml")"
assert_execution_json typed "${typed_json}" 250m 384Mi 1Gi 2 3Gi 20Gi

raw_json="$(render_execution_json raw "${work_dir}/raw.yaml")"
assert_execution_json raw "${raw_json}" 375m 640Mi 2Gi 3 4Gi 24Gi
