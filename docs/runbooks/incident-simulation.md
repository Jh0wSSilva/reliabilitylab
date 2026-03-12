# Framework de Simulação de Incidentes — ReliabilityLab

## Visão Geral

Este framework define cenários de simulação de incidentes para praticar:
- **Detecção** — Identificar o problema rapidamente
- **Diagnóstico** — Entender a causa raiz
- **Mitigação** — Restaurar o serviço
- **Comunicação** — Documentar e comunicar status
- **Postmortem** — Analisar e prevenir recorrência

> Todos os cenários são executados **localmente** no cluster Kubernetes.

---

## Cenários de Incidente

### Cenário 1: Indisponibilidade Total do Serviço

**Severidade:** SEV-1 (Crítico)  
**Trigger:** Todos os pods do site-kubectl são eliminados  
**Alerta esperado:** `ServiceUnavailable`, `SLOBurnRateCritical`

#### Execução

```bash
# Executar cenário
kubectl apply -f chaos/scenarios/total-pod-kill.yaml

# Ou via pipeline
./scripts/run-resilience-tests.sh pod-kill
```

#### Roteiro de Resposta

1. **Detecção (0-2 min)**
   - Verificar alertas no Prometheus: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`
   - Abrir Grafana SLO dashboard: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
   - Confirmar: `kubectl get pods -n reliabilitylab`

2. **Diagnóstico (2-5 min)**
   - Verificar eventos: `kubectl get events -n reliabilitylab --sort-by=.lastTimestamp`
   - Verificar logs: `kubectl logs -n reliabilitylab -l app=site-kubectl --previous`
   - Verificar deployment: `kubectl describe deployment site-kubectl -n reliabilitylab`

3. **Mitigação (5-10 min)**
   - O Kubernetes deve recriar os pods automaticamente (ReplicaSet)
   - Se não restaurar: `kubectl rollout restart deployment/site-kubectl -n reliabilitylab`
   - Verificar: `kubectl rollout status deployment/site-kubectl -n reliabilitylab`

4. **Validação (10-15 min)**
   - Confirmar pods Running: `kubectl get pods -n reliabilitylab`
   - Testar endpoint: `curl http://site-kubectl.local/api/health`
   - Verificar que alertas resolveram

---

### Cenário 2: Degradação de Latência

**Severidade:** SEV-2 (Alto)  
**Trigger:** Exaustão de CPU/memória causa throttling  
**Alerta esperado:** `HighLatencyP95`, `HighCPUUsage`, `SLOBurnRateHigh`

#### Execução

```bash
# Executar cenário
kubectl apply -f chaos/scenarios/resource-exhaustion.yaml

# Monitorar
watch kubectl top pods -n reliabilitylab
```

#### Roteiro de Resposta

1. **Detecção (0-3 min)**
   - Verificar dashboard de latência no Grafana
   - Confirmar P95 > 500ms no dashboard SLO
   - `kubectl top pods -n reliabilitylab`

2. **Diagnóstico (3-10 min)**
   - Identificar pods consumindo recursos: `kubectl top pods -n reliabilitylab --sort-by=cpu`
   - Verificar HPA: `kubectl get hpa -n reliabilitylab`
   - Verificar limits: `kubectl describe pods -n reliabilitylab -l app=site-kubectl | grep -A5 Limits`

3. **Mitigação (10-15 min)**
   - Remover fonte de stress: `kubectl delete -f chaos/scenarios/resource-exhaustion.yaml`
   - Se HPA não escalou: `kubectl scale deployment site-kubectl -n reliabilitylab --replicas=4`
   - Aguardar estabilização

4. **Validação (15-20 min)**
   - Verificar latência voltou ao normal no Grafana
   - Confirmar burn rate diminuiu
   - `kubectl top pods -n reliabilitylab`

---

### Cenário 3: Falha de Rede (Partição)

**Severidade:** SEV-1 (Crítico)  
**Trigger:** NetworkPolicy bloqueia todo tráfego  
**Alerta esperado:** `HighErrorRate`, `ServiceUnavailable`, `SLOBurnRateCritical`

#### Execução

```bash
# Executar cenário (60s de partição)
CHAOS_DURATION=60 ./scripts/run-resilience-tests.sh network

# Ou manualmente
kubectl apply -f chaos/scenarios/network-partition.yaml
```

#### Roteiro de Resposta

1. **Detecção (0-2 min)**
   - Requisições retornando timeout/connection refused
   - Alertas de error rate no Prometheus
   - Pods aparecem como Running mas não respondem

2. **Diagnóstico (2-5 min)**
   - Verificar NetworkPolicies: `kubectl get networkpolicies -n reliabilitylab`
   - Testar conectividade do pod: `kubectl exec -n reliabilitylab deploy/site-kubectl -- wget -qO- --timeout=5 http://localhost:8000/api/health`
   - Verificar se o problema é rede (pods Running mas sem tráfego)

3. **Mitigação (5-10 min)**
   - Remover NetworkPolicy maliciosa: `kubectl delete networkpolicy chaos-network-block -n reliabilitylab`
   - Se persistir: `kubectl delete networkpolicies -n reliabilitylab -l chaos-scenario`
   - Verificar: `curl http://site-kubectl.local/api/health`

4. **Validação (10-15 min)**
   - Confirmar serviço acessível
   - Verificar error rate voltou a 0 no Grafana
   - Confirmar alertas resolvidos

---

### Cenário 4: Vazamento de Memória (OOMKill)

**Severidade:** SEV-2 (Alto)  
**Trigger:** Container excede limit de memória → OOMKilled  
**Alerta esperado:** `PodCrashLooping`, `HighMemoryUsage`

#### Execução

```bash
# Aplicar apenas stress de memória
kubectl apply -f chaos/scenarios/resource-exhaustion.yaml
```

#### Roteiro de Resposta

1. **Detecção (0-3 min)**
   - Verificar eventos de OOMKill: `kubectl get events -n reliabilitylab --field-selector reason=OOMKilling`
   - Pods em CrashLoopBackOff: `kubectl get pods -n reliabilitylab`

2. **Diagnóstico (3-10 min)**
   - Confirmar OOMKill: `kubectl describe pod <pod-name> -n reliabilitylab | grep -A5 "Last State"`
   - Verificar consumo: `kubectl top pods -n reliabilitylab`

3. **Mitigação**
   - Remover stress: `kubectl delete -f chaos/scenarios/resource-exhaustion.yaml`
   - Se pod não recupera: `kubectl rollout restart deployment/site-kubectl -n reliabilitylab`

---

## Template de Postmortem

Use este template após cada simulação:

```markdown
# Postmortem — [Nome do Incidente]

## Resumo
- **Data:** YYYY-MM-DD HH:MM
- **Duração:** X minutos
- **Severidade:** SEV-X
- **Impacto:** [Descrição do impacto]

## Timeline
| Horário | Evento |
|---------|--------|
| HH:MM | Início do incidente |
| HH:MM | Alerta disparado |
| HH:MM | Equipe notificada |
| HH:MM | Causa identificada |
| HH:MM | Mitigação aplicada |
| HH:MM | Serviço restaurado |

## Causa Raiz
[Descrição técnica da causa raiz]

## Impacto nos SLOs
- **Disponibilidade:** X.XX% (target: 99.9%)
- **Error Budget consumido:** X minutos
- **Burn Rate máximo:** Xx

## O que deu certo
- [Item 1]
- [Item 2]

## O que pode melhorar
- [Item 1]
- [Item 2]

## Action Items
| Ação | Responsável | Prazo | Status |
|------|-------------|-------|--------|
| [Ação 1] | [Nome] | [Data] | TODO |
```

---

## Métricas de Maturidade

Use estas métricas para avaliar a maturidade do processo de resposta a incidentes:

| Métrica | Nível 1 (Básico) | Nível 2 (Intermediário) | Nível 3 (Avançado) |
|---------|-------------------|--------------------------|---------------------|
| MTTD (Tempo para Detectar) | > 15 min | 5-15 min | < 5 min |
| MTTR (Tempo para Recuperar) | > 60 min | 15-60 min | < 15 min |
| Postmortem | Não realizado | Realizado parcialmente | Blameless completo |
| Automação | Manual | Semi-automático | Totalmente automatizado |
| Alertas | Sem alertas | Alertas básicos | Multi-window burn rate |
| Error Budget | Não monitorado | Monitorado | Usado para decisões |

---

## Frequência Recomendada

| Atividade | Frequência |
|-----------|------------|
| Game Day completo (todos cenários) | Mensal |
| Cenário individual de chaos | Semanal |
| Revisão de alertas e SLOs | Quinzenal |
| Revisão de postmortems | Mensal |
| Atualização de runbooks | Após cada incidente |

---

## Referências

- [Google SRE — Managing Incidents](https://sre.google/sre-book/managing-incidents/)
- [PagerDuty Incident Response](https://response.pagerduty.com/)
- [Postmortem Culture: Learning from Failure](https://sre.google/sre-book/postmortem-culture/)
