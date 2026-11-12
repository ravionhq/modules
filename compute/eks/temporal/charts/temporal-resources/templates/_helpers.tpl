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

{{- /* The External Secrets store every ExternalSecret here reads through. */ -}}
{{- define "temporal-resources.secretStoreRef" -}}
name: {{ .Values.externalSecrets.secretStoreName }}
kind: {{ .Values.externalSecrets.secretStoreKind }}
{{- end -}}

{{- /* A remoteRef for a Secrets Manager secret, whole or one JSON key. */ -}}
{{- define "temporal-resources.remoteRef" -}}
key: {{ .remoteSecret | quote }}
{{- with .remoteProperty }}
property: {{ . | quote }}
{{- end }}
{{- end -}}

{{- /* Selector matching the JWKS server's pods. */ -}}
{{- define "temporal-resources.jwksSelector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: jwks
{{- end -}}

{{- /* Selector matching the upstream release's pods of one component. */ -}}
{{- define "temporal-resources.componentSelector" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: temporal
app.kubernetes.io/instance: {{ $root.Values.temporal.releaseName }}
app.kubernetes.io/component: {{ index . 1 }}
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
