#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Build da Imagem Docker
# Constrói a imagem Docker da aplicação site_kubectl
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="${IMAGE_NAME:-local/reliabilitylab-site-kubectl:latest}"

echo "[INFO] Construindo imagem Docker: ${IMAGE_NAME}"
docker build -t "$IMAGE_NAME" -f "$PROJECT_DIR/site_kubectl/Dockerfile" "$PROJECT_DIR/site_kubectl"
echo "[OK]   Imagem construída com sucesso: ${IMAGE_NAME}"
echo ""
echo "Para verificar:"
echo "  docker images | grep reliabilitylab"
