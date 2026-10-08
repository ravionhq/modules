{{/*
Shared helpers for the rvn-eks-* Ravion application charts.

This file is intentionally duplicated (with the chart-name prefix rewritten)
across rvn-eks-web, rvn-eks-worker and rvn-eks-cron. The charts are fetched
individually by path from a clone of this repository, so each one must be
self-contained: a shared library chart would require `helm dependency update`
at deploy time, which the Ravion runner does not perform.
*/}}

{{/* Base name, truncated to the 63-char label limit. */}}
{{- define "rvn-eks-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified release name. */}}
{{- define "rvn-eks-web.fullname" -}}
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

{{- define "rvn-eks-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Immutable across upgrades — never add anything volatile. */}}
{{- define "rvn-eks-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-eks-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-eks-web.labels" -}}
helm.sh/chart: {{ include "rvn-eks-web.chart" . }}
{{ include "rvn-eks-web.selectorLabels" . }}
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
{{- define "rvn-eks-web.serviceAccountName" -}}
{{- default (include "rvn-eks-web.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/* Name of the Kubernetes Secret materialized by the ExternalSecret. */}}
{{- define "rvn-eks-web.secretName" -}}
{{- printf "%s-secrets" (include "rvn-eks-web.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Container image reference. A digest, when supplied, wins over the tag. */}}
{{- define "rvn-eks-web.image" -}}
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
{{- define "rvn-eks-web.env" -}}
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- range .Values.ravion.secrets }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "rvn-eks-web.secretName" $ }}
      key: {{ .name }}
{{- end }}
{{- end -}}

{{/*
TargetGroupBinding name for the target group at a given index of
targetGroupArns. Shared by the binding itself and the pod readiness gate that
waits on it, which must name the binding exactly.
Usage: include "rvn-eks-web.targetGroupBindingName" (list $ $index)
*/}}
{{- define "rvn-eks-web.targetGroupBindingName" -}}
{{- $root := index . 0 -}}
{{- printf "%s-%d" (include "rvn-eks-web.fullname" $root) (index . 1) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Lowest replica count the chart can run at: the HPA floor when autoscaling,
otherwise the fixed replica count.
*/}}
{{- define "rvn-eks-web.replicaFloor" -}}
{{- if .Values.spotBurst.enabled -}}
{{- .Values.spotBurst.baselineReplicas -}}
{{- else if .Values.autoscaling.enabled -}}
{{- .Values.autoscaling.minReplicas -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-web.spotDeploymentName" -}}
{{- $fullname := include "rvn-eks-web.fullname" . -}}
{{- if le (len $fullname) 58 -}}
{{- printf "%s-spot" $fullname -}}
{{- else -}}
{{- printf "%s-%s-spot" ($fullname | trunc 49 | trimSuffix "-") ($fullname | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "rvn-eks-web.spotSelectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-eks-web.spotDeploymentName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-eks-web.affinityForPool" -}}
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

{{- define "rvn-eks-web.spotDeploymentReplicas" -}}
{{- $root := . -}}
{{- $name := include "rvn-eks-web.spotDeploymentName" $root -}}
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
  {{- dig "spec" "replicas" 0 $deployment -}}
{{- else -}}
0
{{- end -}}
{{- end -}}
