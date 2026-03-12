// =============================================================================
// Teste de Resiliência — k6 + Chaos combinados
//
// Este script executa carga contínua ENQUANTO experimentos de chaos acontecem.
// Mede o impacto na disponibilidade, latência e taxa de erros durante o chaos.
//
// Uso:
//   k6 run load-testing/resilience-test.js
//
// Ou via script:
//   ./scripts/run-resilience-tests.sh
//
// Variáveis de ambiente:
//   BASE_URL — URL base do serviço (padrão: http://site-kubectl.local)
//   DURATION — Duração do teste (padrão: 5m)
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// --- Métricas customizadas ---
const errorRate = new Rate('resilience_error_rate');
const latencyP95 = new Trend('resilience_latency_p95');
const successCounter = new Counter('resilience_success_total');
const failureCounter = new Counter('resilience_failure_total');

// --- Configuração ---
const BASE_URL = __ENV.BASE_URL || 'http://site-kubectl.local';
const DURATION = __ENV.DURATION || '5m';

export const options = {
  scenarios: {
    // Carga base constante — simula tráfego normal durante o chaos
    steady_load: {
      executor: 'constant-arrival-rate',
      rate: 10,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 50,
    },
    // Picos periódicos — simula bursts durante o chaos
    spike_load: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      stages: [
        { duration: '30s', target: 5 },
        { duration: '15s', target: 30 },
        { duration: '30s', target: 5 },
        { duration: '15s', target: 40 },
        { duration: '30s', target: 5 },
        { duration: '15s', target: 20 },
        { duration: '30s', target: 5 },
      ],
      preAllocatedVUs: 30,
      maxVUs: 60,
    },
  },

  // Thresholds baseados nos SLOs definidos
  thresholds: {
    // SLO: 99.9% disponibilidade → no máximo 0.1% de erros
    'resilience_error_rate': [
      { threshold: 'rate<0.01', abortOnFail: false },  // Alerta: > 1%
      { threshold: 'rate<0.05', abortOnFail: false },  // Crítico: > 5%
    ],
    // SLO: P95 < 500ms
    'http_req_duration': [
      { threshold: 'p(95)<500', abortOnFail: false },
      { threshold: 'p(99)<1000', abortOnFail: false },
    ],
    // Verificar que pelo menos 90% das requisições passam
    'checks': [
      { threshold: 'rate>0.90', abortOnFail: false },
    ],
  },
};

// --- Funções de teste ---
export default function () {
  // Teste 1: Página principal
  const mainPage = http.get(`${BASE_URL}/`);
  const mainOk = check(mainPage, {
    'homepage status 200': (r) => r.status === 200,
    'homepage latência < 1s': (r) => r.timings.duration < 1000,
  });

  if (mainOk) {
    successCounter.add(1);
    errorRate.add(false);
  } else {
    failureCounter.add(1);
    errorRate.add(true);
  }
  latencyP95.add(mainPage.timings.duration);

  sleep(0.1);

  // Teste 2: Health check
  const health = http.get(`${BASE_URL}/api/health`);
  const healthOk = check(health, {
    'health status 200': (r) => r.status === 200,
    'health latência < 500ms': (r) => r.timings.duration < 500,
  });

  if (healthOk) {
    successCounter.add(1);
    errorRate.add(false);
  } else {
    failureCounter.add(1);
    errorRate.add(true);
  }

  sleep(0.1);

  // Teste 3: Endpoints variados (simula tráfego real)
  const endpoints = ['/', '/api/health'];
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  const response = http.get(`${BASE_URL}${endpoint}`);

  check(response, {
    'endpoint responde': (r) => r.status < 500,
  });

  errorRate.add(response.status >= 500);

  sleep(Math.random() * 0.5);
}

// --- Relatório final ---
export function handleSummary(data) {
  const totalRequests = data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0;
  const errorRateVal = data.metrics.resilience_error_rate ? data.metrics.resilience_error_rate.values.rate : 0;
  const p95 = data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(95)'] : 0;
  const p99 = data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(99)'] : 0;

  const sloAvailability = (1 - errorRateVal) * 100;
  const sloLatencyP95 = p95 < 500 ? 'PASS' : 'FAIL';
  const sloLatencyP99 = p99 < 1000 ? 'PASS' : 'FAIL';
  const sloCompliance = sloAvailability >= 99.9 ? 'PASS' : 'FAIL';

  const report = `
==========================================
  RELATÓRIO DE RESILIÊNCIA
==========================================

  Total de Requisições: ${totalRequests}
  Taxa de Erros:        ${(errorRateVal * 100).toFixed(2)}%
  Latência P95:         ${p95.toFixed(0)}ms
  Latência P99:         ${p99.toFixed(0)}ms

  --- Validação SLO ---
  Disponibilidade: ${sloAvailability.toFixed(3)}% (target: 99.9%) → ${sloCompliance}
  Latência P95:    ${p95.toFixed(0)}ms (target: <500ms) → ${sloLatencyP95}
  Latência P99:    ${p99.toFixed(0)}ms (target: <1000ms) → ${sloLatencyP99}

  Resultado: ${sloCompliance === 'PASS' && sloLatencyP95 === 'PASS' ? '✅ SLOs MANTIDOS' : '❌ SLOs VIOLADOS'}
==========================================
`;

  console.log(report);

  return {
    'stdout': report,
    'results/resilience-report.json': JSON.stringify(data, null, 2),
  };
}
