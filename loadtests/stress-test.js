import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '2m', target: 50 },
    { duration: '2m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  // Mix de endpoints para gerar carga realista
  const rand = Math.random();
  let res;
  if (rand < 0.6) {
    res = http.get(`${BASE_URL}/`);
  } else if (rand < 0.8) {
    res = http.get(`${BASE_URL}/env`);
  } else {
    // Simula latencia variavel (0-100ms)
    res = http.get(`${BASE_URL}/delay/0.1`);
  }

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 1000ms': (r) => r.timings.duration < 1000,
  });

  sleep(0.3);
}
