# Tutorial 10 — Observando Falhas e Recuperação

## Objetivo

Combinar as ferramentas de **observabilidade**, **chaos engineering** e **load testing** para observar falhas em tempo real e medir a capacidade de recuperação do sistema.

## Conceitos

- **MTTR (Mean Time to Recovery)**: tempo médio de recuperação após uma falha
- **MTTD (Mean Time to Detect)**: tempo médio para detectar um problema
- **Self-healing**: capacidade do sistema se recuperar automaticamente
- **Error Budget**: quanto de indisponibilidade é aceitável
- **Degradação graciosa (Graceful Degradation)**: continuar funcionando com capacidade reduzida

## Pré-requisitos

- Stack de observabilidade instalada (Tutorial 05)
- Aplicação rodando com HPA (Tutorial 06)
- k6 instalado (Tutorial 09)

## Cenário 1: Falha de Pod Sob Carga

### Setup (3 terminais)

**Terminal 1 — Observação:**
```bash
kubectl get pods -n reliabilitylab -w
```

**Terminal 2 — Carga:**
```bash
bash scripts/run-load-test.sh load
```

**Terminal 3 — Chaos (aguarde 30s após iniciar a carga):**
```bash
kubectl delete pod -n reliabilitylab \
    $(kubectl get pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].metadata.name}') \
    --grace-period=0 --force
```

### O que observar

1. **Terminal 1**: pod sendo terminado → novo pod criando → pod ficando Ready
2. **Terminal 2**: possível aumento de erros momentâneo → volta ao normal
3. **Grafana**: spike de latência, queda temporária de disponibilidade

### Perguntas para responder
- Quanto tempo levou para o novo pod ficar Ready? (MTTR)
- Houve erros durante a transição?
- O serviço ficou totalmente indisponível?

## Cenário 2: Stress de CPU + HPA

### Setup (3 terminais)

**Terminal 1 — HPA:**
```bash
kubectl get hpa -n reliabilitylab -w
```

**Terminal 2 — Carga simulando usuários:**
```bash
bash scripts/run-load-test.sh stress
```

**Terminal 3 — Stress de CPU (aguarde 60s):**
```bash
kubectl apply -f chaos/pod-cpu-stress.yaml
```

### O que observar

1. **Terminal 1**: HPA aumentando réplicas
2. **Terminal 2**: latência aumentando → estabilizando com mais pods
3. **Grafana**:
   - CPU subindo
   - Réplicas aumentando
   - Latência estabilizando

### Limpeza
```bash
kubectl delete -f chaos/pod-cpu-stress.yaml --ignore-not-found
```

## Cenário 3: Simulando Degradação

### Reduzir para 1 réplica

```bash
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=1
```

### Criar carga e deletar o único pod

**Terminal 1:**
```bash
# Loop contínuo de verificação
while true; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://site-kubectl.local/api/health 2>/dev/null || echo "000")
    echo "$(date '+%H:%M:%S') - Status: $STATUS"
    sleep 1
done
```

**Terminal 2:**
```bash
kubectl delete pod -n reliabilitylab \
    $(kubectl get pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].metadata.name}') \
    --grace-period=0 --force
```

### O que observar
- Status 000 ou 503 durante a indisponibilidade
- Tempo até voltar para Status 200

### Restaurar
```bash
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=2
```

## Dashboard de Observação

No Grafana, crie ou use os dashboards para monitorar:

### Métricas Essenciais

| Métrica | Query PromQL | Significado |
|---------|-------------|-------------|
| Pods disponíveis | `kube_deployment_status_replicas_available{deployment="site-kubectl"}` | Pods respondendo |
| Restarts | `kube_pod_container_status_restarts_total{namespace="reliabilitylab"}` | Reinícios (indica problemas) |
| CPU | `rate(container_cpu_usage_seconds_total{namespace="reliabilitylab",container="site-kubectl"}[5m])` | Consumo de CPU |
| Memória | `container_memory_working_set_bytes{namespace="reliabilitylab",container="site-kubectl"}` | Consumo de memória |
| HPA réplicas | `kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="site-kubectl"}` | Réplicas atuais |

### Logs no Loki

```logql
# Erros da aplicação
{namespace="reliabilitylab"} |= "error"

# Todos os logs em tempo real
{namespace="reliabilitylab", app_kubernetes_io_name="site-kubectl"}

# Eventos do Kubernetes
{job="kube-events"} |= "reliabilitylab"
```

## Tabela de Recuperação

Documente o MTTR de cada cenário:

| Cenário | MTTR Esperado | Seu Resultado |
|---------|--------------|---------------|
| Pod deletado (2 réplicas) | ~0s (sem impacto) | |
| Pod deletado (1 réplica) | 15-30s | |
| CPU stress + HPA | 30-60s para escalar | |
| OOMKill + restart | 10-20s | |

## Lições Aprendidas

1. **Réplicas importam**: com 2+ réplicas, a deleção de um pod não causa downtime
2. **HPA protege contra carga**: escala automaticamente quando CPU/memória aumentam
3. **PDB garante mínimo**: mesmo durante disruptions, ao menos 1 pod continua ativo
4. **Observabilidade é essencial**: sem métricas e logs, não sabemos o que está acontecendo
5. **Probes são críticos**: readinessProbe garante que tráfego só vai para pods prontos

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Grafana não mostra métricas | Verifique ServiceMonitor e que Prometheus está coletando |
| Onde ver eventos do cluster | `kubectl get events -A --sort-by=.lastTimestamp` |
| Status 000 persistente | Verifique se o Ingress Controller está running |

## Próximo Tutorial

[11 — GitOps com ArgoCD](11-gitops-argocd.md)
