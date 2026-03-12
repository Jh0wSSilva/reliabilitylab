# Tutorial 13 — SLOs e Error Budget

## Objetivo

Neste tutorial você vai aprender a:
- Definir **SLIs** (Service Level Indicators) para medir a qualidade do serviço
- Configurar **SLOs** (Service Level Objectives) com targets realistas
- Calcular e monitorar o **Error Budget** (orçamento de erros)
- Entender o conceito de **Burn Rate** para alertas proativos

## Pré-requisitos

- Tutorial 01 a 04 concluídos (cluster + aplicação + Prometheus/Grafana)
- Cluster Kubernetes rodando com o site-kubectl deployed
- Prometheus e Grafana acessíveis

## Conceitos

### O que são SLIs, SLOs e Error Budget?

**SLI (Service Level Indicator)** é uma métrica que mede a qualidade do serviço:
- Taxa de sucesso das requisições
- Latência (tempo de resposta)
- Disponibilidade

**SLO (Service Level Objective)** é o alvo que definimos para cada SLI:
- "99.9% das requisições devem retornar com sucesso"
- "95% das requisições devem ter latência < 500ms"

**Error Budget** é a margem de falha permitida:
- SLO = 99.9% → Error Budget = 0.1%
- Em 30 dias: 43.200 min × 0.001 = **43,2 minutos** de indisponibilidade

### Burn Rate

O Burn Rate mede a velocidade de consumo do Error Budget:
- **1x** = consumo normal
- **14.4x** = budget esgota em 1 hora → alerta crítico
- **6x** = budget esgota em 6 horas → alerta alto

## Passo a Passo

### Passo 1: Entender o modelo de SLO

Leia o documento de referência:

```bash
cat docs/sre/slo-model.md
```

Este documento define todos os SLIs, SLOs e a política de Error Budget do ReliabilityLab.

### Passo 2: Verificar métricas disponíveis no Prometheus

Acesse o Prometheus:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Abra http://localhost:9090 e execute as queries de SLI:

**Taxa de sucesso (disponibilidade):**
```promql
sum(rate(http_requests_total{namespace="reliabilitylab",status!~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="reliabilitylab"}[5m]))
```

**Latência P95:**
```promql
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{namespace="reliabilitylab"}[5m])) by (le)
)
```

**Burn Rate:**
```promql
(
  1 - (
    sum(rate(http_requests_total{namespace="reliabilitylab",status!~"5.."}[1h]))
    /
    sum(rate(http_requests_total{namespace="reliabilitylab"}[1h]))
  )
) / (1 - 0.999)
```

### Passo 3: Importar o dashboard SLO no Grafana

O dashboard SLO é instalado automaticamente via ConfigMap:

```bash
kubectl apply -f observability/grafana/slo-dashboard-configmap.yaml
```

Acesse o Grafana:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Abra http://localhost:3000 (admin/admin123) e procure o dashboard **"Site Kubectl — SLO Dashboard"**.

O dashboard mostra:
- **Gauge de disponibilidade** — comparando com o target de 99.9%
- **Error Budget consumido** — percentual do budget utilizado
- **Burn Rate** — velocidade de consumo em múltiplas janelas
- **Latência por percentis** — P50, P90, P95, P99

### Passo 4: Simular consumo de Error Budget

Gere erros para consumir o Error Budget:

```bash
# Gerar carga com k6 que causa erros
k6 run -e BASE_URL=http://site-kubectl.local load-testing/stress-test.js
```

Enquanto a carga roda, observe no dashboard:
1. O gauge de disponibilidade cair
2. O Error Budget consumido subir
3. O Burn Rate aumentar

### Passo 5: Entender a política de Error Budget

A política define as ações baseadas no budget restante:

| Budget Restante | Ação |
|----------------|------|
| > 50% | Desenvolvimento normal |
| 25% - 50% | Cautela: revisar deploys |
| 10% - 25% | Alerta: foco em estabilidade |
| < 10% | Congelamento: apenas correções |
| 0% | Parar deploys |

## Verificação

Confirme que você consegue:

1. Executar queries de SLI no Prometheus
2. Visualizar o dashboard SLO no Grafana
3. Entender o Burn Rate e como ele indica a urgência
4. Explicar a política de Error Budget

## Próximo Tutorial

No [Tutorial 14](tutorial-14-prometheus-alerting.md) vamos configurar alertas no Prometheus
baseados nos SLOs definidos aqui.
