# lab-forgejo

Source-of-truth Helm chart and deployment configuration for running **Forgejo** in a hardened Kubernetes homelab on **Talos Linux**.

## Architecture

- **Forgejo**: Official rootless container image (`codeberg.org/forgejo/forgejo:17.0.2-rootless`, UID/GID `1000:1000`) listening on unprivileged HTTP port `3000`.
- **PostgreSQL**: Hardened rootless PostgreSQL from [`joeckr/oci-postgres`](https://github.com/joeckr/oci-postgres) (`ghcr.io/joeckr/postgres:0.3.0`, `PGDATA=/tmp/data`).
- **Storage**: Longhorn `ReadWriteOnce` PersistentVolumeClaims (`storageClassName: longhorn`) with `Recreate` deployment strategies to avoid RWO Multi-Attach deadlocks during rollouts.
- **Security**: Fully compliant with Kubernetes **Pod Security Standards (`restricted`)** — `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, and Talos control-plane/master tolerations.
- **Routing**: Kubernetes Gateway API `HTTPRoute` (`gateway.networking.k8s.io/v1`) attached to a Traefik `Gateway` behind a Cloudflare Tunnel, serving `https://forgejo.joeckr.dev/`.
- **Authentication (OIDC)**: Generic OpenID Connect auto-configured idempotently on startup via an init container (`environment-to-ini` -> `forgejo migrate` -> `forgejo admin auth add-oauth` / `update-oauth`).
- **Zero Secrets in Git**: All sensitive values (`db-password`, `secret-key`, `internal-token`, `jwt-secret`, `oidc-client-id`, `oidc-client-secret`) are referenced from an install-time Kubernetes `Secret` (`forgejo-secrets`) via `secretKeyRef`.

---

## Directory Structure

```text
.
├── .github/
│   └── workflows/
│       ├── lint.yml                 # Lints workflows, commits, and shell scripts
│       ├── security.yml             # Secret scanning (betterleaks) and zizmor audits
│       ├── release.yml              # Semantic release and Helm chart publishing to GHCR
│       └── test_release.yml         # PR dry-run test for releases and chart packaging
├── chart/
│   ├── Chart.yaml                   # Helm chart metadata
│   ├── values.yaml                  # Non-secret configuration defaults
│   ├── .helmignore
│   └── templates/
│       ├── _helpers.tpl             # Shared labels and Forgejo env helpers
│       ├── pvc.yaml                 # Longhorn PVCs for Forgejo and PostgreSQL
│       ├── postgres-deployment.yaml # joeckr/oci-postgres Deployment
│       ├── postgres-service.yaml    # Internal ClusterIP Service for PostgreSQL
│       ├── forgejo-configmap.yaml   # Idempotent migrate + OIDC init script
│       ├── deployment.yaml          # Forgejo Deployment + init containers
│       ├── service.yaml             # Forgejo HTTP (and optional SSH) Service
│       ├── httproute.yaml           # Gateway API HTTPRoute for Traefik
│       ├── ingress.yaml             # Optional Ingress fallback (disabled by default)
│       └── NOTES.txt                # Post-install verification commands
├── scripts/
│   └── create-secrets.sh            # Install-time Secret generator/applier
├── compose.yml                      # Local Forgejo + PostgreSQL test stack
├── hk.pkl                           # Git hooks and lint checks
├── mise.toml                        # Tool versions and task runner
└── README.md
```

---

## Deploying to Talos Linux Kubernetes Homelab

### 1. Create a `restricted` PSS Namespace

```sh
kubectl create namespace forgejo
kubectl label namespace forgejo \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### 2. Configure Your OIDC Provider

In your OIDC identity provider, register a confidential OAuth2/OIDC client for Forgejo with:
- **Redirect URI**: `https://forgejo.joeckr.dev/user/oauth2/OIDC/callback`
  *(If you change `oidc.name` in `values.yaml`, replace `OIDC` in the callback path with that name.)*
- **Scopes**: `openid`, `email`, `profile` (plus `groups` if using group mapping)

### 3. Create the Install-Time Kubernetes Secret

Run the helper script to generate random cryptographic keys locally and apply `forgejo-secrets` directly to the cluster (nothing is written to disk):

```sh
./scripts/create-secrets.sh --namespace forgejo
# or: mise run secrets
```

If you want to deploy without OIDC first, pass `--without-oidc`.

### 4. Install or Upgrade the Helm Chart

Pass your OIDC discovery URL (and adjust `gateway.parentRefs` if your Traefik `Gateway` name, namespace, or listener `sectionName` differs):

```sh
helm upgrade --install forgejo ./chart \
  --namespace forgejo \
  --set oidc.autoDiscoverUrl="https://auth.joeckr.dev/.well-known/openid-configuration"
```

Optional overrides for OIDC group-based admin mapping or Traefik Gateway reference:

```sh
helm upgrade --install forgejo ./chart \
  --namespace forgejo \
  --set oidc.autoDiscoverUrl="https://auth.joeckr.dev/.well-known/openid-configuration" \
  --set oidc.scopes="openid email profile groups" \
  --set oidc.groupClaimName="groups" \
  --set oidc.adminGroup="forgejo-admins" \
  --set gateway.parentRefs[0].name="traefik-gateway" \
  --set gateway.parentRefs[0].namespace="traefik" \
  --set gateway.parentRefs[0].sectionName="web"
```

### 5. Verify Deployment & PSS Compliance

```sh
# Confirm Longhorn PVCs are Bound and pods are Running (no PSA rejections)
kubectl -n forgejo get pvc,pods

# Check init container logs (DB wait, migrations, OIDC reconciliation)
kubectl -n forgejo logs deploy/forgejo -c configure-forgejo

# Check Gateway API HTTPRoute acceptance
kubectl -n forgejo get httproute forgejo-httproute -o yaml

# Confirm OIDC auth source is registered in Forgejo
kubectl -n forgejo exec deploy/forgejo -- \
  forgejo --config /etc/gitea/app.ini admin auth list
```

---

## PSS `restricted` Compliance Matrix

| Security Dimension | `restricted` PSS Requirement | Implementation |
| --- | --- | --- |
| **Workload Execution** | `runAsNonRoot: true` | Forgejo (`1000:1000` rootless), `joeckr/oci-postgres` (arbitrary non-root UID, GID 0) |
| **Capabilities** | `capabilities.drop: ["ALL"]` | Applied to all init and application containers |
| **Privilege Escalation** | `allowPrivilegeEscalation: false` | Applied to all init and application containers |
| **Seccomp Profile** | `RuntimeDefault` | Set in `podSecurityContext` on both Deployments |
| **Service Account Token** | Disabled unless needed | `automountServiceAccountToken: false` on both Deployments |
| **Storage Permissions** | Non-root writable PVCs | `fsGroup` + `fsGroupChangePolicy: OnRootMismatch` on Longhorn PVCs |
| **Ports** | Unprivileged (> 1024) | Forgejo HTTP `3000`, SSH `2222`, PostgreSQL `5432` |

---

## Key Configuration Values (`chart/values.yaml`)

| Parameter | Description | Default |
| --- | --- | --- |
| `existingSecret` | Name of the install-time Kubernetes Secret | `forgejo-secrets` |
| `forgejo.image` / `tag` | Forgejo rootless container image | `codeberg.org/forgejo/forgejo:17.0.2-rootless` |
| `forgejo.domain` | Public domain name | `forgejo.joeckr.dev` |
| `forgejo.rootUrl` | External base URL | `https://forgejo.joeckr.dev/` |
| `forgejo.storage.storageClass` | PVC StorageClass for Forgejo data & config | `longhorn` |
| `forgejo.storage.size` | PVC size for Forgejo | `20Gi` |
| `forgejo.ssh.enabled` | Enable built-in Go SSH server & SSH Service | `false` |
| `oidc.enabled` | Auto-reconcile OIDC auth source on startup | `true` |
| `oidc.name` | Display name of the OIDC login button | `OIDC` |
| `oidc.autoDiscoverUrl` | OIDC `.well-known/openid-configuration` URL | `""` |
| `oidc.scopes` | Space-separated OIDC scopes | `openid email profile` |
| `oidc.groupClaimName` | Optional OIDC claim for group mapping | `""` |
| `oidc.adminGroup` | Optional OIDC group granted Forgejo admin | `""` |
| `postgres.enabled` | Deploy `joeckr/oci-postgres` alongside Forgejo | `true` |
| `postgres.image` / `tag` | Hardened rootless PostgreSQL image | `ghcr.io/joeckr/postgres:0.3.0` |
| `postgres.storage.storageClass` | PVC StorageClass for PostgreSQL | `longhorn` |
| `postgres.storage.size` | PVC size for PostgreSQL | `5Gi` |
| `gateway.enabled` | Create Gateway API `HTTPRoute` | `true` |
| `gateway.parentRefs` | Target Traefik `Gateway` reference(s) | `traefik/traefik-gateway` (`web`) |
| `gateway.hostnames` | Hostnames matched by the `HTTPRoute` | `["forgejo.joeckr.dev"]` |
| `ingress.enabled` | Fallback `networking.k8s.io/v1` Ingress | `false` |

---

## Local Testing & Development

```sh
# Install tools and git hooks
mise run install

# Run all linters and secret/security checks
mise run check

# Lint and render Helm manifests locally
mise run helm-l
mise run helm-t

# Run Forgejo + joeckr/oci-postgres locally via Podman Compose (http://localhost:3000)
mise run compose
mise run logs
mise run down
```

---

## Conventional Commits & Releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). Merging to `main` automatically computes the next semantic version, updates `chart/Chart.yaml`, creates a GitHub Release, and publishes the Helm chart to GHCR.

## License

Please refer to the `LICENSE` file for details.
