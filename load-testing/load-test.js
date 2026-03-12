// =============================================================================
// ReliabilityLab — Load Test (k6)
// Teste de carga normal: simula tráfego típico de produção
//
// Executar:
//   k6 run -e BASE_URL=http://site-kubectl.local load-testing/load-test.js
//
// Duração: ~3 minutos
// VUs: até 20
// =============================================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://site-kubectl.local';

export const options = {
    stages: [
        { duration: '30s', target: 5 },   // Ramp-up: 0 → 5 usuários
        { duration: '1m',  target: 10 },   // Crescer para 10 usuários
        { duration: '30s', target: 20 },   // Pico: 20 usuários
        { duration: '30s', target: 10 },   // Reduzir para 10
        { duration: '30s', target: 0 },    // Ramp-down
    ],
    thresholds: {
        http_req_duration: ['p(95)<1000', 'p(99)<2000'],  // Latência aceitável
        http_req_failed: ['rate<0.05'],                     // Menos de 5% de erros
        'group_duration{group:::Health Check}': ['avg<200'],
    },
};

export default function () {
    group('Health Check', function () {
        const res = http.get(`${BASE_URL}/api/health`);
        check(res, {
            'health: status 200': (r) => r.status === 200,
            'health: latência < 200ms': (r) => r.timings.duration < 200,
        });
    });

    group('Página Principal', function () {
        const res = http.get(`${BASE_URL}/`);
        check(res, {
            'home: status 200': (r) => r.status === 200,
            'home: contém conteúdo': (r) => r.body.length > 100,
        });
    });

    group('Tutoriais Docker', function () {
        const res = http.get(`${BASE_URL}/docker`);
        check(res, {
            'docker: status 200': (r) => r.status === 200,
        });
    });

    group('Tutoriais Kubernetes', function () {
        const res = http.get(`${BASE_URL}/kubernetes`);
        check(res, {
            'kubernetes: status 200': (r) => r.status === 200,
        });
    });

    group('Ferramentas', function () {
        const res = http.get(`${BASE_URL}/tools`);
        check(res, {
            'tools: status 200': (r) => r.status === 200,
        });
    });

    sleep(1);
}
