#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Instalação do ArgoCD
# Instala o ArgoCD e configura a Application para GitOps
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"

echo "============================================"
echo "  Instalando ArgoCD ${ARGOCD_VERSION}"
echo "============================================"
echo ""

# --- Criar namespace ---
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# --- Instalar ArgoCD ---
echo "[INFO] Instalando ArgoCD..."
kubectl apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# --- Aguardar pods ficarem prontos ---
echo "[INFO] Aguardando ArgoCD ficar pronto..."
kubectl wait --namespace argocd \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=argocd-server \
    --timeout=180s

# --- Aplicar Application ---
echo "[INFO] Aplicando ArgoCD Application..."
kubectl apply -f "$PROJECT_DIR/gitops/argocd/application.yaml"

# --- Obter senha inicial ---
echo ""
echo "============================================"
echo "  ArgoCD instalado com sucesso!"
echo ""
echo "  Acessar UI:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "    https://localhost:8443"
echo ""
echo "  Usuário: admin"
echo -n "  Senha:   "
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(aguardando criação do secret)"
echo ""
echo "============================================"
