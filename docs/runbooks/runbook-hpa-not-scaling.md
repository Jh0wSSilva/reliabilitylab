# Runbook — HPA Não Escalando

## Alerta

```
Observação: Não há alerta padrão para HPA broken.
Detectado via: kubectl get hpa mostrando TARGETS como <unknown>/70%
Ou: carga alta sem aumento de réplicas.
```

## Impacto no Usuário

Sem auto-scaling, o serviço opera com réplicas fixas. Sob carga crescente:
- Latência aumenta progressivamente
- Timeouts começam quando pods saturam
- Potencial indisponibilidade total se carga exceder capacidade fixa

## Diagnóstico (< 2 minutos)

### 1. Verificar estado do HPA

```bash
kubectl get hpa -n production

# Saída esperada (funcionando):
# NAME          REFERENCE           TARGETS   MINPODS   MAXPODS   REPLICAS
# content-api   Deployment/...      23%/70%   2         10        2

# Saída de problema:
# NAME          REFERENCE           TARGETS       MINPODS   MAXPODS   REPLICAS
# content-api   Deployment/...      <unknown>/70% 2         10        2
```

### 2. Descrever o HPA para ver eventos

```bash
kubectl describe hpa content-api -n production
```

**Procure por estas mensagens:**
- `unable to get metrics for resource cpu` → metrics-server com problema
- `missing request for cpu` → deployment sem `requests.cpu` definido
- `the HPA controller was unable to get the target's current scale` → deployment não encontrado

### 3. Verificar metrics-server

```bash
# Metrics-server está rodando?
kubectl get pods -n kube-system | grep metrics-server

# Métricas disponíveis?
kubectl top pods -n production
kubectl top nodes

# Se "error: Metrics API not available":
minikube addons enable metrics-server -p reliabilitylab
```

### 4. Verificar requests no deployment

```bash
# HPA requer requests.cpu definido para calcular porcentagem
kubectl get deployment content-api -n production -o jsonpath='{.spec.template.spec.containers[*].resources.requests}'
```

**HPA calcula:** `current_cpu_usage / requests.cpu × 100%`

Se `requests.cpu` não está definido → HPA não consegue calcular → mostra `<unknown>`.

### 5. Verificar ResourceQuota

```bash
# Quota pode estar impedindo criação de novos pods
kubectl describe quota -n production

# Se "pods" ou "limits.cpu" estiver no limite, HPA não consegue escalar
```

### 6. Verificar se metrics-server tem dados recentes

```bash
# Pode levar 60-90s após restart para métricas estarem disponíveis
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | head -20
```

## Mitigação Imediata (< 5 minutos)

### Se metrics-server não está rodando

```bash
minikube addons enable metrics-server -p reliabilitylab

# Aguardar métricas ficarem disponíveis (~90s)
sleep 90
kubectl top pods -n production
```

### Se requests.cpu não está definido

```bash
# Adicionar requests ao deployment
kubectl set resources deployment/content-api -n production \
  --requests=cpu=50m,memory=64Mi
```

### Se quota impedindo scaling

```bash
# Verificar utilização
kubectl describe quota production-quota -n production

# Se necessário, aumentar quota temporariamente
kubectl patch quota production-quota -n production \
  --type='json' -p='[{"op": "replace", "path": "/spec/hard/pods", "value": "50"}]'
```

### Se HPA precisa de scale emergencial

```bash
# Scale manual enquanto HPA não funciona
kubectl scale deployment/content-api -n production --replicas=6
```

## Mitigação Definitiva

1. Garantir que todos os deployments tenham `resources.requests.cpu` definido
2. Garantir que `LimitRange` injeta defaults para pods sem requests (já configurado em `production-limitrange.yaml`)
3. Verificar que metrics-server addon está na lista de addons habilitados no `bootstrap.sh`
4. Adicionar alerta customizado para HPA em estado `<unknown>` por mais de 5 minutos
5. Atualizar o deployment YAML no Git

## Quando Escalar

- **Senior on-call:** quando HPA não funciona e scale manual também falha (quota/resources)
- **Platform team:** quando metrics-server está rodando mas não reporta métricas (possível problema com API aggregation)

## Referências

- [Kubernetes — HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- TROUBLESHOOTING.md — P7 (HPA não escala)
