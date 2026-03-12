#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Destruir Cluster e Recursos
# Remove cluster local e limpa recursos
# =============================================================================

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-reliabilitylab}"

echo "============================================"
echo "  ReliabilityLab — Destruir Ambiente"
echo "============================================"
echo ""

# Detectar ferramenta de cluster
if command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "[INFO] Removendo cluster kind '${CLUSTER_NAME}'..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "[OK]   Cluster kind removido."
elif command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo "[INFO] Removendo cluster k3d '${CLUSTER_NAME}'..."
    k3d cluster delete "$CLUSTER_NAME"
    echo "[OK]   Cluster k3d removido."
elif command -v minikube &>/dev/null && minikube status -p "$CLUSTER_NAME" &>/dev/null; then
    echo "[INFO] Removendo cluster minikube '${CLUSTER_NAME}'..."
    minikube delete -p "$CLUSTER_NAME"
    echo "[OK]   Cluster minikube removido."
else
    echo "[WARN] Nenhum cluster '${CLUSTER_NAME}' encontrado."
fi

# Remover imagem Docker
IMAGE_NAME="${IMAGE_NAME:-local/reliabilitylab-site-kubectl:latest}"
if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[INFO] Removendo imagem Docker '${IMAGE_NAME}'..."
    docker rmi "$IMAGE_NAME" 2>/dev/null || true
    echo "[OK]   Imagem removida."
fi

echo ""
echo "[OK] Ambiente destruído com sucesso."
