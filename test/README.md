# API tests

1. Start Postgres and Redis (local development only, no auth):
   `docker compose up -d` (starts `postgres` and `redis`; check with `docker compose ps`).
2. Start the server from the repo root (env vars read by the server):
   `PORT=8080 PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=postgres PGPASSWORD=postgres REDIS_HOST=127.0.0.1 REDIS_PORT=6379 CACHE_TTL=3600 bend server.bend`
3. Run the functional test (defaults to BASE_URL=http://127.0.0.1:8080):
   `k6 run test/api.k6.js`
   Override with `BASE_URL=http://host:port k6 run test/api.k6.js`.
4. Run the cache checks (needs steps 1 and 2; restarts Redis as part of the test):
   `bash test/cache.sh`

The k6 test creates its own people and deletes them at the end. It passes only if every check passes.
`test/cache.sh` prints PASS/FAIL per check and exits non-zero on any failure.
API contract: `docs/openapi.yaml`.

## Caching

- Key `person:<uuid>` holds the person's JSON. TTL is `CACHE_TTL` seconds (default 3600). `CACHE_TTL=0` disables caching.
- `GET /people/{id}` is cache-aside: a hit is served from Redis; a miss reads Postgres and stores the result with TTL. An unknown id returns 404 and caches nothing.
- `POST /people` and `PUT /people/{id}` write Postgres first, then SET the new JSON in Redis.
- `DELETE /people/{id}` deletes the row, then removes the key.
- If Redis is down, the API keeps working from Postgres.
- Redis is a cache only (no persistence in `docker-compose.yml`), so a restart starts empty.
- `test/cache.sh` reads the Redis container from `docker compose ps`. Override with `BASE_URL`, `CACHE_TTL`, `PG_CONTAINER`, `REDIS_CONTAINER`.
