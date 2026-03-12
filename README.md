# ReliabilityLab — SRE Reliability Engineering Platform

**Plataforma completa de SRE e Engenharia de Confiabilidade — SLOs, alertas, chaos outage, pipeline de resiliência — 100% local, tutorial-driven, pronta para portfólio.**

![Kubernetes](https://img.shields.io/badge/Kubernetes-local-326CE5?style=flat-square&logo=kubernetes)
![FastAPI](https://img.shields.io/badge/FastAPI-Python-009688?style=flat-square&logo=fastapi)
![Prometheus](https://img.shields.io/badge/Prometheus-Grafana-E6522C?style=flat-square&logo=prometheus)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=flat-square&logo=argo)
![Docker](https://img.shields.io/badge/Docker-multi--stage-2496ED?style=flat-square&logo=docker)
![k6](https://img.shields.io/badge/k6-Load%20Testing-7D64FF?style=flat-square&logo=k6)
![Chaos](https://img.shields.io/badge/Chaos-Engineering-FF4444?style=flat-square)
![SLO](https://img.shields.io/badge/SLO-Error%20Budget-00C853?style=flat-square)
![Alertmanager](https://img.shields.io/badge/Alertmanager-Routing-FF6D00?style=flat-square)

---

## O que é este projeto?

É um **laboratório prático de SRE e Engenharia de Confiabilidade** que pode ser executado inteiramente na sua máquina local. Cada componente técnico vem acompanhado de um **tutorial passo-a-passo** explicando o que é, por que existe e como rodar.

A aplicação principal é o **site-kubectl**, um portal educacional construído com Python + FastAPI + Jinja2.

O lab cobre: containerização, orquestração Kubernetes, observabilidade, autoscaling, segurança, **chaos engineering**, **load testing**, **GitOps**, **resposta a incidentes**, **SLOs/SLIs com error budget**, **alerting com Prometheus e Alertmanager**, **simulação de outage** e **pipeline de resiliência contínua**.

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                 Cluster Kubernetes Local                         │
│               (kind / k3d / minikube)                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  reliabilitylab                                          │    │
│  │  ┌──────────┐ ┌──────────┐      HPA: 2-6 réplicas      │    │
│  │  │ Pod :8000 │ │ Pod :8000 │     NetworkPolicy: zero-trust │  │
│  │  └─────┬────┘ └─────┬────┘      PDB: minAvailable=1    │    │
│  │        └──────┬──────┘           RBAC: viewer/deployer  │    │
│  │          Service :80             PSS: restricted         │    │
│  └──────────────┬──────────────────────────────────────────┘    │
│          Ingress │ site-kubectl.local                            │
│                                                                 │
│  ┌────────────────────────────┐  ┌──────────────────────────┐   │
│  │  monitoring                 │  │  argocd                   │   │
│  │  Prometheus + Grafana      │  │  GitOps auto-sync        │   │
│  │  Loki + Promtail          │  │  Self-heal                │   │
│  │  OTel Collector            │  │                           │   │
│  │  ─────────────────────    │  └──────────────────────────┘   │
│  │  SLO Dashboard (Grafana)  │                                  │
│  │  PrometheusRule (12 alerts)│                                  │
│  │  Alertmanager (routing)   │                                  │
│  │  Webhook Logger           │                                  │
│  └────────────────────────────┘                                  │
│                                                                 │
│  ┌────────────────────────────┐  ┌──────────────────────────┐   │
│  │  chaos/                     │  │  load-testing/            │   │
│  │  Pod delete                │  │  k6: smoke, load,        │   │
│  │  CPU / Memory stress       │  │      stress, spike       │   │
│  │  Network latency           │  │  ──────────────────      │   │
│  │  ─────────────────────    │  │  Resilience test (k6)    │   │
│  │  Total Pod Kill (outage)  │  │  SLO threshold validation│   │
│  │  Network Partition        │  │                           │   │
│  │  Resource Exhaustion      │  └──────────────────────────┘   │
│  └────────────────────────────┘                                  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Pipeline de Resiliência (scripts/run-resilience-tests.sh) │   │
│  │  Smoke → Chaos + Load → Validar SLOs → Relatório          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Pré-requisitos

| Ferramenta | Verificar |
|------------|-----------|
| Docker 20.10+ | `docker --version` |
| kubectl 1.28+ | `kubectl version --client` |
| Helm 3.12+ | `helm version` |
| kind / k3d / minikube | `kind --version` / `k3d --version` / `minikube version` |

### Setup automático

```bash
git clone https://github.com/Jh0wSSilva/reliabilitylab.git
cd reliabilitylab
bash scripts/setup.sh
```

O script detecta automaticamente sua ferramenta de cluster (kind, k3d ou minikube) e executa:
1. Criação do cluster com 3 nós
2. Build da imagem Docker
3. Import da imagem no cluster
4. Instalação do NGINX Ingress Controller e Metrics Server
5. Deploy dos manifests Kubernetes

### Setup manual

```bash
# 1. Build da imagem
bash scripts/build.sh

# 2. Criar cluster (exemplo com kind)
kind create cluster --name reliabilitylab --config scripts/kind-config.yaml

# 3. Carregar imagem
bash scripts/load-image.sh

# 4. Instalar Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# 5. Deploy da aplicação
bash scripts/deploy.sh

# 6. Configurar DNS local
echo "127.0.0.1 site-kubectl.local" | sudo tee -a /etc/hosts

# 7. Testar
curl http://site-kubectl.local/api/health
```

---

## Componentes

### Aplicação (site_kubectl/)

| Campo | Valor |
|-------|-------|
| Linguagem | Python 3.12 |
| Framework | FastAPI + Jinja2 |
| Servidor | Uvicorn |
| Porta | 8000 |
| Health check | GET /api/health |

### Kubernetes (k8s/)

| Manifest | Função |
|----------|--------|
| namespace.yaml | Namespace `reliabilitylab` |
| deployment.yaml | 2 réplicas com probes e security context |
| service.yaml | ClusterIP na porta 80 |
| ingress.yaml | NGINX Ingress em `site-kubectl.local` |
| configmap.yaml | Variáveis de ambiente |
| secret.yaml | Valores sensíveis |

### Plataforma (platform/)

| Recurso | Função |
|---------|--------|
| hpa.yaml | Autoscaling horizontal (2-6 pods, CPU 70%) |
| networkpolicy.yaml | Zero-trust (permite apenas Ingress + Prometheus) |
| pdb.yaml | Disponibilidade mínima durante disruptions |

### Observabilidade (observability/)

| Componente | Função |
|-----------|--------|
| Prometheus | Coleta de métricas a cada 30s |
| Grafana | Dashboards e alertas visuais |
| Loki + Promtail | Logs centralizados |
| OTel Collector | Métricas, logs e traces via OpenTelemetry |

### Chaos Engineering (chaos/)

| Experimento | Função |
|-------------|--------|
| pod-delete.yaml | Deleção de pod aleatório para testar self-healing |
| pod-cpu-stress.yaml | Stress de CPU por 60s para testar HPA |
| pod-memory-stress.yaml | Consumo de 256MB para testar OOM behavior |
| pod-network-latency.yaml | Baseline de latência de rede |

### Load Testing (load-testing/)

| Teste | VUs | Duração | Objetivo |
|-------|-----|---------|----------|
| smoke-test.js | 1-3 | 30s | Funcionalidade básica |
| load-test.js | até 20 | 3min | Performance normal |
| stress-test.js | até 50 | 5min | Encontrar limites |
| spike-test.js | 1→80 | 3min | Picos súbitos de tráfego |

### Segurança (security/)

| Recurso | Função |
|---------|--------|
| rbac.yaml | Roles viewer e deployer com menor privilégio |
| pod-security.yaml | Pod Security Standards (restricted) |
| secrets-management.yaml | Guia educacional de gestão de segredos |

### GitOps (gitops/)

| Componente | Função |
|-----------|--------|
| ArgoCD | Sync automático do Git para o cluster |
| Application | Monitora a pasta k8s/ na branch main |

### SLO Monitoring (observability/prometheus/ + observability/grafana/)

| Recurso | Função |
|---------|--------|
| alerts.yaml | PrometheusRule CRD com 12 regras de alerta (SLO burn rate, application, infrastructure) |
| SLO Dashboard | Dashboard Grafana com 18 painéis: availability, error budget, burn rate, latência |
| slo-dashboard-configmap.yaml | ConfigMap para importação automática via Grafana sidecar |

### Alertmanager (observability/alertmanager/)

| Recurso | Função |
|---------|--------|
| config.yaml | ConfigMap com roteamento de alertas: critical, warning, slo, info |
| webhook-logger.yaml | Receptor de alertas local (Python HTTP) para visualização em logs |

### Cenários de Outage (chaos/scenarios/)

| Cenário | Função |
|---------|--------|
| total-pod-kill.yaml | Destrói todos os pods com --force e monitora recuperação |
| network-partition.yaml | Bloqueia todo tráfego de rede via NetworkPolicy temporária |
| resource-exhaustion.yaml | Stress de CPU e memória com monitoramento em tempo real |

### Pipeline de Resiliência (scripts/ + load-testing/)

| Recurso | Função |
|---------|--------|
| run-resilience-tests.sh | Pipeline completo de 5 etapas: smoke → chaos + load → validar SLOs → relatório |
| resilience-test.js | Teste k6 com validação de thresholds SLO (error rate, latência P95/P99) |

---

## Scripts de Automação

Toda a automação é feita via **bash scripts** na pasta `scripts/`:

```bash
bash scripts/setup.sh              # Setup completo automatizado
bash scripts/build.sh              # Construir imagem Docker
bash scripts/load-image.sh         # Carregar imagem no cluster
bash scripts/deploy.sh             # Aplicar manifests K8s
bash scripts/deploy-platform.sh    # Aplicar HPA, NetworkPolicy e PDB
bash scripts/deploy-observability.sh  # Instalar Prometheus, Grafana, Loki, OTel
bash scripts/deploy-argocd.sh      # Instalar ArgoCD
bash scripts/run-load-test.sh smoke|load|stress|spike  # Testes de carga k6
bash scripts/run-chaos.sh apply|delete|list pod-delete # Chaos experiments
bash scripts/run-resilience-tests.sh all|pod-kill|network|resource|quick  # Pipeline de resiliência
bash scripts/status.sh             # Status completo do cluster
bash scripts/destroy.sh            # Remover cluster e imagem
```

---

## Tutoriais

18 tutoriais práticos em **pt-BR** com explicação conceitual, comandos e troubleshooting:

| # | Tutorial | Conceito |
|---|---------|----------|
| 01 | [Rodando a aplicação localmente](docs/tutorials/01-rodando-aplicacao-localmente.md) | Python, FastAPI, Uvicorn |
| 02 | [Containerização com Docker](docs/tutorials/02-containerizacao-docker.md) | Multi-stage build, non-root |
| 03 | [Criando cluster Kubernetes local](docs/tutorials/03-criando-cluster-kubernetes-local.md) | kind, k3d, minikube |
| 04 | [Deploy no Kubernetes](docs/tutorials/04-deploy-kubernetes.md) | Deployment, Service, Ingress |
| 05 | [Observabilidade com Prometheus e Grafana](docs/tutorials/05-observabilidade-prometheus-grafana.md) | Métricas, logs, traces |
| 06 | [Autoscaling com HPA](docs/tutorials/06-autoscaling-hpa.md) | Escala horizontal automática |
| 07 | [Segurança de rede com NetworkPolicy](docs/tutorials/07-seguranca-rede-networkpolicy.md) | Zero-trust, RBAC, PSS |
| 08 | [Chaos Engineering](docs/tutorials/08-chaos-engineering.md) | Experimentos de falha controlada |
| 09 | [Load Testing com k6](docs/tutorials/09-load-testing-k6.md) | Smoke, load, stress, spike |
| 10 | [Observando falhas e recuperação](docs/tutorials/10-observando-falhas-recuperacao.md) | MTTR, self-healing, degradação |
| 11 | [GitOps com ArgoCD](docs/tutorials/11-gitops-argocd.md) | Deploy declarativo, self-heal |
| 12 | [Simulação de resposta a incidentes](docs/tutorials/12-simulacao-resposta-incidentes.md) | Severidade, diagnóstico, post-mortem |
| 13 | [SLO e Error Budget](docs/tutorials/tutorial-13-slo-error-budget.md) | SLI, SLO, error budget, burn rate |
| 14 | [Prometheus Alerting](docs/tutorials/tutorial-14-prometheus-alerting.md) | PrometheusRule, multi-window burn rate |
| 15 | [Alertmanager](docs/tutorials/tutorial-15-alertmanager.md) | Roteamento, receivers, silences |
| 16 | [Chaos Outage Simulation](docs/tutorials/tutorial-16-chaos-outage-simulation.md) | Pod kill total, network partition, resource exhaustion |
| 17 | [Pipeline de Resiliência](docs/tutorials/tutorial-17-resilience-testing-pipeline.md) | Pipeline automatizado, validação SLO |
| 18 | [Confiabilidade Contínua](docs/tutorials/tutorial-18-continuous-reliability.md) | Game Day, postmortem, maturidade |

---

## Documentação Técnica

| Documento | Conteúdo |
|-----------|----------|
| [Arquitetura](docs/architecture.md) | Stack tecnológico, diagrama, decisões |
| [Princípios de SRE](docs/sre-principles.md) | Observabilidade, SLOs, automação, golden signals |
| [Modelo SLO](docs/sre/slo-model.md) | SLI, SLO, error budget, burn rate, PromQL |
| [Runbook](docs/runbook.md) | Guia operacional para resolução de problemas |
| [Resposta a Incidentes](docs/incident-response.md) | Severidades, cenários, post-mortem template |
| [Simulação de Incidentes](docs/runbooks/incident-simulation.md) | 4 cenários de outage, postmortem, métricas de maturidade |
| [Diagrama de Arquitetura](diagrams/architecture.md) | Diagramas Mermaid detalhados |

---

## Estrutura do Repositório

```
reliabilitylab/
├── README.md                          # Este arquivo
├── site_kubectl/                      # Aplicação principal
│   ├── Dockerfile                     # Build multi-stage otimizado
│   ├── docker-compose.yml             # Dev local com hot-reload
│   ├── requirements.txt               # Dependências Python
│   ├── nginx.conf                     # Reverse proxy config
│   ├── app/                           # Código FastAPI
│   │   ├── main.py
│   │   ├── data/                      # Conteúdo JSON
│   │   ├── models/                    # Modelos Pydantic
│   │   ├── routers/                   # Rotas da API
│   │   └── static/                    # CSS/JS
│   └── templates/                     # Templates Jinja2
├── k8s/                               # Manifests Kubernetes
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   └── pvc.yaml
├── platform/                          # Engenharia de confiabilidade
│   ├── hpa.yaml                       # Autoscaling horizontal
│   ├── networkpolicy.yaml             # Zero-trust networking
│   └── pdb.yaml                       # Pod disruption budget
├── observability/                     # Stack de observabilidade
│   ├── prometheus/
│   │   ├── values.yaml
│   │   ├── servicemonitor.yaml
│   │   └── alerts.yaml                # PrometheusRule com 12 alertas (SLO, app, infra)
│   ├── grafana/
│   │   ├── dashboard-configmap.yaml
│   │   ├── slo-dashboard-configmap.yaml  # Dashboard SLO (18 painéis)
│   │   └── dashboards/
│   ├── alertmanager/
│   │   ├── config.yaml                # Roteamento: critical, warning, slo, info
│   │   └── webhook-logger.yaml        # Receptor HTTP local de alertas
│   ├── loki/
│   │   ├── values.yaml
│   │   └── promtail-values.yaml
│   └── otel/
│       └── values.yaml
├── chaos/                             # Chaos Engineering
│   ├── pod-delete.yaml                # Deleção de pod + RBAC
│   ├── pod-cpu-stress.yaml            # Stress de CPU
│   ├── pod-memory-stress.yaml         # Stress de memória
│   ├── pod-network-latency.yaml       # Latência de rede
│   └── scenarios/                     # Cenários de outage
│       ├── total-pod-kill.yaml        # Destruir todos os pods + monitorar recuperação
│       ├── network-partition.yaml     # Partição de rede via NetworkPolicy
│       └── resource-exhaustion.yaml   # Stress CPU + memória + monitor
├── load-testing/                      # Testes de carga k6
│   ├── smoke-test.js                  # Teste rápido
│   ├── load-test.js                   # Carga normal
│   ├── stress-test.js                 # Limites do sistema
│   ├── spike-test.js                  # Picos de tráfego
│   └── resilience-test.js            # Teste de resiliência com validação SLO
├── security/                          # Segurança
│   ├── rbac.yaml                      # Roles e bindings
│   ├── pod-security.yaml              # Pod Security Standards
│   └── secrets-management.yaml        # Guia de gestão de segredos
├── gitops/                            # GitOps com ArgoCD
│   └── argocd/
│       └── application.yaml           # ArgoCD Application
├── scripts/                           # Automação via bash
│   ├── setup.sh                       # Setup completo
│   ├── build.sh                       # Build Docker
│   ├── deploy.sh                      # Deploy K8s
│   ├── deploy-platform.sh            # HPA, NP, PDB
│   ├── deploy-observability.sh        # Prometheus, Grafana, Loki, Alertas, Alertmanager
│   ├── deploy-argocd.sh              # ArgoCD
│   ├── load-image.sh                  # Carregar imagem no cluster
│   ├── run-load-test.sh              # Testes k6
│   ├── run-chaos.sh                   # Chaos experiments
│   ├── run-resilience-tests.sh        # Pipeline de resiliência (smoke → chaos → SLO → relatório)
│   ├── status.sh                      # Status do cluster
│   ├── destroy.sh                     # Remover tudo
│   └── kind-config.yaml              # Config do cluster kind
├── docs/                              # Documentação
│   ├── architecture.md
│   ├── sre-principles.md
│   ├── runbook.md
│   ├── incident-response.md
│   ├── sre/
│   │   └── slo-model.md              # Modelo SLI/SLO/Error Budget/Burn Rate
│   ├── runbooks/
│   │   └── incident-simulation.md    # 4 cenários de outage + postmortem template
│   └── tutorials/                     # 18 tutoriais em pt-BR
│       ├── 01-rodando-aplicacao-localmente.md
│       ├── 02-containerizacao-docker.md
│       ├── 03-criando-cluster-kubernetes-local.md
│       ├── 04-deploy-kubernetes.md
│       ├── 05-observabilidade-prometheus-grafana.md
│       ├── 06-autoscaling-hpa.md
│       ├── 07-seguranca-rede-networkpolicy.md
│       ├── 08-chaos-engineering.md
│       ├── 09-load-testing-k6.md
│       ├── 10-observando-falhas-recuperacao.md
│       ├── 11-gitops-argocd.md
│       ├── 12-simulacao-resposta-incidentes.md
│       ├── tutorial-13-slo-error-budget.md
│       ├── tutorial-14-prometheus-alerting.md
│       ├── tutorial-15-alertmanager.md
│       ├── tutorial-16-chaos-outage-simulation.md
│       ├── tutorial-17-resilience-testing-pipeline.md
│       └── tutorial-18-continuous-reliability.md
└── diagrams/
    └── architecture.md                # Diagramas Mermaid
```

---

## Competências Demonstradas

| Área | Tecnologia / Prática |
|------|---------------------|
| Containerização | Docker multi-stage, non-root, healthcheck |
| Orquestração | Kubernetes (Deployment, Service, Ingress, ConfigMap, Secret) |
| Confiabilidade | Probes (readiness, liveness, startup), PDB, RollingUpdate |
| SLO/SLI | Error budget, burn rate multi-window, PromQL, PrometheusRule |
| Alerting | Prometheus alerting rules, Alertmanager routing, webhook receivers |
| Autoscaling | HPA com CPU e memória, políticas de scale up/down |
| Segurança | NetworkPolicy zero-trust, RBAC, Pod Security Standards, securityContext |
| Observabilidade | Prometheus, Grafana (dashboards SLO), Loki, Promtail, OpenTelemetry |
| Chaos Engineering | Pod delete, stress CPU/memória, total pod kill, network partition, resource exhaustion |
| Load Testing | k6 (smoke, load, stress, spike, resilience com validação SLO) |
| Resiliência | Pipeline automatizado: smoke → chaos + load → validação SLO → relatório |
| GitOps | ArgoCD com auto-sync e self-heal |
| Incident Response | Severidades, diagnóstico, mitigação, post-mortem blameless, Game Day |
| Automação | Scripts bash, infraestrutura como código |
| Documentação | 18 tutoriais, runbooks, diagramas, princípios de SRE, modelo SLO |

---

## Licença

Este projeto é de uso educacional. Sinta-se à vontade para usar, modificar e compartilhar.
