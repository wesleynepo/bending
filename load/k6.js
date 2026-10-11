import http from 'k6/http';
import { check } from 'k6';

// Load test for server.bend (GET /people/{id} through the Redis cache, then Postgres on a miss).
//
// setup() creates one person (POST /people); the iterations read it (200) and look up a
// random uuid that does not exist (404); teardown() deletes the person.
// Start the stack first (docker compose up -d) and the server (bend server.bend).
// Run:                  k6 run load/k6.js
// Override the target:  k6 run -e BASE_URL=http://host:8080 load/k6.js

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';
const JSON_HEADERS = { 'Content-Type': 'application/json', Connection: 'close' };

export const options = {
  scenarios: {
    // Fixed request rate (one request per iteration), stepped up. Kept low enough
    // that closed connections in TIME_WAIT don't exhaust the client's ephemeral ports.
    steps: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 400,
      stages: [
        { target: 100, duration: '10s' },
        { target: 250, duration: '10s' },
        { target: 400, duration: '10s' },
        { target: 550, duration: '10s' },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],     // <1% errors
    http_req_duration: ['p(95)<250'],   // 95% of requests under 250ms
    dropped_iterations: ['count==0'],   // server kept up with the arrival rate
  },
};

// A random uuid-shaped string; the server answers 404 for any id it does not store.
function randomId() {
  return 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g, () =>
    Math.floor(Math.random() * 16).toString(16));
}

export function setup() {
  const body = JSON.stringify({ name: 'load-test', birthdate: '1990-06-15' });
  const res = http.post(`${BASE_URL}/people`, body, { headers: JSON_HEADERS });
  if (res.status !== 201) {
    throw new Error(`setup: POST /people returned ${res.status}`);
  }
  return { id: res.json('id') };
}

export default function (data) {
  // The server closes each connection, so don't try to reuse it.
  // A 404 is the expected answer for an unknown id, so don't count it as a failure.
  const params = {
    headers: { Connection: 'close' },
    responseCallback: http.expectedStatuses(200, 404),
  };

  // Alternate between the person created in setup() and an id that doesn't exist.
  if (__ITER % 2 === 0) {
    const hit = http.get(`${BASE_URL}/people/${data.id}`, params);
    check(hit, {
      'hit: status 200': (r) => r.status === 200,
      'hit: JSON body': (r) => r.json('id') === data.id,
    });
  } else {
    const miss = http.get(`${BASE_URL}/people/${randomId()}`, params);
    check(miss, {
      'miss: status 404': (r) => r.status === 404,
    });
  }
}

export function teardown(data) {
  http.del(`${BASE_URL}/people/${data.id}`, null, { headers: { Connection: 'close' } });
}
