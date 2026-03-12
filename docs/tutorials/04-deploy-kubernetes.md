# Tutorial 04 — Deploy no Kubernetes

## Objetivo

Fazer o deploy da aplicação site-kubectl no cluster Kubernetes local usando manifests declarativos.

## Conceitos

- **Namespace**: isolamento lógico de recursos no cluster
- **Deployment**: define o estado desejado dos pods (réplicas, imagem, probes)
- **Service (ClusterIP)**: expõe o Deployment internamente no cluster
- **Ingress**: expõe o Service externamente via HTTP/HTTPS
- **ConfigMap**: armazena configurações não-sensíveis
- **Secret**: armazena dados sensíveis (tokens, senhas)
- **Probes**: verificações de saúde (readiness, liveness, startup)

## Pré-requisitos

- Cluster Kubernetes rodando (Tutorial 03)
- Imagem Docker construída (`bash scripts/build.sh`)

## Passo a Passo

### 1. Carregar a imagem no cluster

```bash
bash scripts/load-image.sh
```

### 2. Entender os manifests

Os arquivos ficam na pasta `k8s/`:

| Arquivo | Função |
|---------|--------|
| `namespace.yaml` | Cria o namespace `reliabilitylab` |
| `configmap.yaml` | Variáveis de configuração (APP_ENV, LOG_LEVEL, etc.) |
| `secret.yaml` | Valores sensíveis (APP_SECRET_KEY) |
| `deployment.yaml` | 2 réplicas com probes e security context |
| `service.yaml` | ClusterIP na porta 80 → targetPort 8000 |
| `ingress.yaml` | Acesso via `site-kubectl.local` |

### 3. Aplicar os manifests

```bash
bash scripts/deploy.sh
```

Ou manualmente:
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

### 4. Verificar o deploy

```bash
# Ver pods
kubectl get pods -n reliabilitylab

# Resultado esperado:
# NAME                            READY   STATUS    RESTARTS   AGE
# site-kubectl-xxxxxxxxx-xxxxx   1/1     Running   0          30s
# site-kubectl-xxxxxxxxx-yyyyy   1/1     Running   0          30s

# Ver service
kubectl get svc -n reliabilitylab

# Ver ingress
kubectl get ingress -n reliabilitylab
```

### 5. Testar a aplicação

```bash
# Via Ingress
curl http://site-kubectl.local/api/health

# Resultado esperado:
# {"status":"ok","message":"App is running normally"}

# Se o Ingress não está pronto, usar port-forward:
kubectl port-forward svc/site-kubectl -n reliabilitylab 8080:80
curl http://localhost:8080/api/health
```

### 6. Ver logs

```bash
kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -f --tail=50
```

### 7. Explorar o Deployment

```bash
# Ver detalhes
kubectl describe deployment site-kubectl -n reliabilitylab

# Observar as probes:
# - readinessProbe: verifica se o pod está pronto para tráfego
# - livenessProbe: reinicia o pod se parar de responder
# - startupProbe: protege durante inicialização lenta
```

## Recursos de Segurança Aplicados

O Deployment inclui `securityContext`:

```yaml
securityContext:
  allowPrivilegeEscalation: false  # Não permite escalada de privilégio
  readOnlyRootFilesystem: false    # Permite escrita (necessário para FastAPI)
  runAsNonRoot: true               # Bloqueia execução como root
  runAsUser: 10001                 # UID do appuser
  capabilities:
    drop: [ALL]                    # Remove todas as capabilities Linux
```

## Atualizar a Aplicação

```bash
# 1. Rebuildar a imagem
bash scripts/build.sh

# 2. Recarregar no cluster
bash scripts/load-image.sh

# 3. Reiniciar o deployment
kubectl rollout restart deployment/site-kubectl -n reliabilitylab

# 4. Acompanhar o rollout
kubectl rollout status deployment/site-kubectl -n reliabilitylab
```

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `ImagePullBackOff` | A imagem não foi carregada no cluster. Execute `bash scripts/load-image.sh` |
| `CrashLoopBackOff` | Verifique logs: `kubectl logs -n reliabilitylab -l app.kubernetes.io/name=site-kubectl` |
| Ingress retorna 502 | Pods não estão ready. Verifique as probes |
| `0/3 nodes are available` | Verifique se os nós estão Ready: `kubectl get nodes` |

## Próximo Tutorial

[05 — Observabilidade com Prometheus e Grafana](05-observabilidade-prometheus-grafana.md)
