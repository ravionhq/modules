# Helm values for the community opentelemetry-collector chart running as the
# LOG collector, rendered by otel_logs_collector.tf. Structured values are
# emitted with jsonencode() because JSON is valid YAML — it keeps globs and
# resource maps out of the business of YAML quoting and indentation.
#
# This is the second log collector, and it exists because Alloy speaks the Loki
# protocol and nothing else. Every non-Loki destination — CloudWatch Logs,
# Datadog, New Relic, a custom OTLP endpoint — is an exporter here, and they all
# hang off ONE filelog receiver: the node's pod logs are read once however many
# vendors the cluster ships to.
#
# Chart defaults are removed by setting them to null, which is how Helm deletes
# a key a chart shipped: the chart's default config accepts OTLP, Jaeger and
# Zipkin and exports to debug, and a merge alone would leave all of it running.
mode: daemonset
fullnameOverride: ${jsonencode(name)}

image:
  repository: ${jsonencode(image_repository)}
  tag: ${jsonencode(image_tag)}

# The chart renders this as `/<name>`.
command:
  name: ${jsonencode(command_name)}

serviceAccount:
  create: true
  name: ${jsonencode(service_account)}

# k8sattributes resolves a pod's workload from the API server, which is the only
# thing here that reads the Kubernetes API at all. Nothing writes.
clusterRole:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods", "namespaces", "nodes"]
      verbs: ["get", "list", "watch"]
    - apiGroups: ["apps"]
      resources: ["replicasets"]
      verbs: ["get", "list", "watch"]

resources: ${jsonencode(resources)}

# The kubelet writes pod logs owned by root with no world read bit. A collector
# that tails files on the host reads them as root or not at all; the container
# is otherwise unprivileged, and this is the trade for keeping log reads off the
# API server.
securityContext:
  runAsUser: 0
  runAsGroup: 0

# Vendor tokens, by reference: the values come from Kubernetes Secrets the
# External Secrets Operator materializes from Secrets Manager, and the exporter
# configuration reads them as $${env:...}.
extraEnvs: ${jsonencode(extra_envs)}

# /var/log/pods holds the real files; /var/log/containers is only symlinks into
# it, so one read-only host mount covers the whole node.
extraVolumes:
  - name: varlogpods
    hostPath:
      path: /var/log/pods
      type: DirectoryOrCreate

extraVolumeMounts:
  - name: varlogpods
    mountPath: /var/log/pods
    readOnly: true

# Nothing sends telemetry to this collector — it reads files. No Service, and
# none of the chart's default receiver ports.
service:
  enabled: false

ports:
  otlp:
    enabled: false
  otlp-http:
    enabled: false
  jaeger-compact:
    enabled: false
  jaeger-thrift:
    enabled: false
  jaeger-grpc:
    enabled: false
  zipkin:
    enabled: false
  metrics:
    enabled: false

config:
  receivers:
    jaeger: null
    zipkin: null
    otlp: null
    filelog:
      include: ["/var/log/pods/*/*/*.log"]
      # The collector's own output, and every namespace the operator asked to
      # keep out. The pod log path is /var/log/pods/<namespace>_<pod>_<uid>/,
      # so a namespace exclusion is a glob rather than a filter processor —
      # the file is never opened, instead of being read and then dropped.
      exclude: ${jsonencode(exclude_paths)}
      # Only what the node produces from now on. Replaying a node's entire log
      # history into a vendor on every collector restart is a surprise bill.
      start_at: end
      include_file_path: true
      include_file_name: false
      operators:
        # One operator, deliberately: `container` handles the CRI and Docker
        # line formats, recovers the container's own timestamp, reassembles
        # partial lines, and lifts namespace, pod, container and UID out of the
        # file path into resource attributes.
        - type: container
          id: container-parser

  processors:
    # Sized as a percentage of the container's memory limit, which is why
    # otel_logs_collector_resources sets one by default.
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
    batch: {}

    # The workload a pod belongs to, from the API server. Associated by pod UID
    # because that is what the container operator recovered from the path —
    # there is no pod IP on a log line to match against.
    k8sattributes:
      auth_type: serviceAccount
      passthrough: false
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.node.name
          - k8s.container.name
          - k8s.deployment.name
          - k8s.statefulset.name
          - k8s.daemonset.name
          - k8s.cronjob.name
          - k8s.job.name
      pod_association:
        - sources:
            - from: resource_attribute
              name: k8s.pod.uid

    # The label contract, in OpenTelemetry's spelling: namespace, pod,
    # container, workload. `workload` is whichever controller kind owns the pod,
    # falling back to the pod's own name for a bare pod.
    transform/ravion:
      error_mode: ignore
      log_statements:
        - context: resource
          statements: ${jsonencode(resource_statements)}

  exporters: ${jsonencode(exporters)}

  extensions: ${jsonencode(extensions)}

  service:
    # health_check is the chart's readiness and liveness probe; removing it
    # fails the pod, not just the extension.
    extensions: ${jsonencode(service_extensions)}
    pipelines:
      metrics: null
      traces: null
      logs:
        receivers:
          - filelog
        processors:
          - memory_limiter
          - k8sattributes
          - transform/ravion
          - batch
        exporters: ${jsonencode(pipeline_exporters)}
