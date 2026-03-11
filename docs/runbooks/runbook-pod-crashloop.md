# Runbook — Pod CrashLooping

## Alerta

```
Alert: KubePodCrashLooping
Severity: warning
Labels:
  namespace: <namespace>
  pod: <pod_name>
  container: <container_name>
```

## Impacto no Usuário

O pod está em ciclo de crash e restart. Dependendo do número de réplicas disponíveis:
- **Todas as réplicas em CrashLoop:** serviço completamente indisponível
- **Algumas réplicas em CrashLoop:** degradação de capacidade, aumento de latência nos pods saudáveis
- **Uma réplica em CrashLoop:** impacto mínimo se HPA mantiver réplicas suficientes

## Diagnóstico (< 2 minutos)

### 1. Estado atual do pod

```bash
# Ver status e restart count
kubectl get pods -n production -l app=content-api

# Detalhes do pod — procure por exit codes e estados
kubectl describe pod <POD_NAME> -n production
```

**Exit codes comuns:**
| Code | Significado | Causa usual |
|------|------------|-------------|
| 0 | Sucesso (saiu voluntariamente) | Configuração errada, comando único |
| 1 | Erro genérico da aplicação | Bug no código, dependência ausente |
| 137 | OOMKilled (SIGKILL) | Limite de memória insuficiente |
| 139 | Segmentation fault | Bug de código, corrupção de memória |
| 143 | SIGTERM (graceful shutdown) | Preemption, eviction |

### 2. Logs do container

```bash
# Logs do container atual (se ainda rodando)
kubectl logs <POD_NAME> -n production -c <CONTAINER_NAME>

# Logs do crash anterior
kubectl logs <POD_NAME> -n production -c <CONTAINER_NAME> --previous

# Últimos 100 linhas de todos os pods do deployment
kubectl logs -n production -l app=content-api --tail=100 --all-containers
```

### 3. Verificar eventos

```bash
kubectl get events -n production --field-selector involvedObject.name=<POD_NAME> --sort-by='.metadata.creationTimestamp'
```

### 4. Verificar recursos

```bash
# Pod está sendo OOMKilled?
kubectl describe pod <POD_NAME> -n production | grep -A5 "Last State:"

# Verificar requests/limits
kubectl get pod <POD_NAME> -n production -o jsonpath='{.spec.containers[*].resources}'

# Verificar ResourceQuota do namespace
kubectl describe quota -n production
```

### 5. Verificar probes

```bash
# Probes estão falhando?
kubectl describe pod <POD_NAME> -n production | grep -A10 "Liveness:\|Readiness:"

# Testar endpoint manualmente
kubectl exec <POD_NAME> -n production -- wget -qO- http://localhost:80/ 2>&1 || echo "FAILED"
```

## Mitigação Imediata (< 5 minutos)

### Se OOMKilled (exit code 137)

```bash
# Aumentar limite de memória temporariamente
kubectl set resources deployment/content-api -n production \
  --limits=memory=512Mi
```

### Se deploy recente causou o crash

```bash
# Rollback
kubectl rollout undo deployment/content-api -n production

# Confirmar que está estável
kubectl rollout status deployment/content-api -n production
```

### Se probe está falhando

```bash
# Verificar se o endpoint responde
kubectl port-forward <POD_NAME> -n production 8080:9898
curl -v http://localhost:8080/

# Se a aplicação precisa de mais tempo para iniciar:
kubectl patch deployment content-api -n production \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value": 60}]'
```

### Se ConfigMap/Secret incorreto

```bash
# Verificar variáveis de ambiente
kubectl exec <POD_NAME> -n production -- env

# Verificar mounts de ConfigMap/Secret
kubectl describe pod <POD_NAME> -n production | grep -A5 "Mounts:"
```

## Mitigação Definitiva

1. Analisar root cause nos logs (antes e depois do crash)
2. Se OOMKilled: profile de memória do serviço, ajustar limits de forma permanente no YAML
3. Se bug de código: fix no código, PR com teste que reproduz o cenário
4. Se probe incorreta: ajustar thresholds e paths no deployment manifest
5. Atualizar o deployment YAML no Git — ArgoCD sincroniza automaticamente

## Quando Escalar

- **Senior on-call:** quando todas as réplicas estão em CrashLoop e rollback não resolve
- **Service owner:** quando o crash é causado por bug de código (não infra)
- **Platform team:** quando o crash é causado por problema sistêmico (OOM em todos os nós, etcd instável)

## Referências

- [Kubernetes — Debug CrashLoopBackOff](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- TROUBLESHOOTING.md
