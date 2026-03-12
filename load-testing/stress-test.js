// =============================================================================
// ReliabilityLab — Stress Test (k6)
// Teste de stress: encontra o limite da aplicação sob carga extrema
//
// Executar:
//   k6 run -e BASE_URL=http://site-kubectl.local load-testing/stress-test.js
//
// Duração: ~5 minutos
// VUs: até 50
// =============================================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://site-kubectl.local';

export const options = {
    stages: [
        { duration: '30s', target: 10 },   // Warmup
        { duration: '1m',  target: 25 },   // Carga média-alta
        { duration: '1m',  target: 50 },   // Carga máxima
        { duration: '1m',  target: 50 },   // Sustentação do pico
        { duration: '30s', target: 25 },   // Redução gradual
        { duration: '30s', target: 0 },    // Ramp-down
    ],
    thresholds: {
        // Em stress test, aceitamos degradação mas não falha total
        http_req_duration: ['p(95)<3000'],  // 95% das requisições < 3s
        http_req_failed: ['rate<0.15'],      // Menos de 15% de erros
    },
};

export default function () {
    group('Endpoints Críticos', function () {
        // Health check — deve ser o mais rápido
        const health = http.get(`${BASE_URL}/api/health`);
        check(health, {
            'health: status 200': (r) => r.status === 200,
        });

        // Página principal
        const home = http.get(`${BASE_URL}/`);
        check(home, {
            'home: status 200': (r) => r.status === 200,
        });
    });

    group('Navegação Completa', function () {
        // Simular navegação completa do usuário
        const pages = [
            '/docker',
            '/kubernetes',
            '/tools',
            '/projects',
            '/cheatsheets',
        ];

        for (const page of pages) {
            const res = http.get(`${BASE_URL}${page}`);
            check(res, {
                [`${page}: respondeu`]: (r) => r.status === 200 || r.status === 404,
            });
        }
    });

    group('API Search', function () {
        const queries = ['docker', 'kubernetes', 'pod', 'container'];
        const query = queries[Math.floor(Math.random() * queries.length)];
        const res = http.get(`${BASE_URL}/api/search?q=${query}`);
        check(res, {
            'search: respondeu': (r) => r.status === 200,
        });
    });

    sleep(0.5);
}
