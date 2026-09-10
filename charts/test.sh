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
ALL_CHARTS=(rvn-eks-web rvn-eks-worker rvn-eks-cron)
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
  helm template test-release "${CHARTS_DIR}/${chart}" "$@" |
    yq ea '[.] | map(select(. != null))' >"${out}"
  echo "${out}"
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

################################################################################
# helm lint — every chart against every ci/*-values.yaml
################################################################################

lint_chart() {
  local chart="$1"
  for values in "${CHARTS_DIR}/${chart}"/ci/*-values.yaml; do
    local label
    label="$(basename "${values}")"
    if helm lint "${CHARTS_DIR}/${chart}" --values "${values}" >"${WORK_DIR}/lint.out" 2>&1; then
      pass "lint ${chart} (${label})"
    else
      fail "lint ${chart} (${label})" "exit 0" "$(cat "${WORK_DIR}/lint.out")"
    fi
  done
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
  assert_eq "web: replicas come from replicaCount when autoscaling is off" \
    "1" "$(q "${default}" "${dep} | .spec.replicas")"

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
}

################################################################################
# rvn-eks-worker
################################################################################

test_rvn_eks_worker() {
  local chart=rvn-eks-worker
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

  test_secrets_contract "${chart}" "${full}" "${default}" Deployment
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

for chart in "${CHARTS[@]}"; do
  printf '\n==> %s\n' "${chart}"
  lint_chart "${chart}"
  case "${chart}" in
    rvn-eks-web) test_rvn_eks_web ;;
    rvn-eks-worker) test_rvn_eks_worker ;;
    rvn-eks-cron) test_rvn_eks_cron ;;
    *)
      echo "unknown chart: ${chart}" >&2
      exit 1
      ;;
  esac
done

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
