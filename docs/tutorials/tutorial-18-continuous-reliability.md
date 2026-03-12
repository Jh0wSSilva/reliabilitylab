# Tutorial 18 — Confiabilidade Contínua e Game Days

## Objetivo

Neste tutorial você vai aprender a:
- Estruturar **Game Days** para praticar resposta a incidentes
- Implementar um ciclo de **melhoria contínua** de confiabilidade
- Escrever **postmortems blameless** (sem culpados)
- Medir a maturidade do processo de SRE

## Pré-requisitos

- Tutoriais 13-17 concluídos (SLO + alertas + chaos + pipeline)
- Familiaridade com todos os cenários de chaos disponíveis

## Conceitos

### O que é um Game Day?

Um Game Day é uma **sessão prática** onde a equipe:
1. Simula falhas reais no serviço
2. Pratica detecção, diagnóstico e mitigação
3. Mede métricas como MTTD (tempo para detectar) e MTTR (tempo para recuperar)
4. Documenta aprendizados em postmortems

### Confiabilidade Contínua

```
        ┌──────────────────────────┐
        │                          │
        ▼                          │
  Definir SLOs  →  Monitorar  →  Alertar  →  Investigar
        │                                        │
        │                                        ▼
        └──────── Melhorar ◄── Postmortem ◄── Mitigar
```

O ciclo se repete continuamente, com cada iteração melhorando:
- Alertas mais precisos (menos falsos positivos)
- Runbooks mais completos
- Automação de respostas
- SLOs mais adequados à realidade

## Passo a Passo

### Passo 1: Planejar um Game Day

Defina o escopo do Game Day:

```markdown
# Planejamento do Game Day

## Objetivo
Validar que a equipe consegue detectar e recuperar de uma
indisponibilidade total do serviço em menos de 15 minutos.

## Participantes
- Operador (executa o chaos)
- Respondente (detecta e resolve)
- Observador (documenta timeline)

## Cenário
Total pod kill + carga simultânea

## Métricas de Sucesso
- MTTD < 5 minutos
- MTTR < 15 minutos
- Error Budget consumido < 5%
- Postmortem escrito em até 1 hora após o incidente
```

### Passo 2: Executar o Game Day

**Operador:** Prepare o cenário sem avisar o respondente sobre qual tipo de falha será
injetada.

```bash
# Iniciar carga de fundo
k6 run -e BASE_URL=http://site-kubectl.local \
  -e DURATION=10m \
  load-testing/resilience-test.js &

# Esperar 2 minutos (serviço estável)
sleep 120

# Injetar falha (escolha um cenário)
kubectl apply -f chaos/scenarios/total-pod-kill.yaml
```

**Respondente:** Use apenas as ferramentas de monitoramento para diagnosticar:

```bash
# Verificar alertas
# → Prometheus: http://localhost:9090/alerts
# → Alertmanager: http://localhost:9093
# → Grafana SLO: http://localhost:3000

# Verificar pods
kubectl get pods -n reliabilitylab

# Verificar eventos
kubectl get events -n reliabilitylab --sort-by=.lastTimestamp

# Verificar logs
kubectl logs -n reliabilitylab -l app=site-kubectl --previous
```

**Observador:** Documente a timeline:

| Horário | Evento |
|---------|--------|
| HH:MM | Chaos injetado |
| HH:MM | Primeiro alerta (qual?) |
| HH:MM | Respondente notificou |
| HH:MM | Causa raiz identificada |
| HH:MM | Mitigação aplicada |
| HH:MM | Serviço restaurado |

### Passo 3: Escrever o Postmortem

Use o template em `docs/runbooks/incident-simulation.md`:

```bash
cat docs/runbooks/incident-simulation.md | grep -A 50 "Template de Postmortem"
```

Preencha cada seção:
- **Resumo** — O que aconteceu em 1-2 frases
- **Timeline** — Cronologia exata dos eventos
- **Causa Raiz** — Por que aconteceu (técnico)
- **Impacto nos SLOs** — Quanto error budget foi consumido
- **O que deu certo** — O que funcionou na resposta
- **O que pode melhorar** — Gaps identificados
- **Action Items** — Ações concretas com responsável e prazo

> **Importante:** O postmortem é **blameless** (sem culpados). O foco é no sistema,
> não nas pessoas.

### Passo 4: Medir maturidade

Após cada Game Day, avalie a maturidade:

| Métrica | Nível 1 | Nível 2 | Nível 3 | Seu Resultado |
|---------|---------|---------|---------|---------------|
| MTTD | > 15 min | 5-15 min | < 5 min | |
| MTTR | > 60 min | 15-60 min | < 15 min | |
| Postmortem | Não feito | Parcial | Blameless completo | |
| Automação | Manual | Semi-auto | Totalmente auto | |
| Alertas | Sem alertas | Básicos | Multi-window burn rate | |
| Error Budget | Não monitora | Monitora | Usa para decisões | |

O objetivo é evoluir gradualmente para o **Nível 3** em todas as métricas.

### Passo 5: Ciclo de Melhoria

Após o Game Day, implemente as melhorias:

```bash
# 1. Ajustar alertas se houve falso positivos/negativos
vim observability/prometheus/alerts.yaml
kubectl apply -f observability/prometheus/alerts.yaml

# 2. Atualizar runbooks com novos passos de diagnóstico
vim docs/runbooks/incident-simulation.md

# 3. Adicionar automação para problemas recorrentes
# (ex: script que reinicia deployment automaticamente)

# 4. Revisar SLOs se os targets estão adequados
vim docs/sre/slo-model.md
```

### Passo 6: Frequência Recomendada

| Atividade | Frequência |
|-----------|------------|
| Game Day completo (todos cenários) | Mensal |
| Cenário individual de chaos | Semanal |
| Pipeline de resiliência automatizado | A cada deploy |
| Revisão de alertas e SLOs | Quinzenal |
| Revisão de postmortems | Mensal |

### Passo 7: Pipeline automatizado como "guarda de confiabilidade"

Use o pipeline de resiliência como um teste automatizado
que roda após cada deploy:

```bash
# Após cada deploy, rodar teste rápido de resiliência
./scripts/run-resilience-tests.sh quick

# Se o teste falhar (SLOs violados), reverter o deploy
if [ $? -ne 0 ]; then
  echo "Testes de resiliência falharam! Revertendo deploy..."
  kubectl rollout undo deployment/site-kubectl -n reliabilitylab
fi
```

## Verificação

Confirme que você consegue:

1. Planejar e executar um Game Day
2. Medir MTTD e MTTR
3. Escrever um postmortem blameless
4. Avaliar a maturidade do processo de SRE
5. Propor melhorias concretas baseadas nos resultados
6. Executar o pipeline como guarda de confiabilidade

## Conclusão

Parabéns! Você completou todos os 18 tutoriais do **ReliabilityLab**.

### Competências Adquiridas

| Área | Competências |
|------|-------------|
| Kubernetes | Deploy, HPA, probes, RBAC, NetworkPolicy, PDB |
| Observabilidade | Prometheus, Grafana, Loki, OTel, dashboards, métricas |
| SRE | SLI, SLO, Error Budget, Burn Rate, políticas |
| Alertas | PrometheusRule, multi-window burn rate, Alertmanager |
| Chaos Engineering | Pod kill, network partition, resource exhaustion |
| Resiliência | Pipeline automatizado, testes de carga + chaos |
| Incidentes | Game Days, postmortems blameless, ciclo de melhoria |
| GitOps | ArgoCD, auto-sync, self-heal |
| Segurança | RBAC, PSS, zero-trust networking, secrets |

### Próximos Passos

- Adapte os cenários de chaos para seus próprios serviços
- Execute Game Days regularmente com sua equipe
- Publique seu aprendizado no LinkedIn e GitHub
- Contribua com novos cenários e melhorias no repositório
