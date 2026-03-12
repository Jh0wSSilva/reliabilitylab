# Tutorial 15 — Alertmanager: Roteamento e Notificações

## Objetivo

Neste tutorial você vai aprender a:
- Configurar o **Alertmanager** para agrupar e rotear alertas
- Definir **receivers** para diferentes severidades
- Configurar **inibição** de alertas (evitar cascata)
- Visualizar alertas recebidos via webhook logger local

## Pré-requisitos

- Tutorial 14 concluído (alertas no Prometheus)
- kube-prometheus-stack instalado (inclui Alertmanager)
- PrometheusRule aplicada

## Conceitos

### O que é o Alertmanager?

O Alertmanager recebe alertas do Prometheus e:
1. **Agrupa** alertas similares em uma notificação
2. **Roteia** para o receiver correto baseado em labels
3. **Inibe** alertas redundantes (ex: warning quando critical já existe)
4. **Silencia** alertas durante manutenções

### Routing Tree

```
route (receiver: default)
├── severity=critical → critical-receiver (resposta: 10s, repetição: 1h)
├── severity=warning  → warning-receiver  (resposta: 30s, repetição: 4h)
├── slo=*             → slo-receiver      (agrupado por SLO)
└── severity=info     → info-receiver     (apenas logging)
```

### Inibição

Quando um alerta `critical` está ativo, o Alertmanager **suprime** o `warning` do
mesmo namespace/alerta, evitando notificações duplicadas.

## Passo a Passo

### Passo 1: Deploy do Webhook Logger

O webhook logger é um servidor HTTP simples que recebe e loga os alertas
localmente. Em produção, seria substituído por Slack, PagerDuty, etc.

```bash
kubectl apply -f observability/alertmanager/webhook-logger.yaml
```

Verificar:

```bash
kubectl get pods -n monitoring -l app=webhook-logger
```

Ver logs do webhook logger:

```bash
kubectl logs -n monitoring -l app=webhook-logger -f
```

### Passo 2: Aplicar configuração do Alertmanager

```bash
kubectl apply -f observability/alertmanager/config.yaml
```

A configuração define:
- **4 receivers** (critical, warning, slo, info) + default
- **Agrupamento** por alertname, namespace e severity
- **Inibição** de warnings quando critical existe
- **Inibição** de latência quando serviço está indisponível

### Passo 3: Acessar a UI do Alertmanager

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Abra http://localhost:9093 e explore:
- **Alerts** — alertas ativos recebidos do Prometheus
- **Silences** — alertas silenciados durante manutenção
- **Status** — configuração atual carregada

### Passo 4: Disparar alertas para testar roteamento

Vamos disparar um alerta `ServiceUnavailable` (critical):

```bash
# Escalar para 0 — causa ServiceUnavailable
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=0

echo "Aguardando alertas (2-3 min)..."
sleep 180

# Verificar logs do webhook logger
kubectl logs -n monitoring -l app=webhook-logger --tail=20
```

Você deve ver nos logs algo como:
```
[2024-01-01 12:00:00] 🔴 [CRITICAL] 🔥 FIRING | ServiceUnavailable | severity=critical | Serviço site-kubectl completamente indisponível
```

Restaurar:

```bash
kubectl scale deployment site-kubectl -n reliabilitylab --replicas=2
kubectl rollout status deployment/site-kubectl -n reliabilitylab
```

Após restaurar, o webhook logger deve mostrar:
```
[2024-01-01 12:05:00] 🔴 [CRITICAL] ✅ RESOLVED | ServiceUnavailable | severity=critical | ...
```

### Passo 5: Testar inibição de alertas

Quando `ServiceUnavailable` (critical) está ativo, alertas de latência
(warning) do mesmo namespace devem ser suprimidos.

Verifique na UI do Alertmanager (http://localhost:9093) que apenas
o alerta critical aparece, sem warnings de latência duplicados.

### Passo 6: Criar um silence (silenciar alertas)

Na UI do Alertmanager:
1. Clique em **"New Silence"**
2. Adicione matcher: `severity = info`
3. Defina duração: 1 hora
4. Adicione comentário: "Silenciando alertas informativos durante teste"
5. Clique em **"Create"**

Isso simula o silenciamento durante uma manutenção planejada.

### Passo 7: Entender a configuração

Examine os componentes principais:

```bash
cat observability/alertmanager/config.yaml
```

**Routing:**
- `group_by` — agrupa alertas pelos mesmos labels
- `group_wait` — tempo antes de enviar a primeira notificação
- `group_interval` — intervalo entre notificações do mesmo grupo
- `repeat_interval` — reenvio de alertas ainda ativos

**Receivers:**
- Cada receiver aponta para um endpoint do webhook logger
- Os canais `/critical`, `/warning`, `/slo`, `/info` permitem diferenciar

**Inhibit Rules:**
- `source_matchers` — alerta que causa a inibição
- `target_matchers` — alerta que é inibido
- `equal` — labels que devem coincidir

## Verificação

Confirme que você consegue:

1. Deploy do webhook logger e ver logs
2. Acessar a UI do Alertmanager
3. Ver alertas roteados para os receivers corretos
4. Entender como a inibição funciona
5. Criar um silence para manutenção

## Próximo Tutorial

No [Tutorial 16](tutorial-16-chaos-outage-simulation.md) vamos simular interrupções
reais no serviço e observar os alertas e a recuperação.
