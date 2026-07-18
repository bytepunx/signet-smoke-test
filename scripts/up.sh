#!/usr/bin/env bash
# Provisions the disposable cluster: SPIRE + signet, via kluster's own
# "signet" profile (see README.md for exactly what that gets you for free).
# Idempotent — safe to re-run against an already-running cluster.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kluster
require_cmd kubectl

log "kluster up (profile/name/trust-domain from kluster.yaml: $CLUSTER_NAME / $TRUST_DOMAIN)"
kluster --config "$REPO_ROOT/kluster.yaml" up

log "kluster use $CLUSTER_NAME"
kluster --config "$REPO_ROOT/kluster.yaml" use "$CLUSTER_NAME"

log "cluster ready. Run scripts/provision.sh next."
