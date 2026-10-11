#!/usr/bin/env bash
# Cache checks for the People API (Redis write-through / cache-aside).
# Assumes the server, Postgres and Redis are already running (see test/README.md).
# Creates its own people and deletes them at the end. Restarts Redis on exit.
#
# Env overrides: BASE_URL (default http://127.0.0.1:8080), CACHE_TTL (default 3600, must be > 0),
#   PG_CONTAINER, REDIS_CONTAINER (default: from docker compose ps), PG_DATABASE (default postgres).
set -u

cd "$(dirname "$0")/.." || exit 1 # docker-compose.yml lives at the repo root

BASE_URL=${BASE_URL:-http://127.0.0.1:8080}
CACHE_TTL=${CACHE_TTL:-3600}
PG_DATABASE=${PG_DATABASE:-postgres}
PG_CONTAINER=${PG_CONTAINER:-$(docker compose ps -q postgres 2>/dev/null)}
REDIS_CONTAINER=${REDIS_CONTAINER:-$(docker compose ps -q redis 2>/dev/null)}

PASS=0
FAIL=0
CREATED=()
WORK=$(mktemp -d) || exit 1
HTTP_CODE=000

pass() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s%s\n' "$1" "${2:+ -- $2}"; }
abort() { printf 'FAIL: %s\n' "$1"; exit 1; }

# check NAME COMMAND...: passes when COMMAND exits 0.
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

# check_eq NAME ACTUAL EXPECTED
check_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got [$2] expected [$3]"; fi
}

cleanup() {
  if [ -n "$REDIS_CONTAINER" ]; then docker start "$REDIS_CONTAINER" >/dev/null 2>&1 || true; fi
  for id in ${CREATED[@]+"${CREATED[@]}"}; do
    curl -s --max-time 10 -o /dev/null -X DELETE "$BASE_URL/people/$id" || true
    if [ -n "$REDIS_CONTAINER" ]; then
      docker exec "$REDIS_CONTAINER" redis-cli DEL "person:$id" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

redis_cmd() { docker exec "$REDIS_CONTAINER" redis-cli "$@"; }
pg_cmd() { docker exec "$PG_CONTAINER" psql -U postgres -d "$PG_DATABASE" -v ON_ERROR_STOP=1 -t -A -c "$1"; }

# api METHOD PATH OUTFILE [JSON_BODY]: sets HTTP_CODE, writes the response body to OUTFILE.
api() {
  local method=$1 path=$2 out=$3
  local -a args=(-sS --max-time 15 -o "$out" -w '%{http_code}' -X "$method" -H 'Content-Type: application/json')
  if [ $# -ge 4 ]; then args+=(--data-binary "$4"); fi
  HTTP_CODE=$(curl "${args[@]}" "$BASE_URL$path") || HTTP_CODE=000
}

# jfield FILE FIELD: prints a top-level string field of a JSON file (UTF-8).
jfield() {
  python3 -I -c 'import json,sys
with open(sys.argv[1], encoding="utf-8") as f: print(json.load(f)[sys.argv[2]])' "$1" "$2"
}

# json_equal FILE_A FILE_B: exit 0 when both files hold the same JSON value.
json_equal() {
  python3 -I -c 'import json,sys
def load(p):
    with open(p, "rb") as f: return json.loads(f.read().decode("utf-8"))
sys.exit(0 if load(sys.argv[1]) == load(sys.argv[2]) else 1)' "$1" "$2"
}

# name_is FILE NAME_FILE: exit 0 when the JSON "name" equals the exact text in NAME_FILE.
name_is() {
  python3 -I -c 'import json,sys
with open(sys.argv[2], encoding="utf-8") as f: want = f.read()
with open(sys.argv[1], encoding="utf-8") as f: got = json.load(f)["name"]
sys.exit(0 if got == want else 1)' "$1" "$2"
}

# page_has_id FILE ID: prints found, more (full page, keep paging) or end.
page_has_id() {
  python3 -I -c 'import json,sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
print("found" if any(x.get("id") == sys.argv[2] for x in p) else ("more" if len(p) == 200 else "end"))' "$1" "$2"
}

# redis_name_is FILE NAME_FILE: like name_is, but the stored value is ASCII-only JSON in which
# code points above U+FFFF are written as \UXXXXXXXX (not standard JSON), so they are rewritten
# to the real character before parsing.
redis_name_is() {
  python3 -I -c 'import json,re,sys
with open(sys.argv[1], encoding="utf-8") as f: raw = f.read()
raw = re.sub(r"\\U([0-9a-fA-F]{8})", lambda m: chr(int(m.group(1), 16)), raw)
with open(sys.argv[3], encoding="utf-8") as f: want = f.read()
sys.exit(0 if json.loads(raw)["name"] == want else 1)' "$1" "$2" "$2"
}

exists_key() { [ "$(redis_cmd EXISTS "person:$1")" = 1 ]; }
ttl_ok() { [ "$1" -gt 0 ] 2>/dev/null && [ "$1" -le "$CACHE_TTL" ]; }
redis_get() { redis_cmd GET "person:$1" >"$2"; }

case $CACHE_TTL in
  '' | *[!0-9]* | 0) echo "CACHE_TTL must be a positive integer (0 disables caching; these checks need it on)"; exit 2 ;;
esac
[ -n "$PG_CONTAINER" ] || { echo "Postgres container not found; run docker compose up -d or set PG_CONTAINER"; exit 2; }
[ -n "$REDIS_CONTAINER" ] || { echo "Redis container not found; run docker compose up -d or set REDIS_CONTAINER"; exit 2; }

# Preflight: every dependency must answer before any check runs.
api GET /health "$WORK/health.json"
[ "$HTTP_CODE" = 200 ] || abort "server not reachable at $BASE_URL (HTTP $HTTP_CODE)"
[ "$(redis_cmd PING 2>/dev/null)" = PONG ] || abort "Redis not answering in $REDIS_CONTAINER"
[ "$(pg_cmd 'SELECT 1' 2>/dev/null)" = 1 ] || abort "Postgres not answering in $PG_CONTAINER"

RUN="$$-$RANDOM"
NAME="cache-check-$RUN"
printf 'João Ñandú 😀' >"$WORK/uni_name.txt"

echo "== (a) write-through on POST"
api POST /people "$WORK/post_a.json" "$(printf '{"name":"%s","birthdate":"1990-06-15"}' "$NAME")"
check_eq "(a) POST returns 201" "$HTTP_CODE" 201
ID=$(jfield "$WORK/post_a.json" id 2>/dev/null) || ID=""
[ -n "$ID" ] || abort "POST did not return an id; stopping"
CREATED+=("$ID")
check "(a) key person:<id> exists immediately after POST" exists_key "$ID"
redis_get "$ID" "$WORK/redis_a.json"
check "(a) Redis JSON equals POST response" json_equal "$WORK/redis_a.json" "$WORK/post_a.json"
TTL=$(redis_cmd TTL "person:$ID")
check "(a) TTL > 0 and <= CACHE_TTL ($CACHE_TTL), got $TTL" ttl_ok "$TTL"

echo "== (b) cache hit ignores direct DB change"
pg_cmd "UPDATE people SET name = 'db-changed-$RUN' WHERE id = '$ID'" >/dev/null
check_eq "(b) row changed directly in Postgres" "$(pg_cmd "SELECT name FROM people WHERE id = '$ID'")" "db-changed-$RUN"
api GET "/people/$ID" "$WORK/get_b.json"
check_eq "(b) GET returns 200" "$HTTP_CODE" 200
check_eq "(b) GET returns the cached (old) name" "$(jfield "$WORK/get_b.json" name 2>/dev/null)" "$NAME"

echo "== (c) PUT updates cache immediately"
NAME_C="put-$RUN"
api PUT "/people/$ID" "$WORK/put_c.json" "$(printf '{"name":"%s","birthdate":"1991-01-01"}' "$NAME_C")"
check_eq "(c) PUT returns 200" "$HTTP_CODE" 200
redis_get "$ID" "$WORK/redis_c.json"
check_eq "(c) Redis name updated immediately" "$(jfield "$WORK/redis_c.json" name 2>/dev/null)" "$NAME_C"
check "(c) Redis JSON equals PUT response" json_equal "$WORK/redis_c.json" "$WORK/put_c.json"
api GET "/people/$ID" "$WORK/get_c.json"
check_eq "(c) GET returns the new name" "$(jfield "$WORK/get_c.json" name 2>/dev/null)" "$NAME_C"

echo "== (d) miss path refills the cache"
pg_cmd "UPDATE people SET name = 'db-direct-$RUN' WHERE id = '$ID'" >/dev/null
check_eq "(d) DEL removed the key" "$(redis_cmd DEL "person:$ID")" 1
api GET "/people/$ID" "$WORK/get_d.json"
check_eq "(d) GET after miss returns the DB value" "$(jfield "$WORK/get_d.json" name 2>/dev/null)" "db-direct-$RUN"
check "(d) key re-created after miss" exists_key "$ID"
TTL=$(redis_cmd TTL "person:$ID")
check "(d) re-created key has TTL > 0 and <= CACHE_TTL, got $TTL" ttl_ok "$TTL"
redis_get "$ID" "$WORK/redis_d.json"
check "(d) re-created Redis JSON equals GET response" json_equal "$WORK/redis_d.json" "$WORK/get_d.json"

echo "== (g) non-ASCII name"
api POST /people "$WORK/post_g.json" '{"name":"João Ñandú 😀","birthdate":"1990-06-15"}'
check_eq "(g) POST returns 201" "$HTTP_CODE" 201
UID_G=$(jfield "$WORK/post_g.json" id 2>/dev/null) || UID_G=""
[ -n "$UID_G" ] || abort "unicode POST did not return an id; stopping"
CREATED+=("$UID_G")
check "(g) POST name is exact" name_is "$WORK/post_g.json" "$WORK/uni_name.txt"
api GET "/people/$UID_G" "$WORK/get_g.json"
check_eq "(g) GET returns 200" "$HTTP_CODE" 200
check "(g) GET name survives byte for byte" name_is "$WORK/get_g.json" "$WORK/uni_name.txt"
redis_get "$UID_G" "$WORK/redis_g.json"
check "(g) Redis value decodes to the same name" redis_name_is "$WORK/redis_g.json" "$WORK/uni_name.txt"

echo "== (h) list still returns the person"
list_state=missing
offset=0
while [ "$offset" -lt 100000 ]; do
  api GET "/people?limit=200&offset=$offset" "$WORK/page.json"
  [ "$HTTP_CODE" = 200 ] || break
  list_state=$(page_has_id "$WORK/page.json" "$UID_G" 2>/dev/null) || list_state=error
  case $list_state in
    more) offset=$((offset + 200)) ;;
    *) break ;;
  esac
done
check_eq "(h) GET /people contains the created person" "$list_state" found

echo "== (e) DELETE removes the cache entry"
api DELETE "/people/$ID" "$WORK/delete_e.out"
check_eq "(e) DELETE returns 204" "$HTTP_CODE" 204
check "(e) DELETE has empty body" test ! -s "$WORK/delete_e.out"
check "(e) key removed from Redis" test "$(redis_cmd EXISTS "person:$ID")" = 0
api GET "/people/$ID" "$WORK/get_e.json"
check_eq "(e) GET after DELETE returns 404" "$HTTP_CODE" 404
check "(e) GET after DELETE does not re-create the key" test "$(redis_cmd EXISTS "person:$ID")" = 0

echo "== (f) unknown uuid"
UNKNOWN=$(python3 -I -c 'import uuid; print(uuid.uuid4())')
api GET "/people/$UNKNOWN" "$WORK/get_f.json"
check_eq "(f) GET unknown uuid returns 404" "$HTTP_CODE" 404
check "(f) no key created for unknown uuid" test "$(redis_cmd EXISTS "person:$UNKNOWN")" = 0

echo "== (i) Redis outage"
docker stop "$REDIS_CONTAINER" >/dev/null 2>&1
check "(i) Redis container stopped" test -z "$(docker ps -q --no-trunc --filter "id=$REDIS_CONTAINER")"
api GET "/people/$UID_G" "$WORK/get_i1.json"
check_eq "(i) GET with Redis down returns 200" "$HTTP_CODE" 200
check "(i) GET with Redis down serves the DB name" name_is "$WORK/get_i1.json" "$WORK/uni_name.txt"
NAME_I="down-$RUN"
api PUT "/people/$UID_G" "$WORK/put_i.json" "$(printf '{"name":"%s","birthdate":"1990-06-15"}' "$NAME_I")"
check_eq "(i) PUT with Redis down returns 200" "$HTTP_CODE" 200
api GET "/people/$UID_G" "$WORK/get_i2.json"
check_eq "(i) GET after PUT with Redis down returns the new name" "$(jfield "$WORK/get_i2.json" name 2>/dev/null)" "$NAME_I"

docker start "$REDIS_CONTAINER" >/dev/null 2>&1
ready=0
for _ in $(seq 1 30); do
  if [ "$(redis_cmd PING 2>/dev/null)" = PONG ]; then ready=1; break; fi
  sleep 1
done
check "(i) Redis answers again after docker start" test "$ready" = 1
redis_cmd DEL "person:$UID_G" >/dev/null 2>&1
api GET "/people/$UID_G" "$WORK/get_i3.json"
check_eq "(i) GET after Redis restart returns 200" "$HTTP_CODE" 200
check_eq "(i) GET after Redis restart returns the current name" "$(jfield "$WORK/get_i3.json" name 2>/dev/null)" "$NAME_I"
check "(i) later GET re-fills the cache" exists_key "$UID_G"
TTL=$(redis_cmd TTL "person:$UID_G")
check "(i) re-filled key has TTL > 0 and <= CACHE_TTL, got $TTL" ttl_ok "$TTL"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
