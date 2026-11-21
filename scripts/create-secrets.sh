#!/usr/bin/env bash
set -euo pipefail

# Generates and applies the Kubernetes Secret required by lab-forgejo at install time.
# Secrets are never written to disk or committed to git.

NAMESPACE="forgejo"
SECRET_NAME="forgejo-secrets"
DRY_RUN="false"
WITHOUT_OIDC="false"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Creates or updates the Kubernetes Secret required by the lab-forgejo Helm chart.
Cryptographic keys (db-password, secret-key, internal-token, jwt-secret) are
generated locally with openssl unless provided via environment variables.

Options:
  -n, --namespace NAME      Target Kubernetes namespace (default: forgejo)
  -s, --secret-name NAME    Kubernetes Secret name (default: forgejo-secrets)
      --without-oidc        Skip OIDC client ID / secret prompts
      --dry-run             Print the kubectl command target without applying
  -h, --help                Show this help message

Optional Environment Variables:
  DB_PASSWORD               PostgreSQL password (auto-generated if unset)
  FORGEJO_SECRET_KEY        Forgejo SECRET_KEY (auto-generated if unset)
  FORGEJO_INTERNAL_TOKEN    Forgejo INTERNAL_TOKEN (auto-generated if unset)
  FORGEJO_JWT_SECRET        Forgejo OAuth2 JWT_SECRET (auto-generated if unset)
  OIDC_CLIENT_ID            OIDC client ID (prompted if unset)
  OIDC_CLIENT_SECRET        OIDC client secret (prompted silently if unset)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -s|--secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --without-oidc)
      WITHOUT_OIDC="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in kubectl openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH." >&2
    exit 1
  fi
done

# Generate cryptographically strong secrets if not supplied
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)}"
FORGEJO_SECRET_KEY="${FORGEJO_SECRET_KEY:-$(openssl rand -hex 32)}"
FORGEJO_INTERNAL_TOKEN="${FORGEJO_INTERNAL_TOKEN:-$(openssl rand -base64 64 | tr -d '\n')}"
FORGEJO_JWT_SECRET="${FORGEJO_JWT_SECRET:-$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')}"

ARGS=(
  --namespace "$NAMESPACE"
  --from-literal="db-password=${DB_PASSWORD}"
  --from-literal="secret-key=${FORGEJO_SECRET_KEY}"
  --from-literal="internal-token=${FORGEJO_INTERNAL_TOKEN}"
  --from-literal="jwt-secret=${FORGEJO_JWT_SECRET}"
)

if [[ "$WITHOUT_OIDC" == "false" ]]; then
  if [[ -z "${OIDC_CLIENT_ID:-}" ]]; then
    read -r -p "OIDC Client ID: " OIDC_CLIENT_ID
  fi
  if [[ -z "${OIDC_CLIENT_SECRET:-}" ]]; then
    read -r -s -p "OIDC Client Secret: " OIDC_CLIENT_SECRET
    echo ""
  fi
  if [[ -z "${OIDC_CLIENT_ID}" || -z "${OIDC_CLIENT_SECRET}" ]]; then
    echo "Error: OIDC_CLIENT_ID and OIDC_CLIENT_SECRET must not be empty (or pass --without-oidc)." >&2
    exit 1
  fi
  ARGS+=(
    --from-literal="oidc-client-id=${OIDC_CLIENT_ID}"
    --from-literal="oidc-client-secret=${OIDC_CLIENT_SECRET}"
  )
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] Would create/update Secret '${SECRET_NAME}' in namespace '${NAMESPACE}'."
  exit 0
fi

kubectl create secret generic "$SECRET_NAME" \
  "${ARGS[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret '${SECRET_NAME}' applied in namespace '${NAMESPACE}'."
