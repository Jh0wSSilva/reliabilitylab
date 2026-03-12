# Tutorial 09 — Load Testing com k6

## Objetivo

Realizar testes de carga na aplicação usando **k6** para validar performance, encontrar limites e verificar comportamento do HPA.

## Conceitos

- **Load Testing**: simular múltiplos usuários simultâneos para avaliar performance
- **Smoke Test**: teste rápido para verificar se a aplicação funciona sob carga mínima
- **Load Test**: teste com carga normal para validar SLOs
- **Stress Test**: teste com carga acima do esperado para encontrar limites
- **Spike Test**: teste com pico súbito de tráfego
- **VUs (Virtual Users)**: usuários virtuais simulados pelo k6
- **Thresholds**: limites aceitáveis de performance (latência, erros)

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| k6 | 0.50+ | `k6 version` |
| Aplicação rodando | - | `curl http://site-kubectl.local/api/health` |

### Instalar k6

```bash
# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
    --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
    sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6

# macOS
brew install k6

# Docker (sem instalação)
docker run --rm -i grafana/k6 run - < load-testing/smoke-test.js
```

## Testes Disponíveis

| Teste | Arquivo | Duração | VUs | Objetivo |
|-------|---------|---------|-----|----------|
| Smoke | `load-testing/smoke-test.js` | 30s | 1-3 | Verificar funcionalidade básica |
| Load | `load-testing/load-test.js` | 3min | até 20 | Validar performance normal |
| Stress | `load-testing/stress-test.js` | 5min | até 50 | Encontrar limites |
| Spike | `load-testing/spike-test.js` | 3min | 1→80 | Testar picos súbitos |

## Passo a Passo

### 1. Smoke Test (Comece por aqui!)

```bash
bash scripts/run-load-test.sh smoke
```

**Thresholds:**
- p95 < 500ms
- Erros < 1%
- 95% verificações OK

**Resultado esperado:**
```
✓ status is 200
✓ response time < 500ms

checks.........................: 100.00%
http_req_duration..............: avg=15ms  p(95)=45ms
http_req_failed................: 0.00%
```

### 2. Load Test

```bash
bash scripts/run-load-test.sh load
```

Testa 5 grupos de endpoints:
- Health check
- Página principal
- Docker tutorials
- Kubernetes tutorials
- Tools

**Thresholds:**
- p95 < 1s
- Erros < 5%

### 3. Stress Test

```bash
bash scripts/run-load-test.sh stress
```

> ⚠️ **Dica:** Enquanto o stress test roda, observe o HPA em outro terminal:
> ```bash
> kubectl get hpa -n reliabilitylab -w
> ```

**O que observar:**
- Latência aumentando gradualmente
- HPA escalando pods
- Ponto onde a aplicação começa a degradar

### 4. Spike Test

```bash
bash scripts/run-load-test.sh spike
```

Simula um cenário de Black Friday: tráfego normal → pico súbito → volta ao normal.

**Fases:**
```
1-3 VUs (30s) → 80 VUs (30s) → 1-3 VUs (60s)
         warmup        spike         recovery
```

## Interpretando Resultados

### Métricas Importantes

| Métrica | Significado | Bom | Ruim |
|---------|-------------|-----|------|
| `http_req_duration p(95)` | 95% das requisições abaixo desse valor | < 500ms | > 2s |
| `http_req_failed` | Porcentagem de erros | < 1% | > 5% |
| `checks` | Verificações personalizadas | > 99% | < 95% |
| `http_reqs` | Total de requisições/segundo | Alto | N/A |
| `iteration_duration` | Tempo de uma iteração completa | < 1s | > 5s |

### Status dos Thresholds

```
✓ = threshold passou (dentro do aceitável)
✗ = threshold falhou (precisa investigar)
```

## Correlacionando com Observabilidade

Em paralelo com o teste de carga:

### No Grafana
1. Abrir dashboard **Site-Kubectl Overview**
2. Observar:
   - Aumento de requisições/segundo
   - Latência subindo
   - Uso de CPU aumentando
   - Pods escalando (HPA)

### No Prometheus
```promql
# Taxa de requisições durante o teste
rate(http_requests_total{namespace="reliabilitylab"}[1m])

# Uso de CPU durante o teste
rate(container_cpu_usage_seconds_total{namespace="reliabilitylab",container="site-kubectl"}[1m])
```

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `dial tcp: connection refused` | Aplicação não está rodando. Verifique: `curl http://site-kubectl.local/api/health` |
| k6 não encontrado | Instale o k6 (ver seção Pré-requisitos) |
| Thresholds falhando no smoke test | Possível problema na aplicação. Verifique pods e logs |
| Latência muito alta no load test | Verifique limites de recurso dos pods. Considere aumentar CPU |
| HPA não escala durante stress | Verifique Metrics Server: `kubectl top pods -n reliabilitylab` |

## Próximo Tutorial

[10 — Observando Falhas e Recuperação](10-observando-falhas-recuperacao.md)
