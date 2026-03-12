#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Deploy da Aplicação no Kubernetes
# Aplica todos os manifests K8s e aguarda os pods ficarem prontos
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="${NAMESPACE:-reliabilitylab}"

echo "[INFO] Aplicando manifests Kubernetes..."

cd "$PROJECT_DIR"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

echo "[INFO] Aguardando pods ficarem prontos..."
kubectl wait --namespace "$NAMESPACE" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=site-kubectl \
    --timeout=120s

echo "[OK]   Aplicação deployada com sucesso no namespace '${NAMESPACE}'."
echo ""
echo "Verifique com:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get svc -n ${NAMESPACE}"
echo "  kubectl get ingress -n ${NAMESPACE}"
