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
