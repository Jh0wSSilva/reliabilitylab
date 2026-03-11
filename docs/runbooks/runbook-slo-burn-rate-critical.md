# Runbook — SLO Error Budget Burn Rate Critical

## Alerta

```
Alert: SlothErrorBudgetBurnRateCritical
Severity: critical (PAGE)
Labels:
  sloth_service: <service>
  sloth_slo: <slo_name>
```

## Impacto no Usuário

O serviço está consumindo error budget a uma taxa insustentável. Se mantida, o budget mensal será esgotado em poucas horas. Usuários estão experimentando erros ou degradação significativa de performance.

## Diagnóstico (< 2 minutos)

### 1. Identificar qual serviço está afetado

```bash
# Ver alertas firing no Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
```

No Prometheus UI (`http://localhost:9090/alerts`), procure o alerta `SlothErrorBudgetBurnRateCritical` e identifique o label `sloth_service`.

### 2. Verificar burn rate atual

```promql
# Burn rate na janela de 1h (PAGE threshold: 14.4x)
slo:sli_error:ratio_rate1h{sloth_service="content-api"}
  /
slo:objective:ratio{sloth_service="content-api"}
```

### 3. Verificar error budget restante

```promql
# Budget restante (0 a 1, onde 1 = 100% disponível)
slo:error_budget:ratio{sloth_service="content-api"}
```

### 4. Verificar error rate atual

```promql
# Taxa de erro nos últimos 5 minutos
sum(rate(http_request_duration_seconds_count{job="content-api", status=~"5.."}[5m]))
  /
sum(rate(http_request_duration_seconds_count{job="content-api"}[5m]))
```

### 5. Verificar estado dos pods

```bash
kubectl get pods -n production -l app=content-api
kubectl describe pods -n production -l app=content-api | grep -A5 "State:"
kubectl logs -n production -l app=content-api --tail=50 --all-containers
```

### 6. Verificar eventos recentes

```bash
kubectl get events -n production --sort-by='.metadata.creationTimestamp' | tail -20
```

## Mitigação Imediata (< 5 minutos)

### Se causado por deploy recente

```bash
# Verificar histórico de rollout
kubectl rollout history deployment/content-api -n production

# Rollback para revisão anterior
kubectl rollout undo deployment/content-api -n production

# Verificar se error rate estabilizou
kubectl rollout status deployment/content-api -n production
```

### Se causado por pods em CrashLoopBackOff

```bash
# Restart dos pods afetados
kubectl rollout restart deployment/content-api -n production
```

### Se causado por sobrecarga de recursos

```bash
# Verificar se HPA está no limite
kubectl get hpa -n production

# Scale manual se HPA estiver no maxReplicas
kubectl scale deployment/content-api -n production --replicas=8
```

## Mitigação Definitiva

1. Identificar root cause nos logs e métricas
2. Corrigir o código/configuração que está causando erros
3. Abrir PR com fix, passar pelo pipeline de validação
4. Monitorar burn rate por pelo menos 1h após deploy do fix
5. Documentar no postmortem se error budget foi significativamente impactado

## Quando Escalar

- **Senior on-call:** quando burn rate > 20x e causa não identificada em 10 minutos
- **Service owner:** quando rollback não resolve e fix requer mudança de código
- **Incident commander:** quando múltiplos serviços estão afetados simultaneamente (possível causa sistêmica)

## Referências

- [ADR-003 — Burn Rate Alerts](../adr/ADR-003-burn-rate-alerts.md)
- [Error Budget Policy](../slo/error-budget-policy.md)
- [SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
