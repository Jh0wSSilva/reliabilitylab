# GameDay #01 — Pod Kill: Validação de Self-Healing

**Data:** 2025-01-15  
**Facilitador:** SRE Team  
**Duração:** 2 horas  
**Ambiente:** Minikube 3 nodes (v1.32.0)

---

## Cenário

Validar se o Kubernetes consegue recuperar automaticamente pods terminados em produção, sem impacto perceptível para o usuário final. O teste também valida se o HPA reage corretamente quando os pods restantes atingem alta utilização de CPU.

### Escopo

| Serviço | Replicas | Namespace | Experimento |
|---------|----------|-----------|-------------|
| content-api | 2 | production | PodChaos (pod-kill) |
| content-api | 2 | production | StressChaos (cpu-stress) |
| content-api | 2 | production | NetworkChaos (network-latency) |

### Fora do escopo

- Falha de nó (node drain)
- Falha de storage (PV/PVC)
- Falha de DNS

---

## Hipóteses

| # | Hipótese | Métrica de Validação |
|---|----------|---------------------|
| H1 | Pod kill: recovery em menos de 5s sem erro visível | Tempo entre kill e pod Ready |
| H2 | CPU stress: HPA escala acima de 70% CPU | Número de replicas durante stress |
| H3 | Network latency: sem falha em cascata | Taxa de erro HTTP das dependências |

---

## Setup

### Pré-requisitos verificados

```bash
# Cluster healthy
kubectl get nodes
# NAME                    STATUS   ROLES           AGE   VERSION
# reliabilitylab          Ready    control-plane   2d    v1.32.0
# reliabilitylab-m02      Ready    <none>          2d    v1.32.0
# reliabilitylab-m03      Ready    <none>          2d    v1.32.0

# Chaos Mesh operacional
kubectl get pods -n chaos-mesh
# chaos-controller-manager-xxx   Running
# chaos-daemon-xxx               Running (em cada nó)

# Prometheus coletando métricas
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Validado: targets content-api UP

# Baseline de replicas
kubectl get hpa -n production
# content-api   Deployment/content-api   12%/70%   2     10    2
```

### Dashboards abertos

- Grafana: Kubernetes / Compute Resources / Namespace (Pods) — gnetId 15661
- Prometheus: Alerts page (verificar se não há alertas pré-existentes)
- Terminal: `kubectl get pods -n production -w` (watch mode)

---

## Execução

### Experimento 1: Pod Kill

**Início:** 14:05  
**Chaos Mesh manifest:** `platform/chaos/experiments/chaos-pod-kill.yaml`

```bash
kubectl apply -f platform/chaos/experiments/chaos-pod-kill.yaml
```

**Observação em tempo real:**

```
14:05:01 — PodChaos criado, scheduler seleciona 1 pod (content-api-7d8f9b6c4-x2kp9)
14:05:02 — Pod terminado (Status: Terminating)
14:05:03 — ReplicaSet detecta pod faltante, cria content-api-7d8f9b6c4-m7hn3
14:05:04 — Novo pod em status ContainerCreating (imagem podinfo já em cache)
14:05:05 — Pod Ready (passou readiness probe)
```

**Tempo de recovery: ~1 segundo** (imagem cached no nó)

**Métricas Prometheus:**

```promql
# Pods disponíveis (caiu para 1, voltou a 2)
kube_deployment_status_replicas_available{deployment="content-api", namespace="production"}

# Nenhum erro 5xx detectado no período
rate(http_request_duration_seconds_count{namespace="production", status=~"5.."}[1m]) == 0
```

### Experimento 2: CPU Stress

**Início:** 14:25  
**Chaos Mesh manifest:** `platform/chaos/experiments/chaos-cpu-stress.yaml`

```bash
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

**Observação em tempo real:**

```
14:25:00 — StressChaos aplicado, 2 workers consumindo CPU em content-api pods
14:25:30 — HPA detecta CPU acima de 70% (target atingido: 85%)
14:26:00 — HPA escala para 3 replicas
14:26:30 — CPU ainda alta, HPA escala para 4 replicas
14:27:00 — Escalonamento contínuo: 5 replicas
14:27:30 — Pico: 6 replicas
14:30:00 — StressChaos expirado (duration: 5m)
14:32:00 — CPU normaliza, HPA começa cooldown
14:37:00 — HPA reduz para 2 replicas (cooldown de 5min)
```

**Tempo para escalar: ~2 minutos até 6 replicas**

**Métricas HPA:**

```promql
# Replicas ao longo do tempo
kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="content-api"}

# CPU utilization durante stress
rate(container_cpu_usage_seconds_total{namespace="production", pod=~"content-api.*"}[1m])
```

### Experimento 3: Network Latency

**Início:** 14:45  
**Chaos Mesh manifest:** `platform/chaos/experiments/chaos-network-latency.yaml`

```bash
kubectl apply -f platform/chaos/experiments/chaos-network-latency.yaml
```

**Observação em tempo real:**

```
14:45:00 — NetworkChaos aplicado, 200ms de latência adicionada ao content-api
14:45:10 — Latência visível no Grafana (p99 sobe de ~5ms para ~205ms)
14:45:30 — Serviços dependentes (recommendation-api, player-api) continuam respondendo
14:46:00 — Nenhum timeout observado (threshold padrão é 30s)
14:50:00 — NetworkChaos expirado (duration: 5m)
14:50:05 — Latência volta ao normal (~5ms)
```

**Resultado: Sem falha em cascata**

---

## Resultados

| # | Hipótese | Resultado | Status |
|---|----------|-----------|--------|
| H1 | Recovery < 5s | ~1s (imagem cached) | ✅ Confirmada |
| H2 | HPA escala acima de 70% | 2→6 replicas em ~2min | ✅ Confirmada |
| H3 | Sem falha em cascata | 0 erros em dependências | ✅ Confirmada |

### Métricas consolidadas

| Métrica | Antes | Durante | Depois |
|---------|-------|---------|--------|
| Replicas content-api | 2 | 6 (pico) | 2 |
| Latência p99 | ~5ms | ~205ms | ~5ms |
| Taxa de erro 5xx | 0% | 0% | 0% |
| Error budget consumido | 0% | 0% | 0% |

---

## Surpresas

### 1. Recovery mais rápido que o esperado

O recovery de ~1s foi possível porque `podinfo` já estava em cache nos nós. Em produção real com imagens privadas maiores, o pull poderia levar 10-30s. **Isso mascara um risco real.**

### 2. HPA cooldown delay

Após o stress, o HPA levou 5 minutos para reduzir replicas (comportamento padrão `--horizontal-pod-autoscaler-downscale-stabilization=5m`). Isso significa custo extra de recursos por 5 minutos após cada spike.

### 3. Sem PodDisruptionBudget configurado

O pod kill removeu 1 de 2 replicas (50% de capacidade). Sem PDB, um rollout mal configurado poderia derrubar todas as replicas simultaneamente.

---

## Action Items

| # | Ação | Prioridade | Responsável | Status |
|---|------|------------|-------------|--------|
| 1 | Criar PodDisruptionBudget (`minAvailable: 1`) para cada serviço | Alta | SRE Team | Pendente |
| 2 | Adicionar `initialDelaySeconds` na readiness probe | Média | Dev Team | Pendente |
| 3 | Testar com `imagePullPolicy: Always` para simular cold pull | Baixa | SRE Team | Pendente |
| 4 | Configurar `preStop` hook com `sleep 5` para graceful shutdown | Média | SRE Team | Pendente |
| 5 | Documentar comportamento do HPA cooldown no runbook | Baixa | SRE Team | Pendente |

---

## Conclusão

O cluster Minikube demonstrou capacidade de self-healing eficiente para os cenários testados. O Kubernetes reagiu conforme esperado em todos os 3 experimentos, confirmando que:

1. **ReplicaSet** garante disponibilidade mínima durante falhas individuais de pod
2. **HPA** responde a picos de CPU dentro de um intervalo aceitável (~2min)
3. **Isolamento de rede** (latência) não causa falhas em cascata nos serviços dependentes

Os action items identificados (PDB, readiness delay, graceful shutdown) são melhorias incrementais que aumentariam a resiliência para cenários mais agressivos.

### Próximo GameDay sugerido

- **GameDay #02:** Node drain — drenar um nó worker e validar rescheduling de pods
- **GameDay #03:** Falha de Prometheus — validar se alertas disparam corretamente quando o próprio Prometheus reinicia
