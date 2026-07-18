#!/usr/bin/env bash
# Tears down the disposable cluster. Everything provisioned by up.sh and
# provision.sh lives inside it — nothing persists outside the cluster except
# the encrypted secrets/config committed to this repo (harmless without the
# master key, which only ever existed inside the destroyed cluster).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kluster

log "kluster down --name $CLUSTER_NAME"
kluster --config "$REPO_ROOT/kluster.yaml" down --name "$CLUSTER_NAME"
