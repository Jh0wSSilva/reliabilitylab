# Tutorial 17 — Pipeline de Testes de Resiliência

## Objetivo

Neste tutorial você vai aprender a:
- Executar o **pipeline automatizado** de testes de resiliência
- Combinar **carga (k6) + chaos** em um fluxo integrado
- Validar **SLOs automaticamente** após os testes
- Interpretar os relatórios gerados

## Pré-requisitos

- Tutoriais 13-16 concluídos
- k6 instalado localmente (`brew install k6` ou `apt install k6`)
- Cluster com site-kubectl, Prometheus e Alertmanager

## Conceitos

### Pipeline de Resiliência

O pipeline segue 5 etapas:

```
1. Pré-requisitos  →  2. Smoke Test  →  3. Chaos + Carga  →  4. Validar SLOs  →  5. Relatório
```

Cada etapa valida o estado antes de prosseguir:
- **Pré-requisitos:** kubectl, k6, cluster acessível, pods Running
- **Smoke Test:** confirma que o serviço responde antes do chaos
- **Chaos + Carga:** injeta falhas ENQUANTO carga está sendo gerada
- **Validar SLOs:** verifica pods, restarts, alertas ativos
- **Relatório:** salva resultados em `results/`

### Cenários Disponíveis

| Cenário | Descrição |
|---------|-----------|
| `all` | Todos os cenários em sequência (padrão) |
| `pod-kill` | Eliminação total de pods |
| `network` | Partição de rede |
| `resource` | Exaustão de CPU/memória |
| `quick` | Teste rápido (pod-kill com duração curta) |

## Passo a Passo

### Passo 1: Verificar pré-requisitos

```bash
# Verificar kubectl
kubectl cluster-info

# Verificar k6
k6 version

# Verificar pods
kubectl get pods -n reliabilitylab -l app=site-kubectl
```

### Passo 2: Executar teste rápido (quick)

Para um primeiro teste, use o cenário `quick` que executa apenas o pod-kill
com duração reduzida:

```bash
./scripts/run-resilience-tests.sh quick
```

O pipeline vai:
1. Verificar pré-requisitos ✓
2. Executar smoke test (30s) ✓
3. Iniciar k6 em background + deletar todos os pods
4. Monitorar recuperação por 2 minutos
5. Validar SLOs (pods Running, restarts, alertas)
6. Gerar relatório

### Passo 3: Executar cenário individual

Teste cada cenário separadamente:

```bash
# Cenário: Eliminação Total de Pods
./scripts/run-resilience-tests.sh pod-kill

# Cenário: Partição de Rede
CHAOS_DURATION=45 ./scripts/run-resilience-tests.sh network

# Cenário: Exaustão de Recursos
LOAD_DURATION=5m ./scripts/run-resilience-tests.sh resource
```

### Passo 4: Executar pipeline completo

Execute todos os cenários em sequência (com 60s de intervalo entre eles):

```bash
./scripts/run-resilience-tests.sh all
```

> **Nota:** O pipeline completo leva aproximadamente 15-20 minutos.

### Passo 5: Configurar variáveis de ambiente

Personalize a execução:

```bash
# URL do serviço
export BASE_URL=http://site-kubectl.local

# Namespace
export NAMESPACE=reliabilitylab

# Duração do chaos
export CHAOS_DURATION=90

# Duração da carga k6
export LOAD_DURATION=5m

# Executar
./scripts/run-resilience-tests.sh all
```

### Passo 6: Analisar relatórios

Os resultados são salvos em `results/`:

```bash
# Listar resultados
ls -la results/

# Ver relatório do pipeline
cat results/resilience-*.log

# Ver relatório do k6 (se disponível)
cat results/k6-pod-kill-*.log
```

O relatório mostra:
- Timestamp de cada etapa
- Estado dos pods antes e depois do chaos
- Validação de SLOs (PASS/FAIL)
- Número de restarts
- Alertas ativos no Prometheus

### Passo 7: Entender o teste de carga de resiliência

O k6 usa o script `load-testing/resilience-test.js` que:
- Gera **carga constante** (10 req/s) durante todo o teste
- Adiciona **picos periódicos** (30-40 req/s) para estressar
- Mede **error rate** e **latência** durante o chaos
- Valida contra thresholds SLO automaticamente:
  - Error rate < 1% (alerta), < 5% (crítico)
  - P95 < 500ms, P99 < 1000ms
- Gera relatório com resultado PASS/FAIL

Examine o script:

```bash
cat load-testing/resilience-test.js
```

## Verificação

Confirme que você consegue:

1. Executar o pipeline com `./scripts/run-resilience-tests.sh quick`
2. Interpretar o output do pipeline (etapas, PASS/FAIL)
3. Encontrar e ler os relatórios em `results/`
4. Executar cenários individuais com variáveis customizadas
5. Entender como k6 e chaos são combinados

## Próximo Tutorial

No [Tutorial 18](tutorial-18-continuous-reliability.md) vamos aprender a praticar
**confiabilidade contínua** com game days regulares.
