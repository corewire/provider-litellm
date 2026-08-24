#!/bin/bash
# Sets up the e2e environment: deploys LiteLLM in-cluster, creates the Kubernetes
# Secret and ProviderConfig that the provider under test will use.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

LITELLM_API_BASE="http://litellm.litellm.svc.cluster.local:4000"
LITELLM_API_KEY="sk-e2e-master-key"

echo "Deploying LiteLLM in-cluster..."
kubectl apply -f "${REPO_ROOT}/cluster/test/litellm/deploy.yaml"

echo "Waiting for LiteLLM to become ready (up to 5 minutes)..."
kubectl -n litellm rollout status deployment/litellm --timeout=300s

echo "Creating upbound-system namespace..."
kubectl get namespace upbound-system >/dev/null 2>&1 || kubectl create namespace upbound-system

echo "Creating litellm-credentials Secret..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: litellm-credentials
  namespace: upbound-system
type: Opaque
stringData:
  credentials: |
    {
      "api_base": "${LITELLM_API_BASE}",
      "api_key": "${LITELLM_API_KEY}"
    }
EOF

echo "Creating ProviderConfig..."
kubectl apply -f - <<EOF
apiVersion: litellm.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: upbound-system
      name: litellm-credentials
      key: credentials
EOF

echo "Setup complete. LiteLLM is running at ${LITELLM_API_BASE}"
