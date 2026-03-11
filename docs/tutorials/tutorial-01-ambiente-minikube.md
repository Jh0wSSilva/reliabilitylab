# Tutorial 01 — Ambiente Local com Minikube

**Objetivo:** Subir um cluster Kubernetes local multi-node com Minikube para simular um ambiente de produção.

**Resultado:** Cluster com 3 nós (1 control-plane + 2 workers) rodando Kubernetes v1.32.0, kubectl configurado, addons essenciais ativos e health check verde.

**Tempo estimado:** 20 minutos

**Pré-requisitos:** Docker instalado e rodando, mínimo 12GB RAM livre na máquina host

---

## Contexto

Em ambientes de produção, clusters Kubernetes rodam com dezenas ou centenas de nós distribuídos entre múltiplas zonas de disponibilidade. Para desenvolver e testar localmente, engenheiros precisam de ambientes que repliquem a distribuição real de carga entre nós.

O Minikube permite simular um cluster multi-node na sua máquina, incluindo features como ingress, DNS e metrics-server — tudo que você precisa para montar um lab completo de SRE.

Neste tutorial, criamos um cluster com 3 nós e **4096MB de RAM por nó**. Essa configuração é obrigatória — com 2048MB o cluster fica instável após instalar o stack de monitoramento, causando CoreDNS timeout, `i/o timeout` para o API server e CrashLoopBackOff em componentes como Alertmanager e Chaos Mesh controller-manager. Esse foi um dos aprendizados reais deste projeto (veja [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#p5--cluster-instável-após-horas-rodando)).

---

## Passo 1 — Instalar ferramentas

Verifique se as ferramentas estão instaladas:

```bash
docker --version
minikube version
kubectl version --client
helm version --short
k6 version
```

✅ Esperado: versões impressas sem erro para cada ferramenta.

Se alguma estiver faltando:

```bash
# Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
rm kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# k6
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6 -y
```

---

## Passo 2 — Limpar ambiente anterior (se existir)

```bash
minikube delete -p reliabilitylab 2>/dev/null || true
```

> Sempre limpe profiles antigos antes de recriar para evitar estado corrompido.

---

## Passo 3 — Criar o cluster

```bash
minikube start \
  --driver=docker \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --profile=reliabilitylab \
  --kubernetes-version=v1.32.0
```

| Flag | O que faz |
|------|-----------|
| `--driver=docker` | Usa Docker como runtime (mais leve que VM) |
| `--nodes=3` | 1 control-plane + 2 workers |
| `--cpus=2` | 2 CPUs por nó |
| `--memory=4096` | **4GB RAM por nó** (mínimo para o stack completo) |
| `--profile` | Nome isolado do cluster |
| `--kubernetes-version` | v1.32.0 — LTS estável |

✅ Esperado:
```
🏄  Done! kubectl is now configured to use "reliabilitylab" cluster and "default" namespace by default
```

> **⚠️ IMPORTANTE:** O `--memory=4096` é obrigatório. Com 2048MB, o cluster fica instável quando você instala Prometheus, Grafana, Chaos Mesh e ArgoCD simultaneamente. CoreDNS trava, API server retorna `i/o timeout` e vários pods entram em CrashLoopBackOff. Esse foi um dos problemas reais que encontramos — documentado como P5 no [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md).

---

## Passo 4 — Verificar os nós

```bash
kubectl get nodes -o wide
```

✅ Esperado:
```
NAME                    STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE              CONTAINER-RUNTIME
reliabilitylab          Ready    control-plane   2m    v1.32.0   192.168.49.2   Ubuntu 22.04.x LTS    containerd://1.7.x
reliabilitylab-m02      Ready    <none>          1m    v1.32.0   192.168.49.3   Ubuntu 22.04.x LTS    containerd://1.7.x
reliabilitylab-m03      Ready    <none>          1m    v1.32.0   192.168.49.4   Ubuntu 22.04.x LTS    containerd://1.7.x
```

> Todos os 3 nós devem estar `Ready`. Se algum estiver `NotReady`, aguarde 1-2 minutos e verifique novamente.

---

## Passo 5 — Habilitar addons

```bash
minikube addons enable ingress        -p reliabilitylab
minikube addons enable metrics-server -p reliabilitylab
minikube addons enable dashboard      -p reliabilitylab
```

| Addon | Para que serve |
|-------|---------------|
| `ingress` | Expor serviços via URL (nginx-ingress-controller) |
| `metrics-server` | Necessário para HPA funcionar — coleta CPU/RAM dos pods |
| `dashboard` | Interface web do Kubernetes |

Verificar addons ativos:

```bash
minikube addons list -p reliabilitylab | grep -E "enabled|STATUS"
```

✅ Esperado: `dashboard`, `default-storageclass`, `ingress`, `metrics-server` e `storage-provisioner` com status `enabled`.

---

## Passo 6 — Aguardar estabilização do cluster

O metrics-server e o ingress controller demoram até 2 minutos para estabilizar:

```bash
echo "Aguardando pods do kube-system..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s

echo "Aguardando ingress controller..."
kubectl wait --for=condition=Ready pods --all -n ingress-nginx --timeout=180s
```

✅ Esperado: `condition met` para todos os pods.

---

## Passo 7 — Testar DNS interno

```bash
kubectl run test-dns --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default
```

✅ Esperado:
```
Server:    10.96.0.10
Name:      kubernetes.default.svc.cluster.local
Address:   10.96.0.1
```

---

## Passo 8 — Testar metrics-server

```bash
kubectl top nodes
```

✅ Esperado:
```
NAME                    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
reliabilitylab          150m         7%     800Mi           20%
reliabilitylab-m02      50m          2%     400Mi           10%
reliabilitylab-m03      50m          2%     400Mi           10%
```

> Se retornar `error: Metrics API not available`, aguarde mais 1-2 minutos — o metrics-server ainda está inicializando.

---

## Health Check (antes de avançar para Tutorial 02)

```bash
echo "=== HEALTH CHECK — Tutorial 01 ==="

echo -e "\n[1/5] Nós do cluster:"
kubectl get nodes
echo ""

echo "[2/5] Pods do kube-system:"
kubectl get pods -n kube-system --no-headers | awk '{print $1, $3}'
echo ""

echo "[3/5] Metrics-server:"
kubectl top nodes 2>/dev/null && echo "✅ metrics-server OK" || echo "❌ metrics-server não está pronto"
echo ""

echo "[4/5] Ingress controller:"
kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | awk '{print $1, $3}'
echo ""

echo "[5/5] DNS resolution:"
kubectl run hc-dns --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup kubernetes.default 2>/dev/null \
  && echo "✅ DNS OK" || echo "❌ DNS falhou"

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

**Critério:** Todos os 5 checks devem passar antes de ir para o Tutorial 02.

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| Node `NotReady` por mais de 3 min | Driver Docker sem recursos ou container parado | `docker ps` para verificar containers. Se parado: `minikube delete -p reliabilitylab` e recriar |
| `RSRC_INSUFFICIENT_CORES` | Menos de 2 CPUs disponíveis | Libere processos pesados ou pare outros containers |
| `RSRC_INSUFFICIENT_MEMORY` | Menos de 12GB livres na máquina host | Feche aplicações pesadas (browsers, IDEs extras) |
| metrics-server `Metrics API not available` | Addon ainda inicializando | Aguarde 2-3 min. Se persistir: desabilite e re-habilite o addon |
| DNS timeout `i/o timeout` | CoreDNS não estabilizou ou memória insuficiente | Verifique `kubectl get pods -n kube-system`. Se CoreDNS em CrashLoop, recrie com `--memory=4096` |
| `dial tcp 10.96.0.1:443: i/o timeout` | API server sobrecarregado — RAM insuficiente | **Solução definitiva:** recriar com `--memory=4096` por nó |
| Cluster lento após 1-2h | Swap e OOM killer atuando nos containers | Recrie com `--memory=4096`. Use `minikube stop -p reliabilitylab` quando não estiver usando |

---

## Comandos úteis

```bash
# Parar o cluster (preserva estado)
minikube stop -p reliabilitylab

# Iniciar novamente
minikube start -p reliabilitylab

# Destruir completamente
minikube delete -p reliabilitylab

# Ver status
minikube status -p reliabilitylab

# Dashboard visual
minikube dashboard -p reliabilitylab

# Verificar contexto ativo
kubectl config current-context
```

---

## ⚡ Próximo passo: Bootstrap automático (opcional)

Se você completou este tutorial com sucesso, pode pular os tutoriais 02-07 e provisionar todo o stack de uma vez usando:

```bash
# Torne o script executável
chmod +x scripts/bootstrap.sh

# Execute o bootstrap automático (7 fases: cluster -> namespaces -> monitoramento -> SLOs -> servicos -> chaos -> argocd)
./scripts/bootstrap.sh
```

O script provisiona tudo em ordem e verifica health entre cada fase. **Recomendado para:** quem quer pular a curva de aprendizado e começar com SLOs, chaos engineering e observabilidade.

**Para aprender conceitos:** continue com os tutoriais 02-07 passo a passo. Cada um detalha o "porquê" e o "como" de cada componente.

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `O minikube start falhou com erro X. Diagnostique e sugira como corrigir`
- `Meu cluster está com nós NotReady. Verifique o que pode estar errado`
- `Compare a versão do Kubernetes no cluster com a versão do kubectl e me diga se são compatíveis`
- `Verifique se o Docker está rodando corretamente e se o minikube consegue se conectar`
- `O addon metrics-server não está coletando dados. Diagnostique o motivo`

---

**Próximo:** [Tutorial 02 — Namespaces, ResourceQuota e LimitRange](tutorial-02-namespaces-quota.md)
