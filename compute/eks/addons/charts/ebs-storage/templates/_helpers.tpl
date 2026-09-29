{{- define "ebs-storage.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ebs-storage.labels" -}}
app.kubernetes.io/name: {{ include "ebs-storage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ravion
{{- end -}}

{{- define "ebs-storage.resizerName" -}}
{{- printf "%s-volume-resizer" (include "ebs-storage.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Annotation the admission policy writes on a StatefulSet whose volume claim
templates asked to grow: comma-separated <template>=<storage> pairs.
*/}}
{{- define "ebs-storage.sizesAnnotation" -}}
ravion.com/volume-claim-template-sizes
{{- end -}}
