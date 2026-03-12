# Tutorial 06 — Autoscaling com HPA

## Objetivo

Configurar o **HorizontalPodAutoscaler (HPA)** para escalar automaticamente a aplicação baseado no uso de CPU e memória.

## Conceitos

- **HPA (HorizontalPodAutoscaler)**: recurso do Kubernetes que ajusta automaticamente o número de réplicas de um Deployment
- **Metrics Server**: componente que coleta métricas de CPU e memória dos pods
- **Scale-up**: aumentar réplicas quando o uso de recursos está alto
- **Scale-down**: reduzir réplicas quando o uso normaliza
- **Stabilization Window**: período de espera antes de escalar para evitar flapping

## Pré-requisitos

- Cluster Kubernetes com **Metrics Server** instalado (Tutorial 03)
- Aplicação deployada (Tutorial 04)

## Passo a Passo

### 1. Verificar Metrics Server

```bash
kubectl top nodes
kubectl top pods -n reliabilitylab
```

Se retornar métricas, o Metrics Server está funcionando.

### 2. Aplicar o HPA

```bash
bash scripts/deploy-platform.sh
```

Ou aplicar individualmente:
```bash
kubectl apply -f platform/hpa.yaml
```

### 3. Verificar o HPA

```bash
kubectl get hpa -n reliabilitylab
```

**Resultado esperado:**
```
NAME           REFERENCE                TARGETS          MINPODS   MAXPODS   REPLICAS
site-kubectl   Deployment/site-kubectl  10%/70%, 5%/80%  2         6         2
```

### 4. Entender a configuração

O arquivo `platform/hpa.yaml` define:

| Parâmetro | Valor | Significado |
|-----------|-------|-------------|
| `minReplicas` | 2 | Mínimo de 2 pods sempre rodando |
| `maxReplicas` | 6 | Máximo de 6 pods em pico |
| CPU target | 70% | Escala quando CPU média > 70% |
| Memória target | 80% | Escala quando memória média > 80% |
| Scale-down window | 300s | Espera 5 minutos antes de reduzir |
| Scale-up window | 30s | Escala rápido em caso de necessidade |

### 5. Gerar carga para testar o HPA

Em um terminal, observe o HPA:
```bash
kubectl get hpa -n reliabilitylab -w
```

Em outro terminal, gere carga:
```bash
# Opção 1: loop simples com curl
while true; do
    curl -s http://site-kubectl.local/api/health > /dev/null
    curl -s http://site-kubectl.local/ > /dev/null
    curl -s http://site-kubectl.local/docker > /dev/null
done

# Opção 2: usar k6 (se instalado)
bash scripts/run-load-test.sh stress
```

### 6. Observar o scaling

```bash
# Ver réplicas aumentando
kubectl get pods -n reliabilitylab -w

# Ver eventos do HPA
kubectl describe hpa site-kubectl -n reliabilitylab
```

**Comportamento esperado:**
1. Carga aumenta → CPU dos pods sobe acima de 70%
2. HPA detecta (a cada 15s por padrão)
3. HPA cria novos pods (até maxReplicas=6)
4. Carga para → CPU normaliza
5. Após 5 minutos (stabilization), HPA remove pods extras

### 7. Observar no Grafana

Se a stack de observabilidade está instalada (Tutorial 05):
1. Abrir Grafana: http://localhost:3000
2. Dashboard: **Kubernetes / Compute Resources / Namespace (Pods)**
3. Observar CPU e memória mudando em tempo real

## PodDisruptionBudget (PDB)

O PDB garante disponibilidade mínima durante disrupções:

```bash
kubectl get pdb -n reliabilitylab

# Resultado:
# NAME               MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
# site-kubectl-pdb   1               N/A               1
```

Isso significa que durante atualizações ou manutenção dos nós, pelo menos 1 pod sempre estará disponível.

## Troubleshooting

| Problema | Solução |
|----------|---------|
| HPA mostra `<unknown>/70%` | Metrics Server não está funcionando. Instale ou verifique |
| Pods não escalam | Verifique se há recursos no cluster (`kubectl describe node`) |
| Scale-down muito lento | É por design (5 min de stabilization). Ajuste em `behavior.scaleDown` |
| CPU sempre baixa | A aplicação é leve; gere mais carga simultânea |

## Próximo Tutorial

[07 — Segurança de Rede com NetworkPolicy](07-seguranca-rede-networkpolicy.md)
