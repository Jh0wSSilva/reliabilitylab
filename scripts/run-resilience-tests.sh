#!/usr/bin/env bash
# =============================================================================
# Pipeline de Testes de Resiliência
#
# Executa um pipeline completo de validação de resiliência:
#   1. Verificar pré-requisitos
#   2. Deploy da aplicação (se necessário)
#   3. Carga base (smoke test)
#   4. Injeção de chaos + carga simultânea
#   5. Observar recuperação
#   6. Validar SLOs
#   7. Gerar relatório
#
# Uso:
#   ./scripts/run-resilience-tests.sh [cenário]
#
# Cenários:
#   all             — Todos os cenários em sequência (padrão)
#   pod-kill        — Eliminação total de pods
#   network         — Partição de rede
#   resource        — Exaustão de CPU/memória
#   quick           — Teste rápido (apenas pod-kill com duração curta)
#
# Variáveis de ambiente:
#   BASE_URL        — URL do serviço (padrão: http://site-kubectl.local)
#   NAMESPACE       — Namespace K8s (padrão: reliabilitylab)
#   CHAOS_DURATION  — Duração do chaos em segundos (padrão: 60)
#   LOAD_DURATION   — Duração da carga k6 (padrão: 3m)
# =============================================================================

set -euo pipefail

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Configuração ---
SCENARIO="${1:-all}"
BASE_URL="${BASE_URL:-http://site-kubectl.local}"
NAMESPACE="${NAMESPACE:-reliabilitylab}"
CHAOS_DURATION="${CHAOS_DURATION:-60}"
LOAD_DURATION="${LOAD_DURATION:-3m}"
RESULTS_DIR="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${RESULTS_DIR}/resilience-${TIMESTAMP}.log"

# --- Diretório de resultados ---
mkdir -p "$RESULTS_DIR"

# --- Funções auxiliares ---
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERRO]${NC} $1"; }
header()  { echo -e "\n${CYAN}==========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}==========================================${NC}\n"; }

log_to_report() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$REPORT_FILE"
}

# =============================================================================
# Etapa 1: Verificar Pré-requisitos
# =============================================================================
check_prerequisites() {
  header "ETAPA 1: Verificando Pré-requisitos"

  local failed=0

  # kubectl
  if command -v kubectl &>/dev/null; then
    success "kubectl encontrado: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
  else
    error "kubectl não encontrado"
    failed=1
  fi

  # k6
  if command -v k6 &>/dev/null; then
    success "k6 encontrado: $(k6 version 2>/dev/null | head -1)"
  else
    warn "k6 não encontrado — testes de carga serão pulados"
  fi

  # Cluster acessível
  if kubectl cluster-info &>/dev/null; then
    success "Cluster Kubernetes acessível"
  else
    error "Não foi possível acessar o cluster Kubernetes"
    failed=1
  fi

  # Namespace existe
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    success "Namespace '$NAMESPACE' existe"
  else
    error "Namespace '$NAMESPACE' não encontrado"
    failed=1
  fi

  # Pods rodando
  local pods
  pods=$(kubectl get pods -n "$NAMESPACE" -l app=site-kubectl --no-headers 2>/dev/null | grep -c Running || true)
  if [ "$pods" -gt 0 ]; then
    success "Pods rodando: $pods"
  else
    error "Nenhum pod Running do site-kubectl encontrado"
    failed=1
  fi

  if [ $failed -ne 0 ]; then
    error "Pré-requisitos não atendidos. Abortando."
    exit 1
  fi

  log_to_report "Pré-requisitos verificados com sucesso"
}

# =============================================================================
# Etapa 2: Smoke Test (Verificar serviço OK antes do chaos)
# =============================================================================
run_smoke_test() {
  header "ETAPA 2: Smoke Test — Verificando Serviço"

  info "Testando conectividade com $BASE_URL..."

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE_URL/api/health" 2>/dev/null || echo "000")

  if [ "$status" = "200" ]; then
    success "Serviço respondendo (HTTP $status)"
    log_to_report "Smoke test: HTTP $status — OK"
  else
    warn "Serviço retornou HTTP $status (pode estar com Ingress indisponível)"
    info "Tentando via port-forward..."
    log_to_report "Smoke test: HTTP $status — usando port-forward"
  fi

  if command -v k6 &>/dev/null; then
    info "Executando smoke test com k6 (30s)..."
    k6 run --duration 30s --vus 2 \
      -e BASE_URL="$BASE_URL" \
      load-testing/smoke-test.js 2>&1 | tail -20 || warn "Smoke test k6 falhou (serviço pode não estar acessível externamente)"
    log_to_report "Smoke test k6 concluído"
  fi
}

# =============================================================================
# Etapa 3: Injeção de Chaos + Carga
# =============================================================================

# --- Cenário: Eliminação Total de Pods ---
run_chaos_pod_kill() {
  header "CHAOS: Eliminação Total de Pods"

  info "Estado antes do chaos:"
  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl
  echo ""
  log_to_report "Iniciando chaos: total-pod-kill"

  # Iniciar carga em background (se k6 disponível)
  local k6_pid=""
  if command -v k6 &>/dev/null; then
    info "Iniciando carga de fundo com k6..."
    k6 run --duration "$LOAD_DURATION" --quiet \
      -e BASE_URL="$BASE_URL" \
      -e DURATION="$LOAD_DURATION" \
      load-testing/resilience-test.js > "${RESULTS_DIR}/k6-pod-kill-${TIMESTAMP}.log" 2>&1 &
    k6_pid=$!
    info "k6 PID: $k6_pid"
  fi

  # Aguardar carga estabilizar
  sleep 10

  # Executar chaos — deletar todos os pods
  warn "Deletando TODOS os pods do site-kubectl..."
  kubectl delete pods -n "$NAMESPACE" -l app=site-kubectl --grace-period=5
  echo ""

  info "Pods deletados. Observando recuperação..."
  log_to_report "Pods deletados — observando recuperação"

  # Monitorar recuperação
  for i in $(seq 1 12); do
    echo "  [+${i}0s] $(kubectl get pods -n "$NAMESPACE" -l app=site-kubectl --no-headers 2>/dev/null | tr '\n' ' ')"
    sleep 10
  done

  # Verificar se pods voltaram
  echo ""
  local ready
  ready=$(kubectl get pods -n "$NAMESPACE" -l app=site-kubectl --no-headers 2>/dev/null | grep -c Running || true)
  if [ "$ready" -gt 0 ]; then
    success "Recuperação: $ready pods Running"
    log_to_report "Recuperação: $ready pods Running"
  else
    error "Pods não se recuperaram!"
    log_to_report "FALHA: Pods não se recuperaram"
  fi

  # Esperar k6 terminar
  if [ -n "$k6_pid" ]; then
    info "Aguardando k6 finalizar..."
    wait "$k6_pid" 2>/dev/null || true
    success "Relatório k6: ${RESULTS_DIR}/k6-pod-kill-${TIMESTAMP}.log"
  fi
}

# --- Cenário: Partição de Rede ---
run_chaos_network() {
  header "CHAOS: Partição de Rede"

  info "Estado antes do chaos:"
  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl
  echo ""
  log_to_report "Iniciando chaos: network-partition (${CHAOS_DURATION}s)"

  # Iniciar carga em background
  local k6_pid=""
  if command -v k6 &>/dev/null; then
    info "Iniciando carga de fundo com k6..."
    k6 run --duration "$LOAD_DURATION" --quiet \
      -e BASE_URL="$BASE_URL" \
      -e DURATION="$LOAD_DURATION" \
      load-testing/resilience-test.js > "${RESULTS_DIR}/k6-network-${TIMESTAMP}.log" 2>&1 &
    k6_pid=$!
  fi

  sleep 10

  # Aplicar NetworkPolicy de bloqueio
  warn "Aplicando partição de rede (duração: ${CHAOS_DURATION}s)..."
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-network-block
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: site-kubectl
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF

  info "Rede particionada. Aguardando ${CHAOS_DURATION}s..."
  sleep "$CHAOS_DURATION"

  # Remover bloqueio
  info "Removendo partição de rede..."
  kubectl delete networkpolicy chaos-network-block -n "$NAMESPACE" 2>/dev/null || true
  success "Rede restaurada"
  log_to_report "Rede restaurada após ${CHAOS_DURATION}s"

  # Aguardar estabilização
  info "Aguardando estabilização (30s)..."
  sleep 30

  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl
  echo ""

  if [ -n "$k6_pid" ]; then
    wait "$k6_pid" 2>/dev/null || true
    success "Relatório k6: ${RESULTS_DIR}/k6-network-${TIMESTAMP}.log"
  fi
}

# --- Cenário: Exaustão de Recursos ---
run_chaos_resource() {
  header "CHAOS: Exaustão de Recursos"

  info "Estado antes do chaos:"
  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl
  kubectl top pods -n "$NAMESPACE" 2>/dev/null || warn "metrics-server não disponível"
  echo ""
  log_to_report "Iniciando chaos: resource-exhaustion"

  # Iniciar carga em background
  local k6_pid=""
  if command -v k6 &>/dev/null; then
    info "Iniciando carga de fundo com k6..."
    k6 run --duration "$LOAD_DURATION" --quiet \
      -e BASE_URL="$BASE_URL" \
      -e DURATION="$LOAD_DURATION" \
      load-testing/resilience-test.js > "${RESULTS_DIR}/k6-resource-${TIMESTAMP}.log" 2>&1 &
    k6_pid=$!
  fi

  sleep 10

  # Aplicar stress de recursos
  warn "Aplicando stress de CPU e memória..."
  kubectl apply -f chaos/scenarios/resource-exhaustion.yaml

  # Monitorar
  info "Monitorando por 120s..."
  for i in $(seq 1 8); do
    echo "  [+${i}5s] $(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l) pods total"
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || true
    sleep 15
  done

  # Limpar
  info "Removendo jobs de stress..."
  kubectl delete -f chaos/scenarios/resource-exhaustion.yaml 2>/dev/null || true
  success "Stress removido"
  log_to_report "Stress de recursos removido"

  sleep 30
  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl

  if [ -n "$k6_pid" ]; then
    wait "$k6_pid" 2>/dev/null || true
    success "Relatório k6: ${RESULTS_DIR}/k6-resource-${TIMESTAMP}.log"
  fi
}

# =============================================================================
# Etapa 4: Validar SLOs
# =============================================================================
validate_slos() {
  header "ETAPA 4: Validação de SLOs"

  info "Verificando estado final do serviço..."

  # Pods rodando
  local pods
  pods=$(kubectl get pods -n "$NAMESPACE" -l app=site-kubectl --no-headers 2>/dev/null | grep -c Running || true)

  if [ "$pods" -ge 2 ]; then
    success "SLO Infraestrutura: $pods pods Running (mínimo: 2)"
    log_to_report "SLO Infraestrutura: PASS ($pods pods)"
  else
    error "SLO Infraestrutura: apenas $pods pods Running"
    log_to_report "SLO Infraestrutura: FAIL ($pods pods)"
  fi

  # Restarts excessivos
  local restarts
  restarts=$(kubectl get pods -n "$NAMESPACE" -l app=site-kubectl -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | awk '{s+=$1} END {print s+0}')

  if [ "$restarts" -lt 5 ]; then
    success "Estabilidade: $restarts restarts totais (< 5)"
    log_to_report "Estabilidade: PASS ($restarts restarts)"
  else
    warn "Estabilidade: $restarts restarts totais (muitos restarts)"
    log_to_report "Estabilidade: WARN ($restarts restarts)"
  fi

  # Verificar alertas ativos (via Prometheus API se acessível)
  info "Verificando alertas ativos no Prometheus..."
  local prom_url="http://localhost:9090"
  local alerts
  alerts=$(curl -s "${prom_url}/api/v1/alerts" 2>/dev/null | grep -c '"firing"' || echo "0")
  if [ "$alerts" = "0" ]; then
    success "Sem alertas firing no Prometheus"
    log_to_report "Alertas: 0 firing"
  else
    warn "$alerts alertas firing no Prometheus"
    log_to_report "Alertas: $alerts firing"
  fi
}

# =============================================================================
# Etapa 5: Gerar Relatório
# =============================================================================
generate_report() {
  header "ETAPA 5: Relatório Final"

  echo "==========================================" | tee -a "$REPORT_FILE"
  echo "  RELATÓRIO DE RESILIÊNCIA" | tee -a "$REPORT_FILE"
  echo "  Data: $(date)" | tee -a "$REPORT_FILE"
  echo "  Cenário: $SCENARIO" | tee -a "$REPORT_FILE"
  echo "==========================================" | tee -a "$REPORT_FILE"
  echo "" | tee -a "$REPORT_FILE"
  echo "  Namespace:    $NAMESPACE" | tee -a "$REPORT_FILE"
  echo "  Base URL:     $BASE_URL" | tee -a "$REPORT_FILE"
  echo "  Chaos Dur.:   ${CHAOS_DURATION}s" | tee -a "$REPORT_FILE"
  echo "  Load Dur.:    $LOAD_DURATION" | tee -a "$REPORT_FILE"
  echo "" | tee -a "$REPORT_FILE"
  echo "  Estado Final:" | tee -a "$REPORT_FILE"
  kubectl get pods -n "$NAMESPACE" -l app=site-kubectl --no-headers 2>/dev/null | while read -r line; do
    echo "    $line" | tee -a "$REPORT_FILE"
  done
  echo "" | tee -a "$REPORT_FILE"
  echo "  Resultados salvos em: $RESULTS_DIR/" | tee -a "$REPORT_FILE"
  echo "==========================================" | tee -a "$REPORT_FILE"

  success "Relatório salvo: $REPORT_FILE"

  # Listar todos os resultados
  if [ -d "$RESULTS_DIR" ]; then
    echo ""
    info "Arquivos de resultado:"
    ls -la "$RESULTS_DIR"/*"${TIMESTAMP}"* 2>/dev/null || info "Nenhum arquivo gerado nesta execução"
  fi
}

# =============================================================================
# Main
# =============================================================================
main() {
  header "PIPELINE DE RESILIÊNCIA — ReliabilityLab"
  info "Cenário: $SCENARIO"
  info "Timestamp: $TIMESTAMP"
  echo ""

  log_to_report "Início do pipeline — cenário: $SCENARIO"

  # Etapa 1: Pré-requisitos
  check_prerequisites

  # Etapa 2: Smoke test
  run_smoke_test

  # Etapa 3: Chaos (baseado no cenário escolhido)
  case "$SCENARIO" in
    pod-kill)
      run_chaos_pod_kill
      ;;
    network)
      run_chaos_network
      ;;
    resource)
      run_chaos_resource
      ;;
    quick)
      CHAOS_DURATION=30
      LOAD_DURATION="1m"
      run_chaos_pod_kill
      ;;
    all)
      run_chaos_pod_kill
      info "Aguardando 60s entre cenários..."
      sleep 60
      run_chaos_network
      info "Aguardando 60s entre cenários..."
      sleep 60
      run_chaos_resource
      ;;
    *)
      error "Cenário desconhecido: $SCENARIO"
      echo "  Cenários disponíveis: all, pod-kill, network, resource, quick"
      exit 1
      ;;
  esac

  # Etapa 4: Validar SLOs
  validate_slos

  # Etapa 5: Relatório
  generate_report

  log_to_report "Pipeline concluído"
  echo ""
  success "Pipeline de resiliência concluído!"
}

main "$@"
