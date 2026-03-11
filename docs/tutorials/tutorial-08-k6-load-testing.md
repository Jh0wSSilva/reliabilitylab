# Tutorial 08 — Load Testing com k6

**Objetivo:** Criar e executar testes de carga com k6 para validar que os serviços StreamFlix suportam o tráfego esperado e que o HPA escala corretamente.

**Resultado:** Smoke test e load test executados, thresholds validados contra SLOs, HPA escalando de 2 para 6 réplicas sob carga.

**Tempo estimado:** 20 minutos

**Pré-requisitos:** Tutorial 07 completo com health check verde

---

## Contexto

Em ambientes de produção, load tests são executados continuamente para dimensionar infraestrutura antes de eventos de pico. Times de performance usam ferramentas que simulam milhões de requests simultâneos para validar que os SLOs são mantidos sob carga.

O **k6** é uma ferramenta de load testing open source da Grafana Labs. Diferente do JMeter (pesado, baseado em Java), o k6 é leve, scriptável em JavaScript e integra nativamente com Prometheus e Grafana. É a ferramenta recomendada para testar APIs no ecossistema cloud-native.

No nosso lab, usamos k6 para simular tráfego nos serviços e observar:
1. Se os thresholds de latência e erro são respeitados
2. Se o HPA escala quando a carga aumenta
3. Se o sistema se mantém estável durante e após o teste

---

## Passo 1 — Verificar que o k6 está instalado

```bash
k6 version
```

✅ Esperado: `k6 v0.5x.x` (qualquer versão recente).

Se não estiver instalado, consulte o Tutorial 01, Passo 1.

---

## Passo 2 — Expor o content-api para acesso local

O k6 precisa de um endpoint acessível de fora do cluster. Use port-forward:

```bash
kubectl port-forward svc/content-api -n production 8080:9898 &
```

Teste:

```bash
curl -s http://localhost:8080 | head -5
```

✅ Esperado: resposta JSON do podinfo.

---

## Passo 3 — Criar smoke test

O smoke test valida que o serviço está funcionando com carga mínima — equivalente a um health check com requests reais.

```bash
cat <<'EOFK6' > loadtests/smoke-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1,
  duration: '30s',

  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% das requests < 500ms
    http_req_failed: ['rate<0.01'],     // < 1% de erros
  },
};

export default function () {
  const res = http.get('http://localhost:8080');

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
EOFK6
```

| Config | Valor | Significado |
|--------|-------|-------------|
| `vus: 1` | 1 virtual user | Carga mínima — apenas validação |
| `duration: 30s` | 30 segundos | Tempo curto — smoke test |
| `p(95)<500` | Threshold de latência | Ligado ao SLO de latência |
| `rate<0.01` | Threshold de erro | Ligado ao SLO de disponibilidade |

Executar:

```bash
k6 run loadtests/smoke-test.js
```

✅ Esperado:
```
     ✓ status is 200
     ✓ response time < 500ms

     checks.........................: 100.00% ✓ XX  ✗ 0
     http_req_duration..............: avg=Xms  min=Xms  med=Xms  max=Xms  p(90)=Xms  p(95)=Xms
     http_req_failed................: 0.00%   ✓ 0   ✗ XX
     ✓ http_req_duration............: p(95)<500
     ✓ http_req_failed..............: rate<0.01
```

> Todos os thresholds devem passar (✓). Se algum falhar (✗), o serviço tem problemas antes mesmo de receber carga real.

---

## Passo 4 — Criar load test

O load test simula tráfego crescente para estressar o sistema e validar auto-scaling.

```bash
cat <<'EOFK6' > loadtests/load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // ramp up para 10 VUs
    { duration: '1m',  target: 50 },   // ramp up para 50 VUs
    { duration: '2m',  target: 100 },  // sustenta 100 VUs
    { duration: '30s', target: 0 },    // ramp down
  ],

  thresholds: {
    http_req_duration: ['p(95)<1000'],  // 95% < 1s sob carga
    http_req_failed: ['rate<0.05'],     // < 5% erro sob carga pesada
  },
};

export default function () {
  const res = http.get('http://localhost:8080');

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1s': (r) => r.timings.duration < 1000,
  });

  sleep(0.5);
}
EOFK6
```

| Stage | VUs | Duração | Propósito |
|-------|-----|---------|-----------|
| Ramp up 1 | 10 | 30s | Aquecimento |
| Ramp up 2 | 50 | 1m | Carga moderada |
| Sustain | 100 | 2m | **Carga de pico** — aqui o HPA deve escalar |
| Ramp down | 0 | 30s | Desaceleração graceful |

---

## Passo 5 — Executar load test com monitoramento

Abra 3 terminais:

**Terminal 1 — HPA (monitorar scaling):**
```bash
kubectl get hpa -n production -w
```

**Terminal 2 — Pods (monitorar criação):**
```bash
kubectl get pods -n production -w
```

**Terminal 3 — k6 (executar teste):**
```bash
k6 run loadtests/load-test.js
```

✅ Esperado no Terminal 1 (após ~1-2 minutos da fase de 100 VUs):
```
NAME          REFERENCE                TARGETS    MINPODS   MAXPODS   REPLICAS
content-api   Deployment/content-api   0%/70%     2         10        2
content-api   Deployment/content-api   45%/70%    2         10        2
content-api   Deployment/content-api   82%/70%    2         10        4
content-api   Deployment/content-api   95%/70%    2         10        6
```

> **Nota:** O podinfo consome CPU proporcionalmente à carga HTTP real. Para forçar escala rápida do HPA, use o endpoint `/stress/cpu` do podinfo ou combine com StressChaos do Chaos Mesh.

✅ Esperado no k6:
```
     ✓ status is 200
     ✓ response time < 1s

     http_req_duration..............: avg=XXms  p(95)=XXms
     http_req_failed................: X.XX%
     ✓ http_req_duration............: p(95)<1000
     ✓ http_req_failed..............: rate<0.05
```

---

## Passo 6 — Gerar carga combinada (HTTP + CPU stress)

Se o load test puro com HTTP não acionar o HPA rapidamente, combine com CPU stress via podinfo ou Chaos Mesh:

```bash
# Em paralelo ao k6, aplique StressChaos
kubectl apply -f platform/chaos/experiments/chaos-cpu-stress.yaml
```

Depois de ~2 minutos, observe o HPA:

```bash
kubectl get hpa -n production
```

✅ Esperado: réplicas escalando de 2 para 6.

Limpar após o teste:

```bash
kubectl delete stresschaos cpu-stress-content-api -n chaos-mesh 2>/dev/null
```

---

## Passo 7 — Criar stress test (opcional — para descobrir o limite)

```bash
cat <<'EOFK6' > loadtests/stress-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m',  target: 50 },
    { duration: '1m',  target: 100 },
    { duration: '1m',  target: 200 },
    { duration: '1m',  target: 300 },  // acima da capacidade esperada
    { duration: '30s', target: 0 },
  ],

  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.10'],  // aceita 10% erro em stress
  },
};

export default function () {
  const res = http.get('http://localhost:8080');

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.3);
}
EOFK6
```

> O stress test é projetado para **quebrar** o sistema — o objetivo é descobrir o ponto de ruptura, não passar nos thresholds.

---

## Passo 8 — Fechar port-forward

```bash
kill %1 2>/dev/null  # mata o port-forward do background
```

---

## Health Check (antes de avançar para Tutorial 09)

```bash
echo "=== HEALTH CHECK — Tutorial 08 ==="

echo -e "\n[1/3] Scripts de teste existem:"
for test in smoke-test.js load-test.js stress-test.js; do
  if [ -f "loadtests/$test" ]; then
    echo "  ✅ $test presente"
  else
    echo "  ❌ $test ausente"
  fi
done
echo ""

echo "[2/3] Smoke test passa:"
kubectl port-forward svc/content-api -n production 8080:9898 &>/dev/null &
PF_PID=$!
sleep 3
k6 run --quiet loadtests/smoke-test.js 2>/dev/null
EXIT_CODE=$?
kill $PF_PID 2>/dev/null
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "  ✅ Smoke test passou"
else
  echo "  ❌ Smoke test falhou (exit code $EXIT_CODE)"
fi
echo ""

echo "[3/3] HPA operacional (deve ter escalado e voltado):"
kubectl get hpa -n production --no-headers | awk '{print "  " $1, "replicas=" $6}'

echo -e "\n=== HEALTH CHECK COMPLETO ==="
```

---

## Troubleshooting

| Sintoma | Causa | Solução |
|---------|-------|---------|
| `connection refused` no k6 | Port-forward morreu ou não foi iniciado | `kubectl port-forward svc/content-api -n production 8080:9898 &` |
| k6 threshold falha `p(95)>500ms` | Pod em nó com CPU saturada | Verifique `kubectl top pods -n production`. Considere limpar StressChaos se rodou antes |
| HPA não escala durante load test | Carga insuficiente para atingir 70% CPU | Combine com `/stress/cpu` do podinfo ou StressChaos |
| `WARN[0001] Request Failed error` | Pod OOMKilled ou restartando | `kubectl describe pod <pod> -n production` para ver eventos |
| k6 não encontra arquivo de teste | Path incorreto | Execute do root do repositório: `cd reliabilitylab && k6 run loadtests/smoke-test.js` |
| Port-forward desconecta durante teste | Pod restartou | Normal durante chaos — reconecte: `kubectl port-forward svc/content-api -n production 8080:9898 &` |

---

## Conceitos-chave

- **Smoke test:** validação mínima — o serviço responde? (1 VU, thresholds apertados)
- **Load test:** carga esperada em produção — o sistema escala? (thresholds do SLO)
- **Stress test:** acima da capacidade — onde o sistema quebra? (descobrir limites)
- **Thresholds no k6:** devem ser derivados dos SLOs — se o SLO é 99.9% disponibilidade, o threshold é `rate<0.001`
- **Shift-left testing:** em ambientes maduros, load tests rodam no CI/CD — não apenas antes de releases. O k6 integra nativamente com GitHub Actions e GitLab CI

---

## Prompts para continuar com a IA

> Use estes prompts no Copilot Chat para destravar problemas ou explorar o ambiente.

- `O smoke test falhou com connection refused. Diagnostique o port-forward e o serviço`
- `Crie um script k6 que testa os 3 serviços simultaneamente`
- `Derive os thresholds do load-test.js a partir dos SLOs definidos em platform/slo/`
- `O stress test mostrou erros acima de 1%. Analise o que pode estar causando`
- `Configure o k6 para rodar como step no GitHub Actions CI`

---

**Anterior:** [Tutorial 07 — GitOps com ArgoCD](tutorial-07-argocd.md)
**Próximo:** [Tutorial 09 — GameDay](tutorial-09-gameday.md)
