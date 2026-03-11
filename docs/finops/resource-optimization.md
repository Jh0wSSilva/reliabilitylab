# FinOps — Resource Optimization Analysis

Análise de custos e otimização de recursos para o ambiente StreamFlix no Kubernetes.

---

## Inventário de Recursos Atual

### Pods por Serviço

| Serviço | Replicas | requests.cpu | requests.mem | limits.cpu | limits.mem |
|---------|----------|-------------|-------------|-----------|-----------|
| content-api | 2 | 50m | 64Mi | 200m | 256Mi |
| recommendation-api | 2 | 50m | 64Mi | 200m | 256Mi |
| player-api | 2 | 50m | 64Mi | 200m | 256Mi |
| **Total (6 pods)** | — | **300m** | **384Mi** | **1200m** | **1536Mi** |

### ResourceQuota (namespace: production)

| Recurso | Quota | Usado | Utilização |
|---------|-------|-------|------------|
| requests.cpu | 4 | 300m | 7.5% |
| requests.memory | 4Gi | 384Mi | 9.4% |
| limits.cpu | 8 | 1200m | 15% |
| limits.memory | 8Gi | 1536Mi | 18.8% |
| pods | 30 | 6 | 20% |

**Observação:** A quota está significativamente superdimensionada para a carga atual. Isso é intencional para permitir escalabilidade via HPA (até 10 replicas por serviço = 30 pods máximo).

---

## Análise de Custo em Cloud

### Custo estimado em AWS (EKS)

Baseado em instâncias `t3.medium` (2 vCPU, 4 GiB RAM) — similar ao Minikube.

| Componente | Quantidade | Custo/mês (us-east-1) |
|------------|-----------|----------------------|
| EKS Control Plane | 1 | $73.00 |
| EC2 t3.medium (worker) | 2 | $60.74 ($30.37 × 2) |
| EBS gp3 20GB (por nó) | 3 | $4.80 ($1.60 × 3) |
| **Subtotal infraestrutura** | — | **$138.54** |
| Prometheus (EBS 10GB) | 1 | $0.80 |
| Grafana (incluso) | 1 | $0.00 |
| **Total estimado** | — | **~$139/mês** |

**Com Reserved Instances (1 ano):** ~$95/mês (economia de ~32%)

### Custo estimado em GCP (GKE)

Baseado em `e2-medium` (2 vCPU, 4 GB RAM) — equivalente.

| Componente | Quantidade | Custo/mês (us-central1) |
|------------|-----------|------------------------|
| GKE Management Fee | 1 | $0.00 (free tier: 1 zonal cluster) |
| Compute e2-medium | 2 | $48.92 ($24.46 × 2) |
| Boot Disk 20GB | 3 | $3.00 ($1.00 × 3) |
| **Subtotal infraestrutura** | — | **$51.92** |
| Prometheus (PD 10GB) | 1 | $0.40 |
| **Total estimado** | — | **~$52/mês** |

**Com Committed Use (1 ano):** ~$37/mês (economia de ~29%)

### Comparativo

| Provider | On-Demand/mês | Reservado/mês | Observação |
|----------|--------------|---------------|------------|
| AWS (EKS) | ~$139 | ~$95 | Control plane caro ($73) |
| GCP (GKE) | ~$52 | ~$37 | Free tier para zonal cluster |

---

## Análise de Overprovision

### CPU

```
Alocado (requests): 300m
Alocado (limits):   1200m
Necessário (idle):  ~60m (estimado ~20% utilization)
Ratio request/limit: 4x
```

**Diagnóstico:** O ratio de 4× entre requests e limits é agressivo. Se todos os pods usarem 100% do limit simultaneamente:
- Total CPU demand: 1200m (1.2 cores)
- Total CPU disponível no cluster: 6 cores (3 nós × 2 vCPU)
- Headroom: 80%

**Recomendação:** O ratio 4× é aceitável para workloads burstáveis como APIs HTTP. Para workloads CPU-intensive, reduzir para 2×.

### Memória

```
Alocado (requests): 384Mi
Alocado (limits):   1536Mi
Necessário (idle):  ~192Mi (estimado ~50% utilization para podinfo)
Ratio request/limit: 4x
```

**Diagnóstico:** podinfo usa ~10-20Mi por pod em idle. O request de 64Mi dá margem confortável para spikes de tráfego. O limit de 256Mi é adequado — um OOM a 256Mi indica leak real, não falta de memória.

---

## Impacto do HPA no Custo

### Cenário: Scale-up durante pico

| Fase | Replicas | requests.cpu | requests.mem | Custo incremental* |
|------|----------|-------------|-------------|-------------------|
| Normal | 6 | 300m | 384Mi | Baseline |
| Pico moderado | 12 | 600m | 768Mi | +100% |
| Pico máximo | 30 | 1500m | 1920Mi | +400% |

*Custo incremental em cloud é proporcional aos requests, não limits.

### Análise de capacity

Com 30 pods (máximo da quota):
- CPU requests: 1500m — cabe em 1 worker (2000m disponível)
- Memory requests: 1920Mi — cabe em 1 worker (~3.5Gi disponível)
- **Conclusão:** 2 workers são suficientes mesmo no pico máximo

### Observação sobre HPA cooldown

O HPA padrão leva 5 minutos para scale-down após normalização. Para 30 pods que escalam por 10 minutos:

```
Custo extra = (5 min cooldown × 30 pods × 50m CPU) = 7500m·min ≈ desprezível
```

Em cloud, o custo real é o tempo que os nós ficam ativos. Com Cluster Autoscaler, os nós extras seriam removidos ~10 minutos após scale-down dos pods.

---

## Recomendações de Rightsizing

### 1. Manter requests atuais (50m CPU, 64Mi mem)

**Justificativa:** Os requests de 50m/64Mi são adequados para podinfo em idle. Valores menores arriscariam throttling durante spikes de tráfego.

### 2. Considerar reduzir limits para 2× requests em produção real

| Perfil | requests.cpu | limits.cpu | requests.mem | limits.mem |
|--------|-------------|-----------|-------------|-----------|
| Atual | 50m | 200m | 64Mi | 256Mi |
| Otimizado | 50m | 100m | 64Mi | 128Mi |

**Economia:** Reduz overhead de scheduling e permite maior densidade de pods por nó.

### 3. Ajustar ResourceQuota proporcionalmente

| Recurso | Atual | Otimizado | Observação |
|---------|-------|-----------|------------|
| requests.cpu | 4 | 2 | Suficiente para 30 pods × 50m = 1500m |
| requests.memory | 4Gi | 2Gi | Suficiente para 30 pods × 64Mi = 1920Mi |
| limits.cpu | 8 | 4 | 30 pods × 100m = 3000m |
| limits.memory | 8Gi | 4Gi | 30 pods × 128Mi = 3840Mi |

### 4. Usar Vertical Pod Autoscaler (VPA) em modo recommend

Em produção, o VPA pode analisar padrões de uso reais e sugerir requests/limits ideais:

```bash
# Instalar VPA (exemplo)
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vertical-pod-autoscaler.yaml

# Criar recomendação
kubectl apply -f - <<EOF
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: content-api-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: content-api
  updatePolicy:
    updateMode: "Off"  # Apenas recomenda, não aplica
EOF
```

---

## Stack de Observabilidade — Custo de Infraestrutura

| Componente | CPU request | Memory request | Storage |
|------------|-----------|---------------|---------|
| Prometheus | 200m | 512Mi | 10Gi (retention 7d) |
| Grafana | 100m | 128Mi | — |
| Alertmanager | 50m | 64Mi | — |
| Chaos Mesh | 200m | 256Mi | — |
| ArgoCD | 250m | 512Mi | — |
| **Total plataforma** | **800m** | **1472Mi** | **10Gi** |

**Observação:** A stack de plataforma consome mais recursos que os serviços de aplicação. Isso é normal em ambientes de aprendizado — em produção, a proporção seria inversa.

---

## Resumo Executivo

| Dimensão | Status | Ação |
|----------|--------|------|
| CPU requests | ✅ Adequado | Manter 50m por pod |
| Memory requests | ✅ Adequado | Manter 64Mi por pod |
| CPU limits | ⚠️ Superdimensionado | Considerar 100m (2× request) |
| Memory limits | ✅ Adequado | 256Mi ok para podinfo |
| ResourceQuota | ⚠️ Superdimensionado | Reduzir para 2Gi/4 se otimizar limits |
| HPA range | ✅ Adequado | 2-10 replicas cobre cenários testados |
| Custo cloud | ℹ️ Informativo | GKE ~63% mais barato que EKS |
