# Tutorial 08 — Chaos Engineering

## Objetivo

Introduzir **Chaos Engineering** — a prática de provocar falhas controladas para testar a resiliência do sistema.

## Conceitos

- **Chaos Engineering**: disciplina de experimentação em sistemas distribuídos para construir confiança na resiliência
- **Blast radius**: escopo do impacto de um experimento
- **Steady state**: comportamento normal do sistema antes do experimento
- **Hipótese**: o que esperamos que aconteça durante o experimento

## Princípios do Chaos Engineering

1. **Defina um estado estável** (steady state) — ex: health check retorna 200
2. **Formule uma hipótese** — ex: "se um pod morrer, o serviço continua respondendo"
3. **Introduza variáveis do mundo real** — ex: deletar um pod, injetar latência
4. **Tente refutar a hipótese** — observe se o sistema se comportou como esperado
5. **Minimize o blast radius** — comece com experimentos pequenos

## Pré-requisitos

- Cluster rodando com aplicação deployada (Tutorial 04)
- Stack de observabilidade instalada (Tutorial 05) — recomendada para observar efeitos

## Experimentos Disponíveis

| Experimento | Arquivo | O que faz |
|-------------|---------|-----------|
| Deleção de Pod | `chaos/pod-delete.yaml` | Deleta um pod aleatoriamente |
| Stress de CPU | `chaos/pod-cpu-stress.yaml` | Consome CPU por 60 segundos |
| Stress de Memória | `chaos/pod-memory-stress.yaml` | Consome 256MB de memória |
| Latência de Rede | `chaos/pod-network-latency.yaml` | Testa baseline de latência |

## Experimento 1: Deleção de Pod

### Hipótese
> Com 2 réplicas, se um pod for deletado, o serviço continua respondendo. O Deployment cria um novo pod automaticamente.

### Observar steady state

```bash
# Verificar que tudo está funcionando
curl http://site-kubectl.local/api/health
kubectl get pods -n reliabilitylab
```

### Executar o experimento

```bash
# Opção A: usar o Job de chaos
kubectl apply -f chaos/pod-delete.yaml

# Opção B: deletar manualmente
kubectl delete pod -n reliabilitylab \
    $(kubectl get pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].metadata.name}') \
    --grace-period=0 --force
```

### Observar

```bash
# Observar pods em tempo real (em outro terminal)
kubectl get pods -n reliabilitylab -w

# Verificar se o serviço continua respondendo
curl http://site-kubectl.local/api/health

# Ver eventos
kubectl get events -n reliabilitylab --sort-by='.lastTimestamp' | head -10
```

### Resultado esperado
- O pod é deletado
- O Deployment detecta e cria um novo pod
- O Service redireciona para o pod restante enquanto o novo inicia
- A aplicação **NÃO fica indisponível** (porque temos 2 réplicas)

### Limpar
```bash
kubectl delete -f chaos/pod-delete.yaml --ignore-not-found
```

## Experimento 2: Stress de CPU

### Hipótese
> Sob stress de CPU, o HPA deve escalar automaticamente a aplicação.

### Executar

```bash
kubectl apply -f chaos/pod-cpu-stress.yaml
```

### Observar

```bash
# Em terminais separados:

# Terminal 1: observar HPA
kubectl get hpa -n reliabilitylab -w

# Terminal 2: observar pods
kubectl get pods -n reliabilitylab -w

# Terminal 3: uso de CPU
kubectl top pods -n reliabilitylab
```

### Resultado esperado
- Container de stress consome CPU por 60 segundos
- Se o HPA está configurado, pode escalar réplicas
- Métricas de CPU visíveis no Grafana

### Limpar
```bash
kubectl delete -f chaos/pod-cpu-stress.yaml --ignore-not-found
```

## Experimento 3: Stress de Memória

### Hipótese
> Se um container consome memória além do limit, o Kubernetes mata o container (OOMKilled).

### Executar

```bash
kubectl apply -f chaos/pod-memory-stress.yaml
```

### Observar

```bash
# Ver status do pod de stress
kubectl get pods -n reliabilitylab -l chaos-experiment=memory-stress -w

# Verificar evento de OOM
kubectl get events -n reliabilitylab --field-selector reason=OOMKilled
```

### Resultado esperado
- O container consome memória até o limit (512Mi)
- Se ultrapassar, o Kubernetes mata o container com reason `OOMKilled`
- O Job não reinicia (restartPolicy: Never)

### Limpar
```bash
kubectl delete -f chaos/pod-memory-stress.yaml --ignore-not-found
```

## Experimento 4: Latência de Rede

### Executar

```bash
kubectl apply -f chaos/pod-network-latency.yaml
```

Esse experimento mede a latência baseline para futuras comparações.

### Limpar
```bash
kubectl delete -f chaos/pod-network-latency.yaml --ignore-not-found
```

## Usando o Script de Chaos

```bash
# Listar experimentos disponíveis
bash scripts/run-chaos.sh list

# Aplicar um experimento
bash scripts/run-chaos.sh apply pod-delete

# Remover um experimento
bash scripts/run-chaos.sh delete pod-delete
```

## Evolução: LitmusChaos

Para experimentos mais avançados, instale o **LitmusChaos**:

```bash
bash scripts/run-chaos.sh install-litmus
```

LitmusChaos oferece:
- Catálogo extenso de experimentos pré-definidos
- Interface web (ChaosCenter)
- Workflows de chaos automatizados
- Relatórios detalhados

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Job falhando com `Forbidden` | Aplique o RBAC: `kubectl apply -f chaos/pod-delete.yaml` (inclui ServiceAccount e Role) |
| Pod de stress não inicia | Verifique se a imagem `containerstack/alpine-stress` está acessível |
| Serviço ficou indisponível | Com 1 réplica, isso é esperado. Aumente para 2+ réplicas |

## Próximo Tutorial

[09 — Load Testing com k6](09-load-testing-k6.md)
