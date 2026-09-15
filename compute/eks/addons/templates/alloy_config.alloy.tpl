// Grafana Alloy configuration, rendered by alloy.tf. Alloy syntax, not YAML.
//
// THE LABEL SET BELOW IS A CONTRACT. Ravion's log views build LogQL selectors
// on `namespace`, `app` and `workload` (and, for Operator executor pods only,
// `ravion_module_deployment`), and read `level` and `pod` from structured
// metadata. Adding a label here is cheap to write and expensive to run: every
// distinct combination is a separate Loki stream, so a pod-name label turns one
// stream per workload into one per replica per restart. Anything
// high-cardinality belongs in structured metadata, which is stored but not
// indexed: the pod name travels that way, so a view can filter one replica's
// lines without Loki indexing replicas. Changing these names is a breaking
// change for the dashboard.
//
// ONE PIPELINE, SEVERAL DESTINATIONS. Every loki-family provider the user
// selected gets its own loki.write below, and the same processed stream is
// forwarded to all of them: the files are tailed once however wide the fan-out.

// Pods on THIS node only. Alloy runs as a DaemonSet, so an unfiltered
// discovery would have every instance watching every pod in the cluster and
// then discarding all but its own — the chart sets HOSTNAME from
// spec.nodeName, which is what makes the field selector possible.
discovery.kubernetes "pods" {
  role = "pod"

  selectors {
    role  = "pod"
    field = "spec.nodeName=" + sys.env("HOSTNAME")
  }
}

discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pods.targets

%{ if namespace_exclude_regex != "" ~}
  // Namespaces the operator asked to keep out of the log store, dropped at
  // discovery so their files are never opened at all.
  //
  // One exception: Ravion Operator's executor pods. Each runs a single deploy
  // and its stdout is that deploy's log, which the Ravion deploy page reads
  // back from this Loki. They live in the Operator namespace, which is
  // excluded by default, so the drop is gated on the label the Operator puts
  // on them — a pod without it is dropped exactly as before.
  rule {
    source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_labelpresent_operator_ravion_dev_module_deployment"]
    separator     = ";"
    regex         = "(${namespace_exclude_regex});"
    action        = "drop"
  }

%{ endif ~}
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }

  // `app` prefers the recommended label but accepts the older bare one. Both
  // rules use a regex that only matches non-empty values, so a missing label
  // leaves whatever the previous rule set rather than blanking it.
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app"]
    regex         = "(.+)"
    target_label  = "app"
  }

  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
    regex         = "(.+)"
    target_label  = "app"
  }

  // The controller name for a Deployment's pod is the ReplicaSet, whose name
  // is "<deployment>-<hash>". Stripping the hash gives the workload a human
  // named it, and keeps the label stable across rollouts.
  rule {
    source_labels = ["__meta_kubernetes_pod_controller_name"]
    regex         = "([0-9a-z-.]+?)(-[0-9a-f]{8,10})?"
    target_label  = "workload"
  }

  // Last resort for a pod with no app label at all: match only when `app` is
  // still empty (the leading separator), and copy `workload` into it.
  rule {
    source_labels = ["app", "workload"]
    separator     = ";"
    regex         = ";(.+)"
    replacement   = "$1"
    target_label  = "app"
  }

  // Executor pods: the deploy they ran, so one deploy's log is one selector.
  // Bounded by the number of deploys, not replicas or restarts.
  rule {
    source_labels = ["__meta_kubernetes_pod_label_operator_ravion_dev_module_deployment"]
    regex         = "(.+)"
    target_label  = "ravion_module_deployment"
  }

  // The pod name rides along as a label only as far as loki.process, which
  // moves it into structured metadata (see stage.structured_metadata below).
  // It must never reach Loki as a stream label.
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }

  // The kubelet writes every container's stdout under the pod's UID.
  rule {
    source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    action        = "replace"
    replacement   = "/var/log/pods/*$1/*.log"
    target_label  = "__path__"
  }
}

local.file_match "pod_logs" {
  path_targets = discovery.relabel.pod_logs.output
}

loki.source.file "pod_logs" {
  targets    = local.file_match.pod_logs.targets
  forward_to = [loki.process.pod_logs.receiver]
}

loki.process "pod_logs" {
  forward_to = [${join(", ", [for destination in destinations : "loki.write.${destination.name}.receiver"])}]

  // containerd writes CRI-format lines: "<ts> <stream> <flags> <message>".
  // This stage recovers the container's own timestamp, so a log's time is when
  // the application emitted it rather than when Alloy read the file.
  stage.cri {}

  // Best-effort severity. Structured metadata, not a label: the value is
  // useful to filter on and would be ruinous to index, because a stream would
  // then exist per level per workload and a single request's lines would be
  // split across several of them.
  stage.regex {
    expression = "(?i)\\b(?P<level>trace|debug|info|warn|warning|error|fatal|panic)\\b"
  }

  // `level` comes from the extracted map above. `pod` is read from the stream
  // labels and REMOVED from them by this stage, which is the whole point: the
  // replica name is filterable per line without Loki indexing one stream per
  // replica per restart.
  stage.structured_metadata {
    values = {
      level = "",
      pod   = "",
    }
  }

  // loki.source.file attaches the log file's path as a `filename` label. The
  // path contains the pod UID, so leaving it in place would reintroduce
  // exactly the per-pod cardinality this label set exists to avoid.
  stage.label_drop {
    values = ["filename"]
  }
}
%{ for destination in destinations ~}

// ${destination.comment}
loki.write "${destination.name}" {
  endpoint {
    url = "${destination.url}"
%{ if destination.username != null ~}

    // The password is read from the environment at start-up. It reaches the
    // pod from a Kubernetes Secret the External Secrets Operator materializes
    // out of Secrets Manager, so the token is in neither this file nor Helm.
    basic_auth {
      username = "${destination.username}"
      password = sys.env("${destination.password_env}")
    }
%{ endif ~}
  }
}
%{ endfor ~}
