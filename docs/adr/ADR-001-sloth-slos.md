# ADR-001 — Sloth como SLO Engine

- **Status:** Aceito
- **Data:** 2026-03-10
- **Decisores:** @Jh0wSSilva

## Contexto e Problema

O ReliabilityLab precisa de uma ferramenta para definir SLOs (Service Level Objectives) como código e gerar automaticamente alertas multi-window burn rate no Prometheus. A ferramenta deve:

1. Aceitar definições declarativas (YAML/CRD)
2. Gerar PrometheusRules compatíveis com kube-prometheus-stack
3. Implementar multi-window burn rate conforme SRE Workbook cap. 5
4. Funcionar no Minikube sem dependências externas

## Alternativas Consideradas

### Opção 1 — OpenSLO + Prometheus Rule Generator

- **Prós:** Spec padronizada (OpenSLO), vendor-neutral
- **Contras:** Requer pipeline extra para converter OpenSLO → PrometheusRules. Não existe um controller Kubernetes nativo que faça isso automaticamente. Overhead de tooling para um ambiente local.
- **Veredicto:** Descartada — complexidade desnecessária para o escopo

### Opção 2 — PrometheusRules manuais

- **Prós:** Controle total, sem dependências adicionais
- **Contras:** Escrever manualmente alertas multi-window burn rate com 8 janelas (5m, 30m, 1h, 2h, 6h, 1d, 3d, 30d) para cada SLO é propenso a erros e difícil de manter. Fórmulas complexas de burn rate precisam ser recalculadas quando o target muda.
- **Veredicto:** Descartada — não escala, alto risco de erro humano

### Opção 3 — Sloth (escolhida)

- **Prós:** CRD nativo Kubernetes (`PrometheusServiceLevel`), gera PrometheusRules automaticamente, Helm chart funcional, documentação ativa, usado em produção por diversas equipes
- **Contras:** Mais uma dependência no cluster (controller + CRDs). Geração de rules é opaca — difícil debugar se algo der errado.

## Decisão

Adotar **Sloth** como SLO engine do ReliabilityLab.

Definições de SLO ficam em `platform/slo/` como CRDs `PrometheusServiceLevel`. O Sloth controller gera automaticamente PrometheusRules com alertas multi-window burn rate.

## Consequências

### Positivas

- SLOs definidos como código versionado no Git
- Alertas de burn rate gerados automaticamente — sem erro humano nas fórmulas
- Compatível com o kube-prometheus-stack já instalado
- Padrão MADR de 4 janelas (PAGE + TICKET) conforme SRE Workbook

### Negativas

- Campos do CRD devem ser **camelCase** (`errorQuery`, `totalQuery`, `pageAlert`, `ticketAlert`); snake_case é silenciosamente ignorado — documentado em TROUBLESHOOTING.md como lição aprendida
- Dependência de um controller adicional no namespace monitoring (~50Mi de memória)
- Se o Sloth controller cair, novas regras não são geradas (rules existentes continuam funcionando)

## Referências

- [Sloth Documentation](https://sloth.dev)
- [SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- TROUBLESHOOTING.md
