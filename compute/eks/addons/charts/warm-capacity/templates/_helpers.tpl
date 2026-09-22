{{- define "warm-capacity.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "warm-capacity.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "warm-capacity.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "warm-capacity.labels" -}}
app.kubernetes.io/name: {{ include "warm-capacity.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
