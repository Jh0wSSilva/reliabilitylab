# Princípios de SRE — ReliabilityLab

## O que é SRE?

Site Reliability Engineering (SRE) é uma disciplina de engenharia de software aplicada a operações de infraestrutura. Foi popularizada pelo Google e define práticas para construir sistemas **confiáveis, escaláveis e eficientes**.

Este laboratório aplica os princípios fundamentais de SRE em um ambiente local e controlado.

---

## Princípios Aplicados neste Projeto

### 1. Observabilidade (Observability)

**Conceito:** Você não pode melhorar o que não pode medir.

**Aplicação no lab:**
- **Métricas** → Prometheus coleta métricas de CPU, memória, requisições e latência
- **Logs** → Loki + Promtail centralizam logs de todos os pods
- **Traces** → OpenTelemetry Collector captura traces distribuídos
- **Dashboards** → Grafana oferece visão unificada de toda a stack

### 2. SLIs, SLOs e Error Budgets

**Conceito:**
- **SLI (Service Level Indicator):** métrica que indica a qualidade do serviço (ex: taxa de sucesso HTTP)
- **SLO (Service Level Objective):** objetivo de qualidade (ex: 99.9% de disponibilidade)
- **Error Budget:** quantidade de falha aceitável dentro do SLO

**Aplicação no lab:**
- O endpoint `/api/health` é o SLI mais básico (disponibilidade)
- O readinessProbe e livenessProbe implementam verificações contínuas
- Dashboards do Grafana monitoram a taxa de sucesso das requisições

### 3. Automação e Eliminação de Toil

**Conceito:** Toil é trabalho operacional manual, repetitivo e que escala linearmente.

**Aplicação no lab:**
- **HPA** automatiza o escalonamento horizontal
- **ArgoCD** automatiza deploys via GitOps
- **Scripts bash** automatizam operações comuns (build, deploy, logs)
- **Probes** automatizam detecção e recuperação de falhas

### 4. Engenharia de Confiabilidade

**Conceito:** Projetar sistemas que se recuperam automaticamente de falhas.

**Aplicação no lab:**
- **readinessProbe:** remove pods não saudáveis do balanceamento de carga
- **livenessProbe:** reinicia pods que pararam de responder
- **startupProbe:** protege pods durante inicialização lenta
- **PDB:** garante disponibilidade mínima durante manutenções
- **RollingUpdate:** deploys sem downtime (maxUnavailable=0)

### 5. Defesa em Profundidade

**Conceito:** Múltiplas camadas de proteção sobrepostas.

**Aplicação no lab:**
- **Container:** usuário não-root, capabilities dropadas
- **Pod:** securityContext restritivo
- **Rede:** NetworkPolicy zero-trust (default deny)
- **Build:** multi-stage (menos superfície de ataque)
- **Secrets:** separação entre ConfigMap (público) e Secret (sensível)

### 6. GitOps

**Conceito:** O estado desejado do sistema é declarado em Git. Toda mudança passa por pull request.

**Aplicação no lab:**
- ArgoCD monitora a branch `main` do repositório
- Alterações nos manifests K8s são aplicadas automaticamente
- Self-heal: se alguém alterar algo manualmente, ArgoCD reverte

---

## Hierarquia de Confiabilidade

```
                    ┌─────────────┐
                    │  Produto    │  ← Funcionalidades para o usuário
                    ├─────────────┤
                    │ Observação  │  ← Métricas, logs, traces, alertas
                    ├─────────────┤
                    │ Resiliência │  ← Probes, HPA, PDB, self-heal
                    ├─────────────┤
                    │ Segurança   │  ← NetworkPolicy, non-root, RBAC
                    ├─────────────┤
                    │ Automação   │  ← GitOps, CI/CD, scripts
                    ├─────────────┤
                    │ Infra Base  │  ← Kubernetes, Docker, cluster local
                    └─────────────┘
```

Cada camada depende da camada inferior. Não adianta ter dashboards incríveis se a infraestrutura base não é confiável.

---

## Métricas Chave (Golden Signals)

Os **quatro sinais dourados** do Google SRE são:

| Sinal | O que mede | Como observar no lab |
|-------|-----------|---------------------|
| **Latência** | Tempo de resposta das requisições | Dashboard Grafana → P99 latency |
| **Tráfego** | Volume de requisições | Dashboard Grafana → req/s |
| **Erros** | Taxa de requisições com falha | Dashboard Grafana → HTTP 5xx |
| **Saturação** | Quão cheio está o recurso | Dashboard Grafana → CPU/memória + HPA |

---

## Práticas Avançadas Incluídas no Lab

1. **Chaos Engineering** — experimentos de deleção de pod, stress de CPU/memória e latência de rede
2. **Load Testing** — cenários com k6 (smoke, load, stress, spike)
3. **Incident Response** — cenários de simulação e template de post-mortem
4. **Segurança** — RBAC, Pod Security Standards, NetworkPolicy zero-trust
5. **GitOps** — ArgoCD com auto-sync e self-heal

## Próximos Passos para Evolução

1. **SLOs como código** — implementar Sloth para gerar alertas burn-rate
2. **Alertmanager** — configurar roteamento de alertas (Slack, email)
3. **Error Budget Policy** — definir ações baseadas no consumo do error budget
4. **Distributed Tracing** — instrumentação OpenTelemetry na aplicação
5. **Service Mesh** — adicionar Istio/Linkerd para observabilidade de rede
