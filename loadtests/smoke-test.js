import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  const res = http.get(`${BASE_URL}/`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body is JSON': (r) => r.json() !== null,
    'hostname present': (r) => r.json('hostname') !== '',
  });

  const health = http.get(`${BASE_URL}/healthz`);
  check(health, {
    'healthz is 200': (r) => r.status === 200,
  });

  sleep(1);
}
