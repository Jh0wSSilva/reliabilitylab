# Tutorial 05 — SLOs com Sloth

**Objetivo:** Definir SLOs (Service Level Objectives) como código usando Sloth e gerar automaticamente alertas multi-window burn rate conforme descrito no SRE Workbook.

**Resultado:** 3 SLOs definidos via CRDs, PrometheusRules geradas automaticamente com alertas multi-window burn rate, e métricas visíveis no Prometheus.

**Tempo estimado:** 20 minutos

**Pré-requisitos:** Tutorial 04 completo com health check verde

---

## Contexto

O conceito de SLOs (Service Level Objectives) foi formalizado no SRE Book e no SRE Workbook. Equipes de engenharia usam SLOs + Error Budgets para decidir quando parar de deployar features e focar em confiabilidade. Quando o error budget de um serviço é consumido, o time foca em estabilização ao invés de novas features.

A fórmula é simples: **SLO = "nosso serviço deve funcionar X% do tempo em uma janela de 30 dias"**. O que sobra é o Error Budget — tempo que o serviço pode ficar fora do ar sem violar o compromisso.

| SLO | Error Budget (30 dias) | Exemplo |
|-----|----------------------|-----------------|
| 99.9% | 43 minutos | serviço core (catálogo, player) |
| 99.5% | 3.6 horas | serviço não-crítico (recomendações) |
| 99.0% | 7.2 horas | batch jobs, analytics |

O **Sloth** transforma definições YAML em PrometheusRules com alertas **multi-window burn rate**. Ao invés de alertar "o serviço está com erro", ele alerta "o serviço está queimando error budget X vezes mais rápido que o sustentável". Isso elimina alertas falsos e garante que você acorde às 3h da manhã apenas quando realmente importa.

---

## Passo 1 — Instalar Sloth

```bash
helm repo add sloth https://slok.github.io/sloth
helm repo update

helm upgrade --install sloth sloth/sloth \
  --version 0.15.0 \
  -n monitoring \
  --wait --timeout 5m
```

✅ Esperado:
```
Release "sloth" has been upgraded. Happy Helming!
```

Verificar:

```bash
kubectl get pods -n monitoring | grep sloth
```

✅ Esperado:
```
sloth-xxxxx-yyyyy    1/1     Running   0   30s
```

Verificar CRDs instaladas:

```bash
kubectl get crd | grep sloth
```

✅ Esperado:
```
prometheusservicelevels.sloth.slok.dev    2026-03-10T...
```

---

## Passo 2 — Entender a estrutura de um SLO

Abra o arquivo SLO do content-api:

```bash
cat platform/slo/slo-content-api.yaml
```

```yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: content-api-availability
  namespace: monitoring
spec:
  service: "content-api"
  slos:
  - name: "requests-availability"
    objective: 99.9
    description: "content-api deve estar disponível 99.9% do tempo"
    sli:
      events:
        errorQuery: sum(rate(http_request_duration_seconds_count{job="content-api",status=~"5.."}[{{.window}}]))
        totalQuery: sum(rate(http_request_duration_seconds_count{job="content-api"}[{{.window}}]))
    alerting:
      name: "ContentApiHighErrorRate"
      labels:
        category: "availability"
      pageAlert:
        labels:
          severity: "critical"
      ticketAlert:
        labels:
          severity: "warning"
```

| Campo | Valor | Significado |
|-------|-------|-------------|
| `objective: 99.9` | SLO de 99.9% | Error budget: 43 min/mês |
| `errorQuery` | Requests 5xx | O SLI — o que conta como erro |
| `totalQuery` | Todos os requests | Base de cálculo |
| `{{.window}}` | Template do Sloth | Substituído automaticamente por 5m, 30m, 1h, 6h, 3d |
| `pageAlert` | severity: critical | Alerta que acorda engenheiro (PagerDuty) |
| `ticketAlert` | severity: warning | Alerta que gera ticket (Jira/Linear) |

> **⚠️ IMPORTANTE:** Os campos devem ser **camelCase**: `errorQuery`, `totalQuery`, `pageAlert`, `ticketAlert`. Se usar snake_case (`error_query`, `total_query`), o Sloth silenciosamente ignora e não gera as rules.

---

## Passo 3 — Aplicar os 3 SLOs

```bash
kubectl apply -f platform/slo/
```

✅ Esperado:
```
prometheusservicelevel.sloth.slok.dev/content-api-availability created
prometheusservicelevel.sloth.slok.dev/player-api-availability created
prometheusservicelevel.sloth.slok.dev/recommendation-api-availability created
```

---

## Passo 4 — Verificar PrometheusRules geradas

O Sloth gera automaticamente PrometheusRules com burn rate alerts:

```bash
kubectl get prometheusrules -n monitoring | grep -i slo
```

✅ Esperado:
```
content-api-availability-sloth-slo-rules-...          ...
player-api-availability-sloth-slo-rules-...           ...
recommendation-api-availability-sloth-slo-rules-...   ...
```

Inspecione uma rule para ver a estrutura multi-window:

```bash
kubectl get prometheusrule -n monitoring -l sloth.slok.dev/managed=true -o yaml | head -80
```

✅ Esperado: rules com janelas de 5m, 30m, 1h, 2h, 6h, 1d, 3d — exatamente como descrito no SRE Workbook capítulo 5.

---

## Passo 5 — Entender Multi-Window Burn Rate

O Sloth gera alertas baseados em 4 janelas de tempo combinadas:

```
Burn Rate = (taxa de erro atual) / (taxa de erro sustentável pelo SLO)
```

| Janela Longa | Janela Curta | Burn Rate | Tipo | Descrição |
|-------------|-------------|-----------|------|-----------------|
| 1h | 5m | 14.4x | PAGE (crítico) | Alerta no PagerDuty — engenheiro acorda |
| 6h | 30m | 6x | PAGE (crítico) | Degradação significativa em curso |
| 1d | 2h | 3x | TICKET (warning) | Ticket no Jira — investigar no business hours |
| 3d | 6h | 1x | TICKET (warning) | Erosão lenta do budget — planejar fix |

**Analogia prática:** imagine que seu SLO é 99.9% (error budget = 43 min/mês):

- **Burn rate 14.4x** = você está gastando o budget 14.4x mais rápido que o normal → em 3 horas acaba o budget mensal inteiro → PAGE imediato
- **Burn rate 1x** = gastando no ritmo normal → se continuar assim, o budget acaba exatamente no fim do mês → TICKET para investigar

Em produção, esse modelo é usado para decidir automaticamente se deve rollback um deploy: se o burn rate subiu após deploy, o sistema de CD faz rollback automático. No nosso lab, o ArgoCD (Tutorial 07) fará o equivalente via self-heal.

---

## Passo 6 — Verificar métricas no Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
sleep 2

# Recording rules geradas pelo Sloth
curl -s "http://localhost:9090/api/v1/query?query=slo:sli_error:ratio_rate5m" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  {r[\"metric\"].get(\"sloth_service\",\"?\")} = {r[\"value\"][1]}') for r in d.get('data',{}).get('result',[])]" 2>/dev/null \
  || echo "  (nenhum dado ainda — normal se acabou de instalar)"

kill %1 2>/dev/null
```

✅ Esperado: métricas de SLI para os 3 serviços (pode estar vazio se ainda não há tráfego — normal).

---

## Passo 7 — Verificar alertas no Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
sleep 2

curl -s "http://localhost:9090/api/v1/rules" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for g in data.get('data',{}).get('groups',[]):
    if 'sloth' in g.get('name','').lower() or 'slo' in g.get('name','').lower():
        print(f'Group: {g[\"name\"]}')
        for r in g.get('rules',[])[:3]:
            print(f'  Rule: {r.get(\"name\",\"?\")} ({r.get(\"type\",\"?\")})')
        print()
" 2>/dev/null

kill %1 2>/dev/null
```

✅ Esperado: grupos de rules com nomes como `sloth-slo-sli-recordings-content-api-...` e `sloth-slo-alerts-content-api-...`.

---

## Health Check (antes de avançar para Tutorial 06)

```bash
echo "=== HEALTH CHECK — Tutorial 05 ==="

echo -e "\n[1/4] Sloth pod Running:"
kubectl get pods -n monitoring | grep sloth | grep -q Running \
  && echo "  ✅ Sloth Running" || echo "  ❌ Sloth não está rodando"
echo ""

echo "[2/4] CRD PrometheusServiceLevel instalada:"
kubectl get crd prometheusservicelevels.sloth.slok.dev 2>/dev/null \
  && echo "  ✅ CRD presente" || echo "  ❌ CRD ausente"
echo ""

echo "[3/4] SLOs aplicados (3 esperados):"
COUNT=$(kubectl get prometheusservicelevel -n monitoring --no-headers 2>/dev/null | wc -l)
echo "  Encontrados: $COUNT"
if [ "$COUNT" -eq 3 ]; then
  echo "  ✅ 3 SLOs definidos"
else
  echo "  ❌ Esperava 3, encontrou $COUNT"
fi
echo ""

echo "[4/4] PrometheusRules geradas pelo Sloth:"
RULES=$(kubectl get prometheusrules -n monitoring -l sloth.slok.dev/managed=true --no-headers 2>/dev/null | wc -l)
echo "  Encontradas: $RULES rules"
if [ "$RULES" -ge 3 ]; then
  echo "  ✅ Rules geradas com sucesso"
else
  echo "  ❌ Menos de 3 rules — verifique os SLOs"
fi

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| Sloth pod CrashLoopBackOff | Falta de memória no cluster | Verifique `--memory=4096`. Se necessário, recrie o cluster |
| `prometheusservicelevels.sloth.slok.dev` not found | CRD não instalada | `helm upgrade --install sloth sloth/sloth -n monitoring --wait` |
| SLOs aplicados mas PrometheusRules não geradas | Campos em snake_case ao invés de camelCase | **Corrija:** `errorQuery` (não `error_query`), `totalQuery`, `pageAlert`, `ticketAlert` |
| PrometheusRules geradas mas Prometheus não carrega | `ruleSelectorNilUsesHelmValues: true` no values | Mude para `false` e `helm upgrade` |
| "No data" nas queries de SLO | Sem tráfego nos serviços (ServiceMonitor sem scrape real) | Normal — as recording rules só terão dados quando houver tráfego real (Tutorial 08: k6) |
| Helm chart do Sloth retorna 404 | URL do repo mudou | Verifique: `helm repo add sloth https://slok.github.io/sloth && helm repo update` |

---

## Conceitos-chave

- **SLO:** objetivo de confiabilidade expresso em porcentagem + janela de tempo
- **SLI:** indicador real (ex: taxa de erros 5xx / total de requests)
- **Error Budget:** quanto downtime o SLO permite (100% - SLO%)
- **Burn Rate:** velocidade com que o error budget está sendo consumido
- **Multi-window:** combinar janela longa (tendência) com janela curta (confirmação) para reduzir falsos positivos
- **Page vs Ticket:** page = acorda engenheiro, ticket = resolve no horário comercial
- O SRE Workbook capítulo 5 é a referência canônica para burn rate alerting

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `Verifique se os SLOs estão gerando alertas corretamente no Prometheus`
- `Adicione um novo SLO para latência p99 < 500ms no content-api`
- `Simule um cenário onde o error budget do content-api chega à zona vermelha`
- `Mostre o burn rate atual de cada serviço e me diga se algum está em risco`
- `Explique por que o Sloth usa multi-window burn rate e como isso reduz falsos positivos`

---

**Anterior:** [Tutorial 04 — Prometheus + Grafana com Helm](tutorial-04-prometheus-grafana.md)
**Próximo:** [Tutorial 06 — Chaos Engineering com Chaos Mesh](tutorial-06-chaos-mesh.md)
