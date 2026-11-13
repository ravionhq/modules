{{/* Labels on every object this chart creates. */}}
{{- define "clickhouse-cluster.labels" -}}
app.kubernetes.io/name: clickhouse
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Name of the ClickHouseKeeperInstallation. */}}
{{- define "clickhouse-cluster.keeperName" -}}
{{ .Values.name }}-keeper
{{- end -}}

{{/* Host and port of the shard's first replica's clickhouse-backup API. */}}
{{- define "clickhouse-cluster.replicaHost" -}}
chi-{{ .root.Values.name }}-{{ .root.Values.clusterName }}-{{ .shard }}-{{ .replica }}.{{ .root.Release.Namespace }}.svc.cluster.local
{{- end -}}

{{/* Pod scheduling shared by ClickHouse, Keeper and the jobs. */}}
{{- define "clickhouse-cluster.scheduling" -}}
{{- with .Values.placement.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.placement.nodePool.create }}
nodeSelector:
  karpenter.sh/nodepool: {{ .Values.placement.nodePool.name }}
{{- end }}
{{- end -}}

{{/*
Spread across zones and nodes. A shard's replicas never share a node; zones are
spread as far as capacity allows, or strictly when zoneSpread is required.
Takes a dict with root, selector (labels matching the pods) and matchLabelKeys.
*/}}
{{- define "clickhouse-cluster.topologySpread" -}}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: {{ ternary "DoNotSchedule" "ScheduleAnyway" (eq .root.Values.placement.zoneSpread "required") }}
    labelSelector:
      matchLabels:
        {{- toYaml .selector | nindent 8 }}
    {{- with .matchLabelKeys }}
    matchLabelKeys:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        {{- toYaml .selector | nindent 8 }}
    {{- with .matchLabelKeys }}
    matchLabelKeys:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end -}}

{{/* Environment variables carrying the admin credentials. */}}
{{- define "clickhouse-cluster.adminEnv" -}}
- name: CLICKHOUSE_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.users.admin.secret }}
      key: username
- name: CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.users.admin.secret }}
      key: password
{{- end -}}

{{/* GRANT target for the writer and reader. */}}
{{- define "clickhouse-cluster.grantTarget" -}}
{{- if .Values.database.name -}}
`{{ .Values.database.name }}`.*
{{- else -}}
*.*
{{- end -}}
{{- end -}}

{{/* Where the server certificate Secret is mounted in ClickHouse pods. */}}
{{- define "clickhouse-cluster.tlsMountPath" -}}
/etc/clickhouse-server/tls
{{- end -}}
