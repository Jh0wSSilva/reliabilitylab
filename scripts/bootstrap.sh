#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ReliabilityLab — Bootstrap Script
# Cria e configura todo o stack SRE automaticamente.
# ============================================================================

PROFILE="reliabilitylab"
K8S_VERSION="v1.32.0"
MEMORY="4096"
CPUS="2"
NODES="3"
DRIVER="docker"

# ---- Versões pinadas para reprodutibilidade ----
PODINFO_IMAGE="ghcr.io/stefanprodan/podinfo:6.11.0"
PROMETHEUS_STACK_VERSION="82.10.3"
SLOTH_VERSION="0.15.0"
CHAOS_MESH_VERSION="2.8.1"
ARGOCD_VERSION="v3.3.3"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[✅]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_error() { echo -e "${RED}[❌]${NC} $1"; }

separator() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

check_command() {
  if command -v "$1" &>/dev/null; then
    log_ok "$1 encontrado: $(command -v "$1")"
    return 0
  else
    log_error "$1 NÃO encontrado"
    return 1
  fi
}

wait_for_pods() {
  local namespace="$1"
  local timeout="${2:-300}"
  log_info "Aguardando pods em $namespace ficarem Ready (timeout: ${timeout}s)..."
  if kubectl wait --for=condition=Ready pods --all -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
    log_ok "Todos os pods em $namespace estão Ready"
    return 0
  else
    log_error "Timeout aguardando pods em $namespace"
    kubectl get pods -n "$namespace"
    return 1
  fi
}

# Muda para o diretório do script (raiz do repositório)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cd "$REPO_DIR"

echo ""
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║          ReliabilityLab — Bootstrap           ║"
echo "  ║    SRE Platform com Chaos Engineering,        ║"
echo "  ║    SLOs e Observabilidade completa             ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo ""

# ============================================================================
# FASE 1: Verificar pré-requisitos
# ============================================================================

separator
log_info "FASE 1/7 — Verificando pré-requisitos..."

MISSING=0
check_command docker   || MISSING=$((MISSING + 1))
check_command minikube || MISSING=$((MISSING + 1))
check_command kubectl  || MISSING=$((MISSING + 1))
check_command helm     || MISSING=$((MISSING + 1))
check_command k6       || MISSING=$((MISSING + 1))

if [ "$MISSING" -gt 0 ]; then
  log_error "$MISSING ferramenta(s) ausente(s). Instale antes de continuar."
  echo "  Consulte: docs/tutorials/tutorial-01-ambiente-minikube.md"
  exit 1
fi

# Verificar Docker rodando
if ! docker info &>/dev/null; then
  log_error "Docker não está rodando. Inicie o Docker e tente novamente."
  exit 1
fi
log_ok "Docker está rodando"

# Verificar memória disponível
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
if [ "$TOTAL_MEM_GB" -lt 12 ]; then
  log_warn "Memória total: ${TOTAL_MEM_GB}GB (recomendado: 12GB+)"
  log_warn "O cluster pode ter instabilidade com pouca memória."
else
  log_ok "Memória total: ${TOTAL_MEM_GB}GB (suficiente)"
fi

# ============================================================================
# FASE 2: Criar cluster Minikube
# ============================================================================

separator
log_info "FASE 2/7 — Criando cluster Minikube..."

# Limpar cluster anterior se existir
if minikube status -p "$PROFILE" &>/dev/null; then
  log_warn "Cluster '$PROFILE' já existe. Deletando..."
  minikube delete -p "$PROFILE"
fi

log_info "Criando cluster: $NODES nós, ${MEMORY}MB RAM/nó, $CPUS CPUs/nó, Kubernetes $K8S_VERSION"
minikube start \
  --driver="$DRIVER" \
  --nodes="$NODES" \
  --cpus="$CPUS" \
  --memory="$MEMORY" \
  --profile="$PROFILE" \
  --kubernetes-version="$K8S_VERSION"

log_ok "Cluster criado com sucesso"

# Habilitar addons
log_info "Habilitando addons..."
minikube addons enable ingress        -p "$PROFILE"
minikube addons enable metrics-server -p "$PROFILE"
minikube addons enable dashboard      -p "$PROFILE"
log_ok "Addons habilitados"

# Aguardar estabilização
log_info "Aguardando kube-system estabilizar..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s
log_ok "kube-system estável"

# Aguardar ingress
log_info "Aguardando ingress-nginx..."
sleep 10
kubectl wait --for=condition=Ready pods --all -n ingress-nginx --timeout=180s 2>/dev/null || true
log_ok "Ingress pronto"

# ============================================================================
# FASE 3: Criar namespaces
# ============================================================================

separator
log_info "FASE 3/7 — Criando namespaces..."

for NS in production monitoring chaos-mesh argocd; do
  kubectl create namespace "$NS" 2>/dev/null && log_ok "Namespace $NS criado" || log_warn "Namespace $NS já existe"
done

# Aplicar ResourceQuota e LimitRange
kubectl apply -f k8s/namespaces/production-quota.yaml
kubectl apply -f k8s/namespaces/production-limitrange.yaml
log_ok "ResourceQuota e LimitRange aplicados"

# ============================================================================
# FASE 4: Instalar stack de monitoramento
# ============================================================================

separator
log_info "FASE 4/7 — Instalando Prometheus + Grafana + Alertmanager..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version "$PROMETHEUS_STACK_VERSION" \
  -n monitoring \
  -f helm/values/local/prometheus-values.yaml \
  --wait --timeout 10m

log_ok "kube-prometheus-stack instalado"

# Aplicar ServiceMonitor
kubectl apply -f k8s/servicemonitor-streamflix.yaml
log_ok "ServiceMonitor aplicado"

# Instalar Sloth
log_info "Instalando Sloth (SLO engine)..."
helm repo add sloth https://slok.github.io/sloth 2>/dev/null || true
helm repo update

helm upgrade --install sloth sloth/sloth \
  --version "$SLOTH_VERSION" \
  -n monitoring \
  --wait --timeout 5m

log_ok "Sloth instalado"

# Aplicar SLOs
kubectl apply -f platform/slo/
log_ok "SLOs aplicados (3 definições)"

# Verificar
wait_for_pods monitoring 300

# ============================================================================
# FASE 5: Deploy dos serviços StreamFlix
# ============================================================================

separator
log_info "FASE 5/7 — Fazendo deploy dos serviços StreamFlix..."

# content-api
kubectl apply -f k8s/namespaces/content-api.yaml
log_ok "content-api deployed"

# recommendation-api
kubectl apply -f k8s/namespaces/recommendation-api.yaml
log_ok "recommendation-api deployed"

# player-api
kubectl apply -f k8s/namespaces/player-api.yaml
log_ok "player-api deployed"

# HPA
kubectl autoscale deployment content-api        -n production --min=2 --max=10 --cpu-percent=70 2>/dev/null || true
kubectl autoscale deployment recommendation-api -n production --min=2 --max=8  --cpu-percent=70 2>/dev/null || true
kubectl autoscale deployment player-api         -n production --min=2 --max=6  --cpu-percent=70 2>/dev/null || true
log_ok "HPA configurado para os 3 serviços"

# Network Policies (zero-trust)
kubectl apply -f k8s/network-policies/
log_ok "Network Policies aplicadas (default-deny + allow rules)"

wait_for_pods production 120

# ============================================================================
# FASE 6: Instalar Chaos Mesh
# ============================================================================

separator
log_info "FASE 6/7 — Instalando Chaos Mesh..."

helm repo add chaos-mesh https://charts.chaos-mesh.org 2>/dev/null || true
helm repo update

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --version "$CHAOS_MESH_VERSION" \
  -n chaos-mesh \
  --set controllerManager.replicaCount=1 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout 10m

log_ok "Chaos Mesh instalado"
wait_for_pods chaos-mesh 120

# ============================================================================
# FASE 7: Instalar ArgoCD
# ============================================================================

separator
log_info "FASE 7/7 — Instalando ArgoCD..."

# Aguardar um pouco para o cluster estabilizar após Chaos Mesh
log_info "Aguardando cluster estabilizar (30s)..."
sleep 30

kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log_info "Aguardando ArgoCD pods..."
wait_for_pods argocd 300

# Expor via NodePort
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}' 2>/dev/null || true
log_ok "ArgoCD instalado e exposto via NodePort"

# ============================================================================
# RELATÓRIO FINAL
# ============================================================================

separator
echo ""
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║        ReliabilityLab — Setup Completo!       ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo ""

echo "  📊 Stack instalado:"
echo ""

echo "  Cluster:"
kubectl get nodes --no-headers | while read -r line; do
  echo "    $(echo "$line" | awk '{print $1, $2, $5}')"
done
echo ""

echo "  Namespaces:"
for NS in production monitoring chaos-mesh argocd; do
  POD_COUNT=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c Running || echo 0)
  echo "    $NS: $POD_COUNT pods Running"
done
echo ""

echo "  Serviços StreamFlix:"
kubectl get deployments -n production --no-headers | while read -r line; do
  echo "    $(echo "$line" | awk '{print $1, $2}')"
done
echo ""

echo "  SLOs:"
kubectl get prometheusservicelevel -n monitoring --no-headers 2>/dev/null | while read -r line; do
  echo "    $(echo "$line" | awk '{print $1}')"
done
echo ""

echo "  Acessos:"
GRAFANA_URL=$(minikube service kube-prometheus-stack-grafana -n monitoring -p "$PROFILE" --url 2>/dev/null | head -1 || echo "use: minikube service kube-prometheus-stack-grafana -n monitoring -p $PROFILE")
ARGOCD_URL=$(minikube service argocd-server -n argocd -p "$PROFILE" --url 2>/dev/null | head -1 || echo "use: minikube service argocd-server -n argocd -p $PROFILE")
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "not available yet")

echo "    Grafana:  $GRAFANA_URL  (admin / admin123)"
echo "    ArgoCD:   $ARGOCD_URL  (admin / $ARGOCD_PASS)"
echo ""

echo "  Próximos passos:"
echo "    1. Abra o Grafana e explore os dashboards"
echo "    2. Execute: k6 run loadtests/smoke-test.js"
echo "    3. Execute: kubectl apply -f platform/chaos/experiments/chaos-pod-kill.yaml"
echo "    4. Siga os tutoriais em docs/tutorials/"
echo ""

log_ok "Bootstrap completo! Bom lab! 🚀"
