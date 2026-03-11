# ADR-003 — Alertas Multi-Window Burn Rate

- **Status:** Aceito
- **Data:** 2026-03-10
- **Decisores:** @Jh0wSSilva

## Contexto e Problema

O ReliabilityLab precisa de alertas que detectem degradação de serviço de forma precisa — sem alertas falsos e sem perder incidentes reais. O padrão do kube-prometheus-stack gera alertas baseados em thresholds simples (ex: "error rate > 1%"), que sofrem de dois problemas:

1. **Alertas falsos:** um spike de 2 segundos dispara alerta mesmo sem impacto real no SLO
2. **Alertas perdidos:** degradação lenta (0.5% de erro contínuo) não dispara threshold mas consome error budget gradualmente

## Alternativas Consideradas

### Opção 1 — Threshold simples

```promql
# Alerta quando error rate > 1% por 5 minutos
rate(http_request_duration_seconds_count{status=~"5.."}[5m]) / rate(http_request_duration_seconds_count[5m]) > 0.01
```

- **Prós:** Simples de entender e implementar
- **Contras:** Não tem relação com o SLO ou error budget. Um spike de 2% por 5 minutos pode não impactar o budget mensal. Um gotejamento de 0.3% por 3 dias pode consumir 50% do budget sem disparar alerta.
- **Veredicto:** Descartada — desconectada do SLO

### Opção 2 — Error budget remaining

```promql
# Alerta quando budget < 20%
1 - (sum_over_time(errors[30d]) / (total_requests * (1 - objective))) < 0.2
```

- **Prós:** Diretamente ligado ao SLO
- **Contras:** Sem urgência — detecta apenas quando o dano já está feito. Não diferencia entre "queimamos budget lentamente ao longo do mês" e "estamos queimando budget 14x mais rápido que o normal agora".
- **Veredicto:** Descartada — reativa, não proativa

### Opção 3 — Multi-window burn rate (escolhida)

Fórmula:

```
burn_rate = (error_rate_atual) / (error_rate_sustentável_pelo_SLO)
```

Para um SLO de 99.9% (error budget = 0.1%):
- Error rate sustentável = 0.001 (0.1% por 30 dias)
- Se error rate atual = 0.0144 → burn rate = 14.4x

Janelas combinadas (longa + curta) reduzem falsos positivos:

| Janela Longa | Janela Curta | Burn Rate | Severidade | Significado |
|-------------|-------------|-----------|------------|-------------|
| 1h | 5m | 14.4x | PAGE | Budget acaba em ~3h se continuar |
| 6h | 30m | 6x | PAGE | Degradação significativa em curso |
| 1d | 2h | 3x | TICKET | Erosão detectável — investigar |
| 3d | 6h | 1x | TICKET | Erosão lenta — planejar fix |

A janela curta confirma que o problema é **recente** (não residual). A janela longa confirma que o problema é **sustentado** (não spike).

## Decisão

Adotar **multi-window burn rate** como modelo de alerta para todos os SLOs. O Sloth (ADR-001) gera as PrometheusRules automaticamente a partir dos CRDs.

Os alertas gerados são:
- `SlothErrorBudgetBurnRateCritical` (PAGE) → PagerDuty/on-call
- `SlothErrorBudgetBurnRateWarning` (TICKET) → Jira/investigação

## Consequências

### Positivas

- Alertas diretamente ligados ao error budget — contexto claro para o on-call
- Elimina alertas falsos de spikes curtos (janela curta valida que o problema é real)
- Detecta degradação lenta que threshold simples perderia
- Modelo validado em produção em escala — documentado no SRE Workbook cap. 5

### Negativas

- Complexidade maior que threshold simples — requer entendimento de burn rate para triagem eficaz
- 8 PrometheusRules geradas por SLO (4 janelas × 2 severidades) — 24 rules para nossos 3 serviços
- Debug requer entendimento da fórmula — queries PromQL mais longas

## Referências

- [SRE Workbook — Chapter 5: Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Sloth — How it works](https://sloth.dev/introduction/concepts/)
- ADR-001 — Sloth como SLO Engine
