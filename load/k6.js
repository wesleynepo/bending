import http from 'k6/http';
import { check } from 'k6';

// Load test for server.bend (GET /<key> -> Redis lookup).
//
// Seed the key first:   redis-cli SET greeting hello
// Run:                  k6 run load/k6.js
// Override the target:  k6 run -e BASE_URL=http://host:8080 -e KEY=greeting load/k6.js

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';
const KEY = __ENV.KEY || 'greeting';

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

export default function () {
  // The server closes each connection, so don't try to reuse it.
  // A 404 is the expected answer for a missing key, so don't count it as a failure.
  const params = {
    headers: { Connection: 'close' },
    responseCallback: http.expectedStatuses(200, 404),
  };

  // Alternate between a key that exists and one that doesn't.
  if (__ITER % 2 === 0) {
    const hit = http.get(`${BASE_URL}/${KEY}`, params);
    check(hit, {
      'hit: status 200': (r) => r.status === 200,
      'hit: JSON body': (r) => r.json('key') === KEY,
    });
  } else {
    const miss = http.get(`${BASE_URL}/does-not-exist`, params);
    check(miss, {
      'miss: status 404': (r) => r.status === 404,
    });
  }
}
