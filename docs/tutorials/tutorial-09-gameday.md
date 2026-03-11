# Tutorial 09 — GameDay

**Objetivo:** Executar um GameDay completo simulando falhas reais no StreamFlix, documentar resultados, produzir um postmortem e preparar evidências para portfólio.

**Resultado:** GameDay executado com 3 cenários, resultados documentados, postmortem preenchido e evidências prontas para LinkedIn/GitHub.

**Tempo estimado:** 40 minutos

**Pré-requisitos:** Todos os tutoriais 01-08 completos com health checks verdes

---

## Contexto

GameDays são eventos estruturados onde o time de engenharia executa falhas controladas para validar que os sistemas se comportam como esperado. O equivalente em disaster recovery são os **DiRT tests** (Disaster Recovery Testing) — onde deliberadamente derrubam serviços inteiros para treinar a resposta de incidentes.

Equipes maduras fazem GameDays trimestrais para validar seus runbooks e processos de resposta a incidentes, especialmente antes de eventos de alta demanda.

Um GameDay bem executado tem:
1. **Hipóteses documentadas antes** — o que você espera que aconteça
2. **Observação em tempo real** — Grafana, HPA, logs
3. **Resultados vs expectativa** — o que realmente aconteceu
4. **Action items** — o que melhorar baseado nos findings
5. **Postmortem** — documento final com lições aprendidas

---

## Passo 1 — Preparação (Steady State)

Antes de qualquer experimento, documente o estado normal do cluster:

```bash
echo "=== STEADY STATE BASELINE ==="
echo ""

echo "Deployments:"
kubectl get deployments -n production
echo ""

echo "HPA:"
kubectl get hpa -n production
echo ""

echo "Pods:"
kubectl get pods -n production
echo ""

echo "Resource usage:"
kubectl top pods -n production
echo ""

echo "Node status:"
kubectl get nodes
kubectl top nodes
```

✅ Esperado:
- 3 deployments com 2/2 réplicas cada
- HPA com TARGETS em <70% CPU
- 6 pods Running
- Todos os nós Ready

**Capture um screenshot do Grafana dashboard neste momento** — esse é o baseline.

---

## Passo 2 — Cenário 1: Pod Kill

**Hipótese:** "Se um pod do content-api for morto, o Kubernetes cria um novo pod em menos de 30 segundos, mantendo o SLO de 99.9%."

### Preparação

```bash
# Terminal 1 — monitorar pods
kubectl get pods -n production -l app=content-api -w

# Terminal 2 — monitorar HPA
kubectl get hpa -n production -w
```

### Execução

```bash
# Terminal 3 — executar experimento
kubectl apply -f platform/chaos/experiments/chaos-pod-kill.yaml
```

### Observação

No Terminal 1, observe:

```
content-api-xxxxx   1/1   Terminating   0   10m
content-api-yyyyy   0/1   Pending       0   0s
content-api-yyyyy   0/1   ContainerCreating   0   0s
content-api-yyyyy   1/1   Running       0   1s    ← ~1 segundo!
```

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| Tempo de recuperação | < 30s | **~1s** ✅ |
| Pod substitute Running | Sim | Sim ✅ |
| Requests perdidas | Mínimas | 0 (segunda réplica serviu) ✅ |
| SLO impacto | Desprezível | Desprezível ✅ |

> **Por que ~1 segundo?** A imagem `podinfo` já está em cache nos nós (foi pulled anteriormente). O Kubernetes não precisa fazer pull da imagem — apenas cria o container.

### Limpeza

```bash
kubectl delete podchaos pod-kill-content-api -n chaos-mesh
```

**Screenshot:** capture o gráfico de pods no Grafana mostrando o dip e a recuperação.

---

## Passo 3 — Cenário 2: CPU Stress + HPA Scaling

**Hipótese:** "Quando o CPU do content-api ultrapassa 70%, o HPA escala automaticamente, mantendo o SLO de latência."

### Execução

```bash
# Aplicar stress via Chaos Mesh
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

### Observação

```bash
# Monitorar HPA (Terminal 1 já deve estar aberto)
kubectl get hpa -n production -w
```

Após 1-2 minutos:

```
content-api   Deployment/content-api   12%/70%    2   10   2
content-api   Deployment/content-api   168%/70%   2   10   2    ← CPU spike
content-api   Deployment/content-api   168%/70%   2   10   4    ← escalou!
content-api   Deployment/content-api   120%/70%   2   10   6    ← 6 réplicas
```

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| CPU trigger | > 70% | **168%** ✅ |
| Scale up | 2 → mais réplicas | **2 → 6 réplicas** ✅ |
| Tempo para escalar | < 3min | **~2min** ✅ |
| Disponibilidade mantida | Sim | Sim ✅ |

### Limpeza

```bash
kubectl delete stresschaos cpu-stress-content-api -n chaos-mesh
```

Aguarde ~5 minutos para scale-down automático.

**Screenshot:** capture o dashboard de HPA mostrando o scale-up e scale-down.

---

## Passo 4 — Cenário 3: Network Latency

**Hipótese:** "Com 200ms de latência injetada no recommendation-api, o serviço responde com degradação mas sem erros em cascata."

### Execução

```bash
kubectl apply -f platform/chaos/experiments/chaos-network-latency.yaml
```

### Observação

```bash
# Testar latência de dentro do cluster
kubectl run gameday-curl --image=curlimages/curl --restart=Never --rm -it -n production -- \
  sh -c "for i in 1 2 3 4 5; do
    START=\$(date +%s%N)
    curl -s -o /dev/null http://recommendation-api
    END=\$(date +%s%N)
    DIFF=\$(( (END - START) / 1000000 ))
    echo \"Request \$i: \${DIFF}ms\"
  done"
```

✅ Esperado: ~200-250ms por request (vs <10ms sem chaos).

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| Latência adicionada | 200ms | **~200-250ms** ✅ |
| Erros HTTP | 0 | **0** ✅ |
| Cascading failure | Nenhuma | **Nenhuma** ✅ |
| Recuperação após remoção | Imediata | **Imediata** ✅ |

### Limpeza

```bash
kubectl delete networkchaos network-latency-recommendation -n chaos-mesh
```

---

## Passo 5 — Resumo consolidado do GameDay

```markdown
# GameDay #01 — StreamFlix Resilience Validation
**Data:** $(date +%Y-%m-%d)
**Participante:** [Seu nome]
**Stack:** Kubernetes v1.32.0 + Chaos Mesh + Prometheus + Sloth

## Resumo

| # | Cenário | Hipótese | Resultado | Status |
|---|---------|----------|-----------|--------|
| 1 | Pod Kill content-api | Recuperação < 30s | ~1s | ✅ PASS |
| 2 | CPU Stress + HPA | HPA escala > 70% CPU | 2 → 6 réplicas em ~2min | ✅ PASS |
| 3 | Network Latency recommendation-api | Sem cascading failure | HTTP 200 mantido com ~200ms extra | ✅ PASS |

## Findings
1. Recuperação de pod kill é extremamente rápida (~1s) quando a imagem está em cache
2. HPA reage em ~2 minutos — considerar custom metrics para resposta mais rápida
3. Latência de rede não causa cascading failures com serviços stateless

## Action Items
- [ ] Implementar circuit breaker para proteger contra latência > 500ms
- [ ] Adicionar custom metrics ao HPA (RPS, latência P99)
- [ ] Criar alertas específicos para tempo de recuperação de pods
- [ ] Executar GameDay com múltiplos cenários simultâneos
```

Salve como documento:

```bash
cat <<'EOF' > docs/gamedays/gameday-01-pod-kill.md
# GameDay #01 — StreamFlix Resilience Validation

**Data:** 2026-03-10
**Ambiente:** Minikube v1.38.0 / Kubernetes v1.32.0
**Tools:** Chaos Mesh, Prometheus, Grafana, Sloth, k6
**Duração:** 40 minutos

---

## Objetivos

1. Validar auto-recovery de pods (pod kill)
2. Validar auto-scaling sob stress (HPA)
3. Validar resiliência a degradação de rede

---

## Cenário 1 — Pod Kill (content-api)

**Tipo:** PodChaos (Chaos Mesh)
**Target:** content-api (production namespace)
**Hipótese:** Kubernetes recria pod em < 30s

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| Recovery time | < 30s | ~1s |
| Error rate | < 0.1% | 0% |
| SLO impact | Minimal | None |

**Status:** ✅ PASS

---

## Cenário 2 — CPU Stress + HPA

**Tipo:** StressChaos (Chaos Mesh)
**Target:** content-api (all pods)
**Hipótese:** HPA escala quando CPU > 70%

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| CPU peak | > 70% | 168% |
| Replicas | > 2 | 2 → 6 |
| Scale time | < 3min | ~2min |
| Availability | Maintained | ✅ |

**Status:** ✅ PASS

---

## Cenário 3 — Network Latency (recommendation-api)

**Tipo:** NetworkChaos (Chaos Mesh)
**Target:** recommendation-api (production namespace)
**Hipótese:** Sem cascading failures com 200ms de latência

### Resultado

| Métrica | Esperado | Real |
|---------|----------|------|
| Added latency | 200ms | ~200-250ms |
| HTTP errors | 0 | 0 |
| Cascading failures | None | None |

**Status:** ✅ PASS

---

## Postmortem Summary

### O que funcionou bem
- Self-healing do Kubernetes é eficaz (~1s recovery)
- HPA responde adequadamente a CPU stress
- Serviços stateless isolam degradação de rede

### O que pode melhorar
- HPA baseado apenas em CPU pode ser lento (2min) — considerar custom metrics
- Não há circuit breaker — latência > 500ms não é tratada
- Sem alertas de SLO burn rate dispararando durante os testes

### Action Items

| # | Ação | Prioridade | Owner |
|---|------|-----------|-------|
| 1 | Implementar circuit breaker | Alta | - |
| 2 | Custom metrics no HPA | Média | - |
| 3 | Alerta de recovery time | Baixa | - |
| 4 | GameDay com multi-scenario simultâneo | Média | - |

---

## Referências
- DiRT (Disaster Recovery Testing): https://cloud.google.com/blog/products/management-tools/shrinking-the-time-to-mitigate-production-incidents
- Principles of Chaos: https://principlesofchaos.org
EOF
```

---

## Passo 6 — Template de Postmortem

Crie um template reutilizável para futuros incidentes e GameDays:

```bash
cat <<'EOF' > docs/postmortems/template-postmortem.md
# Postmortem — [Título do Incidente]

**Severidade:** P1/P2/P3/P4
**Data:** YYYY-MM-DD
**Duração:** Xh Xmin
**Autor:** [Nome]
**Status:** Draft / Reviewed / Final

---

## Timeline

| Hora | Evento |
|------|--------|
| HH:MM | Alerta disparou |
| HH:MM | Engenheiro acionado |
| HH:MM | Causa raiz identificada |
| HH:MM | Fix aplicado |
| HH:MM | Serviço recuperado |

---

## Impacto

- **Usuários afetados:** X%
- **Requests falhando:** X/s
- **Error budget consumido:** X%
- **SLO violado:** Sim/Não

---

## Causa Raiz

[Descrição técnica da causa raiz]

---

## O que funcionou

- [Item 1]
- [Item 2]

## O que não funcionou

- [Item 1]
- [Item 2]

---

## Action Items

| # | Ação | Tipo | Prioridade | Owner | Deadline |
|---|------|------|-----------|-------|----------|
| 1 | | Fix | P1 | | |
| 2 | | Prevention | P2 | | |
| 3 | | Detection | P3 | | |

---

## Lições Aprendidas

1.
2.
3.
EOF
```

---

## Passo 7 — Checklist de evidências para portfólio

```bash
echo "=== CHECKLIST DE EVIDÊNCIAS ==="
echo ""
echo "Screenshots necessários:"
echo "  [ ] Grafana dashboard — steady state (baseline)"
echo "  [ ] Grafana dashboard — durante pod kill"
echo "  [ ] HPA scaling de 2 → 6 réplicas"
echo "  [ ] Chaos Mesh dashboard com experimentos"
echo "  [ ] Prometheus targets com serviços UP"
echo "  [ ] ArgoCD dashboard com Application synced"
echo "  [ ] k6 output com thresholds passando"
echo ""
echo "Documentos:"
echo "  [ ] GameDay report (docs/gamedays/gameday-01-pod-kill.md)"
echo "  [ ] Postmortem template preenchido"
echo "  [ ] TROUBLESHOOTING.md com problemas reais"
echo ""
echo "Repositório:"
echo "  [ ] README.md atualizado com badges corretos"
echo "  [ ] Todos os YAMLs commitados e funcionais"
echo "  [ ] Estrutura de pastas organizada"
```

---

## Health Check (antes de avançar para Tutorial 10)

```bash
echo "=== HEALTH CHECK — Tutorial 09 ==="

echo -e "\n[1/3] GameDay report existe:"
[ -f docs/gamedays/gameday-01-pod-kill.md ] \
  && echo "  ✅ GameDay report criado" || echo "  ❌ GameDay report ausente"
echo ""

echo "[2/3] Postmortem template existe:"
[ -f docs/postmortems/template-postmortem.md ] \
  && echo "  ✅ Template criado" || echo "  ❌ Template ausente"
echo ""

echo "[3/3] Cluster saudável após os experimentos:"
NOT_RUNNING=$(kubectl get pods -n production --no-headers 2>/dev/null | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo "  ✅ Todos os pods production Running"
else
  echo "  ❌ $NOT_RUNNING pods com problema — verifique"
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| Pod não se recupera após PodChaos | ReplicaSet não criou novo pod | `kubectl describe rs <replicaset> -n production` para ver eventos |
| HPA não escala durante StressChaos | StressChaos pode não afetar cgroups corretamente | Alternativa: use `kubectl exec` com `dd if=/dev/zero of=/dev/null` |
| Cluster instável após múltiplos experimentos | RAM esgotada | `kubectl top nodes`. Se necessário, reinicie: `minikube stop -p reliabilitylab && minikube start -p reliabilitylab` |
| Network latency não afeta requests | chaos-daemon não tem acesso ao network namespace | Verifique `kubectl get pods -n chaos-mesh` — todos daemons devem estar Running |

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Monte um roteiro de GameDay combinando pod-kill + load test + observação de burn rate`
- `Execute a checklist de verificação completa do ambiente e me diga o que falhou`
- `O cluster ficou instável após o GameDay. Diagnostique e restaure`
- `Gere um relatório de post-mortem baseado nos resultados do último GameDay`
- `Atualize as versões dos Helm charts para as mais recentes estáveis`
- `Revise o TROUBLESHOOTING.md e adicione qualquer novo problema que encontrei durante o lab`

---

**Anterior:** [Tutorial 08 — Load Testing com k6](tutorial-08-k6-load-testing.md)
**Próximo:** [Tutorial 10 — LinkedIn e GitHub](tutorial-10-linkedin-github.md)
