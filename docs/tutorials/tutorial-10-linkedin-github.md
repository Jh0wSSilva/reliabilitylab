# Tutorial 10 — GitHub e LinkedIn

**Objetivo:** Preparar o repositório GitHub como portfólio profissional e criar conteúdo para LinkedIn que atraia atenção de recrutadores e engenheiros de empresas tier-1.

**Resultado:** README profissional com badges corretos, 3 posts LinkedIn prontos para publicar e checklist de screenshots para evidências visuais.

**Tempo estimado:** 30 minutos

**Pré-requisitos:** Tutorial 09 completo com GameDay documentado

---

## Contexto

Engenheiros e recrutadores de empresas de tecnologia avaliam candidatos pelo GitHub antes da entrevista. Um repositório bem documentado com SLOs, chaos engineering e observabilidade demonstra senioridade prática — não apenas conhecimento teórico.

No LinkedIn, a maioria dos posts técnicos são genéricos ("estou estudando Kubernetes!"). Posts com **resultados reais**, **dados concretos** e **comparações com práticas de SRE** geram engajamento de engenheiros seniores e recrutadores tech.

O objetivo: quando um tech recruiter ou um Staff Engineer ver seu perfil, o repositório ReliabilityLab deve comunicar em 30 segundos: "essa pessoa entende SRE de verdade — não apenas ferramentas, mas os princípios por trás delas."

---

## Passo 1 — README profissional

O README.md do repositório já está atualizado com a estrutura correta. Verifique os badges:

```markdown
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-326CE5?style=flat-square&logo=kubernetes)
![Prometheus](https://img.shields.io/badge/Prometheus-stack-E6522C?style=flat-square&logo=prometheus)
![Chaos Mesh](https://img.shields.io/badge/Chaos_Mesh-CNCF-EF4444?style=flat-square)
![SLO](https://img.shields.io/badge/SLO-Sloth-7C3AED?style=flat-square)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?style=flat-square&logo=argo)
![k6](https://img.shields.io/badge/Load_Testing-k6-7D64FF?style=flat-square&logo=k6)
![Local](https://img.shields.io/badge/Runs_on-Minikube-00C896?style=flat-square)
```

**Badges corretos:**
- ✅ Kubernetes 1.32
- ✅ Chaos Mesh (CNCF)
- ✅ Sloth (SLO engine)
- ✅ ArgoCD (GitOps)
- ✅ k6 (Load Testing)

**Badges que NÃO devem estar no README:**
- ❌ ~~LitmusChaos~~ (v3.x quebrado via kubectl)
- ❌ ~~Kubernetes 1.29~~ (migrado para 1.32)

---

## Passo 2 — Checklist de screenshots

Capture estas imagens e salve em uma pasta `docs/screenshots/`:

```bash
mkdir -p docs/screenshots
```

**Screenshots obrigatórios:**

| # | O que capturar | Onde | Para que |
|---|---------------|------|---------|
| 1 | 3 nós Ready no cluster | `kubectl get nodes` | Prova de ambiente multi-node |
| 2 | Grafana dashboard overview | Browser → Grafana | Visual impactante no README |
| 3 | HPA escalando 2 → 6 pods | `kubectl get hpa -w` | Prova de auto-scaling funcionando |
| 4 | Chaos Mesh dashboard | Browser → Chaos Mesh | Prova de chaos engineering |
| 5 | ArgoCD Application synced | Browser → ArgoCD | Prova de GitOps |
| 6 | k6 smoke test passando | Terminal → k6 output | Prova de load testing |
| 7 | Prometheus targets UP | Browser → Prometheus | Prova de observabilidade |
| 8 | SLO definitions no Prometheus | Browser → Prometheus rules | Prova de SLOs como código |

> **Dica pro:** use `Ctrl+Shift+S` no Firefox/Chrome para full page screenshot. No terminal, use `script` para capturar output inteiro.

---

## Passo 3 — Seções do README que impressionam

O README deve ter estas seções nesta ordem (já está no repositório):

1. **Badges** — visual imediato do stack
2. **O Projeto** — 1 parágrafo explicando o que é
3. **Arquitetura** — diagrama ASCII do cluster
4. **SLOs Definidos** — tabela com SLI/SLO/Error Budget
5. **Experimentos de Chaos** — tabela com resultados reais
6. **Quick Start** — passos para replicar
7. **Estrutura do Repositório** — tree organizada
8. **Stack Completa** — tabela de ferramentas
9. **Documentação** — links para ADRs, runbooks, GameDays
10. **Referências** — SRE Book, Chaos Engineering, etc.

---

## Passo 4 — Post LinkedIn #1: O Projeto

```
🎯 Construí uma plataforma de SRE do zero — aplicando as mesmas práticas usadas em ambientes de produção de alta escala.

Montei o ReliabilityLab: um lab completo de Site Reliability Engineering rodando 100% local com Minikube.

O que tem:
→ 3 microserviços com SLOs definidos como código (99.9% e 99.5%)
→ Chaos Engineering com Chaos Mesh
→ Alertas multi-window burn rate (modelo do SRE Workbook)
→ Auto-scaling que escala de 2 → 6 réplicas em 2 minutos
→ GitOps com ArgoCD + self-heal automático
→ Load testing com k6 + thresholds ligados aos SLOs

Resultado real do GameDay:
- Pod kill: recuperação em ~1 segundo (imagem em cache)
- CPU stress: HPA escalou de 2 → 6 réplicas automaticamente
- Network latency: 200ms injetados sem cascading failure

Tudo open source, tudo documentado, tudo replicável.

Link do repositório nos comentários 👇

#SRE #Kubernetes #ChaosEngineering #DevOps #Observability
```

---

## Passo 5 — Post LinkedIn #2: Os problemas reais

```
❌ 6 coisas que quebraram quando tentei montar um lab de SRE — e como resolvi cada uma.

Quando comecei o ReliabilityLab, achei que era só seguir tutoriais. Estava errado.

Aqui estão os problemas REAIS que encontrei:

1️⃣ Alertmanager em CrashLoopBackOff
→ PVC do Minikube não cria diretório automaticamente
→ Fix: desabilitar storage no Alertmanager

2️⃣ LitmusChaos v3.x não funciona via kubectl
→ Helm chart só instala UI, sem CRDs de chaos
→ Fix: migrar para Chaos Mesh (CNCF, maduro)

3️⃣ Chaos Mesh controller em CrashLoop
→ 3 réplicas competindo por leader election com RAM insuficiente
→ Fix: 1 réplica + 4GB RAM por nó

4️⃣ Cluster instável após horas
→ CoreDNS travando, API server timeout
→ Fix: 4GB RAM por nó (não 2GB!)

5️⃣ HPA com targets unknown
→ metrics-server ainda não coletou dados ou não está instalado
→ Fix: verificar metrics-server e usar `/stress/cpu` do podinfo para gerar carga

6️⃣ ArgoCD redis-secret-init timeout
→ Rede interna instável por falta de recursos
→ Fix: instalar ArgoCD só após cluster estável

Documentei tudo com diagnóstico, causa raiz e solução.
Repositório nos comentários 👇

#SRE #DevOps #Kubernetes #LessonsLearned #Engineering
```

---

## Passo 6 — Post LinkedIn #3: O GameDay

```
🧪 Executei um GameDay de Chaos Engineering — e os resultados surpreenderam.

Contexto: Chaos Engineering é a prática de injetar falhas controladas para validar resiliência. DiRT tests (Disaster Recovery Testing) levam isso ainda mais longe, quebrando sistemas deliberadamente.

Resolvi fazer o mesmo no meu lab local.

3 experimentos, 3 hipóteses, 3 resultados:

📌 Experimento 1 — Pod Kill
Hipótese: Kubernetes se recupera em < 30 segundos
Resultado: recuperação em ~1 SEGUNDO
Por quê: imagem podinfo já em cache no nó

📌 Experimento 2 — CPU Stress + Auto-scaling
Hipótese: HPA escala quando CPU > 70%
Resultado: 2 → 6 réplicas em ~2 minutos
Exatamente como esperado — sistema se adaptou à carga

📌 Experimento 3 — Network Latency (200ms)
Hipótese: sem cascading failure
Resultado: HTTP 200 mantido — serviço degradado mas funcional
Stateless services isolam falhas naturalmente

O que aprendi:
→ Resiliência não é mágica — é design deliberado
→ Chaos Engineering revela o que monitoring sozinho não mostra
→ Documentar resultados é tão importante quanto executar

Repositório com tudo documentado nos comentários 👇

#ChaosEngineering #SRE #Kubernetes #GameDay
```

---

## Passo 7 — Dica do vídeo de 60 segundos

O LinkedIn prioriza vídeos no feed. Um vídeo de 60 segundos mostrando o lab em ação pode gerar 10x mais impressões que um post de texto.

**Roteiro (60s):**

```
[0-10s] "Montei do zero uma plataforma que aplica práticas reais de SRE
         para operar sistemas confiáveis em produção."

[10-25s] Mostra tela: Grafana dashboard com métricas, 3 nós no cluster,
         pods rodando.

[25-40s] Mostra tela: Chaos Mesh matando um pod, Kubernetes recriando
         em 1 segundo, HPA escalando de 2 para 6 réplicas.

[40-55s] Mostra tela: ArgoCD sincronizado, k6 passando thresholds,
         SLOs definidos como código.

[55-60s] "Tudo open source, tudo documentado, tudo no GitHub."
         Link do repositório no post.
```

Ferramentas para gravar:
- **OBS Studio** (Linux) — grátis, grava tela + webcam
- **Peek** (Linux) — GIFs animados para README
- **asciinema** — grava terminal com replay (ótimo para demos)

---

## Passo 8 — Commit final

```bash
cd /home/jhow/Project_kubectl/reliabilitylab

git add -A
git status

# Verificar que tudo está incluído
git diff --cached --stat

git commit -m "feat: complete ReliabilityLab with tutorials, GameDay, and documentation

- 10 tutorials covering Minikube, K8s, Prometheus, Sloth, Chaos Mesh, ArgoCD, k6
- GameDay #01 with 3 chaos experiments documented
- Troubleshooting guide with 7 real problems and solutions
- Bootstrap script for automated setup
- SLOs as code with multi-window burn rate alerting
- Load tests with k6 (smoke, load, stress)
- GitOps with ArgoCD self-heal"

git push origin main
```

---

## Health Check Final

```bash
echo "=== HEALTH CHECK FINAL — ReliabilityLab ==="
echo ""

echo "[1/8] Cluster:"
kubectl get nodes --no-headers | wc -l | xargs -I {} echo "  {} nós Ready"

echo "[2/8] Namespaces:"
for ns in production monitoring chaos-mesh argocd; do
  kubectl get namespace "$ns" --no-headers 2>/dev/null | awk '{print "  ✅ " $1}' || echo "  ❌ $ns ausente"
done

echo "[3/8] Serviços StreamFlix:"
kubectl get deployments -n production --no-headers | awk '{print "  " $1, $2}'

echo "[4/8] HPA:"
kubectl get hpa -n production --no-headers | awk '{print "  " $1, "replicas=" $6}'

echo "[5/8] Monitoring stack:"
kubectl get pods -n monitoring --no-headers | grep -c Running | xargs -I {} echo "  {} pods Running"

echo "[6/8] Chaos Mesh:"
kubectl get pods -n chaos-mesh --no-headers | grep -c Running | xargs -I {} echo "  {} pods Running"

echo "[7/8] ArgoCD:"
kubectl get applications -n argocd --no-headers 2>/dev/null | awk '{print "  " $1, $2, $3}'

echo "[8/8] SLOs:"
kubectl get prometheusservicelevel -n monitoring --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  {} SLOs definidos"

echo ""
echo "=== RELIABILITYLAB COMPLETO ==="
echo ""
echo "📁 Repositório: https://github.com/Jh0wSSilva/reliabilitylab"
echo "📖 Tutoriais: docs/tutorials/"
echo "🧪 GameDay: docs/gamedays/"
echo "🔧 Troubleshooting: TROUBLESHOOTING.md"
echo "🚀 Bootstrap: scripts/bootstrap.sh"
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| `git push` rejeitado | Branch protegido ou credencial expirada | Use token: `git remote set-url origin https://<token>@github.com/Jh0wSSilva/reliabilitylab.git` |
| Screenshots não aparecem no GitHub | Path incorreto na referência | Use path relativo: `![Grafana](docs/screenshots/grafana-overview.png)` |
| Post LinkedIn sem engajamento | Publicou em horário ruim | Publique terça a quinta, 8-9h ou 12-13h (horário de Brasília) |

---

**Anterior:** [Tutorial 09 — GameDay](tutorial-09-gameday.md)

---

## Parabéns! 🎉

Você completou os 10 tutoriais do ReliabilityLab. Agora você tem:

- ✅ Cluster Kubernetes multi-node com 4GB RAM/nó
- ✅ 3 microserviços com HPA e SLOs definidos como código
- ✅ Stack de observabilidade completo (Prometheus + Grafana + Alertmanager)
- ✅ SLOs com burn rate alerting via Sloth
- ✅ Chaos Engineering com Chaos Mesh (3 experimentos documentados)
- ✅ GitOps com ArgoCD e self-heal
- ✅ Load testing com k6 (smoke, load, stress)
- ✅ GameDay documentado com postmortem
- ✅ Repositório profissional pronto para portfólio
- ✅ 3 posts LinkedIn prontos para publicar

**Este é o tipo de portfólio que diferencia candidatos em processos seletivos de empresas de tecnologia.**
