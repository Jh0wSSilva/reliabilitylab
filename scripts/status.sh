#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Status dos Recursos
# Exibe o estado completo do cluster e da aplicação
# =============================================================================

set -euo pipefail

NAMESPACE="${NAMESPACE:-reliabilitylab}"

echo "============================================"
echo "  ReliabilityLab — Status do Cluster"
echo "============================================"
echo ""

echo "=== Pods (${NAMESPACE}) ==="
kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || echo "  Nenhum pod encontrado."
echo ""

echo "=== Services (${NAMESPACE}) ==="
kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "  Nenhum service encontrado."
echo ""

echo "=== Ingress (${NAMESPACE}) ==="
kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "  Nenhum ingress encontrado."
echo ""

echo "=== HPA (${NAMESPACE}) ==="
kubectl get hpa -n "$NAMESPACE" 2>/dev/null || echo "  HPA não configurado."
echo ""

echo "=== PDB (${NAMESPACE}) ==="
kubectl get pdb -n "$NAMESPACE" 2>/dev/null || echo "  PDB não configurado."
echo ""

echo "=== NetworkPolicy (${NAMESPACE}) ==="
kubectl get networkpolicy -n "$NAMESPACE" 2>/dev/null || echo "  NetworkPolicy não configurada."
echo ""

echo "=== Monitoring ==="
kubectl get pods -n monitoring --no-headers 2>/dev/null | head -10 || echo "  Namespace monitoring não encontrado."
echo ""

echo "=== ArgoCD ==="
kubectl get pods -n argocd --no-headers 2>/dev/null | head -5 || echo "  ArgoCD não instalado."
echo ""

echo "=== Health Check ==="
kubectl exec -n "$NAMESPACE" \
    "$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" \
    -- python -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:8000/api/health'); print(r.read().decode())" 2>/dev/null \
    || echo "  Não foi possível verificar o health check."
