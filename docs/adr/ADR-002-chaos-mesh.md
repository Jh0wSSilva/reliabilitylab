# ADR-002 — Chaos Mesh para Chaos Engineering

- **Status:** Aceito
- **Data:** 2026-03-10
- **Decisores:** @Jh0wSSilva

## Contexto e Problema

O ReliabilityLab precisa de uma ferramenta de chaos engineering para validar resiliência dos serviços StreamFlix. Requisitos:

1. Experimentos definidos como CRDs (declarativos, versionáveis no Git)
2. Suporte a pod kill, network latency e CPU stress
3. Controle granular de blast radius (namespace, labels, duração)
4. Funcionar no Minikube com containerd

## Alternativas Consideradas

### Opção 1 — LitmusChaos v3.x

- **Prós:** CNCF incubating, grande comunidade, ChaosHub com experimentos pré-definidos
- **Contras:** A v3.x mudou completamente a arquitetura. O Helm chart instala apenas o ChaosCenter (UI web), sem chaos-operator nem CRDs. Os experimentos via `kubectl` (ChaosEngine) não funcionam mais — a imagem `go-runner:1.13.8` não contém os binários dos experimentos. Após extensos testes, concluímos que o LitmusChaos v3.x é inviável para uso via kubectl/CRDs.
- **Veredicto:** Descartada — quebrado para uso GitOps/declarativo

### Opção 2 — Chaos via kubectl delete pod

- **Prós:** Zero dependências, funciona em qualquer cluster
- **Contras:** Apenas pod kill. Não suporta network chaos, CPU stress, disk fill. Não tem CRDs, schedulers ou duração controlada. Não gera métricas de experimento.
- **Veredicto:** Descartada — primitivo demais para demonstrar chaos engineering real

### Opção 3 — Chaos Mesh (escolhida)

- **Prós:** CNCF incubating, CRDs nativos para todos os tipos de falha (PodChaos, NetworkChaos, StressChaos, IOChaos, DNSChaos), dashboard web incluso, compatível com containerd no Minikube
- **Contras:** Requer configuração específica para Minikube (runtime + socket path). O controller-manager precisa de `replicaCount=1` no Minikube para evitar leader election crash.

## Decisão

Adotar **Chaos Mesh** como ferramenta de chaos engineering.

Instalação via Helm com parâmetros obrigatórios para Minikube:

```bash
helm install chaos-mesh chaos-mesh/chaos-mesh \
  -n chaos-mesh \
  --set controllerManager.replicaCount=1 \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false
```

Experimentos ficam em `platform/chaos/experiments/` como CRDs.

## Consequências

### Positivas

- 3 tipos de experimento implementados: PodChaos, NetworkChaos, StressChaos
- Experimentos versionados no Git — reproduzíveis e auditáveis
- Dashboard web para visualização em tempo real
- Compatível com GitOps (ArgoCD pode aplicar experimentos)

### Negativas

- `replicaCount=1` é obrigatório no Minikube — leader election com 2+ réplicas causa CrashLoopBackOff (documentado em TROUBLESHOOTING.md P4)
- Chaos Daemon roda como DaemonSet privilegiado em todos os nós (~100Mi por nó)
- Requer namespace dedicado (`chaos-mesh`) — adiciona ~350Mi de uso de memória total ao cluster

## Referências

- [Chaos Mesh Documentation](https://chaos-mesh.org/docs)
- [Principles of Chaos Engineering](https://principlesofchaos.org)
- TROUBLESHOOTING.md — P3 (LitmusChaos v3.x quebrado), P4 (Leader election crash)
