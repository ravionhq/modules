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

{{/*
Separation the spread above cannot guarantee (maxSkew only balances counts):
pods sharing the selector, and the values of matchLabelKeys (a ClickHouse
shard), on different nodes, strictly when nodeSpread is required and as far as
the nodes allow when it is preferred; and in different zones when zoneSpread
is required. Takes the same dict as topologySpread.
*/}}
{{- define "clickhouse-cluster.antiAffinityTerm" -}}
topologyKey: {{ .topologyKey }}
labelSelector:
  matchLabels:
    {{- toYaml .selector | nindent 4 }}
{{- with .matchLabelKeys }}
matchLabelKeys:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "clickhouse-cluster.antiAffinity" -}}
{{- $nodeRequired := eq .root.Values.placement.nodeSpread "required" -}}
{{- $zoneRequired := eq .root.Values.placement.zoneSpread "required" -}}
{{- $node := dict "topologyKey" "kubernetes.io/hostname" "selector" .selector "matchLabelKeys" .matchLabelKeys -}}
{{- $zone := dict "topologyKey" "topology.kubernetes.io/zone" "selector" .selector "matchLabelKeys" .matchLabelKeys -}}
affinity:
  podAntiAffinity:
    {{- if or $nodeRequired $zoneRequired }}
    requiredDuringSchedulingIgnoredDuringExecution:
      {{- if $nodeRequired }}
      - {{- include "clickhouse-cluster.antiAffinityTerm" $node | nindent 8 }}
      {{- end }}
      {{- if $zoneRequired }}
      - {{- include "clickhouse-cluster.antiAffinityTerm" $zone | nindent 8 }}
      {{- end }}
    {{- end }}
    {{- if not $nodeRequired }}
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          {{- include "clickhouse-cluster.antiAffinityTerm" $node | nindent 10 }}
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
