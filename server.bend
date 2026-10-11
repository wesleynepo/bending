import Base
import ./app/router.bend as R
import ./http/http.bend as H
import ./json/json.bend as Json
import ./people/domain.bend as D
import ./people/types.bend as T
import ./store/store.bend as Store
import ./pg/client.bend as Pg
import ./redis/client.bend as Redis
import ./cache/cache.bend as Cache

# HTTP JSON CRUD server for the people API, with a Redis cache in front of Postgres.
#
# Configuration (environment variables):
#   HOST          interface to bind          (default 127.0.0.1)
#   PORT          port to listen on          (default 8080)
#   PGHOST        PostgreSQL server          (default 127.0.0.1)
#   PGPORT        PostgreSQL port            (default 5432)
#   PGUSER        PostgreSQL user            (default postgres)
#   PGDATABASE    PostgreSQL database        (default postgres)
#   PGPASSWORD    PostgreSQL password        (default "")
#   REDIS_HOST    Redis server               (default 127.0.0.1)
#   REDIS_PORT    Redis port                 (default 6379)
#   CACHE_TTL     cache entry lifetime in seconds (default 3600); 0 disables the cache
#                 and Redis is never contacted
#   MAX_REQUESTS  connections before exiting (default 1000000)
#
# Each connection runs in its own task and opens one Postgres connection per request.
# Postgres is the source of truth. Redis problems never change an HTTP result; they are
# logged with IO.print_err only.

type Cfg is Data:
  Cfg{pghost: String, pgport: U32, pguser: String, pgdb: String, pgpass: String,
    rhost: String, rport: U32, ttl: U32}

# --- config -----------------------------------------------------------------

def env_pick(r: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match r:
    case Fail{e}:
      d
    case Done{v}:
      v

def env_or(name: String, d: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    IO.pure(String, env_pick(r, d))

def env_u32(name: String, d: U32) -> IO(U32):
  do IO<U32>:
    s : String <- env_or(name, "")
    IO.pure(U32, Maybe.default(&2, U32, U32.read(s), d))

# --- responses --------------------------------------------------------------

def send_json(s: Socket, status: U32, j: Json.Json) -> IO(Unit):
  H.send_response(s, status, Json.encode(j))

def send_err(s: Socket, status: U32, msg: String) -> IO(Unit):
  send_json(s, status, D.error_json(msg))

def send_health(s: Socket) -> IO(Unit):
  send_json(s, 200, Json.object([Json.field("status", Json.str("ok"))]))

def bad_msg(+st: U32) -> String:
  match st:
    case 408:
      "request timeout"
    case 413:
      "payload too large"
    case _:
      "bad request"

def send_bad(s: Socket, +st: U32) -> IO(Unit):
  send_err(s, st, bad_msg(st))

def db_fail(s: Socket, e: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err("database error: " ++ e)
    send_err(s, 500, "internal error")

# --- database connection ----------------------------------------------------

def open_db(db: Cfg) -> IO(Result<&1, &1, String, Pg.Conn>):
  match db:
    case Cfg{h, po, u, n, pw, rh, rp, t}:
      Pg.connect(h, po, u, n, pw)

# --- cache: configuration and connection -----------------------------------

def cache_on(+c: Cfg) -> Bool:
  match c:
    case Cfg{h, po, u, n, pw, rh, rp, t}:
      (0 < t : U32)

def ttl_of(+c: Cfg) -> U32:
  match c:
    case Cfg{h, po, u, n, pw, rh, rp, t}:
      t

def redis_open(+c: Cfg) -> IO(Result<&1, &1, U32 & String, Socket>):
  match c:
    case Cfg{h, po, u, n, pw, rh, rp, t}:
      Redis.connect(rh, rp)

def conn_fail_msg(e: U32 & String) -> String:
  match e:
    case (code, msg):
      "cache connect failed: " ++ msg

def cache_text(off: Bool, rh: String, rp: U32, t: U32) -> String:
  match off:
    case True{}:
      "cache off"
    case False{}:
      "cache " ++ rh ++ ":" ++ U32.show(rp) ++ " ttl " ++ U32.show(t) ++ "s"

def cache_desc(+c: Cfg) -> String:
  match c:
    case Cfg{h, po, u, n, pw, rh, rp, t}:
      cache_text(U32.is_eq(t, 0), rh, rp, t)

# Logs a failed Redis step (when there is one) and always closes the connection.
def log_close(res: Result<&1, &1, String, Unit>, rs: Socket, what: String) -> IO(Unit):
  match res:
    case Fail{e}:
      do IO<Unit>:
        IO.print_err(what ++ e)
        Redis.close(rs)
    case Done{u}:
      Redis.close(rs)

# --- cache: refill after a GET miss (the response is already sent) ----------

def refill_settle(r: Socket & Result<&1, &1, String, Unit>) -> IO(Unit):
  match r:
    case (rs, res):
      log_close(res, rs, "cache refill failed: ")

def refill(rs: Socket, +p: T.Person, +db: Cfg) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, String, Unit> <- Cache.put(rs, p, ttl_of(db))
    refill_settle(r)

# --- cache: delete ----------------------------------------------------------

def del_settle(r: Socket & Result<&1, &1, String, Unit>) -> IO(Unit):
  match r:
    case (rs, res):
      log_close(res, rs, "cache delete failed: ")

def del_conn(rc: Result<&1, &1, U32 & String, Socket>, +id: String) -> IO(Unit):
  match rc:
    case Fail{e}:
      IO.print_err(conn_fail_msg(e))
    case Done{rs}:
      do IO<Unit>:
        r : Socket & Result<&1, &1, String, Unit> <- Cache.del(rs, id)
        del_settle(r)

def del_open(+id: String, +db: Cfg) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, Socket> <- redis_open(db)
    del_conn(rc, id)

def del_gate(on: Bool, +id: String, +db: Cfg) -> IO(Unit):
  match on:
    case True{}:
      del_open(id, db)
    case False{}:
      IO.pure(Unit, Unit{})

def cache_del(+id: String, +db: Cfg) -> IO(Unit):
  del_gate(cache_on(db), id, db)

# --- cache: put (write-through) ---------------------------------------------

def person_id(+p: T.Person) -> String:
  match p:
    case T.Person{+id, name, birthdate}:
      id

# A failed put deletes the key, so a stale value cannot survive the write.
def put_fail(e: String, rs: Socket, id: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err("cache put failed, deleting key: " ++ e)
    r : Socket & Result<&1, &1, String, Unit> <- Cache.del(rs, id)
    del_settle(r)

def put_res(res: Result<&1, &1, String, Unit>, rs: Socket, id: String) -> IO(Unit):
  match res:
    case Fail{e}:
      put_fail(e, rs, id)
    case Done{u}:
      Redis.close(rs)

def put_settle(r: Socket & Result<&1, &1, String, Unit>, id: String) -> IO(Unit):
  match r:
    case (rs, res):
      put_res(res, rs, id)

def put_run(rs: Socket, +p: T.Person, +db: Cfg) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, String, Unit> <- Cache.put(rs, p, ttl_of(db))
    put_settle(r, person_id(p))

def put_conn(rc: Result<&1, &1, U32 & String, Socket>, +p: T.Person, +db: Cfg) -> IO(Unit):
  match rc:
    case Fail{e}:
      IO.print_err(conn_fail_msg(e))
    case Done{rs}:
      put_run(rs, p, db)

def put_open(+p: T.Person, +db: Cfg) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, Socket> <- redis_open(db)
    put_conn(rc, p, db)

def put_gate(on: Bool, +p: T.Person, +db: Cfg) -> IO(Unit):
  match on:
    case True{}:
      put_open(p, db)
    case False{}:
      IO.pure(Unit, Unit{})

def cache_put(+p: T.Person, +db: Cfg) -> IO(Unit):
  put_gate(cache_on(db), p, db)

# --- people: list -----------------------------------------------------------

def list_reply(res: Result<&1, &1, String, List<&2, T.Person>>, s: Socket) -> IO(Unit):
  match res:
    case Fail{e}:
      db_fail(s, e)
    case Done{ps}:
      send_json(s, 200, D.people_json(ps))

def list_done(r: Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>, s: Socket) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        list_reply(res, s)

def list_with(c: Result<&1, &1, String, Pg.Conn>, s: Socket, +l: U32, +o: U32) -> IO(Unit):
  match c:
    case Fail{e}:
      db_fail(s, e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, List<&2, T.Person>> <- Store.list(conn, l, o)
        list_done(r, s)

def list_db(+db: Cfg, s: Socket, +l: U32, +o: U32) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    list_with(c, s, l, o)

def list_offset(off: Maybe<&2, U32>, +db: Cfg, s: Socket, +l: U32) -> IO(Unit):
  match off:
    case None{}:
      send_err(s, 400, "invalid offset")
    case Some{+o}:
      list_db(db, s, l, o)

def list_limit(lim: Maybe<&2, U32>, +db: Cfg, s: Socket, +q: String) -> IO(Unit):
  match lim:
    case None{}:
      send_err(s, 400, "invalid limit")
    case Some{+l}:
      list_offset(D.parse_limit(H.query_param(q, "offset"), 0, (4294967295 : U32)), db, s, l)

def list_req(+db: Cfg, s: Socket, +q: String) -> IO(Unit):
  list_limit(D.parse_limit(H.query_param(q, "limit"), 50, 200), db, s, q)

# --- people: create ---------------------------------------------------------

def create_reply(res: Result<&1, &1, String, T.Person>, +db: Cfg, s: Socket) -> IO(Unit):
  match res:
    case Fail{e}:
      db_fail(s, e)
    case Done{+p}:
      do IO<Unit>:
        cache_put(p, db)
        send_json(s, 201, D.person_json(p))

def create_done(r: Pg.Conn & Result<&1, &1, String, T.Person>, +db: Cfg, s: Socket) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        create_reply(res, db, s)

def create_with(c: Result<&1, &1, String, Pg.Conn>, np: T.NewPerson, +db: Cfg, s: Socket) -> IO(Unit):
  match c:
    case Fail{e}:
      db_fail(s, e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, T.Person> <- Store.create(conn, np)
        create_done(r, db, s)

def create_db(np: T.NewPerson, +db: Cfg, s: Socket) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    create_with(c, np, db, s)

def create_parsed(p: Result<&1, &1, String, T.NewPerson>, +db: Cfg, s: Socket) -> IO(Unit):
  match p:
    case Fail{e}:
      send_err(s, 400, e)
    case Done{np}:
      create_db(np, db, s)

def create_req(+db: Cfg, s: Socket, +b: String) -> IO(Unit):
  create_parsed(D.parse_new(b), db, s)

# --- people: get and update (Maybe result) ----------------------------------

def found_json(m: Maybe<&2, T.Person>, s: Socket) -> IO(Unit):
  match m:
    case None{}:
      send_err(s, 404, "not found")
    case Some{p}:
      send_json(s, 200, D.person_json(p))

def maybe_reply(res: Result<&1, &1, String, Maybe<&2, T.Person>>, s: Socket) -> IO(Unit):
  match res:
    case Fail{e}:
      db_fail(s, e)
    case Done{m}:
      found_json(m, s)

def maybe_done(r: Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, s: Socket) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        maybe_reply(res, s)

# --- people: get (cache-aside) ----------------------------------------------

def get_with(c: Result<&1, &1, String, Pg.Conn>, s: Socket, +id: String) -> IO(Unit):
  match c:
    case Fail{e}:
      db_fail(s, e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>> <- Store.get(conn, id)
        maybe_done(r, s)

# Postgres only: used when the cache is off or Redis cannot be reached.
def get_pg(+db: Cfg, s: Socket, +id: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    get_with(c, s, id)

def hit_done(+p: T.Person, rs: Socket, s: Socket) -> IO(Unit):
  do IO<Unit>:
    send_json(s, 200, D.person_json(p))
    Redis.close(rs)

def miss_fail(e: String, rs: Socket, s: Socket) -> IO(Unit):
  do IO<Unit>:
    db_fail(s, e)
    Redis.close(rs)

# Found in Postgres: respond first, then refill the cache best-effort. Not found: nothing is cached.
def miss_found(m: Maybe<&2, T.Person>, rs: Socket, +db: Cfg, s: Socket) -> IO(Unit):
  match m:
    case None{}:
      do IO<Unit>:
        send_err(s, 404, "not found")
        Redis.close(rs)
    case Some{+p}:
      do IO<Unit>:
        send_json(s, 200, D.person_json(p))
        refill(rs, p, db)

def miss_reply(res: Result<&1, &1, String, Maybe<&2, T.Person>>, rs: Socket, +db: Cfg, s: Socket) -> IO(Unit):
  match res:
    case Fail{e}:
      miss_fail(e, rs, s)
    case Done{m}:
      miss_found(m, rs, db, s)

def miss_done(r: Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, rs: Socket, +db: Cfg, s: Socket) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        miss_reply(res, rs, db, s)

def miss_with(c: Result<&1, &1, String, Pg.Conn>, rs: Socket, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match c:
    case Fail{e}:
      miss_fail(e, rs, s)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>> <- Store.get(conn, id)
        miss_done(r, rs, db, s)

def get_miss(rs: Socket, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    miss_with(c, rs, db, s, id)

def got_maybe(m: Maybe<&2, T.Person>, rs: Socket, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match m:
    case None{}:
      get_miss(rs, db, s, id)
    case Some{+p}:
      hit_done(p, rs, s)

def got_res(res: Result<&1, &1, String, Maybe<&2, T.Person>>, rs: Socket, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match res:
    case Fail{e}:
      do IO<Unit>:
        IO.print_err("cache get failed: " ++ e)
        get_miss(rs, db, s, id)
    case Done{m}:
      got_maybe(m, rs, db, s, id)

def got_lookup(r: Socket & Result<&1, &1, String, Maybe<&2, T.Person>>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match r:
    case (rs, res):
      got_res(res, rs, db, s, id)

def get_conn(rc: Result<&1, &1, U32 & String, Socket>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match rc:
    case Fail{e}:
      do IO<Unit>:
        IO.print_err(conn_fail_msg(e))
        get_pg(db, s, id)
    case Done{rs}:
      do IO<Unit>:
        r : Socket & Result<&1, &1, String, Maybe<&2, T.Person>> <- Cache.get(rs, id)
        got_lookup(r, db, s, id)

def get_redis(+db: Cfg, s: Socket, +id: String) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, Socket> <- redis_open(db)
    get_conn(rc, db, s, id)

def get_by_mode(on: Bool, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match on:
    case True{}:
      get_redis(db, s, id)
    case False{}:
      get_pg(db, s, id)

def get_checked(valid: Bool, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match valid:
    case True{}:
      get_by_mode(cache_on(db), db, s, id)
    case False{}:
      send_err(s, 400, "invalid id")

# --- people: update ---------------------------------------------------------

# Write-through: the cache is updated before the response is sent.
def upd_found(m: Maybe<&2, T.Person>, +db: Cfg, s: Socket) -> IO(Unit):
  match m:
    case None{}:
      send_err(s, 404, "not found")
    case Some{+p}:
      do IO<Unit>:
        cache_put(p, db)
        send_json(s, 200, D.person_json(p))

def upd_reply(res: Result<&1, &1, String, Maybe<&2, T.Person>>, +db: Cfg, s: Socket) -> IO(Unit):
  match res:
    case Fail{e}:
      db_fail(s, e)
    case Done{m}:
      upd_found(m, db, s)

def upd_done(r: Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, +db: Cfg, s: Socket) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        upd_reply(res, db, s)

def update_with(c: Result<&1, &1, String, Pg.Conn>, +id: String, np: T.NewPerson, +db: Cfg, s: Socket) -> IO(Unit):
  match c:
    case Fail{e}:
      db_fail(s, e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>> <- Store.update(conn, id, np)
        upd_done(r, db, s)

def update_db(+id: String, np: T.NewPerson, +db: Cfg, s: Socket) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    update_with(c, id, np, db, s)

def update_parsed(p: Result<&1, &1, String, T.NewPerson>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match p:
    case Fail{e}:
      send_err(s, 400, e)
    case Done{np}:
      update_db(id, np, db, s)

def update_checked(valid: Bool, +db: Cfg, s: Socket, +id: String, +b: String) -> IO(Unit):
  match valid:
    case True{}:
      update_parsed(D.parse_new(b), db, s, id)
    case False{}:
      send_err(s, 400, "invalid id")

# --- people: delete ---------------------------------------------------------

def deleted(b: Bool, s: Socket) -> IO(Unit):
  match b:
    case True{}:
      H.send_response(s, 204, "")
    case False{}:
      send_err(s, 404, "not found")

# The key is removed before the response, whether or not the row existed.
def delete_reply(res: Result<&1, &1, String, Bool>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match res:
    case Fail{e}:
      db_fail(s, e)
    case Done{b}:
      do IO<Unit>:
        cache_del(id, db)
        deleted(b, s)

def delete_done(r: Pg.Conn & Result<&1, &1, String, Bool>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        delete_reply(res, db, s, id)

def delete_with(c: Result<&1, &1, String, Pg.Conn>, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match c:
    case Fail{e}:
      db_fail(s, e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, Bool> <- Store.delete(conn, id)
        delete_done(r, db, s, id)

def delete_db(+db: Cfg, s: Socket, +id: String) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    delete_with(c, db, s, id)

def delete_checked(valid: Bool, +db: Cfg, s: Socket, +id: String) -> IO(Unit):
  match valid:
    case True{}:
      delete_db(db, s, id)
    case False{}:
      send_err(s, 400, "invalid id")

# --- routing ----------------------------------------------------------------

def route_it(route: R.Route, +db: Cfg, s: Socket, +q: String, +b: String) -> IO(Unit):
  match route:
    case R.RHealth{}:
      send_health(s)
    case R.RList{}:
      list_req(db, s, q)
    case R.RCreate{}:
      create_req(db, s, b)
    case R.RGet{+id}:
      get_checked(D.valid_uuid(id), db, s, id)
    case R.RUpdate{+id}:
      update_checked(D.valid_uuid(id), db, s, id, b)
    case R.RDelete{+id}:
      delete_checked(D.valid_uuid(id), db, s, id)
    case R.RNotFound{}:
      send_err(s, 404, "not found")
    case R.RBadMethod{}:
      send_err(s, 405, "method not allowed")

def on_ok(ok: Bool, +db: Cfg, s: Socket, +m: String, +p: String, +q: String, +b: String, +st: U32) -> IO(Unit):
  match ok:
    case True{}:
      route_it(R.route(m, H.segments(p)), db, s, q, b)
    case False{}:
      send_bad(s, st)

def on_req(+db: Cfg, r: Socket & H.Request) -> IO(Unit):
  match r:
    case (s, req):
      match req:
        case H.Request{+m, +p, +q, +b, ok, st}:
          on_ok(ok, db, s, m, p, q, b, st)

# --- accept loop ------------------------------------------------------------

def reply(+db: Cfg, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & H.Request <- H.read_request(sock)
    on_req(db, r)

def on_accept(+db: Cfg, r: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Listener):
  match r:
    case (l, res):
      match res:
        case Fail{e}:
          IO.pure(Listener, l)
        case Done{sock}:
          do IO<Listener>:
            IO.spawn(Unit, reply(db, sock))   # one task per connection
            IO.pure(Listener, l)

# Serves `fuel` connections, then shuts down (Bend loops need a decreasing argument).
def serve(fuel: Nat, +db: Cfg, l: Listener) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
        l2 : Listener <- on_accept(db, r)
        serve(p, db, l2)

# --- startup: migrate, then serve -------------------------------------------

def migrate_result(res: Result<&1, &1, String, Unit>) -> IO(Unit):
  match res:
    case Fail{e}:
      IO.die(Unit, 1, "migration failed: " ++ e)
    case Done{u}:
      IO.pure(Unit, Unit{})

def migrated(r: Pg.Conn & Result<&1, &1, String, Unit>) -> IO(Unit):
  match r:
    case (conn, res):
      do IO<Unit>:
        Pg.close(conn)
        migrate_result(res)

def migrate_with(c: Result<&1, &1, String, Pg.Conn>) -> IO(Unit):
  match c:
    case Fail{e}:
      IO.die(Unit, 1, "database connection failed: " ++ e)
    case Done{conn}:
      do IO<Unit>:
        r : Pg.Conn & Result<&1, &1, String, Unit> <- Store.migrate(conn)
        migrated(r)

def startup(+db: Cfg) -> IO(Unit):
  do IO<Unit>:
    c : Result<&1, &1, String, Pg.Conn> <- open_db(db)
    migrate_with(c)

def main() -> IO(Unit):
  do IO<Unit>:
    +host : String <- env_or("HOST", "127.0.0.1")
    +port : U32 <- env_u32("PORT", 8080)
    +pghost : String <- env_or("PGHOST", "127.0.0.1")
    +pgport : U32 <- env_u32("PGPORT", 5432)
    +pguser : String <- env_or("PGUSER", "postgres")
    +pgdb : String <- env_or("PGDATABASE", "postgres")
    +pgpass : String <- env_or("PGPASSWORD", "")
    +rhost : String <- env_or("REDIS_HOST", "127.0.0.1")
    +rport : U32 <- env_u32("REDIS_PORT", 6379)
    ttl : U32 <- env_u32("CACHE_TTL", 3600)
    max : U32 <- env_u32("MAX_REQUESTS", 1000000)
    +db : Cfg <- IO.pure(Cfg, Cfg{pghost, pgport, pguser, pgdb, pgpass, rhost, rport, ttl})
    startup(db)
    l : Listener <- IO.try(Listener, TCP.listen(host, port))
    IO.print("Listening on " ++ host ++ ":" ++ U32.show(port) ++ " " ++ cache_desc(db))
    serve(U32.to_nat(max), db, l)
