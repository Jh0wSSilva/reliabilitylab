# Tutorial 02 — Namespaces, ResourceQuota e LimitRange

**Objetivo:** Criar namespaces isolados para cada componente do stack e aplicar limites de recursos no namespace production.

**Resultado:** 4 namespaces criados (production, monitoring, chaos-mesh, argocd), ResourceQuota e LimitRange aplicados e validados.

**Tempo estimado:** 10 minutos

**Pré-requisitos:** Tutorial 01 completo com health check verde

---

## Contexto

Em plataformas de produção, cada time tipicamente opera dentro de um escopo isolado com limites de custo e capacidade (blast radius isolation). Namespaces com ResourceQuotas evitam que um serviço monopolize o cluster, e RBAC garante que um time não possa acidentalmente derrubar o deployment de outro.

Namespaces no Kubernetes são a unidade de isolamento lógico. Combinados com ResourceQuota (limite total do namespace) e LimitRange (limite por container), eles previnem o principal problema de clusters compartilhados: um serviço consumindo todos os recursos e derrubando os vizinhos — o famoso "noisy neighbor".

No nosso lab, separamos workloads (production), observabilidade (monitoring), chaos engineering (chaos-mesh) e GitOps (argocd) em namespaces dedicados. Isso simula a organização real de clusters multi-tenant em produção.

---

## Passo 1 — Criar namespaces

```bash
kubectl create namespace production
kubectl create namespace monitoring
kubectl create namespace chaos-mesh
kubectl create namespace argocd
```

✅ Esperado:
```
namespace/production created
namespace/monitoring created
namespace/chaos-mesh created
namespace/argocd created
```

Verificar:

```bash
kubectl get namespaces
```

✅ Esperado: os 4 namespaces listados junto com `default`, `kube-system`, `kube-public`, `kube-node-lease` e `ingress-nginx`.

---

## Passo 2 — Aplicar ResourceQuota no production

O ResourceQuota define o teto total de recursos que todos os pods do namespace podem consumir somados.

Verifique o conteúdo do arquivo:

```bash
cat k8s/namespaces/production-quota.yaml
```

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "30"
```

| Campo | Valor | Significado |
|-------|-------|-------------|
| `requests.cpu` | 4 cores | Soma máxima de CPU requests de todos os pods |
| `requests.memory` | 4Gi | Soma máxima de memory requests |
| `limits.cpu` | 8 cores | Soma máxima de CPU limits |
| `limits.memory` | 8Gi | Soma máxima de memory limits |
| `pods` | 30 | Máximo de pods simultâneos no namespace |

Aplicar:

```bash
kubectl apply -f k8s/namespaces/production-quota.yaml
```

✅ Esperado: `resourcequota/production-quota created`

Verificar:

```bash
kubectl describe resourcequota production-quota -n production
```

✅ Esperado:
```
Name:            production-quota
Namespace:       production
Resource         Used  Hard
--------         ----  ----
limits.cpu       0     8
limits.memory    0     8Gi
pods             0     30
requests.cpu     0     4
requests.memory  0     4Gi
```

> `Used` deve estar zerado — nenhum pod rodando ainda no namespace.

---

## Passo 3 — Aplicar LimitRange no production

O LimitRange define default, mínimo e máximo de recursos **por container**. Quando um pod é criado sem especificar resources, o LimitRange injeta os defaults automaticamente.

```bash
cat k8s/namespaces/production-limitrange.yaml
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limitrange
  namespace: production
spec:
  limits:
  - type: Container
    default:
      cpu: "200m"
      memory: "256Mi"
    defaultRequest:
      cpu: "50m"
      memory: "64Mi"
    max:
      cpu: "1"
      memory: "1Gi"
```

| Campo | Significado |
|-------|-------------|
| `default` | Limits aplicados se o container não declarar |
| `defaultRequest` | Requests aplicados se o container não declarar |
| `max` | Máximo que qualquer container individual pode pedir |

Aplicar:

```bash
kubectl apply -f k8s/namespaces/production-limitrange.yaml
```

✅ Esperado: `limitrange/production-limitrange created`

---

## Passo 4 — Testar os defaults do LimitRange

Crie um pod sem especificar resources:

```bash
kubectl run test-limits --image=ghcr.io/stefanprodan/podinfo:6.11.0 -n production
```

Aguarde ficar Running e inspecione:

```bash
kubectl get pod test-limits -n production -o jsonpath='{.spec.containers[0].resources}' | python3 -m json.tool
```

✅ Esperado:
```json
{
    "limits": {
        "cpu": "200m",
        "memory": "256Mi"
    },
    "requests": {
        "cpu": "50m",
        "memory": "64Mi"
    }
}
```

> O Kubernetes injetou automaticamente os defaults do LimitRange. Isso evita que containers sem limits consumam recursos indefinidamente.

Limpar o pod de teste:

```bash
kubectl delete pod test-limits -n production
```

---

## Passo 5 — Testar o ResourceQuota (recurso excedido)

Tente criar um pod que exceda o `max` do LimitRange:

```bash
kubectl run test-exceed --image=ghcr.io/stefanprodan/podinfo:6.11.0 -n production \
  --overrides='{"spec":{"containers":[{"name":"test","image":"ghcr.io/stefanprodan/podinfo:6.11.0","resources":{"requests":{"cpu":"2","memory":"2Gi"}}}]}}'
```

✅ Esperado: erro indicando que o pod excede os limites:
```
Error from server (Forbidden): ... maximum cpu usage per Container is 1, but limit is 2
```

> O LimitRange rejeitou a criação porque `cpu: 2` ultrapassa o `max.cpu: 1`.

---

## Passo 6 — Verificar status do quota

```bash
kubectl describe resourcequota production-quota -n production
```

✅ Esperado: `Used` deve estar zerado (o pod de teste já foi deletado e o pod excedido foi rejeitado).

---

## Health Check (antes de avançar para Tutorial 03)

```bash
echo "=== HEALTH CHECK — Tutorial 02 ==="

echo -e "\n[1/4] Namespaces:"
for ns in production monitoring chaos-mesh argocd; do
  kubectl get namespace "$ns" --no-headers 2>/dev/null \
    && echo "  ✅ $ns existe" || echo "  ❌ $ns NÃO encontrado"
done
echo ""

echo "[2/4] ResourceQuota:"
kubectl get resourcequota -n production --no-headers 2>/dev/null \
  && echo "  ✅ ResourceQuota aplicada" || echo "  ❌ ResourceQuota ausente"
echo ""

echo "[3/4] LimitRange:"
kubectl get limitrange -n production --no-headers 2>/dev/null \
  && echo "  ✅ LimitRange aplicado" || echo "  ❌ LimitRange ausente"
echo ""

echo "[4/4] Defaults funcionando:"
kubectl run hc-limits --image=ghcr.io/stefanprodan/podinfo:6.11.0 -n production --restart=Never 2>/dev/null
sleep 5
LIMITS=$(kubectl get pod hc-limits -n production -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)
kubectl delete pod hc-limits -n production --force 2>/dev/null
if [ "$LIMITS" = "200m" ]; then
  echo "  ✅ LimitRange defaults injetados corretamente"
else
  echo "  ❌ LimitRange defaults NÃO estão funcionando (cpu limits = $LIMITS)"
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| `namespace already exists` | Namespace já foi criado | Pode ignorar — não afeta nada |
| Pod rejeitado sem mensagem clara | ResourceQuota atingida ou LimitRange violado | `kubectl describe resourcequota -n production` para ver `Used` vs `Hard` |
| Pod fica `Pending` sem motivo óbvio | Faltam resources requests/limits e o namespace tem quota | Com ResourceQuota ativa, **todo pod deve ter resources definidos** (LimitRange injeta defaults se configurado) |
| LimitRange não injeta defaults | LimitRange aplicado em namespace diferente | Confirme com `kubectl get limitrange -n production` |

---

## Conceitos-chave

- **Namespace:** isolamento lógico — DNS, RBAC, quotas e policies são scoped por namespace
- **ResourceQuota:** limite agregado (soma de todos os pods do namespace)
- **LimitRange:** limite individual (por container) + injeção de defaults
- Em produção real, quotas são definidas pelo platform team e cada squad recebe seu namespace com limites pré-configurados

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Valide se os Network Policies estão bloqueando tráfego corretamente entre namespaces`
- `Meu pod não sobe porque excede a ResourceQuota. Diagnostique e mostre quanto já está consumido`
- `Crie um LimitRange mais restritivo para o namespace production`
- `Explique a diferença entre ResourceQuota e LimitRange com exemplos do meu cluster`
- `Quero adicionar um novo namespace para staging com quotas menores. Gere os manifests`

---

**Anterior:** [Tutorial 01 — Ambiente e Minikube](tutorial-01-ambiente-minikube.md)
**Próximo:** [Tutorial 03 — Deployments, Services e HPA](tutorial-03-deployments-hpa.md)
