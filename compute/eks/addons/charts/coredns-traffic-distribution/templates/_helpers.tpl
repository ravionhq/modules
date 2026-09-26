{{- define "coredns-traffic-distribution.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coredns-traffic-distribution.labels" -}}
app.kubernetes.io/name: {{ include "coredns-traffic-distribution.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ravion
{{- end -}}

{{/*
One Job body shared by the apply and revert hooks. The only difference is the
JSON merge patch: the configured value on the way in, null on the way out.
*/}}
{{- define "coredns-traffic-distribution.job" -}}
{{- $root := index . 0 -}}
{{- $suffix := index . 1 -}}
{{- $hooks := index . 2 -}}
{{- $patch := index . 3 -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "coredns-traffic-distribution.name" $root }}-{{ $suffix }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "coredns-traffic-distribution.labels" $root | nindent 4 }}
  annotations:
    helm.sh/hook: {{ $hooks }}
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ $root.Values.backoffLimit }}
  template:
    metadata:
      labels:
        {{- include "coredns-traffic-distribution.labels" $root | nindent 8 }}
    spec:
      serviceAccountName: {{ include "coredns-traffic-distribution.name" $root }}
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: kubectl
          image: {{ $root.Values.image.repository }}:{{ $root.Values.image.tag }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          # Resolved through the image's PATH rather than relying on an
          # ENTRYPOINT, so a mirror built from a different base still works.
          command: ["kubectl"]
          args:
            - patch
            - service
            - {{ $root.Values.service.name }}
            - --namespace={{ $root.Values.service.namespace }}
            - --type=merge
            - {{ printf "--patch=%s" ($patch | toJson) | quote }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 64Mi
{{- end -}}
