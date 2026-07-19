#!/usr/bin/env bash
# Shared helpers sourced by the other scripts in this directory.
set -euo pipefail

CLUSTER_NAME="signet-smoke"
TRUST_DOMAIN="smoke.cluster.local"
SIGNET_NAMESPACE="signet"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Namespace/service pairs, one per language, plus the shared scope. Every
# other script in this directory iterates this same list so it only needs
# to be edited in one place when a language is added or removed.
#
# python is deliberately excluded: grpc-python has no public API to
# validate a server certificate carrying only a SPIFFE URI SAN (which is
# what signet's workload listener presents), so the Python client's
# dial_workload cannot connect to a real signet instance at all — confirmed
# live, not just theorized. See bytepunx/signet-clients#14 for the full
# writeup and tracking; re-add "python" here once that's resolved.
LANGUAGES=(go typescript rust csharp)

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
die() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found on PATH"
}

# admin_token mints (or reuses, within this shell) a short-lived signet-admin
# token. Requires manifests/admin-rbac.yaml to already be applied — without
# it, the token authenticates fine but every admin RPC returns
# PERMISSION_DENIED (see manifests/admin-rbac.yaml's own comment for why).
#
# --audience signet is required: the chart's default signet.kubeAudiences
# value is "signet" (deploy/helm/signet/values.yaml), and TokenReview rejects
# any token whose audience list doesn't include one of the configured
# audiences. A bare `kubectl create token` (no --audience) mints a token
# scoped to the default API server audiences, which does not include
# "signet" — that token authenticates to the *cluster* fine but signetd
# itself rejects it as Unauthenticated.
admin_token() {
  kubectl create token signet-admin -n "$SIGNET_NAMESPACE" --audience signet --duration=1h
}
