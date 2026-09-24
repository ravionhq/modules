#!/bin/sh
# Grows the PersistentVolumeClaims of every StatefulSet that carries the
# requested-sizes annotation written by the admission policy.
#
# Each pass lists annotated StatefulSets and all PVCs once, works out which
# bound PVCs of ordinals 0..replicas-1 are smaller than the requested size,
# and patches their storage request. The EBS CSI driver expands the volume and
# the kubelet grows the filesystem while the pod keeps running. The patch only
# ever raises a request, and a pass that finds nothing to do changes nothing,
# so passes are safe to repeat.
set -u

ANNOTATION="${SIZES_ANNOTATION:?}"
INTERVAL="${INTERVAL_SECONDS:-30}"
WORK="${TMPDIR:-/tmp}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

pass() {
  kubectl get statefulsets --all-namespaces -o go-template='{{range .items}}{{$s := .}}{{with .metadata.annotations}}{{with index . "'"${ANNOTATION}"'"}}{{$s.metadata.namespace}} {{$s.metadata.name}} {{$s.spec.replicas}} {{.}}{{"\n"}}{{end}}{{end}}{{end}}' \
    >"${WORK}/statefulsets" || return 1
  [ -s "${WORK}/statefulsets" ] || return 0

  kubectl get persistentvolumeclaims --all-namespaces -o go-template='{{range .items}}{{.metadata.namespace}} {{.metadata.name}} {{.status.phase}} {{.spec.resources.requests.storage}}{{"\n"}}{{end}}' \
    >"${WORK}/claims" || return 1

  # Prints "<namespace> <claim> <current> <requested>" for each claim to grow.
  awk '
    function bytes(q,    n, u, m) {
      if (!match(q, /^[0-9.]+/)) return -1
      n = substr(q, 1, RLENGTH) + 0
      u = substr(q, RLENGTH + 1)
      m = 1
      if (u == "Ki") m = 1024; else if (u == "Mi") m = 1024^2; else if (u == "Gi") m = 1024^3
      else if (u == "Ti") m = 1024^4; else if (u == "Pi") m = 1024^5; else if (u == "Ei") m = 1024^6
      else if (u == "k") m = 1e3; else if (u == "M") m = 1e6; else if (u == "G") m = 1e9
      else if (u == "T") m = 1e12; else if (u == "P") m = 1e15; else if (u == "E") m = 1e18
      else if (u == "m") m = 1e-3; else if (u != "") return -1
      return n * m
    }
    FNR == NR { phase[$1 "/" $2] = $3; size[$1 "/" $2] = $4; next }
    {
      namespace = $1; statefulset = $2; replicas = $3 + 0
      count = split($4, pairs, ",")
      for (p = 1; p <= count; p++) {
        if (split(pairs[p], kv, "=") != 2) continue
        want = bytes(kv[2])
        if (want < 0) { print "skip " namespace " " statefulset " unparseable size " kv[2] > "/dev/stderr"; continue }
        for (i = 0; i < replicas; i++) {
          key = namespace "/" kv[1] "-" statefulset "-" i
          if (!(key in phase) || phase[key] != "Bound") continue
          have = bytes(size[key])
          if (have >= 0 && have < want) print namespace, kv[1] "-" statefulset "-" i, size[key], kv[2]
        }
      }
    }
  ' "${WORK}/claims" "${WORK}/statefulsets" >"${WORK}/resizes" || return 1

  while read -r namespace claim current requested; do
    log "growing ${namespace}/${claim} from ${current} to ${requested}"
    kubectl patch persistentvolumeclaim "${claim}" --namespace "${namespace}" --type=merge \
      --patch "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${requested}\"}}}}" \
      || log "could not grow ${namespace}/${claim}; retrying next pass (a StorageClass without allowVolumeExpansion cannot grow)"
  done <"${WORK}/resizes"
}

log "resizer started; pass every ${INTERVAL}s"
while true; do
  pass || log "pass failed; retrying"
  sleep "${INTERVAL}"
done
