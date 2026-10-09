{{/*
Shared helpers for the rvn-eks-* Ravion application charts.

This file is intentionally duplicated (with the chart-name prefix rewritten)
across rvn-eks-web, rvn-eks-worker and rvn-eks-cron. The charts are fetched
individually by path from a clone of this repository, so each one must be
self-contained: a shared library chart would require `helm dependency update`
at deploy time, which the Ravion runner does not perform.
*/}}

{{/* Base name, truncated to the 63-char label limit. */}}
{{- define "rvn-eks-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified release name. */}}
{{- define "rvn-eks-worker.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Immutable across upgrades — never add anything volatile. */}}
{{- define "rvn-eks-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-eks-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-eks-worker.labels" -}}
helm.sh/chart: {{ include "rvn-eks-worker.chart" . }}
{{ include "rvn-eks-worker.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ravion
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Service account name. EKS Pod Identity associates an IAM role with a service
account by NAMESPACE + NAME, so this must be stable and configurable; no IRSA
role-arn annotation is emitted.
*/}}
{{- define "rvn-eks-worker.serviceAccountName" -}}
{{- default (include "rvn-eks-worker.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/* Name of the Kubernetes Secret materialized by the ExternalSecret. */}}
{{- define "rvn-eks-worker.secretName" -}}
{{- printf "%s-secrets" (include "rvn-eks-worker.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Container image reference. A digest, when supplied, wins over the tag. */}}
{{- define "rvn-eks-worker.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (required "image.tag or image.digest is required" .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{/*
Container env. Plain values first, then one secretKeyRef per ravion.secrets
entry. secretKeyRef (rather than envFrom) is deliberate: it fails the pod
closed if the ExternalSecret has not yet materialized the key, instead of
silently starting the container with the variable unset.
*/}}
{{- define "rvn-eks-worker.env" -}}
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- range .Values.ravion.secrets }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "rvn-eks-worker.secretName" $ }}
      key: {{ .name }}
{{- end }}
{{- end -}}

{{/*
The lowest number of pods this release can be running: what an HPA may scale
down to, or the fixed replica count. A PodDisruptionBudget is only safe to
render above it.
*/}}
{{- define "rvn-eks-worker.replicaFloor" -}}
{{- if .Values.spotBurst.enabled -}}
{{- .Values.spotBurst.baselineReplicas -}}
{{- else if .Values.autoscaling.enabled -}}
{{- .Values.autoscaling.minReplicas -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-worker.spotDeploymentName" -}}
{{- $fullname := include "rvn-eks-worker.fullname" . -}}
{{- if le (len $fullname) 58 -}}
{{- printf "%s-spot" $fullname -}}
{{- else -}}
{{- printf "%s-%s-spot" ($fullname | trunc 49 | trimSuffix "-") ($fullname | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-worker.spotSelectorName" -}}
{{- $name := include "rvn-eks-worker.name" . -}}
{{- if le (len $name) 58 -}}
{{- printf "%s-spot" $name -}}
{{- else -}}
{{- printf "%s-%s-spot" ($name | trunc 49 | trimSuffix "-") ($name | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-worker.spotSelectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-eks-worker.spotSelectorName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-eks-worker.spotReplicasAtMinimum" -}}
{{- max .minimum .replicas -}}
{{- end -}}

{{- define "rvn-eks-worker.affinityForPool" -}}
{{- $root := index . 0 -}}
{{- $isSpot := index . 1 -}}
{{- $affinity := deepCopy ($root.Values.affinity | default dict) -}}
{{- if not $root.Values.spotBurst.enabled -}}
{{- if $affinity -}}
{{- toYaml $affinity -}}
{{- end -}}
{{- else -}}
{{- $nodeAffinity := get $affinity "nodeAffinity" | default dict -}}
{{- $required := get $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" | default dict -}}
{{- $terms := list (dict) -}}
{{- if hasKey $required "nodeSelectorTerms" -}}
{{- $terms = get $required "nodeSelectorTerms" -}}
{{- end -}}
{{- $capacityRequirements := list
  (dict "key" "eks.amazonaws.com/capacityType" "operator" "In" "values" (list (ternary "SPOT" "ON_DEMAND" $isSpot)))
  (dict "key" "karpenter.sh/capacity-type" "operator" "In" "values" (list (ternary "spot" "on-demand" $isSpot)))
-}}
{{- $combinedTerms := list -}}
{{- range $term := $terms -}}
  {{- range $requirement := $capacityRequirements -}}
    {{- $combined := deepCopy $term -}}
    {{- $expressions := get $combined "matchExpressions" | default (list) -}}
    {{- $_ := set $combined "matchExpressions" (append $expressions $requirement) -}}
    {{- $combinedTerms = append $combinedTerms $combined -}}
  {{- end -}}
{{- end -}}
{{- $_ := set $required "nodeSelectorTerms" $combinedTerms -}}
{{- $_ := set $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" $required -}}
{{- $_ := set $affinity "nodeAffinity" $nodeAffinity -}}
{{- toYaml $affinity -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-worker.spotDeploymentReplicas" -}}
{{- $root := . -}}
{{- $name := include "rvn-eks-worker.spotDeploymentName" $root -}}
{{- $deployment := lookup "apps/v1" "Deployment" $root.Release.Namespace $name -}}
{{- if $deployment -}}
  {{- $labels := dig "metadata" "labels" (dict) $deployment -}}
  {{- $annotations := dig "metadata" "annotations" (dict) $deployment -}}
  {{- if or
    (ne (get $labels "app.kubernetes.io/managed-by") "Helm")
    (ne (get $annotations "meta.helm.sh/release-name") $root.Release.Name)
    (ne (get $annotations "meta.helm.sh/release-namespace") $root.Release.Namespace)
  -}}
    {{- fail (printf "spot-burst Deployment %q already exists but is not owned by Helm release %s in namespace %s; refusing to adopt it" $name $root.Release.Name $root.Release.Namespace) -}}
  {{- end -}}
  {{- include "rvn-eks-worker.spotReplicasAtMinimum" (dict "minimum" $root.Values.spotBurst.minReplicas "replicas" (dig "spec" "replicas" 0 $deployment)) -}}
{{- else -}}
{{- include "rvn-eks-worker.spotReplicasAtMinimum" (dict "minimum" $root.Values.spotBurst.minReplicas "replicas" 0) -}}
{{- end -}}
{{- end -}}
