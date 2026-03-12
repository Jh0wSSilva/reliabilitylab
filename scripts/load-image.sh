#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Carregar Imagem no Cluster
# Detecta automaticamente a ferramenta de cluster e carrega a imagem
# =============================================================================

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-reliabilitylab}"
IMAGE_NAME="${IMAGE_NAME:-local/reliabilitylab-site-kubectl:latest}"

echo "[INFO] Carregando imagem '${IMAGE_NAME}' no cluster '${CLUSTER_NAME}'..."

if command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"
    echo "[OK]   Imagem carregada no cluster kind."
elif command -v k3d &>/dev/null && k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    k3d image import "$IMAGE_NAME" -c "$CLUSTER_NAME"
    echo "[OK]   Imagem carregada no cluster k3d."
elif command -v minikube &>/dev/null; then
    minikube image load "$IMAGE_NAME" -p "$CLUSTER_NAME"
    echo "[OK]   Imagem carregada no minikube."
else
    echo "[ERRO] Nenhum cluster '${CLUSTER_NAME}' encontrado."
    exit 1
fi
