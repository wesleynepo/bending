// Functional test for the People API. Not a load test: one VU, one iteration.
// Run: BASE_URL=http://127.0.0.1:8080 k6 run test/api.k6.js
import http from 'k6/http';
import { check, group } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate==1'],
  },
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TAG = Math.random().toString(16).slice(2, 10);
const created = new Set(); // ids to delete at the end, even if a check fails

function randomV4() {
  const h = () => Math.floor(Math.random() * 16).toString(16);
  let s = '';
  for (let i = 0; i < 32; i++) s += h();
  const variant = '89ab'[Math.floor(Math.random() * 4)];
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-4${s.slice(13, 16)}-${variant}${s.slice(17, 20)}-${s.slice(20, 32)}`;
}

// Every request sends Connection: close. Expected statuses are declared per call,
// so an expected 4xx/404/405 does not count as http_req_failed.
function call(method, path, body, expected) {
  let payload = null;
  if (body !== undefined && body !== null) {
    payload = typeof body === 'string' ? body : JSON.stringify(body);
  }
  const params = {
    headers: { Connection: 'close', 'Content-Type': 'application/json' },
    responseCallback: http.expectedStatuses(...expected),
    tags: { endpoint: path.replace(/\?.*$/, '').replace(/\/[0-9a-f-]{36}/, '/:id') },
  };
  return http.request(method, BASE_URL + path, payload, params);
}

function json(res) {
  try {
    return res.json();
  } catch (_) {
    return undefined;
  }
}

function hasError(res, message) {
  const b = json(res);
  return !!b && typeof b.error === 'string' && (message === undefined || b.error === message);
}

function isEmptyBody(res) {
  return res.body === null || res.body === undefined || res.body.length === 0;
}

// Pages through GET /people with limit=200 and returns every person in server order.
function allPeople() {
  const people = [];
  for (let offset = 0; offset < 100000; offset += 200) {
    const page = json(call('GET', `/people?limit=200&offset=${offset}`, null, [200]));
    if (!Array.isArray(page)) return null;
    people.push(...page);
    if (page.length < 200) break;
  }
  return people;
}

export default function () {
  let adaId;
  let uniId;
  let hostileId;
  let aaaId;
  let zzzId;
  let boundaryId;

  try {
    group('health', () => {
      const res = call('GET', '/health', null, [200]);
      check(res, {
        'health: 200': (r) => r.status === 200,
        'health: body status ok': () => {
          const b = json(res);
          return !!b && b.status === 'ok';
        },
      });
    });

    group('create', () => {
      const res = call('POST', '/people', { name: `  Ada Test ${TAG}  `, birthdate: '1990-12-10' }, [201]);
      const b = json(res) || {};
      check(res, {
        'create: 201': (r) => r.status === 201,
        'create: id is canonical uuid': () => UUID_RE.test(b.id),
        'create: name trimmed': () => b.name === `Ada Test ${TAG}`,
        'create: birthdate echoed': () => b.birthdate === '1990-12-10',
      });
      adaId = b.id;
      if (adaId) created.add(adaId);

      const uni = call('POST', '/people', { name: 'João Ñandú 😀', birthdate: '1990-06-15' }, [201]);
      const ub = json(uni) || {};
      check(uni, {
        'create unicode: 201': (r) => r.status === 201,
        'create unicode: name round-trips': () => ub.name === 'João Ñandú 😀',
      });
      uniId = ub.id;
      if (uniId) created.add(uniId);

      const edge = call('POST', '/people', { name: 'a'.repeat(200), birthdate: '1900-01-01' }, [201]);
      const eb = json(edge) || {};
      check(edge, { 'create 200-char name: 201': (r) => r.status === 201 });
      boundaryId = eb.id;
      if (boundaryId) created.add(boundaryId);

      const aaa = call('POST', '/people', { name: `k6-aaa-${TAG}`, birthdate: '2000-02-29' }, [201]);
      aaaId = (json(aaa) || {}).id;
      if (aaaId) created.add(aaaId);
      const zzz = call('POST', '/people', { name: `k6-zzz-${TAG}`, birthdate: '2000-02-29' }, [201]);
      zzzId = (json(zzz) || {}).id;
      if (zzzId) created.add(zzzId);
    });

    group('create invalid bodies', () => {
      const cases = [
        ['bad JSON', '{"name": "x", "birthdate": '],
        ['missing name', { birthdate: '1990-01-01' }],
        ['missing birthdate', { name: 'x' }],
        ['non-string name', { name: 42, birthdate: '1990-01-01' }],
        ['empty name', { name: '', birthdate: '1990-01-01' }],
        ['whitespace-only name', { name: '   ', birthdate: '1990-01-01' }],
        ['201-char name', { name: 'a'.repeat(201), birthdate: '1990-01-01' }],
        ['date 2023-02-29', { name: 'x', birthdate: '2023-02-29' }],
        ['date 2021-13-01', { name: 'x', birthdate: '2021-13-01' }],
        ['date "yesterday"', { name: 'x', birthdate: 'yesterday' }],
        ['year 1899', { name: 'x', birthdate: '1899-12-31' }],
        ['year 3000', { name: 'x', birthdate: '3000-01-01' }],
      ];
      for (const [label, body] of cases) {
        const res = call('POST', '/people', body, [400]);
        check(res, {
          [`invalid create (${label}): 400`]: (r) => r.status === 400,
          [`invalid create (${label}): error body`]: (r) => hasError(r),
        });
      }
    });

    group('get', () => {
      const res = call('GET', `/people/${adaId}`, null, [200]);
      const b = json(res) || {};
      check(res, {
        'get: 200': (r) => r.status === 200,
        'get: matches created person': () =>
          b.id === adaId && b.name === `Ada Test ${TAG}` && b.birthdate === '1990-12-10',
      });

      const bad = call('GET', '/people/not-a-uuid', null, [400]);
      check(bad, {
        'get invalid uuid: 400': (r) => r.status === 400,
        'get invalid uuid: error body': (r) => hasError(r),
      });

      const unknown = call('GET', `/people/${randomV4()}`, null, [404]);
      check(unknown, {
        'get unknown uuid: 404': (r) => r.status === 404,
        'get unknown uuid: error not found': (r) => hasError(r, 'not found'),
      });
    });

    group('list', () => {
      const people = allPeople();
      check(people, {
        'list: full scan returns array': (p) => Array.isArray(p),
      });
      const ids = (people || []).map((p) => p.id);
      check(ids, {
        'list: contains created person': (list) => list.includes(adaId),
        'list: ordered by name (aaa before zzz)': (list) =>
          list.indexOf(aaaId) >= 0 && list.indexOf(zzzId) > list.indexOf(aaaId),
        'list: every item is a canonical uuid': () => (people || []).every((p) => UUID_RE.test(p.id)),
      });

      const page1 = json(call('GET', '/people?limit=2&offset=0', null, [200]));
      const page2 = json(call('GET', '/people?limit=1&offset=1', null, [200]));
      check(page1, {
        'list limit=2: two items': (p) => Array.isArray(p) && p.length === 2,
      });
      check(page2, {
        'list offset=1 limit=1: one item equal to second item': (p) =>
          Array.isArray(p) && p.length === 1 && Array.isArray(page1) && p[0].id === page1[1].id,
      });

      const def = json(call('GET', '/people', null, [200]));
      check(def, { 'list default limit: at most 50': (p) => Array.isArray(p) && p.length <= 50 });

      const clamped = call('GET', '/people?limit=1000', null, [200]);
      check(clamped, {
        'list limit=1000: 200 (clamped, not an error)': (r) => r.status === 200,
        'list limit=1000: at most 200 items': (r) => {
          const p = json(r);
          return Array.isArray(p) && p.length <= 200;
        },
      });

      const zero = json(call('GET', '/people?limit=0', null, [200]));
      check(zero, { 'list limit=0: empty array': (p) => Array.isArray(p) && p.length === 0 });

      for (const q of ['limit=-1', 'limit=abc', 'limit=1.5', 'offset=-1']) {
        const res = call('GET', `/people?${q}`, null, [400]);
        check(res, {
          [`list bad ${q}: 400`]: (r) => r.status === 400,
          [`list bad ${q}: error body`]: (r) => hasError(r),
        });
      }
    });

    group('update', () => {
      const res = call('PUT', `/people/${adaId}`, { name: `Ada Updated ${TAG}`, birthdate: '1991-01-01' }, [200]);
      const b = json(res) || {};
      check(res, {
        'update: 200': (r) => r.status === 200,
        'update: body reflects change': () =>
          b.id === adaId && b.name === `Ada Updated ${TAG}` && b.birthdate === '1991-01-01',
      });

      const persisted = json(call('GET', `/people/${adaId}`, null, [200])) || {};
      check(persisted, {
        'update: change persisted': (p) => p.name === `Ada Updated ${TAG}` && p.birthdate === '1991-01-01',
      });

      const unknown = call('PUT', `/people/${randomV4()}`, { name: 'x', birthdate: '1990-01-01' }, [404]);
      check(unknown, {
        'update unknown id: 404': (r) => r.status === 404,
        'update unknown id: error not found': (r) => hasError(r, 'not found'),
      });

      const badBody = call('PUT', `/people/${adaId}`, { name: '', birthdate: '2021-13-01' }, [400]);
      check(badBody, {
        'update invalid body: 400': (r) => r.status === 400,
        'update invalid body: error body': (r) => hasError(r),
      });

      const badId = call('PUT', '/people/not-a-uuid', { name: 'x', birthdate: '1990-01-01' }, [400]);
      check(badId, { 'update invalid id: 400': (r) => r.status === 400 });
    });

    group('delete', () => {
      const res = call('DELETE', `/people/${adaId}`, null, [204]);
      check(res, {
        'delete: 204': (r) => r.status === 204,
        'delete: empty body': (r) => isEmptyBody(r),
      });
      if (res.status === 204) created.delete(adaId);

      const gone = call('GET', `/people/${adaId}`, null, [404]);
      check(gone, { 'after delete, get: 404': (r) => r.status === 404 });

      const again = call('DELETE', `/people/${adaId}`, null, [404]);
      check(again, {
        'delete again: 404': (r) => r.status === 404,
        'delete again: error not found': (r) => hasError(r, 'not found'),
      });

      const badId = call('DELETE', '/people/not-a-uuid', null, [400]);
      check(badId, { 'delete invalid id: 400': (r) => r.status === 400 });
    });

    group('method and path errors', () => {
      const patch = call('PATCH', `/people/${zzzId}`, { name: 'x' }, [405]);
      check(patch, {
        'PATCH /people/{id}: 405': (r) => r.status === 405,
        'PATCH /people/{id}: error method not allowed': (r) => hasError(r, 'method not allowed'),
      });

      const postHealth = call('POST', '/health', {}, [405]);
      check(postHealth, {
        'POST /health: 405': (r) => r.status === 405,
        'POST /health: error method not allowed': (r) => hasError(r, 'method not allowed'),
      });

      const unknownPath = call('GET', '/nope', null, [404]);
      check(unknownPath, {
        'unknown path: 404': (r) => r.status === 404,
        'unknown path: error not found': (r) => hasError(r, 'not found'),
      });
    });

    group('hostile name', () => {
      const hostile = "x'); DROP TABLE people;--";
      const res = call('POST', '/people', { name: hostile, birthdate: '1990-01-01' }, [201]);
      const b = json(res) || {};
      check(res, { 'hostile create: 201': (r) => r.status === 201 });
      hostileId = b.id;
      if (hostileId) created.add(hostileId);

      const got = json(call('GET', `/people/${hostileId}`, null, [200])) || {};
      check(got, { 'hostile name round-trips unchanged': (p) => p.name === hostile });

      const people = allPeople();
      check(people, {
        'list still works after hostile name': (p) => Array.isArray(p),
        'list contains hostile person': (p) => Array.isArray(p) && p.some((x) => x.id === hostileId),
      });
    });
  } finally {
    group('cleanup', () => {
      for (const id of created) {
        const res = call('DELETE', `/people/${id}`, null, [204, 404]);
        check(res, { 'cleanup: delete succeeded': (r) => r.status === 204 || r.status === 404 });
      }
    });
  }
}
