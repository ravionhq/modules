#!/usr/bin/env bash
#
# Lint + template tests for the Ravion application charts.
#
# No cluster is required: every assertion is made against `helm template`
# output. Requires helm >= 3.14 and yq >= 4.
#
#   ./charts/test.sh              # all charts
#   ./charts/test.sh rvn-eks-web  # one chart
#
# Rendered output is collected into a single YAML array document so that a
# query sees every manifest at once; expressions are therefore written against
# that array (`.[] | select(.kind == "Deployment")`).
#
set -euo pipefail

CHARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_CHARTS=(rvn-eks-web rvn-eks-worker rvn-eks-cron karpenter-resources warm-capacity ebs-storage)
if [[ $# -gt 0 ]]; then
  CHARTS=("$@")
else
  CHARTS=("${ALL_CHARTS[@]}")
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PASS=0
FAIL=0

for tool in helm yq; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: ${tool} is required but not installed" >&2
    exit 1
  }
done

# Where a chart lives. Service charts sit next to this script; the add-ons
# module carries its own charts and they are tested from here too.
chart_path() {
  case "$1" in
    karpenter-resources | warm-capacity | ebs-storage) echo "${CHARTS_DIR}/../compute/eks/addons/charts/$1" ;;
    *) echo "${CHARTS_DIR}/$1" ;;
  esac
}

pass() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
  printf '         expected: %s\n' "$2"
  printf '         actual:   %s\n' "$3"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    pass "${desc}"
  else
    fail "${desc}" "${expected}" "${actual}"
  fi
}

# Renders a chart into ${WORK_DIR} as a single array document; echoes the path.
# Usage: render <chart> <label> [helm args...]
render() {
  local chart="$1" label="$2"
  shift 2
  local out="${WORK_DIR}/${chart}-${label}.yaml"
  helm template test-release "$(chart_path "${chart}")" "$@" |
    yq ea '[.] | map(select(. != null))' >"${out}"
  echo "${out}"
}

# Asserts that Helm rejects values for a chart.
expect_template_failure() {
  local chart="$1" desc="$2"
  shift 2
  if helm template test-release "$(chart_path "${chart}")" "$@" >"${WORK_DIR}/expected-failure.out" 2>&1; then
    fail "${desc}" "render rejected the values" "render succeeded"
  else
    pass "${desc}"
  fi
}

# Queries a rendered manifest array. Usage: q <file> <expression>
# Prints an empty string rather than "null" when the path is absent.
q() {
  local file="$1" expr="$2"
  local value
  value="$(yq eval "${expr}" "${file}" | tr -d '\r')"
  [[ "${value}" == "null" ]] && value=""
  echo "${value}"
}

# Number of manifests of a given kind. Usage: count <file> <kind>
count() {
  q "$1" "[.[] | select(.kind == \"$2\")] | length"
}

assert_json_unique_keys() {
  python3 - "$1" <<'PY'
import json
import sys

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

with open(sys.argv[1], encoding="utf-8") as stream:
    json.load(stream, object_pairs_hook=unique_object)
PY
}

################################################################################
# helm lint — every chart against every ci/*-values.yaml
################################################################################

lint_chart() {
  local chart="$1"
  local schema
  schema="$(chart_path "${chart}")/values.schema.json"
  if [[ -f "${schema}" ]]; then
    if assert_json_unique_keys "${schema}" >"${WORK_DIR}/schema-keys.out" 2>&1; then
      pass "schema ${chart} has no duplicate JSON keys"
    else
      fail "schema ${chart} has no duplicate JSON keys" "unique object keys" "$(cat "${WORK_DIR}/schema-keys.out")"
    fi
  fi
  for values in "$(chart_path "${chart}")"/ci/*-values.yaml; do
    local label
    label="$(basename "${values}")"
    if helm lint "$(chart_path "${chart}")" --values "${values}" >"${WORK_DIR}/lint.out" 2>&1; then
      pass "lint ${chart} (${label})"
    else
      fail "lint ${chart} (${label})" "exit 0" "$(cat "${WORK_DIR}/lint.out")"
    fi
  done
}

################################################################################
# KEDA-backed Spot burst shared by the web and worker charts.
################################################################################

test_spot_burst_chart() {
  local chart="$1"
  local values="${CHARTS_DIR}/${chart}/ci/spot-burst-values.yaml"
  local base_name="test-release-${chart}"
  local spot_name="${base_name}-spot"
  local burst_args=(--values "${values}" --set autoscaling.enabled=true)
  if [[ "${chart}" == "rvn-eks-web" ]]; then
    burst_args+=(--set networkPolicy.enabled=true)
  fi

  local burst
  burst="$(render "${chart}" spot-burst "${burst_args[@]}")"
  local baseline='.[] | select(.kind == "Deployment") | select(.metadata.name == "'"${base_name}"'")'
  local spot='.[] | select(.kind == "Deployment") | select(.metadata.name == "'"${spot_name}"'")'
  local scaled='.[] | select(.kind == "ScaledObject")'

  assert_eq "${chart}: burst mode renders a baseline and Spot Deployment" \
    "2" "$(count "${burst}" Deployment)"
  assert_eq "${chart}: burst mode creates the Spot Deployment at zero, including an upgrade render" \
    "0" "$(q "$(render "${chart}" spot-upgrade --values "${values}" --is-upgrade)" \
      '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .spec.replicas')"
  assert_eq "${chart}: baseline keeps its stable release name and fixed replica floor" \
    "3" "$(q "${burst}" "${baseline} | .spec.replicas")"
  assert_eq "${chart}: Spot Deployment name ends in -spot" \
    "${spot_name}" "$(q "${burst}" "${spot} | .metadata.name")"
  assert_eq "${chart}: Spot Deployment selector uses a distinct app name" \
    "${chart}-spot" "$(q "${burst}" "${spot} | .spec.selector.matchLabels.\"app.kubernetes.io/name\"")"
  assert_eq "${chart}: Spot Deployment and ScaledObject target names agree" \
    "${spot_name}" "$(q "${burst}" "${scaled} | .spec.scaleTargetRef.name")"
  assert_eq "${chart}: no CPU/memory HPA competes with KEDA" \
    "0" "$(count "${burst}" HorizontalPodAutoscaler)"
  assert_eq "${chart}: one KEDA ScaledObject is rendered" \
    "1" "$(count "${burst}" ScaledObject)"
  assert_eq "${chart}: KEDA may scale the Spot Deployment from zero" \
    "0 8 30 300" \
    "$(q "${burst}" "${scaled} | [.spec.minReplicaCount, .spec.maxReplicaCount, .spec.pollingInterval, .spec.cooldownPeriod] | join(\" \")")"
  assert_eq "${chart}: KEDA scale-down stabilization and restore policy are fixed" \
    "300 false" \
    "$(q "${burst}" "${scaled} | [.spec.advanced.horizontalPodAutoscalerConfig.behavior.scaleDown.stabilizationWindowSeconds, .spec.advanced.restoreToOriginalReplicaCount] | join(\" \")")"
  assert_eq "${chart}: scaler receives the configured external trigger unchanged" \
    "prometheus vector(0)" \
    "$(q "${burst}" "${scaled} | [.spec.triggers[0].type, .spec.triggers[0].metadata.query] | join(\" \")")"
  local utilization
  utilization="$(render "${chart}" utilization-metric-type --values "${values}" \
    --set-json 'spotBurst.triggers=[{"type":"prometheus","metadata":{"serverAddress":"http://example.invalid:9090","query":"vector(0)","threshold":"1","activationThreshold":"0","ignoreNullValues":"false"},"metricType":"Utilization"}]')"
  assert_eq "${chart}: KEDA Utilization metric type survives schema validation and rendering" \
    "Utilization" "$(q "${utilization}" '.[] | select(.kind == "ScaledObject") | .spec.triggers[0].metricType')"
  assert_eq "${chart}: baseline and Spot pods use the same image" \
    "1" \
    "$(q "${burst}" "[.[] | select(.kind == \"Deployment\") | .spec.template.spec.containers[0].image] | unique | length")"
  assert_eq "${chart}: pod environment is shared across both pools" \
    "1" \
    "$(q "${burst}" "[.[] | select(.kind == \"Deployment\") | .spec.template.spec.containers[0].env] | unique | length")"
  assert_eq "${chart}: both pools use the same ServiceAccount" \
    "test-release-${chart}" \
    "$(q "${burst}" "[.[] | select(.kind == \"Deployment\") | .spec.template.spec.serviceAccountName] | unique | join(\" \")")"
  assert_eq "${chart}: both pool pods carry the EC2 compute annotation" \
    "ec2" \
    "$(q "${burst}" "[.[] | select(.kind == \"Deployment\") | .spec.template.metadata.annotations.\"eks.amazonaws.com/compute-type\"] | unique | join(\" \")")"
  assert_eq "${chart}: custom pod annotations remain present" \
    "retained" \
    "$(q "${burst}" "${baseline} | .spec.template.metadata.annotations.\"example.com/test-annotation\"")"
  assert_eq "${chart}: user pod labels cannot replace reserved identity or pool labels" \
    "rvn-eks-${chart#rvn-eks-} test-release baseline ${chart}-spot test-release spot" \
    "$(q "${burst}" "${baseline} | [.spec.template.metadata.labels.\"app.kubernetes.io/name\", .spec.template.metadata.labels.\"app.kubernetes.io/instance\", .spec.template.metadata.labels.\"ravion.com/spot-burst-pool\"] | join(\" \")") $(q "${burst}" "${spot} | [.spec.template.metadata.labels.\"app.kubernetes.io/name\", .spec.template.metadata.labels.\"app.kubernetes.io/instance\", .spec.template.metadata.labels.\"ravion.com/spot-burst-pool\"] | join(\" \")")"
  assert_eq "${chart}: non-reserved user pod labels remain present" \
    "retained" "$(q "${burst}" "${spot} | .spec.template.metadata.labels.\"example.com/test-label\"")"
  assert_eq "${chart}: baseline spread is scoped to the baseline pool" \
    "baseline" \
    "$(q "${burst}" "${baseline} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.\"ravion.com/spot-burst-pool\"")"
  assert_eq "${chart}: Spot spread is scoped to the Spot pool" \
    "spot" \
    "$(q "${burst}" "${spot} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.\"ravion.com/spot-burst-pool\"")"
  assert_eq "${chart}: Spot spread selector matches the Spot app name" \
    "${chart}-spot" \
    "$(q "${burst}" "${spot} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.\"app.kubernetes.io/name\"")"
  assert_eq "${chart}: each pool gets separate required affinity terms" \
    "4 4" \
    "$(q "${burst}" "${baseline} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms | length") $(q "${burst}" "${spot} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms | length")"
  assert_eq "${chart}: On-Demand terms admit managed and Karpenter capacity labels only" \
    "ON_DEMAND on-demand" \
    "$(q "${burst}" "[${baseline} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[] | select(.key == \"eks.amazonaws.com/capacityType\") | .values[0]] | unique | join(\" \")") $(q "${burst}" "[${baseline} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[] | select(.key == \"karpenter.sh/capacity-type\") | .values[0]] | unique | join(\" \")")"
  assert_eq "${chart}: Spot terms admit managed and Karpenter capacity labels only" \
    "SPOT spot" \
    "$(q "${burst}" "[${spot} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[] | select(.key == \"eks.amazonaws.com/capacityType\") | .values[0]] | unique | join(\" \")") $(q "${burst}" "[${spot} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[] | select(.key == \"karpenter.sh/capacity-type\") | .values[0]] | unique | join(\" \")")"
  assert_eq "${chart}: user hardware requirements apply to all expanded terms" \
    "c8a.xlarge test-node" \
    "$(q "${burst}" "[${spot} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions[] | select(.key == \"kubernetes.io/instance-type\") | .values[0]] | unique | join(\" \")") $(q "${burst}" "[${spot} | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchFields[] | select(.key == \"metadata.name\") | .values[0]] | unique | join(\" \")")"
  assert_eq "${chart}: preferred node and pod affinities are preserved" \
    "1 example" \
    "$(q "${burst}" "${spot} | .spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution | length") $(q "${burst}" "${spot} | .spec.template.spec.affinity.podAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchLabels.app")"
  assert_eq "${chart}: PDB is baseline-only and uses the fixed baseline floor" \
    "1 rvn-eks-${chart#rvn-eks-} test-release" \
    "$(count "${burst}" PodDisruptionBudget) $(q "${burst}" '.[] | select(.kind == "PodDisruptionBudget") | [.spec.selector.matchLabels."app.kubernetes.io/name", .spec.selector.matchLabels."app.kubernetes.io/instance"] | join(" ")')"
  assert_eq "${chart}: no Spot pool label is added to the baseline-only PDB" \
    "" "$(q "${burst}" '.[] | select(.kind == "PodDisruptionBudget") | .spec.selector.matchLabels."ravion.com/spot-burst-pool"')"

  local explicit_spread
  explicit_spread="$(render "${chart}" explicit-spot-spread --values "${values}" \
    --set-json 'topologySpreadConstraints=[{"maxSkew":2,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway","labelSelector":{"matchLabels":{"custom":"value"}}}]')"
  assert_eq "${chart}: explicit user spread selectors are not rewritten" \
    "value" "$(q "${explicit_spread}" "${spot} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.custom")"
  assert_eq "${chart}: explicit spread is not silently made pool-specific" \
    "" "$(q "${explicit_spread}" "${spot} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.\"ravion.com/spot-burst-pool\"")"

  local disabled long_name long_first long_second override_case
  disabled="$(render "${chart}" disabled-stale-values --values "${values}" \
    --set spotBurst.enabled=false --set spotBurst.baselineReplicas=7 --set autoscaling.enabled=true)"
  assert_eq "${chart}: disabled burst ignores stale settings and restores ordinary HPA" \
    "1 1 0" \
    "$(count "${disabled}" Deployment) $(count "${disabled}" HorizontalPodAutoscaler) $(count "${disabled}" ScaledObject)"
  assert_eq "${chart}: inactive burst baseline stays under ordinary autoscaling" \
    "" "$(q "${disabled}" '.[] | select(.kind == "Deployment") | .spec.replicas')"

  long_name="spot-burst-fullname-override-that-is-longer-than-sixty-three-characters"
  long_first="$(render "${chart}" long-spot-name --values "${values}" --set "nameOverride=${long_name}")"
  long_second="$(render "${chart}" long-spot-name-repeat --values "${values}" --set "nameOverride=${long_name}")"
  local long_baseline_name hashed_spot_name
  long_baseline_name="$(q "${long_first}" '.[] | select(.kind == "Deployment") | select((.metadata.name | test("-spot$")) | not) | .metadata.name')"
  hashed_spot_name="$(q "${long_first}" '.[] | select(.kind == "Deployment") | select(.metadata.name | test("-spot$")) | .metadata.name')"
  assert_eq "${chart}: long Spot Deployment names fit the Kubernetes 63-character limit" \
    "63" "${#hashed_spot_name}"
  assert_eq "${chart}: long Spot name retains the -spot suffix" \
    "true" "$([[ "${hashed_spot_name}" == *-spot ]] && echo true || echo false)"
  if [[ "${hashed_spot_name}" =~ -[a-f0-9]{8}-spot$ ]]; then
    pass "${chart}: long Spot name includes a deterministic hash"
  else
    fail "${chart}: long Spot name includes a deterministic hash" "8 lowercase hex digits before -spot" "${hashed_spot_name}"
  fi
  assert_eq "${chart}: long-name Spot hashes are deterministic" \
    "${hashed_spot_name}" "$(q "${long_second}" '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .metadata.name')"
  if [[ "${long_baseline_name}" == "${hashed_spot_name}" ]]; then
    fail "${chart}: long Spot and baseline names remain distinct" "different names" "${long_baseline_name}"
  else
    pass "${chart}: long Spot and baseline names remain distinct"
  fi
  local long_baseline_selector long_spot_selector
  long_baseline_selector="$(q "${long_first}" '.[] | select(.kind == "Deployment") | select((.metadata.name | test("-spot$")) | not) | .spec.selector.matchLabels."app.kubernetes.io/name"')"
  long_spot_selector="$(q "${long_first}" '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .spec.selector.matchLabels."app.kubernetes.io/name"')"
  if [[ ${#long_spot_selector} -le 63 ]]; then
    pass "${chart}: long Spot selector name fits the Kubernetes 63-character limit"
  else
    fail "${chart}: long Spot selector name fits the Kubernetes 63-character limit" "at most 63" "${#long_spot_selector}"
  fi
  if [[ "${long_spot_selector}" =~ -[a-f0-9]{8}-spot$ ]]; then
    pass "${chart}: long Spot selector retains its deterministic hash"
  else
    fail "${chart}: long Spot selector retains its deterministic hash" "8 lowercase hex digits before -spot" "${long_spot_selector}"
  fi
  assert_eq "${chart}: long baseline selector matches its pod label" \
    "${long_baseline_selector}" "$(q "${long_first}" '.[] | select(.kind == "Deployment") | select((.metadata.name | test("-spot$")) | not) | .spec.template.metadata.labels."app.kubernetes.io/name"')"
  assert_eq "${chart}: long Spot selector matches its pod label and spread selector" \
    "${long_spot_selector} ${long_spot_selector}" "$(q "${long_first}" '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .spec.template.metadata.labels."app.kubernetes.io/name"') $(q "${long_first}" '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels."app.kubernetes.io/name"')"
  assert_eq "${chart}: long Spot selector is distinct from the baseline selector" \
    "true" "$([[ "${long_baseline_selector}" != "${long_spot_selector}" ]] && echo true || echo false)"
  assert_eq "${chart}: long Spot selector hash is deterministic" \
    "${long_spot_selector}" "$(q "${long_second}" '.[] | select(.kind == "Deployment" and (.metadata.name | test("-spot$"))) | .spec.selector.matchLabels."app.kubernetes.io/name"')"

  override_case="$(render "${chart}" selector-name-override --values "${values}" \
    --set fullnameOverride=api --set nameOverride=api-spot)"
  local override_baseline='.[] | select(.kind == "Deployment" and .metadata.name == "api")'
  local override_spot='.[] | select(.kind == "Deployment" and .metadata.name == "api-spot")'
  assert_eq "${chart}: fullname/name override baseline selector remains stable" \
    "api-spot" "$(q "${override_case}" "${override_baseline} | .spec.selector.matchLabels.\"app.kubernetes.io/name\"")"
  assert_eq "${chart}: fullname/name override baseline pod matches its selector" \
    "api-spot" "$(q "${override_case}" "${override_baseline} | .spec.template.metadata.labels.\"app.kubernetes.io/name\"")"
  assert_eq "${chart}: fullname/name override Spot selector derives from baseline name" \
    "api-spot-spot" "$(q "${override_case}" "${override_spot} | .spec.selector.matchLabels.\"app.kubernetes.io/name\"")"
  assert_eq "${chart}: fullname/name override Spot selector matches pod and spread selectors" \
    "api-spot-spot api-spot-spot" "$(q "${override_case}" "${override_spot} | .spec.template.metadata.labels.\"app.kubernetes.io/name\"") $(q "${override_case}" "${override_spot} | .spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels.\"app.kubernetes.io/name\"")"

  expect_template_failure "${chart}" "${chart}: burst requires at least one external trigger" \
    --values "${values}" --set-json 'spotBurst.triggers=[]'
  expect_template_failure "${chart}" "${chart}: CPU-only trigger cannot wake a zero-replica Deployment" \
    --values "${values}" --set-json 'spotBurst.triggers=[{"type":"cpu","metadata":{"value":"80"}}]'
  expect_template_failure "${chart}" "${chart}: CPU and memory triggers alone cannot wake a zero-replica Deployment" \
    --values "${values}" --set-json 'spotBurst.triggers=[{"type":"cpu","metadata":{"value":"80"}},{"type":"memory","metadata":{"value":"80"}}]'
  expect_template_failure "${chart}" "${chart}: baseline replicas must be at least one" \
    --values "${values}" --set spotBurst.baselineReplicas=0
  expect_template_failure "${chart}" "${chart}: trigger metadata values must be strings" \
    --values "${values}" --set-json 'spotBurst.triggers=[{"type":"prometheus","metadata":{"threshold":1}}]'
  expect_template_failure "${chart}" "${chart}: unsupported TriggerAuthentication kind is rejected" \
    --values "${values}" --set-json 'spotBurst.triggers=[{"type":"prometheus","metadata":{"threshold":"1"},"authenticationRef":{"name":"test-auth","kind":"Other"}}]'
  if helm template test-release "$(chart_path "${chart}")" --values "${values}" \
    --set spotBurst.kedaEnabled=false >"${WORK_DIR}/missing-keda.out" 2>&1; then
    fail "${chart}: burst requires KEDA add-on" "clear prerequisite error" "render succeeded"
  elif rg -q "requires KEDA to be installed by rvn-eks-addons" "${WORK_DIR}/missing-keda.out"; then
    pass "${chart}: burst requires KEDA add-on"
  else
    fail "${chart}: burst requires KEDA add-on" "clear prerequisite error" "$(cat "${WORK_DIR}/missing-keda.out")"
  fi
}

################################################################################
# rvn-eks-web
################################################################################

test_rvn_eks_web() {
  local chart=rvn-eks-web
  local default full
  default="$(render "${chart}" default --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml")"
  full="$(render "${chart}" full --values "${CHARTS_DIR}/${chart}/ci/full-values.yaml")"

  local dep='.[] | select(.kind == "Deployment")'
  local ctr="${dep} | .spec.template.spec.containers[0]"
  local sa='.[] | select(.kind == "ServiceAccount")'
  local tgb0='.[] | select(.kind == "TargetGroupBinding") | select(.metadata.name == "test-release-rvn-eks-web-0")'
  local hpa='.[] | select(.kind == "HorizontalPodAutoscaler")'

  # --- container-only happy path: image, port, probes, resources, env -------
  assert_eq "web: image maps repository:tag" \
    "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo-web:v1.2.3" \
    "$(q "${default}" "${ctr} | .image")"
  assert_eq "web: containerPort maps to the http port" \
    "3000" "$(q "${default}" "${ctr} | .ports[0].containerPort")"
  assert_eq "web: container port is named http" \
    "http" "$(q "${default}" "${ctr} | .ports[0].name")"
  assert_eq "web: liveness probe uses the configured path" \
    "/healthz" "$(q "${default}" "${ctr} | .livenessProbe.httpGet.path")"
  assert_eq "web: readiness probe defaults its port to the http port" \
    "http" "$(q "${default}" "${ctr} | .readinessProbe.httpGet.port")"
  assert_eq "web: probe timings come from values" \
    "10 10 5 3" \
    "$(q "${default}" "${ctr} | .livenessProbe | [.initialDelaySeconds, .periodSeconds, .timeoutSeconds, .failureThreshold] | join(\" \")")"
  assert_eq "web: readiness defaults to every second with about 30 seconds of failure tolerance" \
    "0 1 5 30" \
    "$(q "${default}" "${ctr} | .readinessProbe | [.initialDelaySeconds, .periodSeconds, .timeoutSeconds, .failureThreshold] | join(\" \")")"
  local fast_rollout
  fast_rollout="$(render "${chart}" fast-rollout --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml" --set probes.readiness.initialDelaySeconds=0 --set probes.readiness.periodSeconds=1)"
  assert_eq "web: fast rollout readiness and surge settings render exactly" \
    "0 1 100% 0" \
    "$(q "${fast_rollout}" "${ctr} | .readinessProbe.initialDelaySeconds") $(q "${fast_rollout}" "${ctr} | .readinessProbe.periodSeconds") $(q "${fast_rollout}" "${dep} | .spec.strategy.rollingUpdate.maxSurge") $(q "${fast_rollout}" "${dep} | .spec.strategy.rollingUpdate.maxUnavailable")"
  assert_eq "web: startup probe is off by default" \
    "" "$(q "${default}" "${ctr} | .startupProbe")"
  assert_eq "web: startup probe renders when enabled" \
    "/startup" "$(q "${full}" "${ctr} | .startupProbe.httpGet.path")"
  assert_eq "web: resource requests are rendered" \
    "100m" "$(q "${default}" "${ctr} | .resources.requests.cpu")"
  assert_eq "web: resource limits are rendered" \
    "512Mi" "$(q "${default}" "${ctr} | .resources.limits.memory")"
  assert_eq "web: plain env entries are mapped in order" \
    "LOG_LEVEL PORT" "$(q "${default}" "[${ctr} | .env[].name] | join(\" \")")"
  assert_eq "web: plain env values are rendered as strings" \
    "info" "$(q "${default}" "${ctr} | .env[0].value")"
  assert_eq "web: command and args are passed through" \
    "/bin/app serve --port=3000" \
    "$(q "${full}" "${ctr} | ((.command + .args) | join(\" \"))")"
  assert_eq "web: a ClusterIP Service is rendered" \
    "ClusterIP" "$(q "${default}" '.[] | select(.kind == "Service") | .spec.type')"
  assert_eq "web: Service targets the named container port" \
    "http" "$(q "${default}" '.[] | select(.kind == "Service") | .spec.ports[0].targetPort')"
  assert_eq "web: two replicas by default, so one pod stopping is never an outage" \
    "2" "$(q "${default}" "${dep} | .spec.replicas")"

  # --- ServiceAccount / Pod Identity ---------------------------------------
  assert_eq "web: ServiceAccount name defaults to the fullname" \
    "test-release-rvn-eks-web" "$(q "${default}" "${sa} | .metadata.name")"
  assert_eq "web: pod uses the chart's ServiceAccount" \
    "test-release-rvn-eks-web" \
    "$(q "${default}" "${dep} | .spec.template.spec.serviceAccountName")"
  assert_eq "web: no IRSA role-arn annotation (Pod Identity binds by name)" \
    "" "$(q "${default}" "${sa} | .metadata.annotations.\"eks.amazonaws.com/role-arn\"")"
  assert_eq "web: serviceAccount.name overrides the default" \
    "demo-web" "$(q "${full}" "${sa} | .metadata.name")"
  assert_eq "web: pod uses the overridden ServiceAccount name" \
    "demo-web" "$(q "${full}" "${dep} | .spec.template.spec.serviceAccountName")"

  # --- image digest wins over tag ------------------------------------------
  assert_eq "web: digest pins the image instead of a tag" \
    "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo-web@sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    "$(q "${full}" "${ctr} | .image")"

  # --- no Ingress, ever ----------------------------------------------------
  assert_eq "web: never renders an Ingress (Terraform owns the listener rule)" \
    "0" "$(count "${full}" Ingress)"

  # --- TargetGroupBinding present iff a target group ARN is supplied -------
  assert_eq "web: no TargetGroupBinding when targetGroupArns is empty" \
    "0" "$(count "${default}" TargetGroupBinding)"
  assert_eq "web: one TargetGroupBinding per supplied ARN" \
    "2" "$(count "${full}" TargetGroupBinding)"
  assert_eq "web: TargetGroupBinding carries the supplied ARN" \
    "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/demo-web-tg-1/abc123" \
    "$(q "${full}" "${tgb0} | .spec.targetGroupARN")"
  assert_eq "web: TargetGroupBinding points at the chart's Service and port" \
    "test-release-rvn-eks-web 80" \
    "$(q "${full}" "${tgb0} | [.spec.serviceRef.name, .spec.serviceRef.port] | join(\" \")")"
  assert_eq "web: TargetGroupBinding targets pod IPs" \
    "ip" "$(q "${full}" "${tgb0} | .spec.targetType")"

  # --- HPA toggling ---------------------------------------------------------
  assert_eq "web: no HPA by default" \
    "0" "$(count "${default}" HorizontalPodAutoscaler)"
  assert_eq "web: HPA rendered when autoscaling.enabled" \
    "1" "$(count "${full}" HorizontalPodAutoscaler)"
  assert_eq "web: HPA min/max come from values" \
    "2 20" "$(q "${full}" "${hpa} | [.spec.minReplicas, .spec.maxReplicas] | join(\" \")")"
  assert_eq "web: HPA carries both cpu and memory metrics when set" \
    "cpu memory" "$(q "${full}" "${hpa} | [.spec.metrics[].resource.name] | join(\" \")")"
  assert_eq "web: HPA targets the chart's Deployment" \
    "Deployment test-release-rvn-eks-web" \
    "$(q "${full}" "${hpa} | [.spec.scaleTargetRef.kind, .spec.scaleTargetRef.name] | join(\" \")")"
  assert_eq "web: Deployment omits replicas when the HPA owns scale" \
    "" "$(q "${full}" "${dep} | .spec.replicas")"

  # --- zone-local routing (on by default) -----------------------------------
  local svc='.[] | select(.kind == "Service")'
  local tsc="${dep} | .spec.template.spec.topologySpreadConstraints"
  assert_eq "web: Service prefers same-zone endpoints by default" \
    "PreferClose" "$(q "${default}" "${svc} | .spec.trafficDistribution")"
  assert_eq "web: default zone spread constraint is rendered" \
    "1 topology.kubernetes.io/zone ScheduleAnyway" \
    "$(q "${default}" "${tsc}[0] | [.maxSkew, .topologyKey, .whenUnsatisfiable] | join(\" \")")"
  assert_eq "web: default zone spread selects this chart's pods" \
    "rvn-eks-web test-release" \
    "$(q "${default}" "${tsc}[0].labelSelector.matchLabels | [.\"app.kubernetes.io/name\", .\"app.kubernetes.io/instance\"] | join(\" \")")"
  assert_eq "web: default node spread keeps replicas off a single node" \
    "1 kubernetes.io/hostname ScheduleAnyway" \
    "$(q "${default}" "${tsc}[1] | [.maxSkew, .topologyKey, .whenUnsatisfiable] | join(\" \")")"
  assert_eq "web: explicit topologySpreadConstraints replace the default" \
    "1 kubernetes.io/hostname" \
    "$(q "${full}" "${tsc} | [length, .[0].topologyKey] | join(\" \")")"
  local zone_off
  zone_off="$(render "${chart}" zone-off --values "${CHARTS_DIR}/${chart}/ci/zone-routing-off-values.yaml")"
  assert_eq "web: trafficDistribution is omitted when set to empty" \
    "" "$(q "${zone_off}" "${svc} | .spec.trafficDistribution")"
  assert_eq "web: no spread constraint when topologySpread is disabled" \
    "" "$(q "${zone_off}" "${tsc}")"

  test_secrets_contract "${chart}" "${full}" "${default}" Deployment

  # --- single-provider secrets: no reference to the unused store ------------
  local ssm_only
  ssm_only="$(render "${chart}" ssm-only --values "${CHARTS_DIR}/${chart}/ci/parameter-store-only-values.yaml")"
  local es='.[] | select(.kind == "ExternalSecret")'
  assert_eq "web: parameterStore-only secrets default the store to the SSM store" \
    "ravion-aws-parameter-store ClusterSecretStore" \
    "$(q "${ssm_only}" "${es} | [.spec.secretStoreRef.name, .spec.secretStoreRef.kind] | join(\" \")")"
  assert_eq "web: parameterStore-only secrets need no per-entry override" \
    "0" "$(q "${ssm_only}" "[${es} | .spec.data[] | select(has(\"sourceRef\"))] | length")"
  assert_eq "web: parameterStore-only secrets never name the Secrets Manager store" \
    "0" "$(q "${ssm_only}" "[${es} | .. | select(. == \"ravion-aws\")] | length")"
  assert_eq "web: every parameterStore secret still lands as env" \
    "FEATURE_FLAGS RATE_LIMIT" \
    "$(q "${ssm_only}" "[${ctr} | .env[] | select(.valueFrom.secretKeyRef != null) | .name] | join(\" \")")"

  # --- ingress allow-list ----------------------------------------------------
  local np='.[] | select(.kind == "NetworkPolicy")'
  assert_eq "web: no NetworkPolicy renders by default" \
    "0" "$(count "${default}" NetworkPolicy)"
  assert_eq "web: an enabled allow-list renders one NetworkPolicy" \
    "1" "$(count "${full}" NetworkPolicy)"
  assert_eq "web: the NetworkPolicy selects this release's pods" \
    "test-release" "$(q "${full}" "${np} | .spec.podSelector.matchLabels[\"app.kubernetes.io/instance\"]")"
  assert_eq "web: only ingress is restricted, egress stays open" \
    "Ingress" "$(q "${full}" "${np} | .spec.policyTypes | join(\",\")")"
  assert_eq "web: allowed releases become same-namespace pod selectors" \
    "api,worker" "$(q "${full}" "${np} | [.spec.ingress[0].from[] | select(.podSelector) | .podSelector.matchLabels[\"app.kubernetes.io/instance\"]] | join(\",\")")"
  assert_eq "web: allowed namespaces become namespace selectors" \
    "monitoring" "$(q "${full}" "${np} | [.spec.ingress[0].from[] | select(.namespaceSelector) | .namespaceSelector.matchLabels[\"kubernetes.io/metadata.name\"]] | join(\",\")")"
  assert_eq "web: load balancer CIDRs become ipBlocks" \
    "10.0.0.0/20,10.0.16.0/20" "$(q "${full}" "${np} | [.spec.ingress[0].from[] | select(.ipBlock) | .ipBlock.cidr] | join(\",\")")"
  assert_eq "web: the allow-list opens only the container port" \
    "3000" "$(q "${full}" "${np} | .spec.ingress[0].ports[0].port")"

  # --- graceful shutdown: grace period, preStop sleep, readiness gates, PDB --
  local pdb='.[] | select(.kind == "PodDisruptionBudget")'
  assert_eq "web: grace period defaults to 30s" \
    "30" "$(q "${default}" "${dep} | .spec.template.spec.terminationGracePeriodSeconds")"
  assert_eq "web: grace period comes from values" \
    "120" "$(q "${full}" "${dep} | .spec.template.spec.terminationGracePeriodSeconds")"
  assert_eq "web: a 10s preStop sleep by default" \
    "10" "$(q "${default}" "${ctr} | .lifecycle.preStop.sleep.seconds")"
  assert_eq "web: preStopSleepSeconds 0 renders no hook" \
    "" "$(q "$(render "${chart}" no-prestop --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml" --set lifecycle.preStopSleepSeconds=0)" "${ctr} | .lifecycle")"
  assert_eq "web: preStopSleepSeconds renders the native preStop sleep action" \
    "15" "$(q "${full}" "${ctr} | .lifecycle.preStop.sleep.seconds")"
  assert_eq "web: no readiness gates without a target group" \
    "" "$(q "${default}" "${dep} | .spec.template.spec.readinessGates")"
  assert_eq "web: one load balancer readiness gate per TargetGroupBinding" \
    "target-health.elbv2.k8s.aws/test-release-rvn-eks-web-0 target-health.elbv2.k8s.aws/test-release-rvn-eks-web-1" \
    "$(q "${full}" "[${dep} | .spec.template.spec.readinessGates[].conditionType] | join(\" \")")"
  assert_eq "web: readiness gates name the rendered TargetGroupBindings" \
    "test-release-rvn-eks-web-0 test-release-rvn-eks-web-1" \
    "$(q "${full}" "[.[] | select(.kind == \"TargetGroupBinding\") | .metadata.name] | join(\" \")")"
  assert_eq "web: a PodDisruptionBudget by default" \
    "1" "$(count "${default}" PodDisruptionBudget)"
  assert_eq "web: PodDisruptionBudget rendered when enabled above the replica floor" \
    "1" "$(count "${full}" PodDisruptionBudget)"
  assert_eq "web: PodDisruptionBudget keeps minAvailable and lets unhealthy pods go" \
    "1 AlwaysAllow" "$(q "${full}" "${pdb} | [.spec.minAvailable, .spec.unhealthyPodEvictionPolicy] | join(\" \")")"
  assert_eq "web: PodDisruptionBudget selects this release's pods" \
    "rvn-eks-web test-release" \
    "$(q "${full}" "${pdb} | .spec.selector.matchLabels | [.\"app.kubernetes.io/name\", .\"app.kubernetes.io/instance\"] | join(\" \")")"
  local single
  single="$(render "${chart}" pdb-single --values "${CHARTS_DIR}/${chart}/ci/pdb-single-replica-values.yaml")"
  assert_eq "web: PodDisruptionBudget skipped when it would block every drain" \
    "0" "$(count "${single}" PodDisruptionBudget)"
  assert_eq "web: a load balancer readiness gate by default when a target group is bound" \
    "target-health.elbv2.k8s.aws/test-release-rvn-eks-web-0" \
    "$(q "${single}" "[${dep} | .spec.template.spec.readinessGates[].conditionType] | join(\" \")")"
  assert_eq "web: podReadinessGate false renders no gate" \
    "" "$(q "$(render "${chart}" no-gate --values "${CHARTS_DIR}/${chart}/ci/pdb-single-replica-values.yaml" --set targetGroupBinding.podReadinessGate=false)" "${dep} | .spec.template.spec.readinessGates")"
  if helm template test-release "$(chart_path "${chart}")" \
    --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml" \
    --set lifecycle.preStopSleepSeconds=30 >/dev/null 2>"${WORK_DIR}/prestop.err"; then
    fail "web: preStop sleep >= grace period fails the render" "render error" "render succeeded"
  else
    assert_eq "web: preStop sleep >= grace period fails the render" \
      "1" "$(grep -c 'must be less than terminationGracePeriodSeconds' "${WORK_DIR}/prestop.err")"
  fi
  assert_eq "web: preStop sleep is skipped on Kubernetes < 1.30, which lacks the sleep action" \
    "" "$(q "$(render "${chart}" old-kube --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml" --kube-version 1.29.0)" "${ctr} | .lifecycle")"

  local deny_all
  deny_all="$(render "${chart}" deny-all --values "${CHARTS_DIR}/${chart}/ci/network-policy-deny-all-values.yaml")"
  assert_eq "web: an allow-list with no sources still renders a policy" \
    "1" "$(count "${deny_all}" NetworkPolicy)"
  assert_eq "web: an allow-list with no sources denies every ingress peer" \
    "0" "$(q "${deny_all}" "${np} | .spec.ingress | length")"

  test_spot_burst_chart rvn-eks-web
  local spot_burst
  spot_burst="$(render "${chart}" spot-burst-service --values "${CHARTS_DIR}/${chart}/ci/spot-burst-values.yaml" \
    --set networkPolicy.enabled=true)"
  assert_eq "web: shared Service selects both release pools by instance label only" \
    "app.kubernetes.io/instance" \
    "$(q "${spot_burst}" '.[] | select(.kind == "Service") | .spec.selector | keys | join(" ")')"
  assert_eq "web: shared NetworkPolicy selects both release pools by instance label only" \
    "app.kubernetes.io/instance" \
    "$(q "${spot_burst}" '.[] | select(.kind == "NetworkPolicy") | .spec.podSelector.matchLabels | keys | join(" ")')"
  assert_eq "web: both pools retain the same TargetGroupBinding readiness gate" \
    "target-health.elbv2.k8s.aws/test-release-rvn-eks-web-0" \
    "$(q "${spot_burst}" '[.[] | select(.kind == "Deployment") | .spec.template.spec.readinessGates[].conditionType] | unique | join(" ")')"
}

################################################################################
# rvn-eks-worker
################################################################################

test_rvn_eks_worker() {
  local chart=rvn-eks-worker
  local fast_rollout
  fast_rollout="$(render "${chart}" fast-rollout --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml" --set replicaCount=2)"
  assert_eq "worker: full replacement surge preserves zero-unavailable rollout" \
    "2 100% 0" \
    "$(q "${fast_rollout}" '.[] | select(.kind == "Deployment") | .spec | "\(.replicas) \(.strategy.rollingUpdate.maxSurge) \(.strategy.rollingUpdate.maxUnavailable)"')"
  local default full
  default="$(render "${chart}" default --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml")"
  full="$(render "${chart}" full --values "${CHARTS_DIR}/${chart}/ci/full-values.yaml")"

  local dep='.[] | select(.kind == "Deployment")'
  local ctr="${dep} | .spec.template.spec.containers[0]"

  assert_eq "worker: image maps repository:tag" \
    "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo-worker:v1.2.3" \
    "$(q "${default}" "${ctr} | .image")"
  assert_eq "worker: args are passed through" \
    "worker --queue=default" "$(q "${default}" "${ctr} | .args | join(\" \")")"
  assert_eq "worker: env is mapped" \
    "QUEUE" "$(q "${default}" "[${ctr} | .env[].name] | join(\" \")")"
  assert_eq "worker: resources are rendered" \
    "256Mi" "$(q "${default}" "${ctr} | .resources.requests.memory")"
  assert_eq "worker: replicas come from replicaCount when autoscaling is off" \
    "1" "$(q "${default}" "${dep} | .spec.replicas")"
  assert_eq "worker: ServiceAccount name defaults to the fullname" \
    "test-release-rvn-eks-worker" \
    "$(q "${default}" '.[] | select(.kind == "ServiceAccount") | .metadata.name')"

  # --- no load-balancer surface --------------------------------------------
  assert_eq "worker: renders no Service" "0" "$(count "${full}" Service)"
  assert_eq "worker: renders no Ingress" "0" "$(count "${full}" Ingress)"
  assert_eq "worker: renders no TargetGroupBinding" \
    "0" "$(count "${full}" TargetGroupBinding)"
  assert_eq "worker: container declares no ports" \
    "" "$(q "${full}" "${ctr} | .ports")"
  assert_eq "worker: container declares no probes" \
    "" "$(q "${full}" "${ctr} | .livenessProbe")"

  # --- HPA toggling ---------------------------------------------------------
  assert_eq "worker: no HPA by default" \
    "0" "$(count "${default}" HorizontalPodAutoscaler)"
  assert_eq "worker: HPA rendered when autoscaling.enabled" \
    "1" "$(count "${full}" HorizontalPodAutoscaler)"
  assert_eq "worker: Deployment omits replicas when the HPA owns scale" \
    "" "$(q "${full}" "${dep} | .spec.replicas")"

  # --- zone spread (on by default) ------------------------------------------
  local tsc="${dep} | .spec.template.spec.topologySpreadConstraints"
  assert_eq "worker: default zone spread constraint is rendered" \
    "1 topology.kubernetes.io/zone ScheduleAnyway" \
    "$(q "${default}" "${tsc}[0] | [.maxSkew, .topologyKey, .whenUnsatisfiable] | join(\" \")")"
  assert_eq "worker: default zone spread selects this chart's pods" \
    "rvn-eks-worker test-release" \
    "$(q "${default}" "${tsc}[0].labelSelector.matchLabels | [.\"app.kubernetes.io/name\", .\"app.kubernetes.io/instance\"] | join(\" \")")"
  assert_eq "worker: explicit topologySpreadConstraints replace the default" \
    "1 kubernetes.io/hostname" \
    "$(q "${full}" "${tsc} | [length, .[0].topologyKey] | join(\" \")")"
  local zone_off
  zone_off="$(render "${chart}" zone-off --values "${CHARTS_DIR}/${chart}/ci/zone-routing-off-values.yaml")"
  assert_eq "worker: no spread constraint when topologySpread is disabled" \
    "" "$(q "${zone_off}" "${tsc}")"

  # A worker loses in-flight work when it is evicted, so a fleet drained all at
  # once loses all of it. The budget is on by default wherever it can be, and
  # skipped where it would block drains instead of pacing them.
  local pdb='.[] | select(.kind == "PodDisruptionBudget")'
  assert_eq "worker: no PodDisruptionBudget on the single-replica default" \
    "0" "$(count "${default}" PodDisruptionBudget)"
  assert_eq "worker: PodDisruptionBudget rendered above the replica floor" \
    "1" "$(count "${full}" PodDisruptionBudget)"
  assert_eq "worker: PodDisruptionBudget keeps minAvailable and lets unhealthy pods go" \
    "1 AlwaysAllow" "$(q "${full}" "${pdb} | [.spec.minAvailable, .spec.unhealthyPodEvictionPolicy] | join(\" \")")"
  assert_eq "worker: PodDisruptionBudget selects this release's pods" \
    "rvn-eks-worker test-release" \
    "$(q "${full}" "${pdb} | .spec.selector.matchLabels | [.\"app.kubernetes.io/name\", .\"app.kubernetes.io/instance\"] | join(\" \")")"
  local pdb_single
  pdb_single="$(render "${chart}" pdb-single --values "${CHARTS_DIR}/${chart}/ci/pdb-single-replica-values.yaml")"
  assert_eq "worker: PodDisruptionBudget skipped when it would block every drain" \
    "0" "$(count "${pdb_single}" PodDisruptionBudget)"

  test_secrets_contract "${chart}" "${full}" "${default}" Deployment
  test_spot_burst_chart rvn-eks-worker
}

################################################################################
# rvn-eks-cron
################################################################################

test_rvn_eks_cron() {
  local chart=rvn-eks-cron
  local default full
  default="$(render "${chart}" default --values "${CHARTS_DIR}/${chart}/ci/default-values.yaml")"
  full="$(render "${chart}" full --values "${CHARTS_DIR}/${chart}/ci/full-values.yaml")"

  local cj='.[] | select(.kind == "CronJob")'
  local ctr="${cj} | .spec.jobTemplate.spec.template.spec.containers[0]"

  assert_eq "cron: a CronJob is rendered" "1" "$(count "${default}" CronJob)"
  assert_eq "cron: schedule comes from values" \
    "0 3 * * *" "$(q "${default}" "${cj} | .spec.schedule")"
  assert_eq "cron: image maps repository:tag" \
    "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo-cron:v1.2.3" \
    "$(q "${default}" "${ctr} | .image")"
  assert_eq "cron: args are passed through" \
    "rake db:cleanup" "$(q "${default}" "${ctr} | .args | join(\" \")")"
  assert_eq "cron: env is mapped" \
    "LOG_LEVEL" "$(q "${default}" "[${ctr} | .env[].name] | join(\" \")")"
  assert_eq "cron: resources are rendered" \
    "256Mi" "$(q "${default}" "${ctr} | .resources.requests.memory")"
  assert_eq "cron: ServiceAccount name defaults to the fullname" \
    "test-release-rvn-eks-cron" \
    "$(q "${default}" '.[] | select(.kind == "ServiceAccount") | .metadata.name')"

  # --- cron defaults --------------------------------------------------------
  assert_eq "cron: concurrencyPolicy defaults to Allow" \
    "Allow" "$(q "${default}" "${cj} | .spec.concurrencyPolicy")"
  assert_eq "cron: history limits default to 3/1" \
    "3 1" \
    "$(q "${default}" "${cj} | [.spec.successfulJobsHistoryLimit, .spec.failedJobsHistoryLimit] | join(\" \")")"
  assert_eq "cron: no timeZone unless set" \
    "" "$(q "${default}" "${cj} | .spec.timeZone")"
  assert_eq "cron: no startingDeadlineSeconds unless set" \
    "" "$(q "${default}" "${cj} | .spec.startingDeadlineSeconds")"
  assert_eq "cron: restartPolicy defaults to OnFailure" \
    "OnFailure" "$(q "${default}" "${cj} | .spec.jobTemplate.spec.template.spec.restartPolicy")"

  # --- cron knobs -----------------------------------------------------------
  assert_eq "cron: schedule, timeZone and concurrencyPolicy come from values" \
    "*/15 * * * * America/New_York Forbid" \
    "$(q "${full}" "${cj} | [.spec.schedule, .spec.timeZone, .spec.concurrencyPolicy] | join(\" \")")"
  assert_eq "cron: history limits come from values" \
    "1 5" \
    "$(q "${full}" "${cj} | [.spec.successfulJobsHistoryLimit, .spec.failedJobsHistoryLimit] | join(\" \")")"
  assert_eq "cron: startingDeadlineSeconds comes from values" \
    "120" "$(q "${full}" "${cj} | .spec.startingDeadlineSeconds")"
  assert_eq "cron: job knobs come from values" \
    "0 600 3600 Never" \
    "$(q "${full}" "${cj} | .spec.jobTemplate.spec | [.backoffLimit, .activeDeadlineSeconds, .ttlSecondsAfterFinished, .template.spec.restartPolicy] | join(\" \")")"

  # --- no long-running or load-balancer surface -----------------------------
  assert_eq "cron: renders no Service" "0" "$(count "${full}" Service)"
  assert_eq "cron: renders no Deployment" "0" "$(count "${full}" Deployment)"
  assert_eq "cron: renders no TargetGroupBinding" \
    "0" "$(count "${full}" TargetGroupBinding)"

  test_secrets_contract "${chart}" "${full}" "${default}" CronJob
}

################################################################################
# The ravion.secrets contract (ENG-5034), asserted identically for all charts.
################################################################################

test_secrets_contract() {
  local chart="$1" with_secrets="$2" without_secrets="$3" workload_kind="$4"
  local es='.[] | select(.kind == "ExternalSecret")'
  local ctr
  if [[ "${workload_kind}" == "CronJob" ]]; then
    ctr='.[] | select(.kind == "CronJob") | .spec.jobTemplate.spec.template.spec.containers[0]'
  else
    ctr='.[] | select(.kind == "Deployment") | .spec.template.spec.containers[0]'
  fi

  # --- absent when no secrets ----------------------------------------------
  assert_eq "${chart}: no ExternalSecret when ravion.secrets is empty" \
    "0" "$(count "${without_secrets}" ExternalSecret)"
  assert_eq "${chart}: no Secret object when ravion.secrets is empty" \
    "0" "$(count "${without_secrets}" Secret)"

  # --- one ExternalSecret targeting a chart-managed Secret ------------------
  assert_eq "${chart}: one ExternalSecret when secrets are supplied" \
    "1" "$(count "${with_secrets}" ExternalSecret)"
  assert_eq "${chart}: uses the external-secrets.io/v1 API (the only served version)" \
    "external-secrets.io/v1" "$(q "${with_secrets}" "${es} | .apiVersion")"
  assert_eq "${chart}: targets a chart-managed Secret it owns" \
    "test-release-${chart}-secrets Owner" \
    "$(q "${with_secrets}" "${es} | [.spec.target.name, .spec.target.creationPolicy] | join(\" \")")"
  assert_eq "${chart}: refresh interval comes from values" \
    "1h" "$(q "${with_secrets}" "${es} | .spec.refreshInterval")"

  # --- remoteRef mapping, including property and version --------------------
  local db='.spec.data[] | select(.secretKey == "DB_PASSWORD")'
  assert_eq "${chart}: remoteRef.key is the supplied ARN" \
    "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf" \
    "$(q "${with_secrets}" "${es} | ${db} | .remoteRef.key")"
  assert_eq "${chart}: remoteRef.property carries the JSON key" \
    "password" "$(q "${with_secrets}" "${es} | ${db} | .remoteRef.property")"

  # --- provider routing to the right SecretStore ----------------------------
  assert_eq "${chart}: mixed providers default the store to ravion-aws" \
    "ravion-aws ClusterSecretStore" \
    "$(q "${with_secrets}" "${es} | [.spec.secretStoreRef.name, .spec.secretStoreRef.kind] | join(\" \")")"
  assert_eq "${chart}: secretsManager entries do not override the store" \
    "" "$(q "${with_secrets}" "${es} | ${db} | .sourceRef")"
  local flags='.spec.data[] | select(.secretKey == "FEATURE_FLAGS")'
  assert_eq "${chart}: parameterStore entries override to the SSM store" \
    "ravion-aws-parameter-store ClusterSecretStore" \
    "$(q "${with_secrets}" "${es} | ${flags} | [.sourceRef.storeRef.name, .sourceRef.storeRef.kind] | join(\" \")")"
  assert_eq "${chart}: a reference without property omits property" \
    "" "$(q "${with_secrets}" "${es} | ${flags} | .remoteRef.property")"

  # --- env wiring -----------------------------------------------------------
  assert_eq "${chart}: every secret reference lands as a container env var" \
    "true" \
    "$(q "${with_secrets}" "([${ctr} | .env[] | select(.valueFrom.secretKeyRef != null) | .name] | join(\",\")) == ([${es} | .spec.data[].secretKey] | join(\",\"))")"
  assert_eq "${chart}: both providers reach the container env" \
    "DB_PASSWORD FEATURE_FLAGS" \
    "$(q "${with_secrets}" "[${ctr} | .env[] | select(.valueFrom.secretKeyRef != null) | .name | select(. == \"DB_PASSWORD\" or . == \"FEATURE_FLAGS\")] | join(\" \")")"
  assert_eq "${chart}: env var reads from the chart-managed Secret" \
    "test-release-${chart}-secrets DB_PASSWORD" \
    "$(q "${with_secrets}" "${ctr} | .env[] | select(.name == \"DB_PASSWORD\") | [.valueFrom.secretKeyRef.name, .valueFrom.secretKeyRef.key] | join(\" \")")"

  # --- the load-bearing invariant: no secret VALUE anywhere -----------------
  assert_eq "${chart}: no env entry for a secret carries an inline value" \
    "0" \
    "$(q "${with_secrets}" "[${ctr} | .env[] | select(.name == \"DB_PASSWORD\") | select(has(\"value\"))] | length")"
  assert_eq "${chart}: chart renders no Secret object of its own" \
    "0" "$(count "${with_secrets}" Secret)"
}

################################################################################
# karpenter-resources (compute/eks/addons)
################################################################################

test_karpenter_resources() {
  local chart="karpenter-resources"
  local default positive with_key ebs static
  default="$(render "${chart}" default --values "$(chart_path "${chart}")/ci/default-values.yaml")"
  positive="$(render "${chart}" positive --values "$(chart_path "${chart}")/ci/default-values.yaml" --set spotWarm.minInstances=3)"
  with_key="$(render "${chart}" customer-key --values "$(chart_path "${chart}")/ci/customer-key-values.yaml")"
  ebs='.[] | select(.kind == "EC2NodeClass") | .spec.blockDeviceMappings[0]'
  static='.[] | select(.kind == "NodePool") | select(.metadata.name == "spot-warm")'

  assert_eq "${chart}: renders one EC2NodeClass and one NodePool" \
    "1 1" "$(count "${default}" EC2NodeClass) $(count "${default}" NodePool)"
  assert_eq "${chart}: zero warm instances omits the static NodePool" \
    "1" "$(count "${default}" NodePool)"
  assert_eq "${chart}: positive warm instances render a second NodePool" \
    "2" "$(count "${positive}" NodePool)"
  assert_eq "${chart}: static pool uses the requested replicas and replacement headroom" \
    "3 4" "$(q "${positive}" "${static} | [.spec.replicas, .spec.limits.nodes] | join(\" \")")"
  assert_eq "${chart}: static pool is Spot-only and inherits scheduling constraints" \
    "linux amd64 spot c,m,r Gt 2" \
    "$(q "${positive}" "${static} | [.spec.template.spec.requirements[0].values[0], .spec.template.spec.requirements[1].values[0], .spec.template.spec.requirements[2].values[0], (.spec.template.spec.requirements[3].values | join(\",\")), (.spec.template.spec.requirements[4].operator + \" \" + .spec.template.spec.requirements[4].values[0])] | join(\" \")")"
  assert_eq "${chart}: static pool reuses the default class and expiration" \
    "default 720h" "$(q "${positive}" "${static} | [.spec.template.spec.nodeClassRef.name, .spec.template.spec.expireAfter] | join(\" \")")"
  assert_eq "${chart}: static pool has no dynamic-only controls" \
    "limits replicas template" "$(q "${positive}" "${static} | .spec | keys | sort | join(\" \")")"
  assert_eq "${chart}: static pool template has only permitted fields" \
    "expireAfter nodeClassRef requirements" "$(q "${positive}" "${static} | .spec.template.spec | keys | sort | join(\" \")")"

  if helm template test-release "$(chart_path "${chart}")" --set spotWarm.minInstances=-1 >/dev/null 2>&1; then
    fail "${chart}: negative warm instance count is rejected" "helm template failure" "helm template succeeded"
  else
    pass "${chart}: negative warm instance count is rejected"
  fi
  if helm template test-release "$(chart_path "${chart}")" --set spotWarm.minInstances=1.5 >/dev/null 2>&1; then
    fail "${chart}: fractional warm instance count is rejected" "helm template failure" "helm template succeeded"
  else
    pass "${chart}: fractional warm instance count is rejected"
  fi

  # The Terraform module hands the chart kmsKeyId "" when no customer key is
  # set; the manifest must then carry no kmsKeyID at all, or Karpenter would
  # try to use an empty key and fail every launch.
  assert_eq "${chart}: no customer key omits kmsKeyID from the manifest" \
    "false" "$(q "${default}" "${ebs} | .ebs | has(\"kmsKeyID\")")"
  assert_eq "${chart}: root volume is always encrypted" \
    "true" "$(q "${default}" "${ebs} | .ebs.encrypted")"
  assert_eq "${chart}: root volume is marked as the root device and deleted with the node" \
    "true true" "$(q "${default}" "${ebs} | .rootVolume") $(q "${default}" "${ebs} | .ebs.deleteOnTermination")"
  assert_eq "${chart}: default root volume is 20Gi gp3 on /dev/xvda" \
    "/dev/xvda 20Gi gp3" "$(q "${default}" "${ebs} | .deviceName") $(q "${default}" "${ebs} | .ebs.volumeSize") $(q "${default}" "${ebs} | .ebs.volumeType")"
  assert_eq "${chart}: IMDSv2 is required with a hop limit of 1" \
    "required 1" "$(q "${default}" '.[] | select(.kind == "EC2NodeClass") | .spec.metadataOptions.httpTokens') $(q "${default}" '.[] | select(.kind == "EC2NodeClass") | .spec.metadataOptions.httpPutResponseHopLimit')"

  assert_eq "${chart}: a customer-managed key is rendered as kmsKeyID" \
    "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555" \
    "$(q "${with_key}" "${ebs} | .ebs.kmsKeyID")"
  assert_eq "${chart}: a customer root volume size reaches the manifest" \
    "50Gi" "$(q "${with_key}" "${ebs} | .ebs.volumeSize")"
}

################################################################################
# warm-capacity (compute/eks/addons)
################################################################################

test_warm_capacity() {
  local chart="warm-capacity"
  local default default_enabled full dep pod ctr
  default="$(render "${chart}" default --values "$(chart_path "${chart}")/ci/default-values.yaml")"
  default_enabled="$(render "${chart}" default-enabled --set enabled=true)"
  full="$(render "${chart}" full --values "$(chart_path "${chart}")/ci/full-values.yaml")"
  dep='.[] | select(.kind == "Deployment")'
  pod="${dep} | .spec.template.spec"
  ctr="${pod} | .containers[0]"

  assert_eq "${chart}: disabled values render no reservation objects" \
    "0 0" "$(count "${default}" Deployment) $(count "${default}" PriorityClass)"
  assert_eq "${chart}: enabled values render reservation and low priority class" \
    "1 1 -10 Never" \
    "$(count "${full}" Deployment) $(count "${full}" PriorityClass) $(q "${full}" '.[] | select(.kind == "PriorityClass") | .value') $(q "${full}" '.[] | select(.kind == "PriorityClass") | .preemptionPolicy')"
  assert_eq "${chart}: defaults reserve six executor slots plus a two-pod app surge" \
    "8 100m 256Mi 1Gi" \
    "$(q "${default_enabled}" "${dep} | .spec.replicas") $(q "${default_enabled}" "${ctr} | .resources.requests.cpu") $(q "${default_enabled}" "${ctr} | .resources.requests.memory") $(q "${default_enabled}" "${ctr} | .resources.requests.\"ephemeral-storage\"")"
  assert_eq "${chart}: reservation replicas and requests reach the pod" \
    "9 250m 512Mi 2Gi" \
    "$(q "${full}" "${dep} | .spec.replicas") $(q "${full}" "${ctr} | .resources.requests.cpu") $(q "${full}" "${ctr} | .resources.requests.memory") $(q "${full}" "${ctr} | .resources.requests.\"ephemeral-storage\"")"
  assert_eq "${chart}: placeholders terminate immediately and carry no API token" \
    "0 false" \
    "$(q "${full}" "${pod} | .terminationGracePeriodSeconds") $(q "${full}" "${pod} | .automountServiceAccountToken")"
  assert_eq "${chart}: node selection and tolerations are configurable" \
    "default dedicated apps NoSchedule" \
    "$(q "${full}" "${pod} | .nodeSelector.\"karpenter.sh/nodepool\"") $(q "${full}" "${pod} | .tolerations[0] | [.key, .value, .effect] | join(\" \" )")"
  assert_eq "${chart}: optional topology spread reaches the manifest" \
    "1 kubernetes.io/hostname DoNotSchedule" \
    "$(q "${full}" "${pod} | .topologySpreadConstraints[0] | [.maxSkew, .topologyKey, .whenUnsatisfiable] | join(\" \" )")"
}

################################################################################
# ebs-storage (compute/eks/addons)
################################################################################

test_ebs_storage() {
  local chart="ebs-storage"
  local default class_only sc map dep ctr
  default="$(render "${chart}" default --values "$(chart_path "${chart}")/ci/default-values.yaml")"
  class_only="$(render "${chart}" class-only --values "$(chart_path "${chart}")/ci/storage-class-only-values.yaml")"
  sc='.[] | select(.kind == "StorageClass")'
  map='.[] | select(.kind == "MutatingAdmissionPolicy")'
  dep='.[] | select(.kind == "Deployment")'
  ctr="${dep} | .spec.template.spec.containers[0]"

  assert_eq "${chart}: gp3 is the default class and allows volume expansion" \
    "gp3 true true gp3 true WaitForFirstConsumer" \
    "$(q "${default}" "${sc} | [.metadata.name, .metadata.annotations.\"storageclass.kubernetes.io/is-default-class\", .allowVolumeExpansion, .parameters.type, .parameters.encrypted, .volumeBindingMode] | join(\" \")")"
  assert_eq "${chart}: expansion policy and binding render by default" \
    "1 1 Ignore" \
    "$(count "${default}" MutatingAdmissionPolicy) $(count "${default}" MutatingAdmissionPolicyBinding) $(q "${default}" "${map} | .spec.failurePolicy")"
  assert_eq "${chart}: policy only matches StatefulSet updates" \
    "apps statefulsets UPDATE" \
    "$(q "${default}" "${map} | .spec.matchConstraints.resourceRules[0] | [.apiGroups[0], .resources[0], .operations[0]] | join(\" \")")"
  assert_eq "${chart}: requested sizes are recorded before the templates are reverted" \
    "ApplyConfiguration JSONPatch" \
    "$(q "${default}" "${map} | [.spec.mutations[].patchType] | join(\" \")")"
  assert_eq "${chart}: resizer runs kubectl with a busybox shell" \
    "registry.k8s.io/kubectl:v1.36.4 /tools/sh public.ecr.aws/docker/library/busybox:1.37.0-musl" \
    "$(q "${default}" "${ctr} | .image") $(q "${default}" "${ctr} | .command[0]") $(q "${default}" "${dep} | .spec.template.spec.initContainers[0].image")"
  assert_eq "${chart}: resizer may only list StatefulSets and grow claims" \
    "list get,list,patch" \
    "$(q "${default}" '.[] | select(.kind == "ClusterRole") | .rules[0].verbs | join(",")') $(q "${default}" '.[] | select(.kind == "ClusterRole") | .rules[1].verbs | join(",")')"
  assert_eq "${chart}: class-only values render the StorageClass alone" \
    "1 0 0" \
    "$(count "${class_only}" StorageClass) $(count "${class_only}" MutatingAdmissionPolicy) $(count "${class_only}" Deployment)"
}

################################################################################

for chart in "${CHARTS[@]}"; do
  printf '\n==> %s\n' "${chart}"
  lint_chart "${chart}"
  case "${chart}" in
    rvn-eks-web) test_rvn_eks_web ;;
    rvn-eks-worker) test_rvn_eks_worker ;;
    rvn-eks-cron) test_rvn_eks_cron ;;
    karpenter-resources) test_karpenter_resources ;;
    warm-capacity) test_warm_capacity ;;
    ebs-storage) test_ebs_storage ;;
    *)
      echo "unknown chart: ${chart}" >&2
      exit 1
      ;;
  esac
done

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
