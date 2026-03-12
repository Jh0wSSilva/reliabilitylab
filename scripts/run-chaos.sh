#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Executar Experimentos de Chaos Engineering
# Aplica ou remove experimentos de chaos no cluster
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="${NAMESPACE:-reliabilitylab}"

show_help() {
    echo "Uso: $0 <comando> [experimento]"
    echo ""
    echo "Comandos:"
    echo "  apply <experimento>   - Aplicar um experimento de chaos"
    echo "  delete <experimento>  - Remover um experimento de chaos"
    echo "  list                  - Listar experimentos disponíveis"
    echo "  install-litmus        - Instalar LitmusChaos no cluster"
    echo ""
    echo "Experimentos disponíveis:"
    echo "  pod-delete            - Deletar pods aleatoriamente"
    echo "  pod-cpu-stress        - Estressar CPU dos pods"
    echo "  pod-memory-stress     - Estressar memória dos pods"
    echo "  pod-network-latency   - Injetar latência de rede"
    echo "  all                   - Listar todos os experimentos ativos"
}

install_litmus() {
    echo "[INFO] Instalando LitmusChaos..."

    # Adicionar repositório Helm do Litmus
    helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ 2>/dev/null || true
    helm repo update

    # Instalar Litmus ChaosCenter
    helm upgrade --install litmus litmuschaos/litmus \
        --namespace litmus --create-namespace \
        --set portal.frontend.service.type=ClusterIP \
        --wait --timeout 5m

    echo "[OK]   LitmusChaos instalado."
    echo ""
    echo "  Acessar ChaosCenter:"
    echo "    kubectl port-forward svc/litmus-frontend-service -n litmus 9091:9091"
    echo "    http://localhost:9091 (admin / litmus)"
}

apply_experiment() {
    local experiment="$1"
    local file="$PROJECT_DIR/chaos/${experiment}.yaml"

    if [[ ! -f "$file" ]]; then
        echo "[ERRO] Experimento '${experiment}' não encontrado: ${file}"
        echo "Use '$0 list' para ver experimentos disponíveis."
        exit 1
    fi

    echo "[INFO] Aplicando experimento: ${experiment}"
    kubectl apply -f "$file"
    echo "[OK]   Experimento '${experiment}' aplicado."
    echo ""
    echo "Acompanhe com:"
    echo "  kubectl get pods -n ${NAMESPACE} -w"
    echo "  kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"
}

delete_experiment() {
    local experiment="$1"
    local file="$PROJECT_DIR/chaos/${experiment}.yaml"

    if [[ ! -f "$file" ]]; then
        echo "[ERRO] Experimento '${experiment}' não encontrado: ${file}"
        exit 1
    fi

    echo "[INFO] Removendo experimento: ${experiment}"
    kubectl delete -f "$file" --ignore-not-found
    echo "[OK]   Experimento '${experiment}' removido."
}

list_experiments() {
    echo "Experimentos disponíveis em chaos/:"
    echo ""
    for f in "$PROJECT_DIR/chaos/"*.yaml; do
        [[ -f "$f" ]] && echo "  - $(basename "$f" .yaml)"
    done
}

# --- Processamento dos argumentos ---
COMMAND="${1:-help}"
EXPERIMENT="${2:-}"

case "$COMMAND" in
    apply)
        [[ -z "$EXPERIMENT" ]] && { echo "[ERRO] Especifique um experimento."; show_help; exit 1; }
        apply_experiment "$EXPERIMENT"
        ;;
    delete)
        [[ -z "$EXPERIMENT" ]] && { echo "[ERRO] Especifique um experimento."; show_help; exit 1; }
        delete_experiment "$EXPERIMENT"
        ;;
    list)
        list_experiments
        ;;
    install-litmus)
        install_litmus
        ;;
    *)
        show_help
        ;;
esac
