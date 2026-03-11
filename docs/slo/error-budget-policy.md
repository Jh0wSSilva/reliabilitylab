# Error Budget Policy — ReliabilityLab

> Referência: SRE Workbook — [Implementing SLOs](https://sre.google/workbook/implementing-slos/), cap. 2 e 4.

## Objetivo

Definir regras claras sobre o que acontece quando o error budget é consumido. Sem uma policy, SLOs são apenas números — com uma policy, SLOs direcionam decisões reais de engenharia.

## Serviços Cobertos

| Serviço | SLO | Error Budget (30 dias) | Dono |
|---------|-----|----------------------|------|
| content-api | 99.9% availability | 43 minutos | @Jh0wSSilva |
| recommendation-api | 99.5% availability | 3.6 horas | @Jh0wSSilva |
| player-api | 99.9% availability | 43 minutos | @Jh0wSSilva |

## Tabela de Ações por Nível de Budget

| Budget Restante | Status | Deploys | Chaos Experiments | Ação Obrigatória |
|----------------|--------|---------|------------------|-----------------|
| > 50% | 🟢 Verde | Livre — deploy a qualquer momento | Permitido — todos os tipos | Operação normal |
| 25–50% | 🟡 Amarelo | Review obrigatório antes de deploy | Apenas em horário comercial | Review de SLIs, investigar tendência de consumo |
| 10–25% | 🟠 Laranja | Freeze de features novas | Suspenso | Foco em reliability. Apenas fixes de bugs e melhorias de performance |
| < 10% | 🔴 Vermelho | Freeze total | Suspenso | Post-mortem obrigatório. Apenas hotfixes críticos |
| 0% (esgotado) | 🚨 Crítico | Freeze total + rollback se necessário | Suspenso | Incident response ativo. Notificação de stakeholders |

## Processo de Verificação

### Verificação diária (automatizado)

```promql
# Error budget restante por serviço
slo:error_budget:ratio{sloth_service=~"content-api|recommendation-api|player-api"}
```

### Verificação semanal (manual)

1. Abrir Grafana → dashboard SLO Overview
2. Verificar burn rate dos últimos 7 dias para cada serviço
3. Se algum serviço está em 🟡 ou pior → documentar causa e action items

### Verificação mensal (revisão formal)

1. Revisar todos os SLOs: o target ainda é adequado?
2. Revisar error budget consumido no mês: quanto foi por incidentes vs deploys vs chaos?
3. Ajustar SLO targets se necessário (ex: relaxar de 99.9% para 99.5% se o budget está sempre esgotado)
4. Registrar decisões em ADR se houver mudança de target

## Responsabilidades

| Papel | Responsabilidade |
|-------|-----------------|
| **SLO Owner** (service owner) | Monitorar budget do seu serviço. Decidir sobre deploys em 🟡. Liderar post-mortem em 🔴. |
| **On-call** | Responder a alertas de burn rate critical. Seguir runbooks. Escalar quando necessário. |
| **Tech Lead / Platform** | Revisar SLOs mensalmente. Aprovar mudanças de target. Garantir que a policy é seguida. |

## Definições

- **Error Budget:** quantidade de "indisponibilidade permitida" em uma janela de tempo. Para 99.9% availability em 30 dias: `30d × 24h × 60m × 0.001 = 43.2 minutos`.
- **Burn Rate:** velocidade de consumo do error budget. Burn rate 1x = budget acaba exatamente no fim da janela. Burn rate 14.4x = budget acaba em ~3 horas.
- **PAGE alert:** burn rate alto o suficiente para esgotar o budget em horas → acorda o on-call (Sloth: janelas 1h/5m com 14.4x e 6h/30m com 6x).
- **TICKET alert:** burn rate elevado mas não urgente → ticket para investigar no business hours (Sloth: janelas 1d/2h com 3x e 3d/6h com 1x).

## Exceções

- **Chaos experiments planejados:** se um GameDay consumir budget intencionalmente, o consumo é documentado no report e não aciona freeze.
- **Manutenção programada:** janelas de manutenção pré-aprovadas são excluídas do cálculo de SLO (se configurado no Sloth via `excludeRanges`).
- **Lançamentos críticos de negócio:** se uma feature precisa ir ao ar urgentemente e o budget está em 🟡, o Tech Lead pode aprovar o deploy com documentação da decisão.

## Referências

- [SRE Workbook — Error Budgets](https://sre.google/workbook/error-budget-policy/)
- [ADR-001 — Sloth como SLO Engine](../adr/ADR-001-sloth-slos.md)
- [ADR-003 — Alertas Multi-Window Burn Rate](../adr/ADR-003-burn-rate-alerts.md)
- [Runbook — SLO Burn Rate Critical](../runbooks/runbook-slo-burn-rate-critical.md)
