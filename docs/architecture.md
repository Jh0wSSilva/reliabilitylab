# Arquitetura — ReliabilityLab

## Visão Geral

O ReliabilityLab é uma plataforma de aprendizado DevOps e SRE projetada para rodar **100% localmente** em um cluster Kubernetes (kind, k3d ou minikube).

A aplicação principal é o **site-kubectl**, um portal educacional construído com Python + FastAPI + Jinja2, que serve como serviço central do laboratório.

## Stack Tecnológico

| Componente | Tecnologia | Função |
|------------|-----------|--------|
| Aplicação | Python 3.12, FastAPI, Jinja2 | Portal web educacional |
| Servidor | Uvicorn | ASGI server |
| Container | Docker (multi-stage) | Empacotamento da aplicação |
| Orquestração | Kubernetes | Gerenciamento de containers |
| Ingress | NGINX Ingress Controller | Roteamento HTTP externo |
| Métricas | Prometheus + Grafana | Coleta e visualização de métricas |
| Alertas SLO | PrometheusRule + Alertmanager | Burn rate, error budget, alertas multi-window |
| Logs | Loki + Promtail | Centralização de logs |
| Traces | OpenTelemetry Collector | Rastreamento distribuído |
| GitOps | ArgoCD | Deploy contínuo declarativo |
| Autoscaling | HPA | Escala horizontal automática |
| Segurança de rede | NetworkPolicy | Controle de tráfego zero-trust |
| Chaos Engineering | Jobs K8s + cenários de outage | Testes de falhas (pod-kill, network, recursos) |
| Load Testing | k6 | Smoke, load, stress, spike, resiliência |
| Resiliência | Pipeline bash | Testes automatizados chaos + carga + SLO |

## Diagrama de Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster Kubernetes Local                      │
│                  (kind / k3d / minikube)                         │
│                                                                 │
│  ┌──────────────┐                                               │
│  │ NGINX Ingress│◄── site-kubectl.local ──── Navegador          │
│  │  Controller  │                                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│  ┌──────▼───────────────────────────────────────────────────┐   │
│  │              namespace: reliabilitylab                    │   │
│  │                                                          │   │
│  │  ┌────────────────┐  ┌────────────────┐                  │   │
│  │  │  site-kubectl   │  │  site-kubectl   │  ◄── HPA       │   │
│  │  │  Pod (réplica 1)│  │  Pod (réplica 2)│     2-6 pods   │   │
│  │  │  :8000          │  │  :8000          │                │   │
│  │  └────────┬───────┘  └────────┬───────┘                  │   │
│  │           │                    │                          │   │
│  │  ┌────────▼────────────────────▼───────┐                 │   │
│  │  │         Service (ClusterIP)          │                 │   │
│  │  │         :80 → :8000                  │                 │   │
│  │  └────────────────────────────────────┘                  │   │
│  │                                                          │   │
│  │  NetworkPolicy: zero-trust (ingress + prometheus only)   │   │
│  │  PDB: minAvailable=1                                     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              namespace: monitoring                        │   │
│  │                                                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────┐  ┌─────────────┐  │   │
│  │  │Prometheus │  │ Grafana  │  │ Loki │  │  OTel       │  │   │
│  │  │          │  │          │  │      │  │  Collector  │  │   │
│  │  │  scrape  │  │dashboards│  │ logs │  │  métricas/  │  │   │
│  │  │  /metrics│  │  + alertas│  │      │  │  logs/traces│  │   │
│  │  └──────────┘  └──────────┘  └──────┘  └─────────────┘  │   │
│  │                                                          │   │
│  │  Promtail (DaemonSet) — coleta logs de todos os pods     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              namespace: argocd                            │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────┐                    │   │
│  │  │          ArgoCD Server           │                    │   │
│  │  │  GitOps: monitora repo GitHub    │                    │   │
│  │  │  Auto-sync + Self-heal           │                    │   │
│  │  └──────────────────────────────────┘                    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Fluxo de Dados

1. **Usuário** acessa `http://site-kubectl.local` no navegador
2. **NGINX Ingress Controller** recebe a requisição e roteia para o Service
3. **Service** distribui entre os pods do Deployment (load balancing)
4. **Pod site-kubectl** processa a requisição (FastAPI + Jinja2)
5. **Prometheus** faz scrape das métricas a cada 30s via ServiceMonitor
6. **Promtail** coleta logs dos pods e envia para o **Loki**
7. **Grafana** exibe dashboards unificados (métricas + logs)
8. **HPA** monitora CPU/memória e escala o Deployment automaticamente
9. **ArgoCD** monitora o repositório Git e sincroniza os manifests

## Decisões de Arquitetura

### Por que FastAPI?
- Framework moderno com suporte nativo a async/await
- Documentação automática via OpenAPI (Swagger)
- Performance superior com Uvicorn (ASGI)
- Tipagem forte com Pydantic

### Por que multi-stage Docker build?
- Reduz tamanho da imagem final (sem compiladores/headers)
- Separação clara entre build e runtime
- Segurança: menos superfície de ataque

### Por que Kubernetes local?
- Reprodutibilidade total do ambiente de produção
- Aprendizado prático sem custos de cloud
- Portabilidade entre kind, k3d e minikube

### Por que zero-trust NetworkPolicy?
- Princípio de menor privilégio aplicado à rede
- Visibilidade explícita do tráfego permitido
- Proteção contra movimentação lateral em caso de compromisso

## Arquitetura SRE — SLO Monitoring

### Fluxo de Monitoramento de SLOs

```
Prometheus (scrape) → PrometheusRule (alertas) → Alertmanager (routing)
    ↓                                                     ↓
Grafana SLO Dashboard                           Webhook Logger (local)
    ↓                                                     ↓
- Disponibilidade gauge                        Logs de alertas por canal:
- Error Budget consumido                       - /webhook/critical
- Burn Rate multi-window                       - /webhook/warning
- Latência percentis                           - /webhook/slo
- Taxa de erros                                - /webhook/info
```

### Alertas Configurados

| Alerta | Severidade | Condição |
|--------|-----------|----------|
| SLOBurnRateCritical | critical | Burn rate > 14.4x (budget esgota em ~1h) |
| SLOBurnRateHigh | warning | Burn rate > 6x (budget esgota em ~6h) |
| SLOBurnRateWarning | info | Burn rate > 2x (budget esgota em ~3d) |
| HighErrorRate | critical | Taxa de erros > 5% por 5 min |
| HighLatencyP95 | warning | P95 > 1s por 5 min |
| HighLatencyP99 | critical | P99 > 3s por 5 min |
| PodCrashLooping | critical | > 3 restarts em 15 min |
| ServiceUnavailable | critical | 0 pods disponíveis |
| ReplicasMismatch | warning | Réplicas < desejado por 10 min |
| HighCPUUsage | warning | CPU > 90% do limit por 10 min |
| HighMemoryUsage | warning | Memória > 85% do limit por 5 min |

### Pipeline de Resiliência

```
run-resilience-tests.sh
├── 1. Verificar pré-requisitos (kubectl, k6, cluster, namespace, pods)
├── 2. Smoke test (verificar serviço OK)
├── 3. Chaos + Carga simultânea
│   ├── pod-kill: eliminação total de pods
│   ├── network: partição de rede via NetworkPolicy
│   └── resource: exaustão de CPU/memória
├── 4. Validar SLOs (pods, restarts, alertas)
└── 5. Gerar relatório
```
