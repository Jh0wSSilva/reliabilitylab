# Tutorial 07 — Segurança de Rede com NetworkPolicy

## Objetivo

Implementar o princípio **zero-trust** na rede do cluster usando **NetworkPolicy**, restringindo o tráfego apenas ao necessário.

## Conceitos

- **NetworkPolicy**: recurso do Kubernetes que controla tráfego de rede entre pods
- **Zero-trust**: modelo onde nenhum tráfego é permitido por padrão; tudo deve ser explicitamente autorizado
- **Ingress (regra)**: tráfego entrando no pod
- **Egress (regra)**: tráfego saindo do pod
- **Pod Security Standards (PSS)**: políticas de segurança para pods no namespace

## Pré-requisitos

- Cluster com CNI que suporta NetworkPolicy (kind com kindnet, k3d com Flannel, minikube com CNI)
- Aplicação deployada (Tutorial 04)

## Passo a Passo

### 1. Entender a NetworkPolicy

O arquivo `platform/networkpolicy.yaml` define:

```yaml
# Tráfego de ENTRADA (Ingress) permitido:
# 1. Ingress Controller (NGINX) → porta 8000
# 2. Prometheus (monitoring) → porta 8000 (scrape)
#
# Tráfego de SAÍDA (Egress) permitido:
# 1. DNS (porta 53 UDP/TCP) — necessário para resolução de nomes
#
# TODO o resto: BLOQUEADO
```

### 2. Aplicar NetworkPolicy e RBAC

```bash
bash scripts/deploy-platform.sh

# Aplicar também as políticas de segurança
kubectl apply -f security/rbac.yaml
kubectl apply -f security/pod-security.yaml
```

### 3. Verificar as políticas

```bash
# NetworkPolicy
kubectl get networkpolicy -n reliabilitylab

# RBAC
kubectl get role,rolebinding -n reliabilitylab

# Pod Security Standards (labels do namespace)
kubectl get namespace reliabilitylab --show-labels
```

### 4. Testar o bloqueio de tráfego

Crie um pod temporário para testar conectividade:

```bash
# Criar pod de teste no namespace default
kubectl run test-pod --image=busybox --restart=Never -n default -- sleep 3600

# Tentar acessar a aplicação de fora do namespace (DEVE FALHAR)
kubectl exec test-pod -n default -- wget -qO- --timeout=5 http://site-kubectl.reliabilitylab.svc.cluster.local/api/health

# Resultado esperado: timeout ou connection refused

# Limpar
kubectl delete pod test-pod -n default
```

### 5. Testar o acesso permitido

```bash
# Acessar via Ingress (DEVE FUNCIONAR)
curl http://site-kubectl.local/api/health

# Resultado esperado:
# {"status":"ok","message":"App is running normally"}
```

### 6. Entender o RBAC

O arquivo `security/rbac.yaml` define dois papéis:

| Role | Permissões | Uso |
|------|-----------|-----|
| `reliabilitylab-viewer` | Leitura de pods, services, events, deployments | Dashboards, monitoramento |
| `reliabilitylab-deployer` | Criar/atualizar deployments, services, configmaps | CI/CD, operações |

### 7. Pod Security Standards

O namespace tem labels que aplicam restrições:

```yaml
pod-security.kubernetes.io/enforce: restricted
```

Isso significa que pods devem:
- Rodar como não-root
- Não ter `privileged: true`
- Dropar `ALL` capabilities
- Usar `seccompProfile: RuntimeDefault`

### 8. Verificar segurança do container

```bash
kubectl get pod -n reliabilitylab -l app.kubernetes.io/name=site-kubectl -o jsonpath='{.items[0].spec.containers[0].securityContext}' | python3 -m json.tool
```

**Resultado esperado:**
```json
{
    "allowPrivilegeEscalation": false,
    "runAsNonRoot": true,
    "runAsUser": 10001,
    "capabilities": {
        "drop": ["ALL"]
    }
}
```

## Boas Práticas de Segurança

| Prática | Status no Lab |
|---------|--------------|
| NetworkPolicy zero-trust | ✅ Implementado |
| Container não-root | ✅ UID 10001 |
| Capabilities dropadas | ✅ `drop: ALL` |
| RBAC com menor privilégio | ✅ viewer e deployer roles |
| Pod Security Standards | ✅ enforce: restricted |
| Secrets separados do código | ✅ stringData em Secret |
| Imagem multi-stage | ✅ Menor superfície de ataque |

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Aplicação parou de funcionar após NetworkPolicy | Verifique se os labels do ingress-nginx namespace estão corretos |
| Pod rejeitado pelo PSS | Verifique `securityContext` no Deployment |
| DNS não resolve | Garanta que a regra de egress permite porta 53 |
| Prometheus não consegue fazer scrape | Verifique se o namespace `monitoring` tem o label correto |

## Próximo Tutorial

[08 — Chaos Engineering](08-chaos-engineering.md)
