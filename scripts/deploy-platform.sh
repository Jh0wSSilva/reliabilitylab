#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Deploy de Recursos de Plataforma
# Aplica HPA, NetworkPolicy e PDB
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "[INFO] Aplicando recursos de plataforma..."

cd "$PROJECT_DIR"
kubectl apply -f platform/hpa.yaml
kubectl apply -f platform/networkpolicy.yaml
kubectl apply -f platform/pdb.yaml

echo "[OK]   HPA, NetworkPolicy e PDB aplicados com sucesso."
echo ""
echo "Verifique com:"
echo "  kubectl get hpa -n reliabilitylab"
echo "  kubectl get networkpolicy -n reliabilitylab"
echo "  kubectl get pdb -n reliabilitylab"
