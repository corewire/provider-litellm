#!/bin/bash
set -euo pipefail

if [[ -z "${LITELLM_API_BASE:-}" ]]; then
  echo "LITELLM_API_BASE must be set"
  exit 1
fi

if [[ -z "${LITELLM_API_KEY:-}" ]]; then
  echo "LITELLM_API_KEY must be set"
  exit 1
fi

kubectl get namespace upbound-system >/dev/null 2>&1 || kubectl create namespace upbound-system

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: litellm-credentials
  namespace: upbound-system
type: Opaque
stringData:
  LITELLM_API_BASE: ${LITELLM_API_BASE}
  LITELLM_API_KEY: ${LITELLM_API_KEY}
  credentials: |
    LITELLM_API_BASE=${LITELLM_API_BASE}
    LITELLM_API_KEY=${LITELLM_API_KEY}
EOF

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
