# Tutorial 06 — Chaos Engineering com Chaos Mesh

**Objetivo:** Instalar o Chaos Mesh e executar 3 experimentos de chaos engineering para validar a resiliência dos serviços StreamFlix.

**Resultado:** Chaos Mesh operacional, 3 experimentos executados com sucesso (PodChaos, NetworkChaos, StressChaos) e resultados documentados.

**Tempo estimado:** 30 minutos

**Pré-requisitos:** Tutorial 05 completo com health check verde

---

## Contexto

O **Chaos Engineering** surgiu da necessidade de testar resiliência em produção de forma proativa. A ideia: matar instâncias aleatórias para forçar engenheiros a construir sistemas resilientes. Isso evoluiu para frameworks completos que executam experimentos controlados com blast radius definido.

O princípio: **se você não testa falhas proativamente, descobre falhas reativamente — às 3h da manhã, em produção, na Black Friday.**

O **Chaos Mesh** é uma ferramenta open source de chaos engineering, mantida pela CNCF (Cloud Native Computing Foundation). Ele injeta falhas via CRDs do Kubernetes — pod kill, network latency, CPU stress, disk fill — com controle granular de namespace, labels e duração.

### Por que Chaos Mesh e não LitmusChaos?

O LitmusChaos v3.x mudou completamente a arquitetura: o Helm chart só instala o ChaosCenter (UI web), sem chaos-operator nem CRDs. Os experimentos via `kubectl` (ChaosEngine) não funcionam mais. A imagem `go-runner:1.13.8` não contém os binários dos experimentos. Após extensos testes, concluímos que o LitmusChaos v3.x é inviável para uso via kubectl — documentamos essa decisão no [ADR-002](../adr/ADR-002-chaos-mesh.md) e no [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md#p3--litmuschaos-v3x-quebrado-via-kubectl).

O Chaos Mesh é CNCF, ativamente mantido, funciona 100% via CRDs, e tem dashboard web incluso.

---

## Passo 1 — Adicionar repositório Helm do Chaos Mesh

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
```

✅ Esperado:
```
"chaos-mesh" has been added to your repositories
...Successfully got an update from the "chaos-mesh" chart repository
```

---

## Passo 2 — Instalar Chaos Mesh com parâmetros corretos para Minikube

```bash
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --version 2.8.1 \
  -n chaos-mesh \
  --set controllerManager.replicaCount=1 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout 10m
```

| Parâmetro | Motivo |
|-----------|--------|
| `controllerManager.replicaCount=1` | **OBRIGATÓRIO no Minikube.** Com 3 réplicas (padrão), ocorre `leader election lost` → CrashLoopBackOff. A competição entre réplicas + RAM limitada causa instabilidade (P4) |
| `chaosDaemon.runtime=containerd` | Minikube usa containerd como runtime (não Docker) |
| `chaosDaemon.socketPath=/run/containerd/containerd.sock` | Socket do containerd no Minikube |
| `dashboard.securityMode=false` | Desabilita autenticação no dashboard (lab local) |

✅ Esperado:
```
Release "chaos-mesh" has been upgraded. Happy Helming!
```

---

## Passo 3 — Verificar instalação

```bash
kubectl get pods -n chaos-mesh
```

✅ Esperado (todos Running, 0 restarts):
```
NAME                                        READY   STATUS    RESTARTS   AGE
chaos-controller-manager-xxxxx-yyyyy        1/1     Running   0          2m
chaos-daemon-xxxxx                          1/1     Running   0          2m
chaos-daemon-yyyyy                          1/1     Running   0          2m
chaos-daemon-zzzzz                          1/1     Running   0          2m
chaos-dashboard-xxxxx-yyyyy                 1/1     Running   0          2m
```

> O `chaos-daemon` roda como DaemonSet — 1 por nó (3 no nosso cluster). O `chaos-controller-manager` deve ter exatamente 1 réplica.

Verificar CRDs:

```bash
kubectl get crd | grep chaos-mesh
```

✅ Esperado: múltiplos CRDs incluindo `podchaos`, `networkchaos`, `stresschaos`, `iochaos`, etc.

---

## Passo 4 — Acessar o Dashboard do Chaos Mesh

```bash
minikube service chaos-dashboard -n chaos-mesh -p reliabilitylab
```

Ou via port-forward:

```bash
kubectl port-forward svc/chaos-dashboard -n chaos-mesh 2333:2333 &
echo "Dashboard: http://localhost:2333"
```

✅ Esperado: interface web do Chaos Mesh carregando no browser.

---

## Passo 5 — Experimento 1: PodChaos (Pod Kill)

Este experimento mata pods aleatórios e verifica se o Kubernetes se recupera dentro do SLO.

**Hipótese:** "Se um pod do content-api for morto, o Kubernetes cria um novo pod em menos de 30 segundos."

Crie o manifesto:

```bash
cat <<'EOF' > platform/chaos/experiments/chaos-pod-kill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-content-api
  namespace: chaos-mesh
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - production
    labelSelectors:
      app: content-api
  duration: "30s"
EOF
```

| Campo | Valor | Significado |
|-------|-------|-------------|
| `action: pod-kill` | Mata o container | Equivalente a `kubectl delete pod --force` |
| `mode: one` | Mata apenas 1 pod | Blast radius controlado |
| `selector.namespaces` | production | Escopo do experimento |
| `selector.labelSelectors` | app: content-api | Qual deployment atacar |
| `duration` | 30s | Período do experimento |

Monitor em um terminal separado:

```bash
# Terminal 1 — monitorar pods em tempo real
kubectl get pods -n production -l app=content-api -w
```

Executar o experimento:

```bash
# Terminal 2 — aplicar o experimento
kubectl apply -f platform/chaos/experiments/chaos-pod-kill.yaml
```

✅ Esperado no Terminal 1:
```
content-api-xxxxx-yyyyy   1/1     Running       0          5m
content-api-xxxxx-zzzzz   1/1     Running       0          5m
content-api-xxxxx-yyyyy   1/1     Terminating   0          5m     ← pod morto
content-api-xxxxx-aaaaa   0/1     Pending       0          0s     ← novo pod criado
content-api-xxxxx-aaaaa   0/1     ContainerCreating   0    0s
content-api-xxxxx-aaaaa   1/1     Running       0          1s     ← Running em ~1s!
```

**Resultado esperado:** recuperação em ~1-3 segundos (imagem podinfo já em cache nos nós).

Verificar resultado:

```bash
kubectl get podchaos -n chaos-mesh
```

✅ Esperado: `pod-kill-content-api` com status indicando experimento executado.

Limpar o experimento:

```bash
kubectl delete podchaos pod-kill-content-api -n chaos-mesh
```

---

## Passo 6 — Experimento 2: NetworkChaos (Latência)

Este experimento simula um problema de rede — adiciona 200ms de latência em todas as requests para o recommendation-api.

**Hipótese:** "Com 200ms de latência injetada, o recommendation-api continua respondendo sem erros em cascata."

```bash
cat <<'EOF' > platform/chaos/experiments/chaos-network-latency.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-latency-recommendation
  namespace: chaos-mesh
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - production
    labelSelectors:
      app: recommendation-api
  delay:
    latency: "200ms"
    correlation: "100"
    jitter: "50ms"
  duration: "60s"
EOF
```

| Campo | Significado |
|-------|-------------|
| `action: delay` | Injeta latência (não derruba o pod) |
| `latency: 200ms` | 200ms de delay adicionado |
| `jitter: 50ms` | Variação de ±50ms no delay |
| `correlation: 100` | 100% dos pacotes afetados |
| `duration: 60s` | Experimento dura 1 minuto |

Executar:

```bash
kubectl apply -f platform/chaos/experiments/chaos-network-latency.yaml
```

Testar latência durante o experimento:

```bash
# De dentro do cluster, medir tempo de resposta
kubectl run test-latency --image=curlimages/curl --restart=Never --rm -it -n production -- \
  sh -c "for i in 1 2 3 4 5; do time curl -s -o /dev/null http://recommendation-api; done"
```

✅ Esperado: cada request levando ~200ms (+ jitter) ao invés de <10ms.

Verificar que o serviço ainda responde (sem erro):

```bash
kubectl run test-response --image=curlimages/curl --restart=Never --rm -it -n production -- \
  sh -c "curl -s -o /dev/null -w '%{http_code}' http://recommendation-api"
```

✅ Esperado: `200` (serviço lento mas funcional).

Limpar:

```bash
kubectl delete networkchaos network-latency-recommendation -n chaos-mesh
```

---

## Passo 7 — Experimento 3: StressChaos (CPU Stress)

Este experimento simula um pico de CPU no content-api e verifica se o HPA responde escalando as réplicas.

**Hipótese:** "Quando o CPU do content-api ultrapassa 70%, o HPA escala automaticamente para mais réplicas."

```bash
cat <<'EOF' > platform/chaos/experiments/chaos-cpu-stress.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-content-api
  namespace: chaos-mesh
spec:
  mode: all
  selector:
    namespaces:
      - production
    labelSelectors:
      app: content-api
  stressors:
    cpu:
      workers: 2
      load: 80
  duration: "3m"
EOF
```

| Campo | Significado |
|-------|-------------|
| `stressors.cpu.workers: 2` | 2 workers gerando carga de CPU |
| `stressors.cpu.load: 80` | 80% de carga por worker |
| `duration: 3m` | 3 minutos (tempo suficiente para HPA reagir) |

Monitor HPA em um terminal:

```bash
# Terminal 1 — acompanhar HPA
kubectl get hpa -n production -w
```

Executar:

```bash
# Terminal 2 — aplicar stress
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

✅ Esperado (após 1-2 minutos):
```
NAME          REFERENCE                TARGETS    MINPODS   MAXPODS   REPLICAS
content-api   Deployment/content-api   165%/70%   2         10        2
content-api   Deployment/content-api   165%/70%   2         10        4
content-api   Deployment/content-api   120%/70%   2         10        6
```

**Resultado:** HPA escala de 2 para 6 réplicas em ~2 minutos.

Limpar:

```bash
kubectl delete stresschaos cpu-stress-content-api -n chaos-mesh
```

Aguarde ~5 minutos para o HPA fazer scale-down de volta para 2 réplicas.

---

## Passo 8 — Resumo dos resultados

| Experimento | Método | Hipótese | Resultado |
|------------|--------|----------|-----------|
| Pod Kill | PodChaos (Chaos Mesh) | Recuperação < 30s | ✅ ~1s (imagem em cache) |
| Network Latency | NetworkChaos | Sem erros em cascata com 200ms delay | ✅ HTTP 200 mantido |
| CPU Stress | StressChaos | HPA escala > 70% CPU | ✅ 2 → 6 réplicas em ~2min |

Compare os tipos de experimentos:

| Conceito | StreamFlix (open source) |
|-------------------|--------------------------|
| Kill de instância | PodChaos: mata pod |
| Injeção de latência | NetworkChaos: injeta delay |
| Stress test controlado | StressChaos: CPU/memory stress |
| Suite completa | Chaos Mesh: todas as primitivas em um tool |

---

## Health Check (antes de avançar para Tutorial 07)

```bash
echo "=== HEALTH CHECK — Tutorial 06 ==="

echo -e "\n[1/4] Chaos Mesh pods (todos Running):"
NOT_RUNNING=$(kubectl get pods -n chaos-mesh --no-headers | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo "  ✅ Todos os pods Running"
else
  echo "  ❌ $NOT_RUNNING pods com problema:"
  kubectl get pods -n chaos-mesh | grep -v Running | grep -v NAME
fi
echo ""

echo "[2/4] CRDs do Chaos Mesh:"
CRD_COUNT=$(kubectl get crd | grep chaos-mesh | wc -l)
echo "  $CRD_COUNT CRDs instalados"
if [ "$CRD_COUNT" -ge 5 ]; then
  echo "  ✅ CRDs OK"
else
  echo "  ❌ Menos de 5 CRDs — reinstale o Chaos Mesh"
fi
echo ""

echo "[3/4] Controller Manager (exatamente 1 réplica):"
CM_COUNT=$(kubectl get pods -n chaos-mesh -l app.kubernetes.io/component=controller-manager --no-headers | wc -l)
if [ "$CM_COUNT" -eq 1 ]; then
  echo "  ✅ 1 réplica (correto para Minikube)"
else
  echo "  ❌ $CM_COUNT réplicas (deveria ser 1)"
fi
echo ""

echo "[4/4] Chaos Daemon (1 por nó = 3):"
CD_COUNT=$(kubectl get pods -n chaos-mesh -l app.kubernetes.io/component=chaos-daemon --no-headers | wc -l)
if [ "$CD_COUNT" -eq 3 ]; then
  echo "  ✅ 3 daemons (1 por nó)"
else
  echo "  ❌ $CD_COUNT daemons (esperava 3)"
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| controller-manager CrashLoopBackOff `leader election lost` | 3 réplicas competindo + RAM insuficiente (**P4**) | `--set controllerManager.replicaCount=1` + `--memory=4096` |
| chaos-daemon CrashLoopBackOff `cannot find container runtime` | Runtime ou socket path incorreto | `--set chaosDaemon.runtime=containerd --set chaosDaemon.socketPath=/run/containerd/containerd.sock` |
| PodChaos não mata o pod | Selector labels incorretas | `kubectl get pods -n production --show-labels` e confirme que `app=content-api` existe |
| NetworkChaos não injeta latência | chaos-daemon não tem acesso ao namespace do pod | Verifique se chaos-daemon está rodando no mesmo nó do pod alvo |
| StressChaos não gera CPU | Container com limits muito baixos | Verifique `resources.limits.cpu` no deployment. O StressChaos respeita cgroups limits |
| Dashboard não abre | Service tipo ClusterIP | Use `kubectl port-forward svc/chaos-dashboard -n chaos-mesh 2333:2333` |
| `unknown field "spec.duration"` | Versão antiga do Chaos Mesh | Atualize: `helm repo update && helm upgrade chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh ...` |
| Cluster instável após experiments | RAM esgotada (usando 2GB?) | **Obrigatório:** `--memory=4096` por nó. Recrie o cluster se necessário |

---

## Conceitos-chave

- **Chaos Engineering:** disciplina de experimentar em sistemas distribuídos para construir confiança na resiliência
- **Steady state:** define o comportamento normal (baseline) antes do experimento
- **Blast radius:** escopo controlado do experimento — comece pequeno
- **Game Day:** evento planejado para executar múltiplos experiments (Tutorial 09)
- **Chaos Mesh:** ferramenta CNCF que injeta falhas via CRDs
- Sempre tenha hipótese + métrica + rollback plan antes de executar qualquer experimento

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Crie um experimento de chaos que mata 50% dos pods de todos os serviços simultaneamente`
- `Crie um novo runbook para o cenário de network latency no recommendation-api`
- `O chaos-controller-manager está em CrashLoopBackOff. Diagnostique e corrija`
- `Monte um experimento de IOChaos que simula disco lento no player-api`
- `Qual o impacto esperado do chaos-cpu-stress.yaml nos SLOs do content-api?`

---

**Anterior:** [Tutorial 05 — SLOs com Sloth](tutorial-05-slos-sloth.md)
**Próximo:** [Tutorial 07 — GitOps com ArgoCD](tutorial-07-argocd.md)
