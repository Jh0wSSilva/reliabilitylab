# Tutorial 16 — Simulação de Interrupções (Chaos Outage)

## Objetivo

Neste tutorial você vai aprender a:
- Executar cenários de **interrupção real** no serviço
- Observar o comportamento do Kubernetes durante falhas
- Acompanhar **alertas, SLO e recovery** no Grafana
- Praticar a resposta a incidentes

## Pré-requisitos

- Tutoriais 13-15 concluídos (SLO + alertas + Alertmanager)
- Prometheus alerts e Alertmanager configurados
- Dashboard SLO importado no Grafana

## Cenários Disponíveis

O ReliabilityLab inclui 3 cenários de outage em `chaos/scenarios/`:

| Cenário | Arquivo | Efeito |
|---------|---------|--------|
| Total Pod Kill | `total-pod-kill.yaml` | Elimina todos os pods simultaneamente |
| Network Partition | `network-partition.yaml` | Bloqueia todo tráfego de/para os pods |
| Resource Exhaustion | `resource-exhaustion.yaml` | Satura CPU e memória do namespace |

## Passo a Passo

### Preparação

Antes de cada cenário, abra em terminais separados:

```bash
# Terminal 1: Monitorar pods
watch kubectl get pods -n reliabilitylab -l app=site-kubectl

# Terminal 2: Monitorar eventos
kubectl get events -n reliabilitylab -w

# Terminal 3: Logs do webhook logger (alertas)
kubectl logs -n monitoring -l app=webhook-logger -f

# Terminal 4: Grafana SLO dashboard  
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Abrir: http://localhost:3000 → Dashboard "Site Kubectl — SLO Dashboard"
```

---

### Cenário 1: Eliminação Total de Pods

Este cenário deleta **todos os pods** do site-kubectl simultaneamente, simulando
uma falha catastrófica. O Kubernetes deve recriar os pods automaticamente.

**Executar:**

```bash
# Limpar jobs anteriores
kubectl delete job chaos-total-pod-kill -n reliabilitylab 2>/dev/null || true

# Executar cenário
kubectl apply -f chaos/scenarios/total-pod-kill.yaml
```

**Acompanhar:**

```bash
# Ver logs do job (em tempo real)
kubectl logs -n reliabilitylab -l chaos-scenario=total-pod-kill -f
```

**O que observar:**
1. Todos os pods são terminados → **ServiceUnavailable** deve disparar
2. ReplicaSet recria os pods → pods voltam para Running
3. Alertas transitam de **firing** para **resolved**
4. No Grafana: gauges mostram queda e recuperação
5. Burn rate sobe durante a interrupção

**Verificar:**

```bash
kubectl get pods -n reliabilitylab -l app=site-kubectl
```

---

### Cenário 2: Partição de Rede

Este cenário aplica uma NetworkPolicy que bloqueia **todo o tráfego** de entrada
e saída dos pods. Os pods continuam Running mas ficam inacessíveis.

**Executar:**

```bash
# Limpar anteriores
kubectl delete job chaos-network-partition -n reliabilitylab 2>/dev/null || true
kubectl delete networkpolicy chaos-network-block -n reliabilitylab 2>/dev/null || true

# Executar (60s de partição)
kubectl apply -f chaos/scenarios/network-partition.yaml
```

**Acompanhar:**

```bash
kubectl logs -n reliabilitylab -l chaos-scenario=network-partition-job -f
```

**O que observar:**
1. Pods aparecem como Running, mas não respondem
2. Alertas de **HighErrorRate** disparam (requisições falham com timeout)
3. Após remoção da NetworkPolicy, tráfego é restaurado
4. No Grafana: taxa de erros sobe e depois volta a 0

**Verificar rede:**

```bash
# Listar NetworkPolicies
kubectl get networkpolicies -n reliabilitylab

# Testar conectividade
kubectl exec -n reliabilitylab deploy/site-kubectl -- \
  wget -qO- --timeout=5 http://localhost:8000/api/health || echo "FALHOU"
```

---

### Cenário 3: Exaustão de Recursos

Este cenário cria jobs que consomem CPU e memória intensivamente,
competindo por recursos com os pods do site-kubectl.

**Executar:**

```bash
# Limpar anteriores
kubectl delete -f chaos/scenarios/resource-exhaustion.yaml 2>/dev/null || true

# Executar
kubectl apply -f chaos/scenarios/resource-exhaustion.yaml
```

**Acompanhar:**

```bash
# Monitorar consumo de recursos
watch kubectl top pods -n reliabilitylab

# Logs do monitor
kubectl logs -n reliabilitylab -l chaos-scenario=resource-monitor -f
```

**O que observar:**
1. Jobs de stress consomem CPU e memória
2. Pods do site-kubectl podem sofrer throttling (latência sobe)
3. HPA pode tentar escalar mais réplicas
4. Alertas de **HighCPUUsage** / **HighMemoryUsage** / **HighLatencyP95**
5. Após remover os jobs, recursos normalizam

**Limpar:**

```bash
kubectl delete -f chaos/scenarios/resource-exhaustion.yaml
```

---

### Pós-cenário: Análise

Após cada cenário, responda:

1. **Quanto tempo levou para detectar?** (MTTD)
2. **Quanto tempo levou para recuperar?** (MTTR)
3. **Quais alertas dispararam?**
4. **O Error Budget foi impactado?**
5. **O que poderia ser melhorado?**

Use o template de postmortem em `docs/runbooks/incident-simulation.md`.

## Verificação

Confirme que você executou:

- [ ] Cenário 1: Total Pod Kill → pods recuperaram
- [ ] Cenário 2: Network Partition → rede restaurada
- [ ] Cenário 3: Resource Exhaustion → recursos normalizaram
- [ ] Observou alertas no Prometheus/Alertmanager
- [ ] Analisou impacto no dashboard SLO do Grafana

## Próximo Tutorial

No [Tutorial 17](tutorial-17-resilience-testing-pipeline.md) vamos automatizar estes
cenários em um pipeline de testes de resiliência.
