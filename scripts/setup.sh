#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Script de Setup Completo
# Cria cluster local, builda a imagem, instala dependências e faz deploy
# Suporta: kind, k3d, minikube
# =============================================================================

set -euo pipefail

# --- Cores para output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Configurações ---
CLUSTER_NAME="${CLUSTER_NAME:-reliabilitylab}"
IMAGE_NAME="${IMAGE_NAME:-local/reliabilitylab-site-kubectl:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERRO]${NC}  $*"; }

echo ""
echo "============================================"
echo "  ReliabilityLab — Setup Completo"
echo "============================================"
echo ""

# --- Verificar pré-requisitos ---
verificar_prerequisitos() {
    log_info "Verificando pré-requisitos..."
    local missing=()

    command -v docker &>/dev/null || missing+=("docker")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    command -v helm &>/dev/null || missing+=("helm")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Ferramentas faltando: ${missing[*]}"
        log_error "Instale as ferramentas acima antes de continuar."
        exit 1
    fi

    log_ok "Pré-requisitos verificados: docker, kubectl, helm"
}

# --- Detectar ferramenta de cluster ---
detectar_cluster_tool() {
    if command -v kind &>/dev/null; then
        echo "kind"
    elif command -v k3d &>/dev/null; then
        echo "k3d"
    elif command -v minikube &>/dev/null; then
        echo "minikube"
    else
        log_error "Nenhuma ferramenta de cluster local encontrada."
        log_error "Instale kind, k3d ou minikube."
        exit 1
    fi
}

# --- Fase 1: Criar cluster ---
criar_cluster() {
    local tool="$1"
    echo ""
    log_info "=== Fase 1: Criar cluster Kubernetes (${tool}) ==="

    case "$tool" in
        kind)
            if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
                log_warn "Cluster '${CLUSTER_NAME}' já existe. Pulando criação."
            else
                kind create cluster --name "$CLUSTER_NAME" \
                    --config "$SCRIPT_DIR/kind-config.yaml"
                log_ok "Cluster kind criado com sucesso."
            fi
            ;;
        k3d)
            if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
                log_warn "Cluster '${CLUSTER_NAME}' já existe. Pulando criação."
            else
                k3d cluster create "$CLUSTER_NAME" \
                    --servers 1 --agents 2 \
                    --port "80:80@loadbalancer" \
                    --port "443:443@loadbalancer" \
                    --k3s-arg "--disable=traefik@server:0"
                log_ok "Cluster k3d criado com sucesso."
            fi
            ;;
        minikube)
            if minikube status -p "$CLUSTER_NAME" 2>/dev/null | grep -q "Running"; then
                log_warn "Cluster '${CLUSTER_NAME}' já está rodando. Pulando criação."
            else
                minikube start --driver=docker --nodes=3 --cpus=2 --memory=4096 \
                    --profile="$CLUSTER_NAME" --kubernetes-version=v1.32.0
                minikube addons enable ingress -p "$CLUSTER_NAME"
                minikube addons enable metrics-server -p "$CLUSTER_NAME"
                log_ok "Cluster minikube criado com sucesso."
            fi
            ;;
    esac
}

# --- Fase 2: Build da imagem Docker ---
buildar_imagem() {
    echo ""
    log_info "=== Fase 2: Build da imagem Docker ==="
    docker build -t "$IMAGE_NAME" -f "$PROJECT_DIR/site_kubectl/Dockerfile" "$PROJECT_DIR/site_kubectl"
    log_ok "Imagem construída: ${IMAGE_NAME}"
}

# --- Fase 3: Carregar imagem no cluster ---
carregar_imagem() {
    local tool="$1"
    echo ""
    log_info "=== Fase 3: Carregar imagem no cluster ==="

    case "$tool" in
        kind)     kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME" ;;
        k3d)      k3d image import "$IMAGE_NAME" -c "$CLUSTER_NAME" ;;
        minikube) minikube image load "$IMAGE_NAME" -p "$CLUSTER_NAME" ;;
    esac

    log_ok "Imagem carregada no cluster."
}

# --- Fase 4: Instalar Ingress Controller ---
instalar_ingress() {
    local tool="$1"
    echo ""
    log_info "=== Fase 4: Instalar NGINX Ingress Controller ==="

    if [ "$tool" = "minikube" ]; then
        log_info "Minikube usa addon de ingress (já habilitado)."
        return
    fi

    if kubectl get ns ingress-nginx &>/dev/null; then
        log_warn "Ingress Controller já instalado. Pulando."
        return
    fi

    if [ "$tool" = "kind" ]; then
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    else
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    fi

    log_info "Aguardando Ingress Controller ficar pronto..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=180s

    log_ok "Ingress Controller pronto."
}

# --- Fase 5: Instalar metrics-server (kind/k3d) ---
instalar_metrics_server() {
    local tool="$1"
    echo ""
    log_info "=== Fase 5: Instalar Metrics Server ==="

    if [ "$tool" = "minikube" ]; then
        log_info "Minikube usa addon de metrics-server (já habilitado)."
        return
    fi

    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        log_warn "Metrics Server já instalado. Pulando."
        return
    fi

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    # Para clusters locais, desabilitar verificação de TLS
    kubectl patch deployment metrics-server -n kube-system \
        --type='json' \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

    log_ok "Metrics Server instalado."
}

# --- Fase 6: Deploy da aplicação ---
deployar_aplicacao() {
    echo ""
    log_info "=== Fase 6: Deploy dos manifests Kubernetes ==="

    cd "$PROJECT_DIR"
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/configmap.yaml
    kubectl apply -f k8s/secret.yaml
    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl apply -f k8s/ingress.yaml

    log_info "Aguardando pods ficarem prontos..."
    kubectl wait --namespace reliabilitylab \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=site-kubectl \
        --timeout=120s

    log_ok "Aplicação deployada com sucesso."
}

# --- Execução principal ---
verificar_prerequisitos
CLUSTER_TOOL=$(detectar_cluster_tool)
log_info "Ferramenta de cluster detectada: ${CLUSTER_TOOL}"

criar_cluster "$CLUSTER_TOOL"
buildar_imagem
carregar_imagem "$CLUSTER_TOOL"
instalar_ingress "$CLUSTER_TOOL"
instalar_metrics_server "$CLUSTER_TOOL"
deployar_aplicacao

echo ""
echo "============================================"
echo -e "  ${GREEN}Setup concluído com sucesso!${NC}"
echo ""
echo "  Adicione ao /etc/hosts:"
echo "    127.0.0.1 site-kubectl.local"
echo ""
echo "  Comando:"
echo "    echo '127.0.0.1 site-kubectl.local' | sudo tee -a /etc/hosts"
echo ""
echo "  Acesse: http://site-kubectl.local"
echo "  Health: http://site-kubectl.local/api/health"
echo "============================================"
