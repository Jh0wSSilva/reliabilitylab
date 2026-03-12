# Modelo de SLO/SLI — ReliabilityLab

## Introdução

Este documento define o modelo de **confiabilidade** do ReliabilityLab baseado em práticas de
**Site Reliability Engineering (SRE)** do Google. O objetivo é medir, monitorar e garantir a
qualidade do serviço usando indicadores e objetivos concretos.

---

## Conceitos Fundamentais

### SLI — Service Level Indicator

**SLI** é uma métrica quantitativa que mede um aspecto específico do nível de serviço.

> "O SLI responde: como o serviço está performando agora?"

Exemplos de SLIs:
- **Taxa de sucesso de requisições** — proporção de respostas HTTP 2xx/3xx
- **Latência** — tempo para responder a uma requisição (p50, p95, p99)
- **Disponibilidade** — proporção do tempo em que o serviço está acessível
- **Taxa de erros** — proporção de respostas HTTP 5xx

Fórmula genérica:
```
SLI = (eventos bons / eventos totais) × 100%
```

### SLO — Service Level Objective

**SLO** é o **objetivo alvo** para um SLI. Define qual nível de confiabilidade é aceitável.

> "O SLO responde: qual nível de confiabilidade queremos entregar?"

Exemplo:
- "99.9% das requisições devem retornar com sucesso em um período de 30 dias"
- "95% das requisições devem ter latência abaixo de 500ms"

### SLA — Service Level Agreement

**SLA** é um contrato formal (geralmente com penalidades) baseado nos SLOs.

> Em um ambiente de aprendizado local, não temos SLAs reais, mas praticamos os conceitos.

### Error Budget — Orçamento de Erros

O **Error Budget** é a margem de falha permitida pelo SLO.

```
Error Budget = 100% - SLO
```

Exemplo:
- SLO = 99.9% → Error Budget = 0.1%
- Em 30 dias (43.200 minutos): 43.200 × 0.001 = **43,2 minutos** de indisponibilidade permitidos

O Error Budget é consumido a cada falha. Quando o budget se esgota, a prioridade muda de
features para confiabilidade.

---

## SLIs Definidos para o site-kubectl

### SLI 1: Disponibilidade (Availability)

```
SLI = (requisições com status < 500) / (total de requisições) × 100%
```

**Query Prometheus:**
```promql
# Taxa de sucesso nos últimos 30 minutos
sum(rate(http_requests_total{namespace="reliabilitylab",status!~"5.."}[30m]))
/
sum(rate(http_requests_total{namespace="reliabilitylab"}[30m]))
```

**Métricas alternativas (infraestrutura):**
```promql
# Disponibilidade baseada em pods
kube_deployment_status_replicas_available{deployment="site-kubectl"}
/
kube_deployment_spec_replicas{deployment="site-kubectl"}
```

### SLI 2: Latência (Latency)

```
SLI = (requisições com latência < threshold) / (total de requisições) × 100%
```

**Query Prometheus:**
```promql
# Percentil 95 de latência
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{namespace="reliabilitylab"}[5m])) by (le)
)

# Percentil 99 de latência
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{namespace="reliabilitylab"}[5m])) by (le)
)
```

### SLI 3: Taxa de Erros (Error Rate)

```
SLI = (requisições com status >= 500) / (total de requisições) × 100%
```

**Query Prometheus:**
```promql
sum(rate(http_requests_total{namespace="reliabilitylab",status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="reliabilitylab"}[5m]))
```

### SLI 4: Throughput

```
SLI = requisições por segundo processadas com sucesso
```

**Query Prometheus:**
```promql
sum(rate(http_requests_total{namespace="reliabilitylab",status!~"5.."}[5m]))
```

---

## SLOs Definidos

| SLI | SLO | Janela | Error Budget |
|-----|-----|--------|-------------|
| Disponibilidade | **99.9%** | 30 dias | 43,2 min/mês |
| Latência (p95) | **< 500ms** | 30 dias | 5% das requisições podem exceder |
| Latência (p99) | **< 1000ms** | 30 dias | 1% das requisições podem exceder |
| Taxa de Erros | **< 0.1%** | 30 dias | 0.1% de respostas 5xx permitidas |

---

## Error Budget — Detalhamento

### Cálculo

Para um SLO de 99.9% em 30 dias:
```
Total de minutos no mês   = 30 × 24 × 60 = 43.200 min
Error Budget              = 43.200 × (1 - 0.999) = 43,2 min
```

### Política de Error Budget

| Budget Restante | Ação |
|----------------|------|
| > 50% | Desenvolvimento normal, liberar features |
| 25% - 50% | Cautela: revisar deploys, aumentar testes |
| 10% - 25% | Alerta: pausar features arriscadas, foco em estabilidade |
| < 10% | Congelamento: apenas correções de confiabilidade |
| 0% (esgotado) | Parar deploys até o budget ser restaurado |

### Burn Rate — Taxa de Queima

O **Burn Rate** mede a velocidade com que o Error Budget está sendo consumido.

```
Burn Rate = taxa de erros atual / taxa de erros do SLO
```

| Burn Rate | Significado |
|-----------|-------------|
| 1x | Consumindo o budget no ritmo esperado |
| 2x | Consumindo 2x mais rápido → budget esgota em 15 dias |
| 10x | Consumindo 10x mais rápido → budget esgota em 3 dias |
| 14.4x | Budget esgota em 1 hora (alerta crítico) |

**Query Prometheus para Burn Rate:**
```promql
# Burn rate em janela de 1h
(
  1 - (
    sum(rate(http_requests_total{namespace="reliabilitylab",status!~"5.."}[1h]))
    /
    sum(rate(http_requests_total{namespace="reliabilitylab"}[1h]))
  )
) / (1 - 0.999)
```

---

## Como Monitorar SLOs

### No Grafana

Os dashboards de SLO (importados via ConfigMap) mostram:
1. **Compliance atual** — SLI atual vs SLO target
2. **Error Budget restante** — percentual e minutos restantes
3. **Burn Rate** — velocidade de consumo do budget
4. **Tendência** — projeção de quando o budget vai esgotar

### No Prometheus (Alertas)

Alertas configurados em `observability/prometheus/alerts.yaml`:
- `SLOBurnRateCritical` — burn rate > 14.4x (budget esgota em 1h)
- `SLOBurnRateHigh` — burn rate > 6x (budget esgota em 3 dias)
- `SLOBurnRateWarning` — burn rate > 2x (budget esgota em 15 dias)

### Ciclo de Melhoria Contínua

```
Definir SLOs → Monitorar SLIs → Alertar sobre violações →
Investigar causa → Corrigir → Atualizar Error Budget → Repetir
```

---

## Referências

- [Google SRE Book — Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook — Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- [Burn Rate Alerting — Google SRE](https://sre.google/workbook/alerting-on-slos/)
