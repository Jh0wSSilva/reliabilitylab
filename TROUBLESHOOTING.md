# Troubleshooting — ReliabilityLab

Guia centralizado com todos os problemas reais encontrados durante o desenvolvimento do ReliabilityLab, com diagnóstico, causa raiz e solução passo a passo.

---

## Índice

- [P1 — Alertmanager CrashLoopBackOff](#p1--alertmanager-crashloopbackoff)
- [P2 — LitmusChaos v3.x quebrado via kubectl](#p2--litmuschaos-v3x-quebrado-via-kubectl)
- [P3 — Chaos Mesh controller-manager CrashLoopBackOff](#p3--chaos-mesh-controller-manager-crashloopbackoff)
- [P4 — Cluster instável após horas rodando](#p4--cluster-instável-após-horas-rodando)
- [P5 — ArgoCD redis-secret-init timeout](#p5--argocd-redis-secret-init-timeout)
- [P6 — HPA não escalando](#p6--hpa-não-escalando-targets-unknown-ou-cpu-muito-baixa)
- [P7 — Ingress-nginx pods não ficam Ready](#p7--ingress-nginx-pods-não-ficam-ready)

---

## P1 — Alertmanager CrashLoopBackOff

### Sintoma

O pod do Alertmanager entra em CrashLoopBackOff logo após a instalação do kube-prometheus-stack:

```
alertmanager-kube-prometheus-stack-alertmanager-0   0/2   CrashLoopBackOff   3   5m
```

Nos logs:

```
ts=... caller=main.go:231 msg="Loading configuration file" file=/etc/alertmanager/config_out/alertmanager.env.yaml
...
err="open /alertmanager/data: stat /tmp/hostpath-provisioner/monitoring/alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0: no such file or directory"
```

### Causa raiz

O kube-prometheus-stack, por padrão, configura o Alertmanager com um PVC (Persistent Volume Claim) para persistir estado de silences e notification history. No Minikube, o `hostpath-provisioner` é responsável por criar diretórios em `/tmp/hostpath-provisioner/...`, mas frequentemente falha em criar o diretório no tempo correto, especialmente quando o cluster está sob pressão de recursos.

### Diagnóstico

```bash
# Verificar logs do Alertmanager
kubectl logs alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring -c alertmanager

# Verificar PVC
kubectl get pvc -n monitoring

# Verificar eventos
kubectl describe pod alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring | tail -20
```

### Solução

Desabilitar storage do Alertmanager no `helm/values/local/prometheus-values.yaml`:

```yaml
alertmanager:
  alertmanagerSpec:
    storage: {}
```

Aplicar:

```bash
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f helm/values/local/prometheus-values.yaml \
  --wait --timeout 10m
```

### Como evitar

Sempre inclua `alertmanagerSpec.storage: {}` no values.yaml quando rodando em Minikube. Em produção com PVs reais (EBS, GCE PD), o storage funciona normalmente.

---

## P2 — LitmusChaos v3.x quebrado via kubectl

### Sintoma

Após instalar o LitmusChaos v3.x via Helm:

```bash
helm install litmus litmuschaos/litmus --namespace litmus
```

Os CRDs `ChaosEngine`, `ChaosExperiment` e `ChaosResult` não são instalados:

```bash
kubectl get crd | grep litmus
# Nenhum resultado ou apenas CRDs do ChaosCenter (UI)
```

Ao tentar aplicar um ChaosEngine manualmente:

```
error: the server doesn't have a resource type "chaosengine"
```

Mesmo instalando os CRDs manualmente, a imagem `go-runner:1.13.8` falha:

```
exec: "/usr/local/bin/pod-delete": stat /usr/local/bin/pod-delete: no such file or directory
```

### Causa raiz

O LitmusChaos v3.x redesenhou completamente sua arquitetura:
1. O Helm chart instala apenas o **ChaosCenter** (UI web + API server)
2. O `chaos-operator` (que processava ChaosEngines) foi removido do chart
3. Experimentos agora rodam apenas via API do ChaosCenter, não via CRDs kubectl
4. A imagem `go-runner:1.13.8` foi esvaziada — não contém os binários dos experimentos
5. Os experimentos devem ser orquestrados pelo ChaosCenter workflow engine, não pelo operator

### Diagnóstico

```bash
# Verificar o que foi instalado
helm list -n litmus
kubectl get pods -n litmus
# Apenas pods do ChaosCenter: litmusportal-frontend, litmusportal-server, mongodb

# Verificar CRDs
kubectl get crd | grep -i chaos
# Apenas CRDs do ChaosCenter (chaoshubs, chaosinfrastructures, etc.)
# NÃO inclui: chaosengines, chaosexperiments, chaosresults

# Testar a imagem
kubectl run test-litmus --image=litmuschaos/go-runner:1.13.8 --command -- ls /usr/local/bin/
# Não contém pod-delete, container-kill, etc.
```

### Solução

Migrar para **Chaos Mesh** (CNCF, funciona via CRDs, ativamente mantido):

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  -n chaos-mesh \
  --set controllerManager.replicaCount=1 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout 10m
```

Limpar restos do LitmusChaos (se instalou):

```bash
helm uninstall litmus -n litmus 2>/dev/null
kubectl delete namespace litmus 2>/dev/null
kubectl delete crd $(kubectl get crd | grep litmuschaos | awk '{print $1}') 2>/dev/null
```

### Como evitar

Antes de adotar uma ferramenta, teste o fluxo completo end-to-end em um cluster de teste. Verifique changelogs de major versions — mudanças arquiteturais como essa são documentadas mas fáceis de perder.

---

## P3 — Chaos Mesh controller-manager CrashLoopBackOff

### Sintoma

O pod `chaos-controller-manager` entra em CrashLoopBackOff:

```
chaos-controller-manager-xxxxx-yyyyy   0/1   CrashLoopBackOff   5   10m
chaos-controller-manager-xxxxx-zzzzz   0/1   CrashLoopBackOff   5   10m
chaos-controller-manager-xxxxx-aaaaa   0/1   CrashLoopBackOff   5   10m
```

Nos logs:

```
"msg":"leader election lost"
"msg":"failed to acquire leader lease chaos-mesh/chaos-controller-manager"
```

### Causa raiz

O Chaos Mesh é instalado por padrão com 3 réplicas do controller-manager. No Minikube com RAM limitada:
1. As 3 réplicas competem pelo leader election
2. Apenas 1 pode ganhar — as outras 2 ficam em standby
3. Com RAM insuficiente (2GB/nó), os health checks das réplicas falham por timeout
4. O Kubernetes reinicia os pods → nova eleição → loop infinito
5. O resultado é 3 pods em CrashLoopBackOff alternando com Running

### Diagnóstico

```bash
# Verificar quantas réplicas existem
kubectl get deploy -n chaos-mesh chaos-controller-manager -o jsonpath='{.spec.replicas}'

# Verificar logs do controller
kubectl logs -n chaos-mesh -l app.kubernetes.io/component=controller-manager --tail=50

# Verificar memória dos nós
kubectl top nodes
```

### Solução

Reinstalar com 1 réplica + memória adequada:

```bash
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  -n chaos-mesh \
  --set controllerManager.replicaCount=1 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout 10m
```

Se o cluster foi criado com `--memory=2048`, recrie com `--memory=4096`:

```bash
minikube delete -p reliabilitylab
minikube start \
  --driver=docker \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --profile=reliabilitylab \
  --kubernetes-version=v1.32.0
```

### Como evitar

Em ambiente Minikube/local, sempre use `controllerManager.replicaCount=1`. Não há problema se apenas UM controller ficar `Running` — os demais frequentemente apresentam `Error` ou `CrashLoopBackOff` por perderem a eleição. Alta disponibilidade (3 réplicas) só faz sentido em clusters de produção com recursos abundantes; em ambientes pequenos, múltiplas réplicas só geram erros e consomem CPU sem benefício.

---

## P4 — Cluster instável após horas rodando

### Sintoma

Após 1-2 horas com o stack completo rodando (Prometheus, Grafana, Chaos Mesh, ArgoCD), o cluster apresenta:

```
# CoreDNS em CrashLoop
coredns-xxxxxxx-yyyyy   0/1   CrashLoopBackOff   8   2h

# API server timeout
dial tcp 10.96.0.1:443: i/o timeout

# kubectl lento ou não responde
The connection to the server 192.168.49.2:8443 was refused
```

### Causa raiz

Com `--memory=2048` por nó, o total de memória alocada é 6GB (3 nós × 2GB). O stack completo consome:
- kube-system (CoreDNS, kube-proxy, etcd): ~800MB
- Prometheus + Grafana + Alertmanager: ~1.5GB
- Chaos Mesh: ~500MB
- ArgoCD: ~800MB
- Workloads (6 pods production): ~400MB
- **Total: ~4GB** — bem acima dos 6GB disponíveis quando combinado com overhead do Kubernetes

O resultado: OOM killer começa a matar processos, CoreDNS é killado, API server perde conectividade, kubelet reporta `MemoryPressure`.

### Diagnóstico

```bash
# Verificar pressão de memória nos nós
kubectl describe nodes | grep -A5 "Conditions:" | grep -E "MemoryPressure|DiskPressure"

# Verificar uso de memória
kubectl top nodes

# Verificar eventos de OOMKill
kubectl get events --all-namespaces | grep -i oom

# Verificar pods restartando
kubectl get pods --all-namespaces | awk '$5 > 3 {print $0}'
```

### Solução

Recriar o cluster com 4096MB por nó:

```bash
minikube delete -p reliabilitylab

minikube start \
  --driver=docker \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --profile=reliabilitylab \
  --kubernetes-version=v1.32.0
```

Reinstalar o stack na ordem correta (veja `scripts/bootstrap.sh`).

### Como evitar

**Sempre use `--memory=4096`** quando rodando o stack completo no Minikube. O mínimo absoluto para Prometheus + Grafana + 1 tool extra é 3GB/nó. Para o stack completo (Prometheus + Grafana + Chaos Mesh + ArgoCD + workloads), 4GB/nó é o mínimo confortável.

---

## P5 — ArgoCD redis-secret-init timeout

### Sintoma

Ao instalar o ArgoCD, o pod `argocd-redis` fica preso em `Init:CrashLoopBackOff`:

```
argocd-redis-xxxxx-yyyyy   0/1   Init:CrashLoopBackOff   5   10m
```

O init container `redis-secret-init` timeout tentando se comunicar com a API do Kubernetes.

### Causa raiz

O ArgoCD é um dos componentes mais pesados do stack (Redis, Repo Server, Application Controller, Dex, Server). Quando instalado em um cluster já carregado com Prometheus + Chaos Mesh + workloads, e com memória insuficiente (2GB/nó):
1. A rede interna do cluster está instável (CoreDNS intermitente)
2. O init container `redis-secret-init` precisa comunicar com a API para criar/ler Secrets
3. A comunicação falha por timeout → init container reinicia → CrashLoopBackOff

### Diagnóstico

```bash
# Verificar init containers
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-redis | grep -A10 "Init Containers:"

# Verificar eventos
kubectl get events -n argocd --sort-by=.metadata.creationTimestamp | tail -20

# Verificar DNS (usar FQDN completo para correta resolução)
kubectl run test-dns --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

### Solução

1. Garanta que o cluster está com `--memory=4096`
2. Instale o ArgoCD **somente após o cluster ter estabilizado** com Prometheus e Chaos Mesh
3. Aguarde 2-3 minutos após instalar Chaos Mesh antes de instalar ArgoCD

```bash
# Verificar que o cluster está estável
kubectl top nodes
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Só então instalar ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

### Como evitar

Instale componentes em ordem, verificando saúde entre cada passo. O `scripts/bootstrap.sh` faz isso automaticamente.

---

## P6 — HPA não escalando (targets `<unknown>` ou CPU muito baixa)

### Sintoma

O HPA mostra `<unknown>` nos targets ou CPU extremamente baixa mesmo sob carga:

```
NAME          REFERENCE                TARGETS         MINPODS   MAXPODS   REPLICAS
content-api   Deployment/content-api   <unknown>/70%   2         10        2
```

### Causa raiz

Dois cenários comuns:

1. **Targets `<unknown>`:** O metrics-server ainda não coletou dados (leva ~60 segundos após o pod subir) ou o metrics-server não está instalado/saudável.
2. **CPU muito baixa:** Se o workload é extremamente leve (ex: servir conteúdo estático sem processamento), a CPU real pode nunca atingir o threshold.

> **Nota histórica:** O projeto usava `nginx:alpine` como mock que gerava CPU <5% mesmo sob carga pesada. Migramos para `podinfo` (stefanprodan/podinfo) que consome CPU proporcionalmente à carga real, resolvendo esse problema.

### Diagnóstico

```bash
# Verificar CPU real dos pods
kubectl top pods -n production

# Verificar configuração do HPA
kubectl describe hpa content-api -n production

# Verificar se o metrics-server está saudável
kubectl get pods -n kube-system | grep metrics-server
kubectl top nodes
```

### Solução

Se o HPA mostra `<unknown>`:
```bash
# Verificar se o metrics-server está habilitado
minikube addons enable metrics-server -p reliabilitylab

# Aguardar ~60s e verificar novamente
kubectl get hpa -n production
```

Para forçar carga de CPU no podinfo, use o endpoint de stress:
```bash
# Stress via endpoint do podinfo (consome CPU real)
kubectl port-forward -n production svc/content-api 8081:9898 &
curl -s "http://localhost:8081/stress/cpu?duration=60s"
```

Ou usar StressChaos do Chaos Mesh (mais controlado):
```bash
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

### Como evitar

Use workloads que consumam CPU de forma realista (como podinfo). Para testes de HPA significativos, o endpoint `/stress/cpu` do podinfo ou o StressChaos do Chaos Mesh são as formas recomendadas de gerar carga.

---

---

## P7 — Ingress-nginx pods não ficam Ready

### Sintoma

Ao usar `kubectl wait --for=condition=Ready pods --all -n ingress-nginx`, a operação faz timeout:

```
timed out waiting for the condition on pods/ingress-nginx-admission-create-nht5g
timed out waiting for the condition on pods/ingress-nginx-admission-patch-m7rzp
timed out waiting for the condition on pods/ingress-nginx-controller-6fc6655698-xx7g9
```

Ou o pod controller mostra `0/1 Running` e não sobe para `1/1 Ready`.

### Causa raiz

Dois problemas distintos:

1. **Jobs de admission:** `kubectl wait --all` tenta esperar pelos Jobs de admission (`ingress-nginx-admission-create` e `ingress-nginx-admission-patch`) entrarem em `Ready`, mas Jobs naturalmente completam e não ficam em estado `Ready`. Isso causa timeout falso.

2. **Pod controller não sobe:** O pod controller falha em montar o secret `ingress-nginx-admission` que deveria ter sido criado pelos Jobs. Se os Jobs não completarem com sucesso, o pod controller fica preso em `ContainersReady=True` mas `Ready=False`.

### Diagnóstico

```bash
# Verificar status detalhado
kubectl get pods -n ingress-nginx -o wide

# Verificar se secret foi criado
kubectl get secret -n ingress-nginx ingress-nginx-admission

# Ver logs dos jobs
kubectl logs -n ingress-nginx -l batch.kubernetes.io/job-name=ingress-nginx-admission-create --tail=20

# Ver eventos do pod controller
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep -A10 "Events:"
```

### Solução

**Opção 1: Aguardar apenas o controller (recomendado)**

Em vez de `--all`, aguarde apenas o pod controller usando seu label específico:

```bash
# Coreto: espera apenas o controller, ignora os Jobs
kubectl wait --for=condition=Ready pod \
  -n ingress-nginx \
  -l app.kubernetes.io/component=controller \
  --timeout=180s

# Ou com label mais genérico
kubectl wait --for=condition=Ready pod \
  -n ingress-nginx \
  -l app.kubernetes.io/name=ingress-nginx \
  --timeout=180s
```

**Opção 2: Se o controller ainda não sobe**

Reinicie o deployment:

```bash
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx
```

### Como evitar

1. Nunca use `--all` com namespaces contendo Jobs — sempre especifique labels ou deployments específicos
2. O secret `ingress-nginx-admission` deve ser criado automaticamente pelos Jobs: se vê erro "secret not found", aguarde mais um pouco (Jobs podem levar ~30s)
3. Sempre use `kubectl wait` com labels específicos para aumentar a precisão

### Nota técnica

Os Jobs de admission (`admission-create` e `admission-patch`) são Job da API Kubernetes que executam uma única vez durante o bootstrap do ingress-nginx para:
- Gerar certificados TLS para o webhook
- Criar o secret `ingress-nginx-admission` com os certificados
- Fazer patch nas validating/mutating webhooks com o CA bundle

Apos completarem com sucesso, seu status é `0/1 Completed` (não `1/1 Ready`) — isso é normal. O importante é verificar que o secret foi criado e que o pod controller está `1/1 Ready`.

---

## Referência rápida

| Problema | Solução de uma linha |
|----------|---------------------|
| P1 | `alertmanagerSpec.storage: {}` no values.yaml |
| P2 | Usar Chaos Mesh ao invés de LitmusChaos v3.x |
| P3 | `controllerManager.replicaCount=1` + `--memory=4096` |
| P4 | `--memory=4096` por nó no Minikube |
| P5 | Instalar ArgoCD somente após cluster estável com 4GB RAM |
| P6 | Verificar metrics-server e usar `podinfo /stress/cpu` para simular carga |
| P7 | `kubectl wait` com `-l app.kubernetes.io/component=controller`, não `--all` |
