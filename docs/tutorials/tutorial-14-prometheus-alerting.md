# Tutorial 14 — Alertas no Prometheus

## Objetivo

Neste tutorial você vai aprender a:
- Criar regras de alerta usando **PrometheusRule** (CRD do kube-prometheus-stack)
- Implementar alertas de **burn rate multi-window** baseados nos SLOs
- Configurar alertas de infraestrutura (pods, CPU, memória)
- Verificar alertas no Prometheus UI

## Pré-requisitos

- Tutorial 13 concluído (SLOs e Error Budget)
- kube-prometheus-stack instalado no cluster
- Prometheus acessível via port-forward

## Conceitos

### PrometheusRule CRD

O kube-prometheus-stack usa o CRD `PrometheusRule` para definir regras de alerta.
O Prometheus detecta e carrega automaticamente qualquer PrometheusRule no cluster.

### Alertas Multi-Window Burn Rate

Em vez de alertar apenas em thresholds simples (ex: error rate > 1%), usamos
**burn rate em múltiplas janelas** — a abordagem recomendada pelo Google SRE:

| Janela | Burn Rate | Significado |
|--------|-----------|-------------|
| 5m + 1h | > 14.4x | Budget esgota em ~1h → **CRITICAL** |
| 30m + 6h | > 6x | Budget esgota em ~6h → **WARNING** |
| 6h | > 2x | Budget esgota em ~3d → **INFO** |

A combinação de janela curta + janela longa reduz falsos positivos.

## Passo a Passo

### Passo 1: Examinar as regras de alerta

Abra e leia o arquivo de alertas:

```bash
cat observability/prometheus/alerts.yaml
```

O arquivo define 3 grupos de alertas:

1. **reliabilitylab.slo.burn-rate** — Alertas de SLO com burn rate multi-window
2. **reliabilitylab.application** — Taxa de erros e latência
3. **reliabilitylab.infrastructure** — CrashLoop, indisponibilidade, CPU, memória

### Passo 2: Aplicar as regras no cluster

```bash
kubectl apply -f observability/prometheus/alerts.yaml
```

Verificar que a PrometheusRule foi criada:

```bash
kubectl get prometheusrules -n monitoring
```

Saída esperada:
```
NAME                      AGE
reliabilitylab-alerts     10s
```

### Passo 3: Verificar alertas no Prometheus

Acesse o Prometheus UI:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Abra http://localhost:9090/alerts e verifique que os alertas aparecem:
- `SLOBurnRateCritical`
- `SLOBurnRateHigh`
- `SLOBurnRateWarning`
- `HighErrorRate`
- `HighLatencyP95`
- `HighLatencyP99`
- `PodCrashLooping`
- `ServiceUnavailable`
- `ReplicasMismatch`
- `HighCPUUsage`
- `HighMemoryUsage`
- `PVCAlmostFull`

Todos devem estar no estado **inactive** (verde) se o serviço está saudável.

### Passo 4: Disparar um alerta (controlado)

Vamos forçar o alerta `ServiceUnavailable` escalando o deployment para 0:

```bash
# Salvar o número atual de réplicas
REPLICAS=$(kubectl get deployment site-kubectl -n reliabilitylab -o jsonpath='{.spec.replicas}')

# Escalar para 0 (causa indisponibilidade)
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=0

# Aguardar 2 minutos e verificar alertas
echo "Aguardando 2 minutos para o alerta disparar..."
sleep 120
```

No Prometheus UI, o alerta `ServiceUnavailable` deve mudar para **pending** e depois **firing**.

Restaurar:

```bash
# Restaurar réplicas
kubectl scale deployment site-kubectl -n reliabilitylab --replicas="$REPLICAS"

# Verificar recuperação
kubectl rollout status deployment/site-kubectl -n reliabilitylab
```

### Passo 5: Entender a estrutura de um alerta

Cada alerta tem:

```yaml
- alert: NomeDoAlerta
  annotations:
    summary: "Descrição curta"           # Mostrada nas notificações
    description: "Detalhes com {{ $value }}"  # Pode usar variáveis
  expr: |
    # Query PromQL que retorna > 0 quando o alerta deve disparar
  for: 5m                                # Quanto tempo a condição deve persistir
  labels:
    severity: critical|warning|info       # Severidade para roteamento
    team: sre                            # Time responsável
```

### Passo 6: Verificar regras no Prometheus

Na UI do Prometheus, acesse http://localhost:9090/rules para ver:
- Todas as regras carregadas
- Tempo de avaliação de cada regra
- Erros de avaliação (se houver)

## Verificação

Confirme que você consegue:

1. Aplicar PrometheusRules no cluster
2. Ver os alertas no Prometheus UI (/alerts)
3. Disparar e receber um alerta controlado
4. Entender a estrutura YAML de um alerta
5. Explicar por que usamos burn rate multi-window

## Próximo Tutorial

No [Tutorial 15](tutorial-15-alertmanager.md) vamos configurar o Alertmanager para
rotear alertas por severidade e enviar notificações.
