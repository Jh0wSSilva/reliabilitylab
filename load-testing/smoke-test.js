// =============================================================================
// ReliabilityLab — Smoke Test (k6)
// Teste rápido de verificação: valida que a aplicação está respondendo
//
// Executar:
//   k6 run -e BASE_URL=http://site-kubectl.local load-testing/smoke-test.js
//
// Duração: ~30 segundos
// VUs: 1-3
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://site-kubectl.local';

export const options = {
    stages: [
        { duration: '10s', target: 1 },  // Subir para 1 usuário
        { duration: '10s', target: 3 },  // Subir para 3 usuários
        { duration: '10s', target: 0 },  // Reduzir para 0
    ],
    thresholds: {
        // Requisitos mínimos de qualidade
        http_req_duration: ['p(95)<500'],  // 95% das requisições < 500ms
        http_req_failed: ['rate<0.01'],     // Menos de 1% de erros
    },
};

export default function () {
    // Testar health endpoint
    const healthRes = http.get(`${BASE_URL}/api/health`);
    check(healthRes, {
        'health: status 200': (r) => r.status === 200,
        'health: resposta contém status ok': (r) => r.json().status === 'ok',
    });

    // Testar página principal
    const homeRes = http.get(`${BASE_URL}/`);
    check(homeRes, {
        'home: status 200': (r) => r.status === 200,
    });

    sleep(1);
}
