# Tutorial 11 — GitOps com ArgoCD

## Objetivo

Implementar **GitOps** com **ArgoCD** para gerenciar deployments de forma declarativa — toda mudança no cluster vem de um commit no Git.

## Conceitos

- **GitOps**: paradigma onde o Git é a única fonte de verdade para o estado do cluster
- **ArgoCD**: ferramenta de entrega contínua para Kubernetes que segue os princípios GitOps
- **Sync**: processo de reconciliar o estado do cluster com o estado do Git
- **Self-heal**: corrigir automaticamente quando alguém altera algo diretamente no cluster
- **Auto-prune**: remover recursos que foram deletados do Git

## Princípios GitOps

1. **Declarativo**: toda a infraestrutura descrita em YAML no Git
2. **Versionado**: histórico completo de mudanças via commits
3. **Automático**: mudanças são aplicadas automaticamente
4. **Self-healing**: o estado real sempre converge para o estado desejado

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| Helm | 3.12+ | `helm version` |
| Git | 2.0+ | `git --version` |
| Cluster | Rodando | `kubectl get nodes` |

## Passo a Passo

### 1. Instalar ArgoCD

```bash
bash scripts/deploy-argocd.sh
```

O script instala:
- ArgoCD v2.13.3 via Helm
- Cria o namespace `argocd`
- Aplica a Application que monitora este repositório

### 2. Verificar instalação

```bash
kubectl get pods -n argocd
```

**Resultado esperado:**
```
NAME                                               READY   STATUS
argocd-application-controller-0                   1/1     Running
argocd-dex-server-xxxxxxxxx-xxxxx                1/1     Running
argocd-redis-xxxxxxxxx-xxxxx                     1/1     Running
argocd-repo-server-xxxxxxxxx-xxxxx               1/1     Running
argocd-server-xxxxxxxxx-xxxxx                    1/1     Running
```

### 3. Acessar a UI do ArgoCD

```bash
# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Abra: https://localhost:8443

### 4. Obter senha do admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d; echo
```

- **Usuário:** admin
- **Senha:** (resultado do comando acima)

### 5. Entender a Application

O arquivo `gitops/argocd/application.yaml` define:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: reliabilitylab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Jh0wSSilva/reliabilitylab.git
    targetRevision: main           # ← branch monitorado
    path: k8s                       # ← pasta dos manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: reliabilitylab
  syncPolicy:
    automated:
      prune: true        # Remove recursos deletados do Git
      selfHeal: true     # Corrige drift automático
    syncOptions:
      - CreateNamespace=true
```

### 6. Verificar o estado da Application

```bash
# Via kubectl
kubectl get application -n argocd

# Resultado esperado:
# NAME              SYNC STATUS   HEALTH STATUS
# reliabilitylab   Synced         Healthy
```

### 7. Testar o self-healing

Simule alguém fazendo uma mudança "manual" no cluster:

```bash
# Escalar manualmente para 5 réplicas
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=5

# Observar (ArgoCD vai REVERTER para 2 réplicas em ~3 minutos)
kubectl get pods -n reliabilitylab -w
```

O ArgoCD detecta que o estado real (5 réplicas) difere do Git (2 réplicas) e corrige automaticamente.

### 8. Testar o GitOps flow

Para fazer uma mudança via GitOps:

```bash
# 1. Editar o manifest localmente
# Exemplo: mudar réplicas de 2 para 3 no k8s/deployment.yaml

# 2. Commit e push
git add k8s/deployment.yaml
git commit -m "scale: increase replicas to 3"
git push origin main

# 3. ArgoCD detecta e aplica automaticamente
# Ou forçar sync:
kubectl exec -n argocd deploy/argocd-server -- argocd app sync reliabilitylab --insecure
```

### 9. Ver histórico de sync

Na UI do ArgoCD:
1. Clicar na Application `reliabilitylab`
2. Aba **History** — mostra todos os syncs
3. Aba **Diff** — mostra mudanças entre Git e cluster

## Fluxo GitOps Completo

```
         ┌──────────┐
         │Developer  │
         └─────┬────┘
               │ git push
         ┌─────▼────┐
         │  GitHub   │
         │  (main)   │
         └─────┬────┘
               │ poll (3min)
         ┌─────▼────┐
         │  ArgoCD   │
         │  Server   │
         └─────┬────┘
               │ kubectl apply
         ┌─────▼────────────────┐
         │  Kubernetes Cluster   │
         │  (reliabilitylab)     │
         └──────────────────────┘
```

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Application "OutOfSync" | Verifique diffs na UI ou force sync |
| "ComparisonError" | Repo pode não estar acessível. Verifique URL e acesso |
| Self-heal não funciona | Verifique se `selfHeal: true` está na syncPolicy |
| Senha expirou | `kubectl -n argocd delete secret argocd-initial-admin-secret` e reinicie |
| UI não carrega | Verifique se o pod `argocd-server` está running |

## Próximo Tutorial

[12 — Simulação de Resposta a Incidentes](12-simulacao-resposta-incidentes.md)
