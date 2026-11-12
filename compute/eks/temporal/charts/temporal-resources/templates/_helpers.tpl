{{- define "temporal-resources.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- /* Selector matching every pod of the upstream Temporal release. */ -}}
{{- define "temporal-resources.temporalSelector" -}}
app.kubernetes.io/name: temporal
app.kubernetes.io/instance: {{ .Values.temporal.releaseName }}
{{- end -}}

{{- /* Selector matching the metrics forwarder's pods. */ -}}
{{- define "temporal-resources.metricsSelector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: metrics
{{- end -}}

{{- /* Peers allowed by a namespace list: every namespace when empty. */ -}}
{{- define "temporal-resources.namespacePeers" -}}
{{- if . }}
{{- range . }}
- namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: {{ . }}
{{- end }}
{{- else }}
- namespaceSelector: {}
{{- end }}
{{- end -}}
