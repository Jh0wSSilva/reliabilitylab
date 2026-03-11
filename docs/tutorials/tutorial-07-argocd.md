# Tutorial 07 — GitOps com ArgoCD

**Objetivo:** Instalar o ArgoCD e configurar deploy declarativo (GitOps) para o content-api apontando para o repositório GitHub.

**Resultado:** ArgoCD rodando, Application configurada, self-heal testado — qualquer mudança manual no cluster é automaticamente revertida pelo ArgoCD.

**Tempo estimado:** 25 minutos

**Pré-requisitos:** Tutorial 06 completo com health check verde, cluster estável com 4096MB RAM por nó

---

## Contexto

Existem ferramentas pesadas de CD (continuous delivery) que oferecem canary analysis, rollback automático e multi-cloud, mas requerem múltiplos microserviços próprios para funcionar.

O **ArgoCD** é a alternativa GitOps mais popular: ele monitora um repositório Git e garante que o estado do cluster Kubernetes é **idêntico** ao que está no Git. Se alguém fizer um `kubectl edit` diretamente no cluster, o ArgoCD reverte automaticamente (self-heal). Isso é o princípio do GitOps: **Git é a single source of truth.**

O ArgoCD é amplamente adotado como padrão para deploy em Kubernetes na indústria.

> **⚠️ TIMING IMPORTANTE:** Instale o ArgoCD somente após o cluster estar estável com todo o stack rodando. Com `--memory=2048`, o cluster não tem recursos suficientes para ArgoCD + Prometheus + Chaos Mesh simultaneamente, causando timeout no redis-secret-init job (P6). Com `--memory=4096` o problema desaparece.

---

## Passo 1 — Instalar ArgoCD

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.3/manifests/install.yaml
```

Aguardar todos os pods ficarem Ready:

```bash
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

✅ Esperado:
```
pod/argocd-application-controller-0 condition met
pod/argocd-dex-server-xxxxx-yyyyy condition met
pod/argocd-redis-xxxxx-yyyyy condition met
pod/argocd-repo-server-xxxxx-yyyyy condition met
pod/argocd-server-xxxxx-yyyyy condition met
```

Verificar:

```bash
kubectl get pods -n argocd
```

✅ Esperado: 5-7 pods Running com 0 restarts.

---

## Passo 2 — Expor o ArgoCD via NodePort

No Minikube, precisamos de NodePort para acessar o ArgoCD server:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
```

✅ Esperado: `service/argocd-server patched`

Obter a URL:

```bash
minikube service argocd-server -n argocd -p reliabilitylab --url
```

✅ Esperado: URL como `http://192.168.49.2:3XXXX`

---

## Passo 3 — Obter a senha inicial do admin

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

✅ Esperado: string aleatória (ex: `aB3cD4eF5gH6`)

Credenciais:
- **Usuário:** `admin`
- **Senha:** output do comando acima

---

## Passo 4 — Instalar o CLI do ArgoCD (opcional)

```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/
```

Login via CLI:

```bash
ARGOCD_URL=$(minikube service argocd-server -n argocd -p reliabilitylab --url | head -1)
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)

argocd login "${ARGOCD_URL#http://}" --username admin --password "$ARGOCD_PASS" --insecure
```

✅ Esperado: `'admin:login' logged in successfully`

---

## Passo 5 — Criar Application para content-api

Crie o manifesto da Application:

```bash
cat <<'EOF' > gitops/apps/content-api-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: content-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Jh0wSSilva/reliabilitylab.git
    targetRevision: main
    path: k8s/namespaces
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=false
EOF
```

| Campo | Significado |
|-------|-------------|
| `source.repoURL` | Repositório Git monitorado |
| `source.path` | Pasta com os manifests YAML |
| `targetRevision: main` | Branch a seguir |
| `syncPolicy.automated.selfHeal: true` | **Self-heal:** reverte mudanças manuais no cluster |
| `syncPolicy.automated.prune: true` | Remove recursos que foram deletados do Git |

Aplicar:

```bash
kubectl apply -f gitops/apps/content-api-app.yaml
```

✅ Esperado: `application.argoproj.io/content-api created`

Verificar status:

```bash
kubectl get applications -n argocd
```

✅ Esperado:
```
NAME          SYNC STATUS   HEALTH STATUS
content-api   Synced        Healthy
```

---

## Passo 6 — Testar Self-Heal

O self-heal é a feature mais poderosa do GitOps: se alguém alterar algo diretamente no cluster (drift), o ArgoCD reverte automaticamente para o estado do Git.

Teste: mude as réplicas manualmente:

```bash
# Modificação manual (fora do Git)
kubectl scale deployment content-api -n production --replicas=5

# Verificar que escalou
kubectl get deployment content-api -n production
```

✅ Esperado temporário: `5/5` réplicas.

Aguarde 15-30 segundos:

```bash
# ArgoCD detecta o drift e reverte
kubectl get deployment content-api -n production
```

✅ Esperado: volta para `2/2` réplicas (o valor declarado no Git).

```bash
# Verificar no ArgoCD que o self-heal ocorreu
kubectl get applications content-api -n argocd -o jsonpath='{.status.sync.status}'
echo ""
```

✅ Esperado: `Synced`

---

## Passo 7 — Verificar sync via UI

Acesse a URL do ArgoCD no browser:

```bash
minikube service argocd-server -n argocd -p reliabilitylab
```

Na UI:
1. Veja a Application `content-api` com status **Synced** e **Healthy**
2. Clique nela para ver o grafo de recursos (Deployment → ReplicaSet → Pods)
3. Tente outro `kubectl scale` e observe o ArgoCD revertendo em tempo real

---

## Passo 8 — Workflow GitOps (como funciona em produção)

O fluxo correto com GitOps:

```
1. Desenvolvedor faz change no YAML → git push
2. ArgoCD detecta mudança no repositório
3. ArgoCD aplica mudança no cluster (sync)
4. Cluster sempre reflete o estado do Git
```

Para testar:
1. Edite `k8s/namespaces/content-api.yaml` localmente (ex: mude `replicas: 2` para `replicas: 3`)
2. Faça `git add`, `git commit`, `git push`
3. O ArgoCD detecta e sincroniza automaticamente (~3 minutos por padrão)
4. `kubectl get deployment content-api -n production` mostrará `3/3`

> Em produção, esse fluxo é combinado com Pull Requests + Code Review + CI/CD pipeline. Ninguém faz `kubectl apply` diretamente.

---

## Health Check (antes de avançar para Tutorial 08)

```bash
echo "=== HEALTH CHECK — Tutorial 07 ==="

echo -e "\n[1/4] ArgoCD pods (todos Running):"
NOT_RUNNING=$(kubectl get pods -n argocd --no-headers | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo "  ✅ Todos os pods Running"
else
  echo "  ❌ $NOT_RUNNING pods com problema"
  kubectl get pods -n argocd | grep -v Running | grep -v NAME
fi
echo ""

echo "[2/4] ArgoCD server acessível:"
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' | grep -q NodePort \
  && echo "  ✅ ArgoCD exposto via NodePort" || echo "  ❌ ArgoCD não está exposto"
echo ""

echo "[3/4] Application content-api:"
SYNC=$(kubectl get applications content-api -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
HEALTH=$(kubectl get applications content-api -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
echo "  Sync: $SYNC | Health: $HEALTH"
if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
  echo "  ✅ Application saudável"
else
  echo "  ❌ Application não está Synced+Healthy"
fi
echo ""

echo "[4/4] Self-heal ativo:"
SELF_HEAL=$(kubectl get applications content-api -n argocd -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null)
if [ "$SELF_HEAL" = "true" ]; then
  echo "  ✅ Self-heal habilitado"
else
  echo "  ❌ Self-heal desabilitado — verifique syncPolicy"
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| redis pod `Init:CrashLoopBackOff` ou `redis-secret-init` timeout | Cluster instável — falta de RAM (**P6**) | Recrie com `--memory=4096`. Instale ArgoCD somente após cluster estável |
| `argocd-initial-admin-secret` not found | Secret já foi deletado (ArgoCD >= 2.x auto-deletes) | `argocd admin initial-password -n argocd` ou reset: `kubectl -n argocd patch secret argocd-secret ...` |
| Application `OutOfSync` permanente | Helm hooks ou campos mutáveis | Adicione `syncOptions: [RespectIgnoreDifferences=true]` e configure `ignoreDifferences` |
| Application `Unknown`/`Missing` | Repositório não acessível | Se privado: configure SSH key. Se público: verifique URL e branch |
| Self-heal não reverte | `selfHeal: false` no syncPolicy | Corrija o Application manifest |
| ArgoCD server não abre (connection refused) | Service ainda é ClusterIP | `kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'` |
| `ERR_CERT_AUTHORITY_INVALID` no browser | ArgoCD usa TLS self-signed | Aceite o certificado ou use `--insecure` no CLI |

---

## Conceitos-chave

- **GitOps:** Git como single source of truth para o estado desejado da infraestrutura
- **Self-heal:** ArgoCD reverte automaticamente qualquer drift entre cluster e Git
- **Prune:** remove recursos do cluster que foram deletados do Git
- **Application:** CRD que define a relação Git repo ↔ cluster namespace
- Em ambientes maduros, canary analysis é feita via progressive delivery (Argo Rollouts)
- Em produção, nenhum `kubectl apply` direto é permitido — tudo passa pelo Git

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Configure o ArgoCD para sincronizar também os manifests de platform/slo/`
- `O ArgoCD mostra a Application como OutOfSync. Diagnostique o drift`
- `Crie uma Application do ArgoCD para os experimentos de chaos em platform/chaos/`
- `Simule um drift manual com kubectl e mostre o ArgoCD fazendo self-heal`
- `O argocd-redis está preso em Init:CrashLoopBackOff. Diagnostique e corrija`

---

**Anterior:** [Tutorial 06 — Chaos Engineering com Chaos Mesh](tutorial-06-chaos-mesh.md)
**Próximo:** [Tutorial 08 — Load Testing com k6](tutorial-08-k6-load-testing.md)
