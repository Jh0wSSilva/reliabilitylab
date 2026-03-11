# ReliabilityLab

**SRE Platform com SLOs, Chaos Engineering, GitOps e Observabilidade — 100% local, 100% reproduzivel.**

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-326CE5?style=flat-square&logo=kubernetes)
![Prometheus](https://img.shields.io/badge/Prometheus-stack-E6522C?style=flat-square&logo=prometheus)
![Grafana](https://img.shields.io/badge/Grafana-dashboards-F46800?style=flat-square&logo=grafana)
![Sloth](https://img.shields.io/badge/SLO-Sloth-7C3AED?style=flat-square)
![Chaos Mesh](https://img.shields.io/badge/Chaos_Mesh-CNCF-EF4444?style=flat-square)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?style=flat-square&logo=argo)
![k6](https://img.shields.io/badge/k6-Load_Testing-7D64FF?style=flat-square&logo=k6)
![NetworkPolicy](https://img.shields.io/badge/NetworkPolicy-zero--trust-1D4ED8?style=flat-square)
![Minikube](https://img.shields.io/badge/Runs_on-Minikube-00C896?style=flat-square)

---

## Por que este projeto existe

A maioria dos portfolios de SRE mostra "eu instalei o Prometheus". Este projeto mostra **como um engenheiro pensa sobre confiabilidade**:

- **SLOs como codigo** — nao apenas metricas, mas objetivos com error budget e burn rate alerts
- **Chaos Engineering com hipoteses** — nao "eu quebrei um pod", mas "eu formulei uma hipotese, projetei um experimento e documentei o resultado"
- **Decisoes documentadas** — cada escolha tecnica tem um ADR explicando alternativas consideradas e trade-offs
- **Runbooks operacionais** — respostas a incidentes pre-planejadas, nao improvisacao
- **Zero-trust networking** — default deny com politicas explicitas por servico
- **GitOps** — estado desejado declarado, reconciliacao automatica, self-heal

Este nao e um tutorial. E um **sistema projetado para falhar de forma controlada e se recuperar automaticamente**.

---

## O que voce aprende praticando este projeto

| Competencia | Onde aparece |
|-------------|-------------|
| Definir e monitorar SLOs/SLIs | `platform/slo/`, Sloth, Grafana dashboards |
| Multi-window burn rate alerting | ADR-003, PrometheusRules geradas pelo Sloth |
| Chaos Engineering com metodo cientifico | `platform/chaos/experiments/`, GameDay report |
| Observabilidade (metricas, alertas, dashboards) | kube-prometheus-stack, ServiceMonitor |
| GitOps com ArgoCD | `gitops/apps/`, self-heal automatico |
| Kubernetes avancado (HPA, ResourceQuota, LimitRange) | `k8s/namespaces/` |
| Network Policies (zero-trust) | `k8s/network-policies/` |
| Load Testing com k6 | `loadtests/` (smoke, load, stress) |
| Tomada de decisao tecnica documentada | `docs/adr/` (5 ADRs) |
| Resposta a incidentes | `docs/runbooks/` (4 runbooks) |
| Error Budget Policy | `docs/slo/error-budget-policy.md` |
| Analise de custos (FinOps) | `docs/finops/resource-optimization.md` |

---

## Arquitetura

```
Minikube (3 nos — 1 control-plane + 2 workers)
|
+-- namespace: production          NetworkPolicy: default-deny
|   +-- content-api                HPA: 2-10 pods  |  SLO: 99.9%
|   +-- recommendation-api         HPA: 2-8 pods   |  SLO: 99.5%
|   +-- player-api                 HPA: 2-6 pods   |  SLO: 99.9%
|
+-- namespace: monitoring
|   +-- Prometheus                 coleta metricas (7d retention)
|   +-- Grafana                    dashboards + SLO overview
|   +-- Alertmanager               roteamento de alertas
|   +-- Sloth                      SLO -> burn rate PrometheusRules
|
+-- namespace: chaos-mesh
|   +-- Chaos Mesh                 PodChaos, NetworkChaos, StressChaos
|
+-- namespace: argocd
    +-- ArgoCD                     GitOps — self-heal + auto-prune
```

---

## Quick Start

### Pre-requisitos

| Ferramenta | Versao minima | Verificar |
|------------|--------------|-----------|
| Docker | 20.10+ | `docker --version` |
| Minikube | v1.38+ | `minikube version` |
| kubectl | v1.32+ | `kubectl version --client` |
| Helm | v3.17+ | `helm version` |
| k6 | v0.49+ | `k6 version` |

### Versoes pinadas do stack

| Componente | Versao | Referencia |
|------------|--------|------------|
| Kubernetes (Minikube) | v1.32.0 | `scripts/bootstrap.sh` |
| podinfo (workloads) | 6.11.0 | `k8s/namespaces/*.yaml` |
| kube-prometheus-stack | 82.10.3 | Helm chart |
| Sloth | 0.15.0 | Helm chart |
| Chaos Mesh | 2.8.1 | Helm chart |
| ArgoCD | v3.3.3 | Manifest YAML |

### Setup automatizado

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

O script executa as 7 fases: cluster -> namespaces -> monitoramento -> SLOs -> servicos -> chaos mesh -> ArgoCD.

### Setup manual (passo a passo)

<details>
<summary>Clique para expandir</summary>

**1. Criar o cluster**

```bash
minikube start \
  --driver=docker \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --profile=reliabilitylab \
  --kubernetes-version=v1.32.0

minikube addons enable ingress        -p reliabilitylab
minikube addons enable metrics-server -p reliabilitylab
minikube addons enable dashboard      -p reliabilitylab
```

**2. Criar namespaces e aplicar quotas**

```bash
kubectl create namespace production
kubectl create namespace monitoring
kubectl create namespace chaos-mesh
kubectl create namespace argocd

kubectl apply -f k8s/namespaces/
```

**3. Instalar stack de monitoramento**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 82.10.3 \
  -n monitoring \
  -f helm/values/local/prometheus-values.yaml \
  --wait
```

**4. Instalar Sloth e aplicar SLOs**

```bash
helm repo add sloth https://slok.github.io/sloth
helm upgrade --install sloth sloth/sloth --version 0.15.0 -n monitoring --wait
kubectl apply -f platform/slo/
```

**5. Deploy dos servicos e network policies**

```bash
kubectl apply -f k8s/namespaces/content-api.yaml
kubectl apply -f k8s/network-policies/
```

**6. Acessar Grafana**

```bash
minikube service kube-prometheus-stack-grafana -n monitoring -p reliabilitylab
# Login: admin / admin123
```

</details>

---

## SLOs

| Servico | SLI | SLO | Error Budget (30d) | Manifest |
|---------|-----|-----|--------------------|----------|
| content-api | Availability | 99.9% | 43 minutos | `platform/slo/slo-content-api.yaml` |
| recommendation-api | Availability | 99.5% | 3.6 horas | `platform/slo/slo-recommendation-api.yaml` |
| player-api | Availability | 99.9% | 43 minutos | `platform/slo/slo-player-api.yaml` |

SLOs definidos como codigo via Sloth -> geram PrometheusRules com alertas multi-window burn rate automaticamente.

Politica de error budget documentada em [docs/slo/error-budget-policy.md](docs/slo/error-budget-policy.md) — define acoes por faixa de budget restante.

---

## GameDay #01 — Resultados

| Experimento | Hipotese | Resultado | Tempo |
|-------------|----------|-----------|-------|
| Pod Kill (PodChaos) | Recovery < 5s sem erro visivel | ~1s (imagem cached) | 14:05 |
| CPU Stress (StressChaos) | HPA escala acima de 70% CPU | 2->6 replicas em ~2min | 14:25 |
| Network Latency (NetworkChaos) | Sem falha em cascata | 0 erros nas dependencias | 14:45 |

**Surpresas:** Recovery mascarado por cache de imagem. Sem PodDisruptionBudget configurado. HPA cooldown de 5min apos normalizacao.

**Action items:** Criar PDB (`minAvailable: 1`), adicionar `initialDelaySeconds` na readiness probe, testar com `imagePullPolicy: Always`.

Relatorio completo: [docs/gamedays/gameday-01-pod-kill.md](docs/gamedays/gameday-01-pod-kill.md)

---

## Architecture Decision Records

| ADR | Decisao | Status |
|-----|---------|--------|
| [ADR-001](docs/adr/ADR-001-sloth-slos.md) | Sloth como SLO engine (vs OpenSLO, manual) | Aceita |
| [ADR-002](docs/adr/ADR-002-chaos-mesh.md) | Chaos Mesh para chaos engineering (vs LitmusChaos v3, manual) | Aceita |
| [ADR-003](docs/adr/ADR-003-burn-rate-alerts.md) | Multi-window burn rate alerting (vs threshold, budget-remaining) | Aceita |
| [ADR-004](docs/adr/ADR-004-argocd-gitops.md) | ArgoCD para GitOps (vs Flux CD, Jenkins X, manual) | Aceita |
| [ADR-005](docs/adr/ADR-005-minikube-3-nodes.md) | Minikube 3 nos (vs Kind, k3s, Docker Desktop K8s) | Aceita |

---

## Documentacao

### Runbooks

| Alerta | Runbook |
|--------|---------|
| SlothErrorBudgetBurnRateCritical | [runbook-slo-burn-rate-critical.md](docs/runbooks/runbook-slo-burn-rate-critical.md) |
| KubePodCrashLooping | [runbook-pod-crashloop.md](docs/runbooks/runbook-pod-crashloop.md) |
| HPA com targets `<unknown>` | [runbook-hpa-not-scaling.md](docs/runbooks/runbook-hpa-not-scaling.md) |
| MemoryPressure / DiskPressure | [runbook-node-pressure.md](docs/runbooks/runbook-node-pressure.md) |

### Politicas e analises

- [Error Budget Policy](docs/slo/error-budget-policy.md) — acoes por faixa de budget restante
- [FinOps — Resource Optimization](docs/finops/resource-optimization.md) — analise de custos AWS/GCP, rightsizing, HPA impact

### Tutoriais

| # | Tutorial |
|---|---------|
| 01 | [Ambiente Minikube](docs/tutorials/tutorial-01-ambiente-minikube.md) |
| 02 | [Namespaces e Quotas](docs/tutorials/tutorial-02-namespaces-quota.md) |
| 03 | [Deployments e HPA](docs/tutorials/tutorial-03-deployments-hpa.md) |
| 04 | [Prometheus e Grafana](docs/tutorials/tutorial-04-prometheus-grafana.md) |
| 05 | [SLOs com Sloth](docs/tutorials/tutorial-05-slos-sloth.md) |
| 06 | [Chaos Engineering com Chaos Mesh](docs/tutorials/tutorial-06-chaos-mesh.md) |
| 07 | [GitOps com ArgoCD](docs/tutorials/tutorial-07-argocd.md) |
| 08 | [Load Testing com k6](docs/tutorials/tutorial-08-k6-load-testing.md) |
| 09 | [GameDay](docs/tutorials/tutorial-09-gameday.md) |
| 10 | [LinkedIn e GitHub](docs/tutorials/tutorial-10-linkedin-github.md) |

---

## Estrutura do Repositorio

```
reliabilitylab/
+-- k8s/
|   +-- namespaces/
|   |   +-- content-api.yaml            # Deployment + Service + HPA
|   |   +-- production-quota.yaml       # ResourceQuota
|   |   +-- production-limitrange.yaml  # LimitRange
|   +-- network-policies/
|   |   +-- default-deny.yaml           # Zero-trust: deny all
|   |   +-- allow-streamflix-internal.yaml
|   |   +-- allow-prometheus-scrape.yaml
|   |   +-- allow-ingress.yaml
|   +-- servicemonitor-streamflix.yaml
+-- platform/
|   +-- slo/                            # Sloth PrometheusServiceLevel CRDs
|   +-- chaos/experiments/              # Chaos Mesh experiments
|   +-- monitoring/rules/               # PrometheusRules customizadas
+-- helm/values/local/                  # Helm values para ambiente local
+-- gitops/
|   +-- apps/                           # ArgoCD Applications
|   +-- appsets/                        # ApplicationSets
+-- loadtests/                          # k6: smoke, load, stress
+-- scripts/
|   +-- bootstrap.sh                    # Setup automatizado (7 fases)
+-- docs/
|   +-- adr/                            # 5 ADRs (MADR format)
|   +-- runbooks/                       # 4 runbooks operacionais
|   +-- gamedays/                       # GameDay reports
|   +-- slo/                            # Error budget policy
|   +-- finops/                         # Analise de custos
|   +-- postmortems/                    # Templates de postmortem
|   +-- tutorials/                      # 10 tutoriais passo a passo
+-- .github/workflows/
|   +-- validate.yaml                   # CI: kubeconform + helm lint
+-- TROUBLESHOOTING.md                  # 7 problemas reais (P1-P7)
```

---

## Stack

| Ferramenta | Versao | Funcao |
|-----------|--------|--------|
| Minikube | v1.38+ | Cluster Kubernetes local (3 nos) |
| Kubernetes | v1.32.0 | Orquestracao de containers |
| Helm | v3.14+ | Gerenciador de pacotes K8s |
| Prometheus | kube-prometheus-stack | Coleta e armazenamento de metricas |
| Grafana | latest | Dashboards e visualizacao |
| Alertmanager | latest | Roteamento de alertas |
| Sloth | latest | SLO engine — burn rate alerts |
| Chaos Mesh | latest | Chaos engineering (PodChaos, NetworkChaos, StressChaos) |
| ArgoCD | latest | GitOps — self-heal + auto-prune |
| k6 | latest | Load testing (smoke, load, stress) |

---

## Como adaptar este projeto

Este projeto foi construido para ser **reproduzivel e extensivel**. Veja como adapta-lo:

### Trocar os servicos ficticios por reais

1. Substitua a imagem `ghcr.io/stefanprodan/podinfo` nos Deployments pela sua aplicacao
2. Ajuste as portas nos Services e NetworkPolicies se diferente de 9898
3. Atualize os SLOs em `platform/slo/` com suas metricas reais
4. Reconfigure os thresholds do HPA conforme o perfil de CPU/memoria da sua aplicacao

### Migrar para cloud (EKS/GKE)

1. Substitua o Minikube por um cluster managed (ver [docs/finops/resource-optimization.md](docs/finops/resource-optimization.md) para estimativas de custo)
2. Troque `NodePort` por `LoadBalancer` ou Ingress Controller do provider
3. Configure storage real para o Prometheus (`alertmanagerSpec.storage`)
4. Adicione Cluster Autoscaler para escalar nos automaticamente

### Adicionar novos servicos

1. Crie o Deployment + Service + HPA seguindo o padrao de `k8s/namespaces/content-api.yaml`
2. Adicione uma NetworkPolicy em `k8s/network-policies/`
3. Crie um SLO em `platform/slo/` e um ServiceMonitor
4. Documente a decisao em um novo ADR se houver trade-off relevante

---

## Troubleshooting

Encontrou problemas? Veja o [TROUBLESHOOTING.md](TROUBLESHOOTING.md) com 7 problemas reais documentados (P1-P7) e suas solucoes.

---

## Referencias

- [SRE Workbook — Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- [Sloth Documentation](https://sloth.dev)
- [Chaos Mesh Documentation](https://chaos-mesh.org/docs)
- [Principles of Chaos Engineering](https://principlesofchaos.org)
- [MADR — Markdown Architectural Decision Records](https://adr.github.io/madr/)
