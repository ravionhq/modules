{{/*
Shared helpers for the rvn-gke-* Ravion application charts.

This file is intentionally duplicated (with the chart-name prefix rewritten)
across rvn-gke-web, rvn-gke-worker and rvn-gke-cron (ported from the
rvn-eks-* charts). The charts are fetched
individually by path from a clone of this repository, so each one must be
self-contained: a shared library chart would require `helm dependency update`
at deploy time, which the Ravion runner does not perform.
*/}}

{{/* Base name, truncated to the 63-char label limit. */}}
{{- define "rvn-gke-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified release name. */}}
{{- define "rvn-gke-web.fullname" -}}
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

{{- define "rvn-gke-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Immutable across upgrades — never add anything volatile. */}}
{{- define "rvn-gke-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-gke-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-gke-web.labels" -}}
helm.sh/chart: {{ include "rvn-gke-web.chart" . }}
{{ include "rvn-gke-web.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ravion
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Service account name. The workloadIdentityUser binding on the workload's
Google service account names NAMESPACE + NAME, so this must be stable and
configurable.
*/}}
{{- define "rvn-gke-web.serviceAccountName" -}}
{{- default (include "rvn-gke-web.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/* Name of the Kubernetes Secret materialized by the ExternalSecret. */}}
{{- define "rvn-gke-web.secretName" -}}
{{- printf "%s-secrets" (include "rvn-gke-web.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Container image reference. A digest, when supplied, wins over the tag. */}}
{{- define "rvn-gke-web.image" -}}
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
{{- define "rvn-gke-web.env" -}}
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- range .Values.ravion.secrets }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "rvn-gke-web.secretName" $ }}
      key: {{ .name }}
{{- end }}
{{- end -}}

{{/*
Lowest replica count the chart can run at: the HPA floor when autoscaling,
otherwise the fixed replica count.
*/}}
{{- define "rvn-gke-web.replicaFloor" -}}
{{- if .Values.spotBurst.enabled -}}
{{- .Values.spotBurst.baselineReplicas -}}
{{- else if .Values.autoscaling.enabled -}}
{{- .Values.autoscaling.minReplicas -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{- define "rvn-gke-web.spotDeploymentName" -}}
{{- $fullname := include "rvn-gke-web.fullname" . -}}
{{- if le (len $fullname) 58 -}}
{{- printf "%s-spot" $fullname -}}
{{- else -}}
{{- printf "%s-%s-spot" ($fullname | trunc 49 | trimSuffix "-") ($fullname | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "rvn-gke-web.spotSelectorName" -}}
{{- $name := include "rvn-gke-web.name" . -}}
{{- if le (len $name) 58 -}}
{{- printf "%s-spot" $name -}}
{{- else -}}
{{- printf "%s-%s-spot" ($name | trunc 49 | trimSuffix "-") ($name | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}

{{- define "rvn-gke-web.spotSelectorLabels" -}}
app.kubernetes.io/name: {{ include "rvn-gke-web.spotSelectorName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "rvn-gke-web.spotReplicasAtMinimum" -}}
{{- max .minimum .replicas -}}
{{- end -}}

{{- define "rvn-gke-web.affinityForPool" -}}
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
{{- $requirement := dict "key" "cloud.google.com/gke-spot" "operator" (ternary "In" "NotIn" $isSpot) "values" (list "true") -}}
{{- $combinedTerms := list -}}
{{- range $term := $terms -}}
  {{- $combined := deepCopy $term -}}
  {{- $expressions := get $combined "matchExpressions" | default (list) -}}
  {{- $_ := set $combined "matchExpressions" (append $expressions $requirement) -}}
  {{- $combinedTerms = append $combinedTerms $combined -}}
{{- end -}}
{{- $_ := set $required "nodeSelectorTerms" $combinedTerms -}}
{{- $_ := set $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" $required -}}
{{- $_ := set $affinity "nodeAffinity" $nodeAffinity -}}
{{- toYaml $affinity -}}
{{- end -}}
{{- end -}}

{{- define "rvn-gke-web.spotDeploymentReplicas" -}}
{{- $root := . -}}
{{- $name := include "rvn-gke-web.spotDeploymentName" $root -}}
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
  {{- include "rvn-gke-web.spotReplicasAtMinimum" (dict "minimum" $root.Values.spotBurst.minReplicas "replicas" (dig "spec" "replicas" 0 $deployment)) -}}
{{- else -}}
{{- include "rvn-gke-web.spotReplicasAtMinimum" (dict "minimum" $root.Values.spotBurst.minReplicas "replicas" 0) -}}
{{- end -}}
{{- end -}}

{{/*
Tolerations for one pool. Spot node pools that node auto-provisioning
creates carry the cloud.google.com/gke-spot=true:NoSchedule taint, so the
Spot pool tolerates it; the baseline keeps only the configured tolerations.
Usage: include "rvn-gke-web.tolerationsForPool" (list $ $isSpot)
*/}}
{{- define "rvn-gke-web.tolerationsForPool" -}}
{{- $root := index . 0 -}}
{{- $isSpot := index . 1 -}}
{{- $tolerations := $root.Values.tolerations | default (list) -}}
{{- if and $root.Values.spotBurst.enabled $isSpot -}}
{{- $tolerations = append $tolerations (dict "key" "cloud.google.com/gke-spot" "operator" "Equal" "value" "true" "effect" "NoSchedule") -}}
{{- end -}}
{{- with $tolerations -}}
{{- toYaml . -}}
{{- end -}}
{{- end -}}
