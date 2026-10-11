# bending

A Redis client and a small HTTP server, written in [Bend](https://bend-lang.com).

## Redis client (`redis/`)

- `resp.bend` – pure RESP2 encoding of commands and parsing of replies
- `client.bend` – TCP client: `connect`, `command`, `ping`, `set`, `get`, `del`, `incr`
- `LAWS.bend` / `PROOF.bend` – laws about the encoder/parser; check with `bend redis/PROOF.bend`
- `demo.bend` – example program

Limits: ASCII keys/values, replies up to 64KB, no array replies, no AUTH/TLS.

## JSON (`json/`)

Build, encode, parse and query JSON without hand-writing strings:

```python
import ./json/json.bend as Json

Json.encode(Json.object([
  Json.field("name", Json.str("x\"y")),
  Json.field("tags", Json.array([Json.u32(1), Json.bool(True{}), Json.null()]))]))
# {"name":"x\"y","tags":[1,true,null]}

Json.parse("{\"a\": [1, 2]}")      # Some{...}; None{} if malformed
Json.get(obj, "a")                 # Maybe<Json> member lookup
Json.at(arr, 0n)                   # Maybe<Json> element lookup
Json.as_str(j)                     # Maybe<String>
```

Numbers are kept as their source text, `\uXXXX` escapes decode to a single char
(surrogate pairs are not combined), and trailing commas or trailing garbage are
rejected. `json/LAWS.bend` / `json/PROOF.bend` hold the laws (`bend json/PROOF.bend`).

## SQL (`sql/`)

Builds PostgreSQL statements without string concatenation. Every identifier is
quoted and every value rendered by the library.

```python
import ./sql/sql.bend as Sql

Sql.select("users", ["id", "name"], Sql.Eq{"name", Sql.text("it's")},
  [Sql.Desc{"id"}], Some{10})
# SELECT "id", "name" FROM "users" WHERE "name" = 'it''s' ORDER BY "id" DESC LIMIT 10

Sql.insert("users", ["name", "age"], [Sql.text("O'Neil"), Sql.u32(40)])   # Maybe<String>
Sql.update("users", [Sql.Assign{"age", Sql.u32(41)}], Sql.Eq{"id", Sql.u32(1)})
Sql.delete("users", Sql.Gt{"age", Sql.u32(90)})
Sql.bind("SELECT * FROM t WHERE a = $1", [Sql.text("x")])                  # Maybe<String>
```

Values are `Sql.null()`, `Sql.bool(b)`, `Sql.u32(n)` and `Sql.text(s)`. Conditions are
`Always`, `Eq`, `Ne`, `Lt`, `Gt`, `Le`, `Ge`, `IsNull`, `And`, `Or` and `Not` (`Eq`/`Ne`
against `null()` become `IS [NOT] NULL`). `update` and `delete` always emit a `WHERE`;
pass `Always{}` to mean every row. `insert` and `update` return `None` on mismatched or
empty input, and `bind` returns `None` for a placeholder with no parameter.

Limits: assumes `standard_conforming_strings = on` (the default), NUL characters are
dropped, table names are a single identifier (no `schema.table`), and `bind` leaves `$n`
inside `'...'` and `"..."` alone but not inside `$$...$$`, `E'...'` or comments.
`sql/PROOF.bend` holds the laws (`bend sql/PROOF.bend`).

## PostgreSQL client (`pg/`)

- `wire.bend` – pure protocol v3: UTF-8, message encoding, frame splitting, message parsing
- `client.bend` – `connect(host, port, user, db, password)`, `query(conn, sql)`, `close(conn)`, `to_json(table)`
- `demo.bend` – example (`PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`)
- `LAWS.bend` / `PROOF.bend` – laws for the wire layer (`bend pg/PROOF.bend`)

Simple query protocol with text results (`None` is SQL NULL); an SQL error comes back as
`Fail{"42P01: relation ... does not exist"}` and the connection stays usable.
Authentication: **trust and cleartext password only**. MD5 and SCRAM-SHA-256 (the default
on current Postgres) are rejected with a clear error. No TLS, no prepared statements, no COPY.

## People API (`server.bend`)

HTTP JSON CRUD server for people, stored in PostgreSQL and cached in Redis. The code is in
`server.bend` and the modules it imports (`app/router.bend`, `http/`, `people/`, `store/`,
`pg/`, `redis/`, `cache/`, `json/`).

| Method | Path | Response |
|---|---|---|
| `GET` | `/health` | `200 {"status":"ok"}` |
| `GET` | `/people?limit=&offset=` | `200` list (`limit` 1 to 200, default 50) |
| `POST` | `/people` | `201` created person; body `{"name","birthdate"}` (`birthdate` `YYYY-MM-DD`) |
| `GET` | `/people/{id}` | `200` person, `404` unknown id, `400` malformed id |
| `PUT` | `/people/{id}` | `200` updated person, `404` unknown id |
| `DELETE` | `/people/{id}` | `204` deleted, `404` unknown id |

Errors are JSON `{"error": "..."}`. The full contract is in `docs/openapi.yaml`.

Run it:

```sh
docker compose up -d        # Postgres on 5432 and Redis on 6379 (local development, no auth)
bend server.bend            # listens on 127.0.0.1:8080
```

| Variable | Default | Meaning |
|---|---|---|
| `HOST` | `127.0.0.1` | interface to bind |
| `PORT` | `8080` | port to listen on |
| `PGHOST` | `127.0.0.1` | PostgreSQL server |
| `PGPORT` | `5432` | PostgreSQL port |
| `PGUSER` | `postgres` | PostgreSQL user |
| `PGDATABASE` | `postgres` | PostgreSQL database |
| `PGPASSWORD` | `""` | PostgreSQL password |
| `REDIS_HOST` | `127.0.0.1` | Redis server |
| `REDIS_PORT` | `6379` | Redis port |
| `CACHE_TTL` | `3600` | cache entry lifetime in seconds; `0` disables the cache (Redis is never contacted) |
| `MAX_REQUESTS` | `1000000` | connections to accept before exiting |

The startup line prints the cache setting, for example `Listening on 127.0.0.1:8080 cache 127.0.0.1:6379 ttl 3600s`.
Each connection runs in its own task and opens one Postgres connection per request.

### Caching

- Key `person:<id>` holds the person as JSON, with TTL `CACHE_TTL`.
- `GET /people/{id}` is cache-aside: a hit is served from Redis without touching Postgres; a miss reads Postgres and refills the key after the response. An unknown id returns 404 and caches nothing.
- `POST /people` and `PUT /people/{id}` write through: the new value is in Redis before the response. If a PUT's cache write fails, the key is deleted.
- `DELETE /people/{id}` removes the key before the response.
- `GET /people` (list) always reads Postgres.
- Redis problems never change an HTTP result (Postgres is the source of truth); they are logged to stderr.
- Redis is a cache only (no persistence in `docker-compose.yml`), so a restart starts empty.

### Tests

API tests and cache checks live in `test/` (see `test/README.md`). The OpenAPI contract is `docs/openapi.yaml`.

## Load test

```sh
docker compose up -d
MAX_REQUESTS=10000000 bend server.bend      # in another terminal
ulimit -n 8192 && k6 run load/k6.js
```

The script creates one person in `setup()`, then alternates `GET /people/{id}` (200) with a
random uuid (404), and deletes the person in `teardown()`. It steps from 100 to 550 req/s.
The rate is capped by the client's ephemeral ports (the server closes every connection), so
it does not show the server's ceiling.
