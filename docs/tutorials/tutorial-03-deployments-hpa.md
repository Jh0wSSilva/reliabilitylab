# Tutorial 03 — Deployments, Services e HPA

**Objetivo:** Fazer deploy dos 3 microserviços do StreamFlix com Horizontal Pod Autoscaler (HPA) configurado e testar auto-scaling com carga real de CPU.

**Resultado:** 3 serviços rodando em production (content-api, recommendation-api, player-api), Services expostos internamente e HPA escalando de 2 para 6+ réplicas sob carga de CPU.

**Tempo estimado:** 25 minutos

**Pré-requisitos:** Tutorial 02 completo com health check verde

---

## Contexto

Em plataformas de produção, microserviços rodam em auto-scaling groups configurados com base em métricas de CPU, latência e custom metrics. O sistema escala automaticamente quando a carga aumenta — sem intervenção humana.

O Kubernetes HPA (Horizontal Pod Autoscaler) implementa esse comportamento: monitora CPU/memória dos pods via metrics-server e ajusta o número de réplicas automaticamente. No StreamFlix, usamos HPA para garantir que nossos serviços escalam sob carga e mantêm os SLOs definidos.

**Nota sobre podinfo como mock:** usamos [podinfo](https://github.com/stefanprodan/podinfo) para simular os microsserviços porque é um microsserviço Go leve que expõe métricas Prometheus reais (`/metrics`), endpoints de health (`/healthz`, `/readyz`), e endpoints de stress (`/stress/cpu`, `/stress/memory`). Diferente de um servidor estático, o podinfo consome CPU proporcionalmente à carga e gera métricas HTTP com status codes reais — ideal para testar HPA e SLOs.

---

## Passo 1 — Deploy do content-api

Verifique o manifesto:

```bash
cat k8s/namespaces/content-api.yaml
```

O deployment inclui:
- **2 réplicas** iniciais
- **RollingUpdate** com `maxSurge: 1` e `maxUnavailable: 0` (zero downtime)
- **Resources** definidos (requests + limits)
- **Probes** de liveness e readiness
- **Service** ClusterIP na porta 9898

Aplicar:

```bash
kubectl apply -f k8s/namespaces/content-api.yaml
```

✅ Esperado:
```
deployment.apps/content-api created
service/content-api created
```

Verificar:

```bash
kubectl get pods -n production -l app=content-api
kubectl get svc -n production
```

✅ Esperado: 2 pods Running + 1 Service.

---

## Passo 2 — Deploy do recommendation-api

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: recommendation-api
  namespace: production
  labels:
    app: recommendation-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: recommendation-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: recommendation-api
    spec:
      containers:
      - name: recommendation-api
        image: ghcr.io/stefanprodan/podinfo:6.11.0
        ports:
        - containerPort: 9898
          name: http
        env:
        - name: PODINFO_UI_COLOR
          value: "#347c5a"
        - name: PODINFO_UI_MESSAGE
          value: "recommendation-api (StreamFlix)"
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9898
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readyz
            port: 9898
          initialDelaySeconds: 3
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: recommendation-api
  namespace: production
spec:
  selector:
    app: recommendation-api
  ports:
  - port: 9898
    targetPort: 9898
    name: http
EOF
```

✅ Esperado: `deployment.apps/recommendation-api created` + `service/recommendation-api created`

---

## Passo 3 — Deploy do player-api

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: player-api
  namespace: production
  labels:
    app: player-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: player-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: player-api
    spec:
      containers:
      - name: player-api
        image: ghcr.io/stefanprodan/podinfo:6.11.0
        ports:
        - containerPort: 9898
          name: http
        env:
        - name: PODINFO_UI_COLOR
          value: "#7c3434"
        - name: PODINFO_UI_MESSAGE
          value: "player-api (StreamFlix)"
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9898
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readyz
            port: 9898
          initialDelaySeconds: 3
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: player-api
  namespace: production
spec:
  selector:
    app: player-api
  ports:
  - port: 9898
    targetPort: 9898
    name: http
EOF
```

✅ Esperado: 2 mais pods Running.

---

## Passo 4 — Verificar todos os serviços

```bash
kubectl get deployments -n production
kubectl get pods -n production
kubectl get svc -n production
```

✅ Esperado:
```
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
content-api          2/2     2            2           2m
recommendation-api   2/2     2            2           1m
player-api           2/2     2            2           30s

NAME                                  READY   STATUS    RESTARTS   AGE
content-api-xxxxx-yyyyy               1/1     Running   0          2m
content-api-xxxxx-zzzzz               1/1     Running   0          2m
recommendation-api-xxxxx-yyyyy        1/1     Running   0          1m
recommendation-api-xxxxx-zzzzz        1/1     Running   0          1m
player-api-xxxxx-yyyyy                1/1     Running   0          30s
player-api-xxxxx-zzzzz                1/1     Running   0          30s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
content-api          ClusterIP   10.96.x.x       <none>        9898/TCP   2m
recommendation-api   ClusterIP   10.96.x.x       <none>        9898/TCP   1m
player-api           ClusterIP   10.96.x.x       <none>        9898/TCP   30s
```

---

## Passo 5 — Testar comunicação entre serviços

```bash
kubectl run test-curl --image=curlimages/curl --restart=Never --rm -it -n production -- \
  sh -c "curl -s http://content-api:9898 && echo '' && curl -s http://recommendation-api:9898 && echo '' && curl -s http://player-api:9898"
```

✅ Esperado: resposta JSON do podinfo para cada serviço (com `hostname`, `version`, `message` confirmando que o DNS interno e os Services funcionam).

---

## Passo 6 — Criar HPA para cada serviço

```bash
kubectl autoscale deployment content-api \
  -n production --min=2 --max=10 --cpu=70%

# Se houver um HPA antigo, remova antes
kubectl delete hpa recommendation-api -n production 2>/dev/null || true

# então crie novamente com sintaxe atualizada
kubectl autoscale deployment recommendation-api \
  -n production --min=2 --max=8 --cpu=70%

# (o flag `--cpu-percent` foi deprecado; use `--cpu=70%` ou defina um manifesto v2 manualmente)

kubectl autoscale deployment player-api \
  -n production --min=2 --max=6 --cpu=70%
```

✅ Esperado:
```
horizontalpodautoscaler.autoscaling/content-api autoscaled
horizontalpodautoscaler.autoscaling/recommendation-api autoscaled
horizontalpodautoscaler.autoscaling/player-api autoscaled
```

Verificar:

```bash
kubectl get hpa -n production
```

✅ Esperado:
```
NAME                 REFERENCE                       TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
content-api          Deployment/content-api          0%/70%    2         10        2          30s
recommendation-api   Deployment/recommendation-api   0%/70%    2         8         2          20s
player-api           Deployment/player-api           0%/70%    2         6         2          10s
```

> Se TARGETS mostra `<unknown>/70%`, o metrics-server ainda está coletando dados. Aguarde 1-2 minutos.

---

## Passo 7 — Testar HPA com carga de CPU real

O `podinfo` não expõe mais um endpoint HTTP de stress na versão 6.11.0. Em vez disso, você pode:

* redeployar o pod com a flag `--stress-cpu` ou `--stress-memory` para carregar a aplicação no arranque;
* usar um gerador de carga externo como k6 ou o StressChaos do Chaos Mesh (recomendado);
* executar `kubectl exec` no pod e rodar um comando de carga manualmente (por exemplo `grep -R` loop).

Aqui vamos usar o Chaos Mesh para gerar carga controlada, porque preserva a imagem original e se integra bem com o HPA. Se o controller não estiver saudável, pule esta parte e use o fallback a seguir.

Abra um terminal dedicado para monitorar o HPA:

```bash
# Terminal 1 — monitoramento (mantenha aberto)
kubectl get hpa -n production -w
```

🔔 **Pré-requisito:** o Chaos Mesh deve estar instalado e seus CRDs aplicados no namespace `chaos-mesh`. Caso ainda não tenha executado o bootstrap completo, rode:

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh -n chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --wait
```

Esse comando garante que `StressChaos`, `NetworkChaos`, etc., existam. Se preferir apenas instalar os CRDs rapidamente, execute:

```bash
kubectl apply -f https://raw.githubusercontent.com/chaos-mesh/chaos-mesh/master/manifests/crd.yaml
``` 

> ⚠️ o controller manager usa leader election e costuma entrar em `CrashLoopBackOff` em clusters leves como Minikube (perda de lease). Se os pods `chaos-controller-manager-*` não permanecerem `Running`, os webhooks do Chaos Mesh não responderão e os recursos falharão com `connection refused`. Nesses casos você pode desabilitar a eleição via valor `--set controllerManager.leaderElection.enable=false` ou simplesmente pular para o método alternativo abaixo.

Após garantir que pelo menos um controller esteja `Running`, aplique o experimento de CPU:

```bash
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

Se preferir não usar Chaos Mesh, veja a seção “**Fallback: stress via podinfo flag**” abaixo.

O experimento injeta 80% de CPU em um pod do content-api por 30s, gerando utilização imediata.

> Alternativamente você poderia usar k6 ou um `kubectl exec` com `stress-ng` se preferir.

Observe o HPA no Terminal 1. Após 1-2 minutos:

```bash
kubectl get hpa -n production
```

✅ Esperado: CPU do content-api ultrapassando 70%, réplicas escalando:
```
NAME          REFERENCE                TARGETS    MINPODS   MAXPODS   REPLICAS
content-api   Deployment/content-api   198%/70%   2         10        6
```

---

## Fallback: stress via podinfo flag

Se você não conseguir fazer o Chaos Mesh funcionar devido a controladores em CrashLoopBackOff, pode simular carga diretamente:

```bash
kubectl set args deployment/content-api -n production -- --stress-cpu 2
# aguarde alguns segundos, o pod reiniciará com CPU load contínua
kubectl get pod -n production -l app=content-api
```

Depois de testar o HPA, remova o argumento:

```bash
kubectl set args deployment/content-api -n production --
```
Verifique os pods:

```bash
kubectl get pods -n production -l app=content-api
```

✅ Esperado: 6 pods (ou mais) Running — HPA escalou de 2 para 6 réplicas.

---

## Passo 8 — Remover a carga e observar scale-down

A carga do `/stress/cpu` para automaticamente após a duração solicitada (60s).

> O HPA leva ~5 minutos para fazer scale-down (cooldown period padrão). Isso é by design — evita "flapping" (escalar→desescalar→escalar rapidamente).

Após ~5 minutos:

```bash
kubectl get hpa -n production
```

✅ Esperado: content-api voltando para 2 réplicas.

---

## Health Check (antes de avançar para Tutorial 04)

```bash
echo "=== HEALTH CHECK — Tutorial 03 ==="

echo -e "\n[1/4] Deployments (3 serviços com 2/2 replicas):"
kubectl get deployments -n production --no-headers | awk '{print "  " $1, $2}'
echo ""

echo "[2/4] Services:"
kubectl get svc -n production --no-headers | awk '{print "  " $1, $2, $5}'
echo ""

echo "[3/4] HPA configurado:"
kubectl get hpa -n production --no-headers | awk '{print "  " $1, "min=" $4, "max=" $5, "replicas=" $6}'
echo ""

echo "[4/4] Pods todos Running:"
NOT_RUNNING=$(kubectl get pods -n production --no-headers | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo "  ✅ Todos os pods Running"
else
  echo "  ❌ $NOT_RUNNING pods não estão Running"
  kubectl get pods -n production | grep -v Running
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| HPA mostra `<unknown>/70%` | metrics-server não tem dados ainda | Aguarde 2-3 min. Confirme: `kubectl top pods -n production` |
| HPA não escala mesmo com 100% CPU | metrics-server parado ou crashloop | `kubectl get pods -n kube-system \| grep metrics`. Reinicie o addon se necessário |
| Pods ficam `Pending` | ResourceQuota atingida (30 pods max) | `kubectl describe resourcequota -n production`. Se necessário, aumente o limite |
| Service não resolve | Pod sem label correspondente | Confirme labels: `kubectl get pods -n production --show-labels` |
| Podinfo retorna 404 | Porta errada no port-forward | Use porta 9898: `kubectl port-forward svc/content-api 8081:9898` |

---

## Conceitos-chave

- **Deployment:** garante N réplicas + rolling update com zero downtime
- **Service:** DNS interno estável (`content-api.production.svc.cluster.local`)
- **HPA:** auto-scaling horizontal baseado em métricas (CPU, memória, custom)
- **Scale-down cooldown:** 5 minutos por padrão para evitar flapping
- Em produção, o auto-scaling costuma ser baseado em métricas customizadas (RPS, latência P99) — não apenas CPU

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `O HPA do content-api não está escalando. Diagnostique o motivo`
- `Meu Deployment está preso em Pending. Analise os eventos e sugira correção`
- `Configure o HPA para escalar baseado em requests por segundo em vez de CPU`
- `Simule um rolling update e me mostre como verificar zero downtime`
- `Compare os resource requests/limits dos meus 3 serviços e diga se estão adequados para o cluster`

---

**Anterior:** [Tutorial 02 — Namespaces, ResourceQuota e LimitRange](tutorial-02-namespaces-quota.md)
**Próximo:** [Tutorial 04 — Prometheus + Grafana com Helm](tutorial-04-prometheus-grafana.md)
