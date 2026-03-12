# Tutorial 03 — Criando um Cluster Kubernetes Local

## Objetivo

Criar um cluster Kubernetes local para rodar o laboratório DevOps. Suportamos três ferramentas: **kind**, **k3d** e **minikube**.

## Conceitos

- **Kubernetes**: plataforma de orquestração de containers
- **kind** (Kubernetes IN Docker): cria clusters Kubernetes usando containers Docker como nós
- **k3d**: cria clusters K3s (Kubernetes leve) dentro do Docker
- **minikube**: cria uma VM ou container Docker com um cluster Kubernetes

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| Docker | 20.10+ | `docker --version` |
| kubectl | 1.28+ | `kubectl version --client` |
| Uma das: kind, k3d, minikube | | Ver abaixo |

## Opção A: kind (Recomendada)

### Instalar kind

```bash
# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# macOS
brew install kind
```

Verificar: `kind --version`

### Criar cluster

O projeto inclui uma configuração com 1 control-plane e 2 workers:

```bash
kind create cluster --name reliabilitylab --config scripts/kind-config.yaml
```

O arquivo `scripts/kind-config.yaml` configura:
- 3 nós (1 control-plane + 2 workers)
- Mapeamento de portas 80 e 443 para acesso via Ingress
- Labels para o Ingress Controller

### Instalar NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Aguardar ficar pronto
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s
```

### Instalar Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Corrigir para ambiente local (TLS)
kubectl patch deployment metrics-server -n kube-system \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## Opção B: k3d

### Instalar k3d

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

### Criar cluster

```bash
k3d cluster create reliabilitylab \
    --servers 1 --agents 2 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0"
```

### Instalar NGINX Ingress

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

## Opção C: minikube

### Instalar minikube

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### Criar cluster

```bash
minikube start --driver=docker --nodes=3 --cpus=2 --memory=4096 \
    --profile=reliabilitylab --kubernetes-version=v1.32.0
```

### Habilitar addons

```bash
minikube addons enable ingress -p reliabilitylab
minikube addons enable metrics-server -p reliabilitylab
```

## Setup Automatizado

O script de setup detecta automaticamente qual ferramenta está instalada:

```bash
bash scripts/setup.sh
```

## Verificar o Cluster

```bash
# Ver nós
kubectl get nodes

# Resultado esperado (kind):
# NAME                            STATUS   ROLES           AGE   VERSION
# reliabilitylab-control-plane    Ready    control-plane   1m    v1.32.0
# reliabilitylab-worker           Ready    <none>          1m    v1.32.0
# reliabilitylab-worker2          Ready    <none>          1m    v1.32.0

# Ver namespaces
kubectl get namespaces

# Ver pods do sistema
kubectl get pods -A
```

## Configurar DNS Local

```bash
echo "127.0.0.1 site-kubectl.local" | sudo tee -a /etc/hosts
```

## Destruir o Cluster

```bash
bash scripts/destroy.sh
```

Ou manualmente:
```bash
# kind
kind delete cluster --name reliabilitylab

# k3d
k3d cluster delete reliabilitylab

# minikube
minikube delete -p reliabilitylab
```

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `Cannot connect to the Docker daemon` | Inicie o Docker: `sudo systemctl start docker` |
| `insufficient memory` | Reduza para 2 nós ou aumente memória |
| Ingress não responde na porta 80 | Verifique `kind-config.yaml` e port mappings |
| `metrics-server` não funciona | Aplique o patch `--kubelet-insecure-tls` |

## Próximo Tutorial

[04 — Deploy no Kubernetes](04-deploy-kubernetes.md)
