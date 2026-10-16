#!/bin/sh
# Moves one StatefulSet to the volume layout its owning release is about to
# apply, and recovers pods left behind by an earlier, orphaning migration.
#
# A StatefulSet's volumeClaimTemplates are immutable, so the owner cannot switch
# between an emptyDir and a PersistentVolumeClaim in place. When the layout
# differs, the StatefulSet is deleted together with its pods, and the owner,
# upgraded right after this Job, recreates it with fresh pods on the new
# volumes. Orphaning the pods instead does not work: the recreated StatefulSet
# adopts them, tries to add the claim to each running pod, which Kubernetes
# forbids, and never gets as far as replacing them.
#
# When the layout already matches, only pods that do not mount their claims are
# deleted: the ones chart 0.1.0 orphaned. Their StatefulSet recreates them. A
# StatefulSet in the right shape with healthy pods is left alone.
#
# Before any pod goes, FLUSH_URL (when set) is POSTed so the store writes what
# it holds in memory to object storage.
set -eu

: "${STATEFULSET:?}" "${NAMESPACE:?}" "${PERSISTENT:?}"
FLUSH_URL="${FLUSH_URL:-}"
TIMEOUT="${DELETE_TIMEOUT:-10m}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

flush() {
  [ -n "${FLUSH_URL}" ] || return 0
  log "flushing ${FLUSH_URL}"
  # Best effort: a store that does not answer usually has nothing left in
  # memory, and refusing would leave the layout stuck.
  wget -q -T 120 -O /dev/null --post-data= "${FLUSH_URL}" || log "flush failed; continuing"
}

# "<replicas> <template>,<template>," or nothing when there is no StatefulSet.
current="$(kubectl get statefulset "${STATEFULSET}" --namespace="${NAMESPACE}" --ignore-not-found \
  -o go-template='{{.spec.replicas}} {{range .spec.volumeClaimTemplates}}{{.metadata.name}},{{end}}')"
if [ -z "${current}" ]; then
  log "no StatefulSet ${NAMESPACE}/${STATEFULSET}; nothing to migrate"
  exit 0
fi
replicas="${current%% *}"
templates="$(echo "${current#* }" | tr ',' ' ')"

has_claims=false
[ -n "$(echo "${templates}" | tr -d ' ')" ] && has_claims=true

if [ "${has_claims}" != "${PERSISTENT}" ]; then
  log "volume layout changes (persistent: ${has_claims} -> ${PERSISTENT}); deleting ${NAMESPACE}/${STATEFULSET} and its pods"
  flush
  kubectl delete statefulset "${STATEFULSET}" --namespace="${NAMESPACE}" \
    --cascade=foreground --ignore-not-found --wait --timeout="${TIMEOUT}"
  log "deleted; the owning release recreates it"
  exit 0
fi

i=0
while [ "${i}" -lt "${replicas}" ]; do
  pod="${STATEFULSET}-${i}"
  i=$((i + 1))
  # "present <claim> <claim> ", or nothing when the pod does not exist.
  mounted="$(kubectl get pod "${pod}" --namespace="${NAMESPACE}" --ignore-not-found \
    -o go-template='present {{range .spec.volumes}}{{with .persistentVolumeClaim}}{{.claimName}} {{end}}{{end}}')"
  [ -n "${mounted}" ] || continue

  missing=""
  for template in ${templates}; do
    case " ${mounted} " in
      *" ${template}-${pod} "*) ;;
      *) missing="${missing} ${template}-${pod}" ;;
    esac
  done
  [ -n "${missing}" ] || continue

  log "${NAMESPACE}/${pod} does not mount${missing}; replacing it"
  flush
  kubectl delete pod "${pod}" --namespace="${NAMESPACE}" --ignore-not-found --wait --timeout="${TIMEOUT}"
done
log "volume layout up to date"
