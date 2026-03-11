# ADR-004 — ArgoCD para GitOps

- **Status:** Aceito
- **Data:** 2026-03-10
- **Decisores:** @Jh0wSSilva

## Contexto e Problema

O ReliabilityLab precisa de um mecanismo GitOps para garantir que o estado do cluster Kubernetes seja sempre idêntico ao que está no Git. Requisitos:

1. Sincronização automática Git → Cluster
2. Self-heal: reverter mudanças manuais feitas com `kubectl edit` ou `kubectl apply`
3. Prune: remover recursos do cluster quando deletados do Git
4. UI web para visualizar o estado das aplicações
5. Funcionar no Minikube

## Alternativas Consideradas

### Opção 1 — Flux CD

- **Prós:** CNCF graduated, leve, integração nativa com Helm e Kustomize, multi-tenancy por design
- **Contras:** Sem UI nativa — requer Weave GitOps (produto separado) para dashboard. Modelo pull-based mais opaco para debug. Menor base de adoção comparado ao ArgoCD em projetos open source.
- **Veredicto:** Viável, mas UI nativa do ArgoCD é valiosa para demonstrar o fluxo GitOps em um portfólio

### Opção 2 — Jenkins X

- **Prós:** CI/CD completo, preview environments
- **Contras:** Extremamente pesado para o escopo. Requer vários componentes (Tekton, Lighthouse, etc.). Instalação no Minikube consome > 2GB de RAM apenas para o Jenkins X. Overkill para o problema de GitOps puro.
- **Veredicto:** Descartada — overhead desproporcional

### Opção 3 — Deploy manual (kubectl apply em script)

- **Prós:** Zero dependências adicionais, controle total
- **Contras:** Sem drift detection, sem self-heal, sem UI. Se alguém fizer `kubectl edit`, o estado diverge do Git silenciosamente. Não demonstra GitOps.
- **Veredicto:** Descartada — não atende ao requisito fundamental

### Opção 4 — ArgoCD (escolhida)

- **Prós:** CNCF graduated, UI web rica, self-heal nativo, prune automático, Application CRD declarativo, grande comunidade e adoção, SSO integrado
- **Contras:** Consome ~500Mi de RAM no cluster (server + repo-server + redis + dex + controller). No Minikube com `--memory=2048`, não há recursos suficientes — requer `--memory=4096`.

## Decisão

Adotar **ArgoCD** como ferramenta GitOps do ReliabilityLab.

Instalação via manifests oficiais. Acesso via NodePort no Minikube. Applications definidas em `gitops/apps/` como CRDs.

**Timing crítico:** ArgoCD é instalado por último, após cluster estável com Prometheus + Chaos Mesh. Isso evita timeout do redis-secret-init quando recursos estão escassos (documentado em TROUBLESHOOTING.md P6).

## Consequências

### Positivas

- Estado do cluster sempre sincronizado com o Git — single source of truth
- Self-heal automático: `kubectl edit` em produção é revertido em < 3 minutos
- UI web demonstra visualmente o fluxo GitOps — valor alto para portfólio
- Application CRD versionada no Git — o próprio ArgoCD é gerenciado declarativamente

### Negativas

- ~500Mi de RAM consumidos — significativo em ambiente Minikube
- Deve ser instalado por último, após stack estável (P6)
- Senha admin gerada como Secret — requer `kubectl get secret` para primeiro acesso
- Redis como dependência interna — ponto único de falha dentro do ArgoCD

## Referências

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [CNCF GitOps Working Group](https://opengitops.dev/)
- TROUBLESHOOTING.md — P6 (ArgoCD redis timeout)
