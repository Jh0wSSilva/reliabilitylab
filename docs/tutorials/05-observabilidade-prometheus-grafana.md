# Tutorial 05 — Observabilidade com Prometheus e Grafana

## Objetivo

Instalar uma stack completa de observabilidade para monitorar a aplicação: **Prometheus** (métricas), **Grafana** (dashboards), **Loki** (logs) e **OpenTelemetry** (coleta unificada).

## Conceitos

- **Observabilidade**: capacidade de entender o estado interno do sistema a partir de saídas externas
- **Três pilares**: métricas, logs e traces
- **Prometheus**: coleta e armazena métricas no formato time-series
- **Grafana**: plataforma de visualização e alertas
- **Loki**: sistema de agregação de logs (como Prometheus, mas para logs)
- **Promtail**: agente que coleta logs e envia para o Loki
- **OpenTelemetry (OTel)**: framework unificado para métricas, logs e traces

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| Helm | 3.12+ | `helm version` |
| Cluster | Rodando | `kubectl get nodes` |
| Aplicação | Deployada | `kubectl get pods -n reliabilitylab` |

## Passo a Passo

### 1. Instalar a stack completa

```bash
bash scripts/deploy-observability.sh
```

O script instala automaticamente:
1. **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager)
2. **Loki** (armazenamento de logs)
3. **Promtail** (coleta de logs)
4. **OpenTelemetry Collector** (coleta unificada)
5. **ServiceMonitor** (scrape da aplicação)
6. **Dashboard ConfigMap** (dashboard pré-configurado)

### 2. Verificar a instalação

```bash
kubectl get pods -n monitoring
```

**Resultado esperado:**
```
NAME                                                     READY   STATUS    
kube-prometheus-stack-grafana-xxxxxxxx-xxxxx            3/3     Running
kube-prometheus-stack-prometheus-node-exporter-xxxxx    1/1     Running
prometheus-kube-prometheus-stack-prometheus-0           2/2     Running
alertmanager-kube-prometheus-stack-alertmanager-0       2/2     Running
loki-0                                                  1/1     Running
promtail-xxxxx                                          1/1     Running
otel-collector-xxxxx                                    1/1     Running
```

### 3. Acessar o Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Abra: http://localhost:3000
- **Usuário:** admin
- **Senha:** admin123

### 4. Explorar dashboards

O Grafana inclui dashboards pré-instalados:

1. **Kubernetes / Compute Resources / Namespace (Pods)** — uso de CPU e memória por pod
2. **Kubernetes / Networking / Namespace (Pods)** — tráfego de rede
3. **Site-Kubectl Overview** — dashboard customizado da nossa aplicação

### 5. Acessar o Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Abra: http://localhost:9090

Queries úteis:
```promql
# Uso de CPU da aplicação
rate(container_cpu_usage_seconds_total{namespace="reliabilitylab"}[5m])

# Uso de memória
container_memory_working_set_bytes{namespace="reliabilitylab"}

# Pods em execução
kube_pod_status_phase{namespace="reliabilitylab", phase="Running"}

# Requisições por segundo (se instrumentado)
rate(http_requests_total{namespace="reliabilitylab"}[5m])
```

### 6. Ver logs no Grafana (via Loki)

No Grafana:
1. Ir em **Explore** (ícone de bússola no menu lateral)
2. Selecionar **Loki** como data source
3. Query:
```logql
{namespace="reliabilitylab", app_kubernetes_io_name="site-kubectl"}
```

### 7. Verificar ServiceMonitor

```bash
kubectl get servicemonitor -n reliabilitylab
kubectl describe servicemonitor site-kubectl -n reliabilitylab
```

O ServiceMonitor faz o Prometheus coletar métricas do endpoint `/api/health` a cada 30 segundos.

## Arquitetura da Observabilidade

```
┌─────────────────────────────────────────────────────────┐
│                  Namespace: monitoring                    │
│                                                         │
│  ┌──────────┐    scrape     ┌──────────────────────┐    │
│  │Prometheus │ ◄─────────── │  ServiceMonitor      │    │
│  │           │              │  (reliabilitylab)    │    │
│  └─────┬────┘              └──────────────────────┘    │
│        │ datasource                                      │
│  ┌─────▼────┐              ┌──────────────────────┐    │
│  │ Grafana  │              │  Loki                 │    │
│  │          │ ◄─────────── │  (logs storage)      │    │
│  └──────────┘              └──────────┬───────────┘    │
│                                        ▲                │
│                             ┌──────────┴───────────┐    │
│                             │  Promtail (DaemonSet) │    │
│                             │  coleta logs          │    │
│                             └──────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────┐       │
│  │  OpenTelemetry Collector (DaemonSet)          │       │
│  │  OTLP gRPC :4317 | OTLP HTTP :4318           │       │
│  └──────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────┘
```

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Grafana não carrega | Verifique se o pod está running: `kubectl get pods -n monitoring` |
| Loki sem logs | Verifique se o Promtail está running e coletando: `kubectl logs -n monitoring -l app.kubernetes.io/name=promtail` |
| Prometheus sem métricas | Verifique o ServiceMonitor e se o target está UP no Prometheus UI |
| Dashboard vazio | Verifique se o ConfigMap foi aplicado e o sidecar do Grafana está habilitado |

## Próximo Tutorial

[06 — Autoscaling com HPA](06-autoscaling-hpa.md)
