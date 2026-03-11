# Tutorial 04 — Prometheus + Grafana com Helm

**Objetivo:** Instalar o stack completo de observabilidade (Prometheus, Grafana, Alertmanager) usando kube-prometheus-stack e configurar ServiceMonitors para os serviços StreamFlix.

**Resultado:** Prometheus coletando métricas, Grafana acessível com dashboards, Alertmanager funcional e ServiceMonitor capturando métricas dos 3 serviços.

**Tempo estimado:** 20 minutos

**Pré-requisitos:** Tutorial 03 completo com health check verde

---

## Contexto

O **Prometheus** é o padrão CNCF para métricas no Kubernetes — usado em produção por milhares de empresas ao redor do mundo. Ele foi inspirado em sistemas internos de monitoramento de grandes plataformas, e seus princípios estão documentados no SRE Book.

O **kube-prometheus-stack** é um Helm chart que instala tudo de uma vez: Prometheus (coleta), Grafana (dashboards), Alertmanager (notificações), node-exporter (métricas da máquina), kube-state-metrics (métricas do K8s). É o stack de observabilidade mais usado em produção Kubernetes no mundo.

**Lição aprendida importante:** No Minikube, o Alertmanager tenta criar um PVC (Persistent Volume Claim) via hostpath-provisioner, mas o diretório `/tmp/hostpath-provisioner/...` frequentemente não existe no nó. Isso causa CrashLoopBackOff. A solução é desabilitar storage do Alertmanager com `alertmanagerSpec.storage: {}` no values.yaml. Esse problema é documentado como P1 no [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md).

---

## Passo 1 — Adicionar repositório Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

✅ Esperado:
```
"prometheus-community" has been added to your repositories
...Successfully got an update from the "prometheus-community" chart repository
```

---

## Passo 2 — Verificar o values.yaml

```bash
cat helm/values/local/prometheus-values.yaml
```

```yaml
grafana:
  adminPassword: "admin123"
  service:
    type: NodePort
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        folder: ReliabilityLab
        type: file
        options:
          path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      kubernetes-overview:
        gnetId: 15661
        datasource: Prometheus
      hpa-scaling:
        gnetId: 10257
        datasource: Prometheus

prometheus:
  prometheusSpec:
    retention: 7d
    serviceMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    storage: {}
```

| Configuração | Motivo |
|-------------|--------|
| `grafana.adminPassword` | Senha do admin (em produção use Secrets) |
| `grafana.service.type: NodePort` | Necessário para acessar Grafana no Minikube |
| `dashboards.gnetId: 15661` | Dashboard de Kubernetes Overview do Grafana Labs |
| `dashboards.gnetId: 10257` | Dashboard de HPA Scaling |
| `serviceMonitorSelectorNilUsesHelmValues: false` | Prometheus descobre **todos** os ServiceMonitors, não só os do Helm release |
| `ruleSelectorNilUsesHelmValues: false` | Prometheus carrega **todas** as PrometheusRules, incluindo as geradas pelo Sloth |
| **`alertmanagerSpec.storage: {}`** | **CRÍTICO no Minikube** — desabilita PVC que causa CrashLoopBackOff (P1) |

---

## Passo 3 — Instalar kube-prometheus-stack

```bash
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 82.10.3 \
  -n monitoring \
  -f helm/values/local/prometheus-values.yaml \
  --wait --timeout 10m
```

> O `--wait` garante que o Helm só retorna quando todos os pods estão Running. O `--timeout 10m` dá tempo suficiente para pulls de imagens.

✅ Esperado:
```
Release "kube-prometheus-stack" has been upgraded. Happy Helming!
```

---

## Passo 4 — Verificar pods do stack

```bash
kubectl get pods -n monitoring
```

✅ Esperado (todos Running, 0 restarts):
```
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0         2/2     Running   0          2m
kube-prometheus-stack-grafana-xxxxxxxxx-xxxxx             3/3     Running   0          2m
kube-prometheus-stack-kube-state-metrics-xxxxx-xxxxx      1/1     Running   0          2m
kube-prometheus-stack-operator-xxxxx-xxxxx                1/1     Running   0          2m
kube-prometheus-stack-prometheus-node-exporter-xxxxx      1/1     Running   0          2m
kube-prometheus-stack-prometheus-node-exporter-yyyyy      1/1     Running   0          2m
kube-prometheus-stack-prometheus-node-exporter-zzzzz      1/1     Running   0          2m
prometheus-kube-prometheus-stack-prometheus-0             2/2     Running   0          2m
```

> Deve haver 1 node-exporter **por nó** (3 no nosso cluster).

---

## Passo 5 — Aplicar ServiceMonitor para StreamFlix

O ServiceMonitor diz ao Prometheus quais endpoints scrape:

```bash
cat k8s/servicemonitor-streamflix.yaml
```

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: streamflix-services
  namespace: production
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels: {}
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
```

> `matchLabels: {}` seleciona **todos** os Services no namespace production. O endpoint `/metrics` do podinfo retorna métricas reais (http_request_duration_seconds, go_*, process_*) — o Prometheus coleta automaticamente métricas HTTP com status codes, perfeitas para nossos SLOs.

Aplicar:

```bash
kubectl apply -f k8s/servicemonitor-streamflix.yaml
```

✅ Esperado: `servicemonitor.monitoring.coreos.com/streamflix-services created`

---

## Passo 6 — Acessar o Grafana

```bash
minikube service kube-prometheus-stack-grafana -n monitoring -p reliabilitylab
```

✅ Esperado: browser abre com login do Grafana.

Credenciais:
- **Usuário:** `admin`
- **Senha:** `admin123`

Se o browser não abrir automaticamente, pegue a URL:

```bash
minikube service kube-prometheus-stack-grafana -n monitoring -p reliabilitylab --url
```

---

## Passo 7 — Verificar targets no Prometheus

Acesse o Prometheus:

```bash
minikube service kube-prometheus-stack-prometheus -n monitoring -p reliabilitylab
```

Navegue até **Status → Targets**. Procure por `serviceMonitor/production/streamflix-services`.

✅ Esperado: targets dos 3 serviços (content-api, recommendation-api, player-api) com status `UP`.

Alternativamente, via kubectl:

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
sleep 2

# Verificar targets ativos
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A2 '"job"'

# Executar uma query
curl -s "http://localhost:9090/api/v1/query?query=up" | python3 -m json.tool | grep -E '"job"|"value"'

kill %1 2>/dev/null
```

---

## Passo 8 — Explorar dashboards no Grafana

Dashboards pré-configurados:

| ID Grafana | Nome | O que mostra |
|-----------|------|-------------|
| 15661 | Kubernetes Overview | CPU, memória, pods por namespace |
| 10257 | HPA Dashboard | Réplicas atuais vs desejadas, métricas de scaling |

No Grafana:
1. Vá em **Dashboards → Browse**
2. Procure a pasta **ReliabilityLab**
3. Abra `kubernetes-overview` e confirme que os gráficos carregam

Dashboards extras úteis (importe manualmente via **Dashboards → Import**):

| ID | Nome | Uso |
|----|------|-----|
| 6417 | Kubernetes Cluster | Panorama geral do cluster |
| 13332 | kube-state-metrics v2 | Deployments, pods, réplicas |
| 14981 | CoreDNS | Monitorar resolução DNS |

---

## Passo 9 — Testar Alertmanager

```bash
kubectl get pods -n monitoring | grep alertmanager
```

✅ Esperado: `Running` com 0 restarts.

Se o Alertmanager estiver em CrashLoopBackOff:

```bash
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager
```

> Se o erro for `stat /tmp/hostpath-provisioner/...: no such file or directory`, confirme que `alertmanagerSpec.storage: {}` está no values.yaml e reinstale:

```bash
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 82.10.3 \
  -n monitoring \
  -f helm/values/local/prometheus-values.yaml \
  --wait --timeout 10m
```

---

## Health Check (antes de avançar para Tutorial 05)

```bash
echo "=== HEALTH CHECK — Tutorial 04 ==="

echo -e "\n[1/5] Pods do monitoring (todos Running):"
NOT_RUNNING=$(kubectl get pods -n monitoring --no-headers | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
  echo "  ✅ Todos os pods Running"
else
  echo "  ❌ $NOT_RUNNING pods com problema"
  kubectl get pods -n monitoring | grep -v Running | grep -v NAME
fi
echo ""

echo "[2/5] Prometheus operacional:"
kubectl get pods -n monitoring | grep prometheus-kube-prometheus-stack-prometheus-0 | grep -q "2/2.*Running" \
  && echo "  ✅ Prometheus Running" || echo "  ❌ Prometheus não está saudável"
echo ""

echo "[3/5] Grafana operacional:"
kubectl get pods -n monitoring | grep grafana | grep -q Running \
  && echo "  ✅ Grafana Running" || echo "  ❌ Grafana não está saudável"
echo ""

echo "[4/5] Alertmanager (sem CrashLoopBackOff):"
kubectl get pods -n monitoring | grep alertmanager | grep -q Running \
  && echo "  ✅ Alertmanager Running" || echo "  ❌ Alertmanager com problema — verifique storage: {} no values.yaml"
echo ""

echo "[5/5] ServiceMonitor presente:"
kubectl get servicemonitor -n production --no-headers 2>/dev/null | grep -q streamflix \
  && echo "  ✅ ServiceMonitor streamflix-services configurado" || echo "  ❌ ServiceMonitor ausente"

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| Alertmanager CrashLoopBackOff com erro `hostpath-provisioner` | PVC tentando montar diretório inexistente no Minikube | **Solução (P1):** adicionar `alertmanagerSpec.storage: {}` no values.yaml e `helm upgrade` |
| Grafana retorna 502 ou não carrega | Pod ainda inicializando ou OOMKilled | `kubectl describe pod <grafana-pod> -n monitoring`. Se OOM: aumente `--memory=4096` |
| Prometheus "No data" nos dashboards | ServiceMonitor sem label `release` ou `serviceMonitorSelectorNilUsesHelmValues: true` | Confirme `serviceMonitorSelectorNilUsesHelmValues: false` no values.yaml |
| `helm upgrade` timeout | Cluster sem recursos (RAM) | Usando `--memory=4096`? Se não, recrie o cluster |
| node-exporter não roda em todos os nós | DaemonSet não schedulou em workers | `kubectl get ds -n monitoring`. Se tolerations faltando, o Helm chart já cuida disso |
| Alertas de `Watchdog` firing | Normal — é um alerta de "dead man's switch" | Pode ignorar — confirma que o Alertmanager está funcional |

---

## Conceitos-chave

- **kube-prometheus-stack:** umbrella chart que instala Prometheus Operator + Grafana + Alertmanager + exporters
- **ServiceMonitor:** CRD que configura o Prometheus para scrape endpoints automaticamente (autodiscovery)
- **PrometheusRule:** CRD para alertas e recording rules (será usado pelo Sloth no Tutorial 05)
- **node-exporter:** DaemonSet que roda em cada nó e expõe métricas de hardware (CPU, disco, memória, rede)
- **Dead man's switch (Watchdog):** alerta que sempre está firing — se parar, significa que o Alertmanager morreu
- Sistemas proprietários de métricas usam push model. O Prometheus usa pull model (scrape) — ambos chegam ao mesmo resultado

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Analise os pods com problema no namespace monitoring e sugira correções`
- `O Alertmanager está em CrashLoopBackOff. Diagnostique a causa e corrija`
- `Verifique se o ServiceMonitor está fazendo scrape dos meus serviços corretamente no Prometheus`
- `Crie uma PrometheusRule de alerta para quando a latência p99 do content-api ultrapassar 500ms`
- `Compare as versões pinadas no bootstrap.sh com o que o Helm realmente instalou (helm list --all-namespaces)`

---

**Anterior:** [Tutorial 03 — Deployments, Services e HPA](tutorial-03-deployments-hpa.md)
**Próximo:** [Tutorial 05 — SLOs com Sloth](tutorial-05-slos-sloth.md)
