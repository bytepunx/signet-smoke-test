## signet-smoke-test

> [!WARNING]
> **Testing only. Never deploy these images, or anything derived from them, in a real
> environment.**
>
> The `echo` containers this harness deploys print every secret and config value they
> retrieve from [signet](https://github.com/bytepunx/signet) **directly to stdout, in
> plaintext**, by design — that's how this harness verifies a client library actually
> round-tripped real data through a real signet + SPIRE deployment. Container logs are
> routinely captured by log aggregation (Loki, CloudWatch, Datadog, and similar), which
> would leak those secrets outside signet's control entirely. There is no production use
> case for a container that behaves this way.

### What this is

A disposable Kubernetes cluster that smoke-tests [signet-clients](https://github.com/bytepunx/signet-clients)'
client libraries against a real signet + SPIRE deployment — real SPIFFE mTLS, real
SOPS-encrypted secrets synced from a real GitHub repository, and a real watch → debounce
→ lock → restart cycle. Every language's `examples/echo` fixture (in `signet-clients`)
connects, prints what it fetched, then blocks until signet reports a change and this
replica acquires the fleet-wide restart lock, then exits — proving the coordinated-restart
feature actually works end to end, not just against hand-written fakes.

### Topology

One Kubernetes namespace per active client language, each with a single `echo`
ServiceAccount:

| Namespace         | Secret/config scope    |
|--------------------|--------------------------|
| `smoke-go`         | `smoke-go/echo`          |
| `smoke-typescript` | `smoke-typescript/echo`  |
| `smoke-rust`       | `smoke-rust/echo`        |
| `smoke-csharp`     | `smoke-csharp/echo`      |

Since each namespace's name and its `echo` ServiceAccount exactly match a secret's own
`namespace`/`service`, signet's convention-first automatic-access rule grants each
workload access to its own scope with no policy needed (see signet's
[`docs/policies.md`](https://github.com/bytepunx/signet/blob/main/docs/policies.md)).

A fifth scope, `smoke-shared/common`, holds a secret and config value that don't belong
to any one language. Access to it is granted via a single cross-namespace policy created
by `scripts/provision.sh`:

```
signet policy create --spiffe-id "spiffe://smoke.cluster.local/ns/*/sa/echo" \
  --namespace smoke-shared --service common
```

(any namespace, ServiceAccount literally named `echo` — matches every echo workload here
and nothing else).

### Python is not deployed

`python` is deliberately excluded from `scripts/lib.sh`'s `LANGUAGES` list.
`grpc-python` has no public API to validate a server certificate that carries only a
SPIFFE URI SAN — which is exactly what signet's workload listener presents — so the
Python client's `dial_workload` cannot connect to a real signet instance at all. This
was confirmed live against this exact cluster, not just theorized: every
`grpc.ssl_target_name_override` value was tried and had zero effect. It's a
long-standing, unresolved gap in `grpc-python` itself
([grpc/grpc#10701](https://github.com/grpc/grpc/issues/10701)), not a bug in the client
or in signet. See [bytepunx/signet-clients#14](https://github.com/bytepunx/signet-clients/issues/14)
for the full writeup and tracking, and `manifests/echo-python.yaml` (left in place,
unused) — re-enabling Python here is a one-line change to `LANGUAGES` once that issue is
resolved.

### Prerequisites

- [`kluster`](https://github.com/bytepunx/kluster) — provisions the disposable cluster
  (SPIRE + signet together, via `kluster up --profile signet`)
- [`signet`](https://github.com/bytepunx/signet) CLI, on `PATH`
- `kubectl`, `docker`, `gh` (authenticated, with push access to this repo), `git`,
  `ssh-keygen`, `sops`
- The active languages' echo images already built and available to the cluster (pushed
  to `ghcr.io/bytepunx/signet-echo-<lang>:latest`, or built locally and imported — see
  "Building images locally" below)

### Walkthrough

```
scripts/up.sh              # kluster up --profile signet; kluster use <cluster>
scripts/provision.sh        # admin RBAC, SOPS key, secrets/config, deploy key,
                             # repo registration + sync, shared-secret policy
scripts/deploy-echo.sh      # kubectl apply the echo Deployments
scripts/verify.sh           # grep each pod's logs for its expected secret/config values
scripts/update-secret-and-watch.sh   # change one secret, re-sync, watch a pod cycle live
scripts/down.sh              # kluster down
```

Both `scripts/provision.sh` and the overall sequence are idempotent — safe to re-run
against an already-provisioned cluster (existing repo registration, SOPS key, and policy
are detected and reused rather than duplicated).

### Building images locally

Each language's `examples/echo/Dockerfile` lives in
[signet-clients](https://github.com/bytepunx/signet-clients), build context is that
language's own subdirectory:

```
docker build -t signet-echo-go:local-test -f go/examples/echo/Dockerfile go
```

For a `k3d`-provisioned `kluster` cluster (the default provider here), import the built
image directly into the cluster's containerd rather than pushing to a registry:

```
docker save signet-echo-go:local-test | docker exec -i k3d-<cluster>-server-0 ctr image import -
kubectl set image deploy/echo echo=signet-echo-go:local-test -n smoke-go
kubectl patch deploy echo -n smoke-go --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Never"}]'
```

### Teardown

```
scripts/down.sh
```

Removes the entire disposable cluster. Nothing in this harness is meant to persist —
`scripts/up.sh` starts clean every time.
