// =============================================================================
// ReliabilityLab — Spike Test (k6)
// Teste de pico: simula um aumento repentino e dramático de tráfego
//
// Executar:
//   k6 run -e BASE_URL=http://site-kubectl.local load-testing/spike-test.js
//
// Duração: ~3 minutos
// VUs: 1 → 80 (pico instantâneo) → 1
//
// Objetivo: verificar como a aplicação e o HPA reagem a picos repentinos
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://site-kubectl.local';

export const options = {
    stages: [
        { duration: '20s', target: 1 },    // Tráfego normal
        { duration: '5s',  target: 80 },   // SPIKE! Pico repentino
        { duration: '1m',  target: 80 },   // Sustentar o pico
        { duration: '10s', target: 1 },    // Queda rápida
        { duration: '30s', target: 1 },    // Recuperação
        { duration: '15s', target: 0 },    // Finalizar
    ],
    thresholds: {
        // Durante spikes, esperamos alguma degradação
        http_req_duration: ['p(90)<5000'],   // 90% das requisições < 5s
        http_req_failed: ['rate<0.20'],       // Menos de 20% de erros
    },
};

export default function () {
    // Testar diversos endpoints simultaneamente
    const endpoints = [
        '/api/health',
        '/',
        '/docker',
        '/kubernetes',
    ];

    const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
    const res = http.get(`${BASE_URL}${endpoint}`);

    check(res, {
        'respondeu com sucesso': (r) => r.status === 200,
        'latência < 5s': (r) => r.timings.duration < 5000,
    });

    // Tempo mínimo entre requests para simular comportamento real
    sleep(0.3);
}
