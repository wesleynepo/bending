# bending

A Redis client and a small HTTP server, written in [Bend](https://bend-lang.com).

## Redis client (`redis/`)

- `resp.bend` – pure RESP2 encoding of commands and parsing of replies
- `client.bend` – TCP client: `connect`, `command`, `ping`, `set`, `get`, `del`, `incr`
- `LAWS.bend` / `PROOF.bend` – laws about the encoder/parser; check with `bend redis/PROOF.bend`
- `demo.bend` – example program

Limits: ASCII keys/values, replies up to 64KB, no array replies, no AUTH/TLS.

## HTTP server (`server.bend`)

`GET /<key>` looks the key up in Redis and answers JSON:

| Case | Response |
|---|---|
| key exists | `200 {"key":"k","value":"v"}` |
| key missing | `404 {"error":"not found"}` |
| empty path | `400 {"error":"missing key"}` |
| Redis unreachable | `502 {"error":"redis unavailable"}` |

Run it with `bend server.bend`, or build it with `bend server.bend -o server`.
Each connection runs in its own task, and a client that sends nothing for 5s is dropped.

| Variable | Default | Meaning |
|---|---|---|
| `HOST` | `127.0.0.1` | interface to bind |
| `PORT` | `8080` | port to listen on |
| `REDIS_HOST` | `127.0.0.1` | Redis server |
| `REDIS_PORT` | `6379` | Redis port |
| `MAX_REQUESTS` | `1000000` | connections to accept before exiting |

## Load test

```sh
docker run -d --rm --name bend-redis -p 6379:6379 redis:7
docker exec bend-redis redis-cli set greeting hello
MAX_REQUESTS=10000000 bend server.bend      # in another terminal
ulimit -n 8192 && k6 run load/k6.js
```

The script steps from 100 to 550 req/s. On an 11-core Mac it held 550 req/s with
p95 ≈ 3ms and no errors. The rate is capped by the client's ephemeral ports (the
server closes every connection), so it does not show the server's ceiling.
