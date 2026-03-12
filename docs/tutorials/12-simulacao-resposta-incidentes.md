# Tutorial 12 — Simulação de Resposta a Incidentes

## Objetivo

Simular um incidente real e praticar o processo de **detecção, diagnóstico, mitigação e post-mortem** seguindo práticas de SRE.

## Conceitos

- **Incidente**: evento que causa degradação ou indisponibilidade de um serviço
- **Severidade**: classificação do impacto (SEV1-SEV4)
- **Incident Commander (IC)**: pessoa que coordena a resposta
- **MTTR**: tempo médio para recuperar
- **MTTD**: tempo médio para detectar
- **Post-mortem**: análise após o incidente para prevenir recorrência
- **Blameless**: cultura de não culpar pessoas, mas melhorar processos

## Pré-requisitos

- Stack completa rodando (observabilidade, HPA, NetworkPolicy)
- k6 instalado (opcional mas recomendado)
- Familiaridade com os tutoriais anteriores (01-11)

## Severidades

| Nível | Impacto | Exemplo | Tempo para Resposta |
|-------|---------|---------|---------------------|
| SEV1 | Serviço completamente indisponível | Todos os pods mortos | Imediato |
| SEV2 | Degradação severa de performance | Latência > 5s | < 15 min |
| SEV3 | Degradação parcial | Um endpoint com erro | < 1 hora |
| SEV4 | Problema menor | Logs com warns | Próximo dia útil |

## Simulação 1: CrashLoopBackOff (SEV2)

### Criar o incidente

```bash
# Forçar um CrashLoopBackOff simulando uma variável de ambiente inválida
kubectl set env deployment/site-kubectl -n reliabilitylab APP_PORT=invalid_port
```

### Fase 1: Detecção (MTTD)

Inicie o cronômetro. Como você detectaria esse problema?

```bash
# Verificar status dos pods
kubectl get pods -n reliabilitylab

# Resultado: pods em CrashLoopBackOff
# NAME                           READY   STATUS             RESTARTS
# site-kubectl-xxxxx-xxxxx      0/1     CrashLoopBackOff   3

# Verificar health
curl -s http://site-kubectl.local/api/health
# Resultado: falha ou timeout
```

### Fase 2: Diagnóstico

```bash
# Ver logs do container
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --tail=20

# Ver eventos
kubectl get events -n reliabilitylab --sort-by='.lastTimestamp' | head -10

# Descrever o pod
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl
```

**Causa raiz**: a variável `APP_PORT=invalid_port` fez o uvicorn falhar ao iniciar.

### Fase 3: Mitigação

```bash
# Reverter a variável
kubectl set env deployment/site-kubectl -n reliabilitylab APP_PORT-

# Observar recuperação
kubectl get pods -n reliabilitylab -w

# Verificar
curl http://site-kubectl.local/api/health
```

### Fase 4: Verificação

```bash
# Confirmar que tudo voltou ao normal
bash scripts/status.sh
```

Pare o cronômetro. Documente o MTTD e MTTR.

## Simulação 2: Alta Latência (SEV2)

### Criar o incidente

```bash
# Reduzir recursos drasticamente
kubectl patch deployment site-kubectl -n reliabilitylab --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50m"}]'
```

### Detecção

```bash
# Rodar smoke test
bash scripts/run-load-test.sh smoke

# Observar latência alta nos resultados
# http_req_duration p(95) > 500ms → threshold falha
```

### Diagnóstico

```bash
# Ver uso de recursos
kubectl top pods -n reliabilitylab

# Resultado: CPU throttled
# NAME                          CPU(cores)   MEMORY(bytes)
# site-kubectl-xxxxx-xxxxx    50m          100Mi       ← no limit!

# Verificar eventos de throttling
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl
```

### Mitigação

```bash
# Restaurar recursos originais
kubectl patch deployment site-kubectl -n reliabilitylab --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"500m"}]'

# Verificar
bash scripts/run-load-test.sh smoke
```

## Simulação 3: OOMKilled (SEV2)

### Criar o incidente

```bash
# Reduzir limit de memória para provocar OOM
kubectl patch deployment site-kubectl -n reliabilitylab --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"32Mi"}]'
```

### Detecção

```bash
kubectl get pods -n reliabilitylab

# STATUS: OOMKilled ou CrashLoopBackOff
# RESTARTS: incrementando
```

### Diagnóstico

```bash
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl | grep -A5 "Last State"

# Last State:     Terminated
#   Reason:       OOMKilled
#   Exit Code:    137
```

### Mitigação

```bash
# Restaurar memória
kubectl patch deployment site-kubectl -n reliabilitylab --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
```

## Simulação 4: Perda Total de Pods (SEV1)

### Criar o incidente

```bash
# Escalar para zero
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=0
```

### Detecção

```bash
curl -s -o /dev/null -w "%{http_code}" http://site-kubectl.local/api/health
# Resultado: 503 ou connection refused
```

### Diagnóstico

```bash
kubectl get deployment site-kubectl -n reliabilitylab
# READY: 0/0

kubectl get events -n reliabilitylab --sort-by='.lastTimestamp'
```

### Mitigação

```bash
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=2
```

> **Nota:** Se o ArgoCD estiver ativo (Tutorial 11), ele corrigirá isso automaticamente via self-heal!

## Template de Post-mortem

Após cada simulação, preencha este template:

```markdown
# Post-mortem: [Título do Incidente]

**Data:** YYYY-MM-DD
**Severidade:** SEV1/SEV2/SEV3/SEV4
**Duração:** XX minutos
**Impacto:** Descrição do impacto no usuário

## Timeline
- HH:MM — Incidente criado
- HH:MM — Detecção (MTTD: XX min)
- HH:MM — Diagnóstico concluído
- HH:MM — Mitigação aplicada (MTTR: XX min)
- HH:MM — Serviço restaurado

## Causa Raiz
Descrição técnica da causa.

## O que funcionou bem
- Item 1

## O que pode melhorar
- Item 1

## Action Items
- [ ] Item 1 — Responsável — Prazo
```

## Tabela de Resultados

Registre seus tempos:

| Simulação | MTTD | MTTR | Severidade |
|-----------|------|------|------------|
| CrashLoopBackOff | | | SEV2 |
| Alta Latência | | | SEV2 |
| OOMKilled | | | SEV2 |
| Perda Total | | | SEV1 |

## Comandos de Diagnóstico Essenciais

```bash
# Status geral rápido
bash scripts/status.sh

# Pods com problemas
kubectl get pods -A --field-selector=status.phase!=Running

# Eventos recentes
kubectl get events -A --sort-by='.lastTimestamp' | head -20

# Logs de erro
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --tail=50 | grep -i error

# Uso de recursos
kubectl top pods -n reliabilitylab

# Descrever recursos
kubectl describe deployment site-kubectl -n reliabilitylab
```

## Lições Finais

1. **Monitore sempre**: sem observabilidade, incidentes demoram mais para serem detectados
2. **Automatize a recuperação**: HPA, self-heal do ArgoCD, e PDB protegem contra falhas
3. **Pratique regularmente**: GameDays frequentes melhoram o tempo de resposta
4. **Documente tudo**: post-mortems blameless ajudam a prevenir recorrência
5. **Multiple réplicas**: nunca rode produção com 1 réplica
6. **Resource limits**: sem limits, um pod pode consumir o nó inteiro

---

## Parabéns! 🎉

Você completou todos os 12 tutoriais do **ReliabilityLab**!

### O que você aprendeu:
1. ✅ Rodar aplicação localmente
2. ✅ Containerizar com Docker
3. ✅ Criar cluster Kubernetes
4. ✅ Deploy com manifests declarativos
5. ✅ Observabilidade completa (Prometheus, Grafana, Loki)
6. ✅ Autoscaling com HPA
7. ✅ Segurança (NetworkPolicy, RBAC, PSS)
8. ✅ Chaos Engineering
9. ✅ Load Testing com k6
10. ✅ Observar falhas e medir recuperação
11. ✅ GitOps com ArgoCD
12. ✅ Resposta a incidentes

### Próximos passos sugeridos:
- Implementar SLOs com Sloth
- Adicionar tracing distribuído com Jaeger/Tempo
- Criar pipelines CI/CD com GitHub Actions
- Estudar para certificações CKA/CKAD
