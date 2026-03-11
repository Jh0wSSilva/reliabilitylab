# ADR-005 — Minikube com 3 Nós e 4096MB de RAM

- **Status:** Aceito
- **Data:** 2026-03-10
- **Decisores:** @Jh0wSSilva

## Contexto e Problema

O ReliabilityLab precisa de um cluster Kubernetes local para desenvolvimento e testes. O cluster deve:

1. Simular distribuição de pods entre múltiplos nós (scheduler real)
2. Suportar DaemonSets (Chaos Mesh daemon, node-exporter)
3. Ter recursos suficientes para todo o stack (Prometheus + Grafana + Alertmanager + Sloth + Chaos Mesh + ArgoCD + 3 serviços + HPAs)
4. Funcionar em máquina com 16GB de RAM sem comprometer o host

## Alternativas Consideradas

### Opção 1 — Kind (Kubernetes in Docker)

- **Prós:** Rápido para criar/destruir, usa containers Docker como nós, configuração multi-node simples
- **Contras:** Sem addons nativos para ingress/metrics-server (requer instalação manual). Networking mais complexo para acessar serviços do host. Sem `minikube service` — requer port-forward manual para cada serviço. Menos documentação para stacks complexos.
- **Veredicto:** Viável, mas Minikube tem melhor UX para labs educacionais

### Opção 2 — k3s

- **Prós:** Leve (~512MB por nó), produção-ready, suporta multi-node via k3s agent
- **Contras:** Usa containerd com paths diferentes. Traz componentes próprios (Traefik, ServiceLB) que conflitam com as escolhas do lab. Menos isolamento — roda diretamente no host. Automação de multi-node requer VMs separadas ou k3d (outro layer).
- **Veredicto:** Descartada — menos adequado para ambiente controlado de lab

### Opção 3 — Docker Desktop Kubernetes

- **Prós:** Integrado ao Docker Desktop, zero setup
- **Contras:** Single-node apenas. Não suporta multi-node — impossível testar scheduler, node affinity, DaemonSet distribution. Sem controle de versão do Kubernetes. Configuração limitada de recursos.
- **Veredicto:** Descartada — single-node é insuficiente

### Opção 4 — Minikube multi-node (escolhida)

- **Prós:** Addons nativos (ingress, metrics-server, dashboard), multi-node via `--nodes=N`, controle de versão do K8s via `--kubernetes-version`, `minikube service` para acesso fácil, ampla documentação
- **Contras:** Consome mais recursos que Kind. Cada nó é um container Docker separado. Startup mais lento (~2-3 minutos para 3 nós).

## Decisão

Adotar **Minikube** com as seguintes configurações:

```bash
minikube start \
  --driver=docker \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --profile=reliabilitylab \
  --kubernetes-version=v1.32.0
```

### Por que 3 nós?

- 1 control-plane + 2 workers simula a topologia mínima de produção
- Pods podem ser distribuídos entre workers pelo scheduler
- DaemonSets (chaos-daemon, node-exporter) rodam em cada nó — testável
- Pod kill em um nó re-schedulea para outro nó — chaos engineering real

### Por que 4096MB e não 2048MB?

Com 2048MB por nó (6GB total), o cluster fica instável após instalar o stack completo:

| Componente | Memória estimada |
|-----------|-----------------|
| kube-system (apiserver, etcd, coredns, etc.) | ~800Mi |
| kube-prometheus-stack | ~600Mi |
| Sloth controller | ~50Mi |
| Chaos Mesh (controller + daemon × 3) | ~400Mi |
| ArgoCD | ~500Mi |
| StreamFlix services (6 pods × 64Mi) | ~400Mi |
| **Total estimado** | **~2.75Gi** |

Com 2048MB/nó, o overhead do kubelet + OS deixa apenas ~1.5GB/nó livre → ~4.5GB para workloads. O stack precisa de ~2.75GB, mas spikes durante HPA scaling e chaos experiments ultrapassam o disponível, causando OOMKill e CoreDNS timeout.

Com 4096MB/nó: ~3.5GB/nó livre → ~10.5GB para workloads. Margem confortável mesmo sob stress tests.

## Consequências

### Positivas

- Cluster estável mesmo com stack completo + chaos experiments simultâneos
- Multi-node permite testar scheduler, node affinity e DaemonSet distribution
- Addons nativos simplificam setup (ingress, metrics-server, dashboard)
- Versão do K8s fixada — ambiente reproduzível

### Negativas

- Consome ~12GB de RAM da máquina host (3 × 4096MB)
- Startup lento (~2-3 min) comparado a Kind (~30s)
- Requer Docker Desktop com pelo menos 14GB de memória alocada
- Profile isolado (`reliabilitylab`) requer flag `-p` em todos os comandos minikube

## Referências

- [Minikube Documentation — Multi-node](https://minikube.sigs.k8s.io/docs/tutorials/multi_node/)
- TROUBLESHOOTING.md — P5 (Cluster instável com 2GB)
