# Resposta a Incidentes — ReliabilityLab

## Introdução

Este documento descreve como identificar, responder e resolver incidentes no ambiente ReliabilityLab. O objetivo é ensinar práticas de **Incident Response** usadas em equipes de SRE em produção.

---

## Processo de Resposta a Incidentes

### Fluxo de Resposta

```
Detecção → Triagem → Mitigação → Resolução → Post-mortem
```

| Fase | Descrição | Responsável |
|------|-----------|-------------|
| **Detecção** | Alertas do Prometheus/Grafana ou relato de usuário | Sistema de monitoramento |
| **Triagem** | Classificar severidade e impacto | Engenheiro de plantão |
| **Mitigação** | Ação imediata para reduzir impacto | Engenheiro de plantão |
| **Resolução** | Correção definitiva do problema | Time de engenharia |
| **Post-mortem** | Análise sem culpa, identificar melhorias | Time todo |

### Níveis de Severidade

| Nível | Descrição | Tempo de Resposta | Exemplo |
|-------|-----------|-------------------|---------|
| **SEV1** | Serviço completamente indisponível | 5 minutos | 100% dos pods em CrashLoop |
| **SEV2** | Degradação severa de performance | 15 minutos | Latência p99 > 5s |
| **SEV3** | Funcionalidade parcialmente afetada | 30 minutos | Um endpoint retornando erro |
| **SEV4** | Problema menor sem impacto visível | 4 horas | Warning em logs |

---

## Cenários de Incidente

### Cenário 1: Aplicação em CrashLoopBackOff

**Sintoma:** Pods reiniciando continuamente.

**Detecção:**
```bash
# Verificar status dos pods
kubectl get pods -n reliabilitylab

# Saída esperada: STATUS = CrashLoopBackOff
```

**Diagnóstico:**
```bash
# Ver logs do pod que está falhando
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --previous

# Ver eventos do namespace
kubectl get events -n reliabilitylab --sort-by='.lastTimestamp'

# Descrever o pod para ver detalhes
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl
```

**Causas comuns:**
1. Erro na aplicação (exceção não tratada)
2. Configuração errada (ConfigMap/Secret)
3. Imagem Docker incorreta ou corrompida
4. Falta de recursos (OOMKilled)

**Mitigação:**
```bash
# Se o problema é de configuração, corrigir e reaplicar:
kubectl apply -f k8s/configmap.yaml
kubectl rollout restart deployment/site-kubectl -n reliabilitylab

# Se o problema é de imagem, fazer rollback:
kubectl rollout undo deployment/site-kubectl -n reliabilitylab

# Verificar se voltou ao normal:
kubectl rollout status deployment/site-kubectl -n reliabilitylab
```

**Verificação:**
```bash
curl http://site-kubectl.local/api/health
# Esperado: {"status":"ok","message":"App is running normally"}
```

---

### Cenário 2: Latência Alta (Degradação de Performance)

**Sintoma:** Tempo de resposta > 2 segundos.

**Detecção:**
```bash
# Verificar métricas de latência no Grafana
# Dashboard: Site-Kubectl Overview
# Painel: Request Duration p99

# Ou via Prometheus:
# rate(http_request_duration_seconds_bucket[5m])
```

**Diagnóstico:**
```bash
# Verificar uso de recursos dos pods
kubectl top pods -n reliabilitylab

# Verificar se o HPA está escalando
kubectl get hpa -n reliabilitylab

# Verificar logs para erros
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl --tail=50

# Verificar se há throttling de CPU
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl | grep -A5 "Resources"
```

**Causas comuns:**
1. CPU throttling (limits muito baixos)
2. Muitas requisições (precisar escalar)
3. Latência de rede (NetworkPolicy muito restritiva)
4. Contenção de recursos no nó

**Mitigação:**
```bash
# Escalar manualmente se o HPA não está reagindo rápido o suficiente
kubectl scale deployment/site-kubectl -n reliabilitylab --replicas=4

# Aumentar limites de CPU temporariamente
kubectl set resources deployment/site-kubectl -n reliabilitylab \
    --limits=cpu=1000m,memory=1Gi \
    --requests=cpu=200m,memory=256Mi

# Verificar distribuição dos pods entre nós
kubectl get pods -n reliabilitylab -o wide
```

**Verificação:**
```bash
# Testar latência manualmente
time curl -s http://site-kubectl.local/api/health > /dev/null
# Esperado: < 0.5 segundos
```

---

### Cenário 3: Esgotamento de Recursos (OOMKilled)

**Sintoma:** Pods sendo terminados com razão OOMKilled.

**Detecção:**
```bash
# Verificar status dos pods
kubectl get pods -n reliabilitylab

# Verificar eventos de OOM
kubectl get events -n reliabilitylab --field-selector reason=OOMKilled
```

**Diagnóstico:**
```bash
# Ver detalhes do pod
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl

# Verificar uso real de memória
kubectl top pods -n reliabilitylab

# Ver último estado do container
kubectl get pods -n reliabilitylab -o jsonpath='{.items[*].status.containerStatuses[*].lastState}'
```

**Causas comuns:**
1. Memory leak na aplicação
2. Limits de memória muito baixos
3. Muitas requisições simultâneas
4. Payload grande sendo processado

**Mitigação:**
```bash
# Aumentar limite de memória
kubectl set resources deployment/site-kubectl -n reliabilitylab \
    --limits=cpu=500m,memory=1Gi \
    --requests=cpu=100m,memory=256Mi

# Reiniciar para limpar memória acumulada
kubectl rollout restart deployment/site-kubectl -n reliabilitylab

# Verificar se voltou ao normal
kubectl rollout status deployment/site-kubectl -n reliabilitylab
```

---

### Cenário 4: Ingress Não Responde

**Sintoma:** `curl http://site-kubectl.local` retorna connection refused ou 502.

**Detecção:**
```bash
curl -v http://site-kubectl.local
# Esperado: Connection refused, 502 Bad Gateway, ou timeout
```

**Diagnóstico:**
```bash
# 1. Verificar se o Ingress Controller está rodando
kubectl get pods -n ingress-nginx

# 2. Verificar se o Ingress está configurado corretamente
kubectl describe ingress site-kubectl -n reliabilitylab

# 3. Verificar se o Service tem endpoints
kubectl get endpoints site-kubectl -n reliabilitylab

# 4. Verificar se os pods estão prontos
kubectl get pods -n reliabilitylab -l app.kubernetes.io/name=site-kubectl

# 5. Verificar /etc/hosts
grep site-kubectl /etc/hosts
```

**Causas comuns:**
1. Ingress Controller não está rodando
2. DNS local não configurado (/etc/hosts)
3. Pods não estão ready (probe falhando)
4. Service sem endpoints

**Mitigação:**
```bash
# Se Ingress Controller não está rodando
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Se /etc/hosts não está configurado
echo "127.0.0.1 site-kubectl.local" | sudo tee -a /etc/hosts

# Se pods não estão ready, verificar probes
kubectl describe pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl | grep -A10 "Readiness"
```

---

## Template de Post-mortem

### Título do Incidente

**Data:** YYYY-MM-DD
**Duração:** XX minutos
**Severidade:** SEV#
**Impacto:** Descrição do impacto para o usuário

### Timeline

| Horário | Evento |
|---------|--------|
| HH:MM | Alerta disparado |
| HH:MM | Engenheiro de plantão notificado |
| HH:MM | Início da investigação |
| HH:MM | Causa raiz identificada |
| HH:MM | Mitigação aplicada |
| HH:MM | Serviço restaurado |

### Causa Raiz

Descrição detalhada do que causou o incidente.

### O que funcionou

- Itens que ajudaram na resolução rápida

### O que não funcionou

- Itens que dificultaram a resolução

### Action Items

| Ação | Responsável | Prazo | Status |
|------|-------------|-------|--------|
| Item 1 | Pessoa | Data | Pendente |
| Item 2 | Pessoa | Data | Pendente |

### Lições Aprendidas

- Lição 1
- Lição 2

---

## Comandos Úteis para Diagnóstico Rápido

```bash
# Status geral do cluster
bash scripts/status.sh

# Logs da aplicação
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -f --tail=100

# Eventos recentes
kubectl get events -n reliabilitylab --sort-by='.lastTimestamp' | head -20

# Uso de recursos
kubectl top pods -n reliabilitylab
kubectl top nodes

# Health check direto
kubectl exec -n reliabilitylab \
    $(kubectl get pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].metadata.name}') \
    -- python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/api/health').read().decode())"

# Rollback rápido
kubectl rollout undo deployment/site-kubectl -n reliabilitylab
```
