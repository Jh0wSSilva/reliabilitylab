# Runbook — Node Under Pressure

## Alerta

```
Alert: KubeNodeNotReady / NodeMemoryPressure / NodeDiskPressure
Severity: warning → critical (se nó fica NotReady)
Labels:
  node: <node_name>
  condition: <MemoryPressure|DiskPressure|PIDPressure>
```

## Impacto no Usuário

- **MemoryPressure:** Kubelet começa a evictar pods por ordem de prioridade. Pods sem PriorityClass são os primeiros. Serviços podem ficar com menos réplicas que o mínimo do HPA.
- **DiskPressure:** Kubelet para de aceitar novos pods no nó. Imagens não são pulled. Logs podem parar de ser escritos.
- **NotReady:** Nó é removido do scheduling. Pods são re-schedulados para outros nós (se houver capacidade). Se todos os nós ficarem NotReady → cluster indisponível.

## Diagnóstico (< 2 minutos)

### 1. Estado dos nós

```bash
kubectl get nodes
kubectl describe node <NODE_NAME> | grep -A10 "Conditions:"
```

### 2. Uso de recursos por nó

```bash
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory | head -20
```

### 3. Verificar pressão de memória

```bash
# Pods consumindo mais memória no nó afetado
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<NODE_NAME> \
  --sort-by='.status.containerStatuses[0].restartCount'

# Verificar OOMKills recentes
kubectl get events --all-namespaces --field-selector reason=OOMKilling --sort-by='.metadata.creationTimestamp' | tail -10
```

### 4. Verificar pressão de disco

```bash
# No Minikube, acessar o nó diretamente
minikube ssh -p reliabilitylab -n <NODE_NAME> -- df -h

# Verificar uso de disco por imagens Docker
minikube ssh -p reliabilitylab -n <NODE_NAME> -- crictl images | sort -k4 -h -r | head -10
```

### 5. Verificar evictions

```bash
kubectl get events --all-namespaces --field-selector reason=Evicted --sort-by='.metadata.creationTimestamp' | tail -10

# Pods evictados ficam em status Evicted
kubectl get pods --all-namespaces --field-selector status.phase=Failed | grep Evicted
```

## Mitigação Imediata (< 5 minutos)

### Se MemoryPressure

```bash
# Identificar pods com maior consumo no nó afetado
kubectl top pods --all-namespaces --sort-by=memory | head -10

# Se há chaos experiments rodando, parar imediatamente
kubectl delete podchaos --all -n chaos-mesh 2>/dev/null
kubectl delete stresschaos --all -n chaos-mesh 2>/dev/null

# Limpar pods evictados
kubectl get pods --all-namespaces --field-selector status.phase=Failed | grep Evicted | \
  awk '{print "kubectl delete pod " $2 " -n " $1}' | sh
```

### Se DiskPressure

```bash
# Limpar imagens não utilizadas
minikube ssh -p reliabilitylab -n <NODE_NAME> -- sudo crictl rmi --prune

# Limpar containers parados
minikube ssh -p reliabilitylab -n <NODE_NAME> -- sudo crictl rm $(sudo crictl ps -a -q --state exited)
```

### Se nó NotReady

```bash
# Verificar se o nó está acessível
minikube ssh -p reliabilitylab -n <NODE_NAME> -- uptime

# Se o nó não responde, restart
# ATENÇÃO: isso vai causar re-scheduling de todos os pods no nó
minikube node stop <NODE_NAME> -p reliabilitylab
minikube node start <NODE_NAME> -p reliabilitylab

# Se Minikube está instável como um todo
minikube stop -p reliabilitylab
minikube start -p reliabilitylab
```

## Mitigação Definitiva

1. Se ocorre frequentemente: aumentar `--memory` do Minikube (4096 → 6144)
2. Rever `resources.limits` dos deployments — pode estar permitindo consumo excessivo
3. Adicionar `PodDisruptionBudget` para garantir mínimo de pods disponíveis durante evictions
4. Configurar `eviction-hard` thresholds no kubelet se o default for agressivo demais
5. Para DiskPressure: configurar garbage collection de imagens mais agressivo

## Quando Escalar

- **Senior on-call:** quando múltiplos nós estão em NotReady simultaneamente
- **Platform team:** quando o problema persiste após restart dos nós — pode indicar recursos insuficientes para o stack instalado
- **Todo o time:** se o cluster Minikube precisa ser recriado — executar `scripts/bootstrap.sh` para restaurar

## Referências

- [Kubernetes — Node Pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- TROUBLESHOOTING.md — P5 (Cluster instável com 2GB)
- ADR-005 — Minikube com 3 nós e 4096MB
