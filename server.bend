import Base
import ./redis/client.bend as Redis
import ./redis/resp.bend as Resp

# HTTP -> Redis bridge: GET /<key> looks <key> up in Redis and answers JSON.
#
# Configuration (environment variables):
#   HOST          interface to bind          (default 127.0.0.1)
#   PORT          port to listen on          (default 8080)
#   REDIS_HOST    Redis server               (default 127.0.0.1)
#   REDIS_PORT    Redis port                 (default 6379)
#   MAX_REQUESTS  connections before exiting (default 1000000)
#
# Each connection runs in its own task; a client that sends nothing for 5s is dropped.

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

def http(status: String, +body: String) -> String:
  "HTTP/1.1 " ++ status ++ "\r\nContent-Type: application/json\r\nContent-Length: "
    ++ Nat.show(String.length(body)) ++ "\r\nConnection: close\r\n\r\n" ++ body

def esc.go(q: Bool, bs: Bool, h: Char, rest: String) -> String:
  match q:
    case True{}:
      "\\\"" ++ rest
    case False{}:
      match bs:
        case True{}:
          "\\\\" ++ rest
        case False{}:
          SCon{h, rest}

def esc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      esc.go(Char.is_eq(h, '"'), Char.is_eq(h, '\\'), h, esc(t))

def render(+key: String, r: Result<&1, &1, String, Resp.Reply>) -> String:
  match r:
    case Fail{e}:
      http("502 Bad Gateway", "{\"error\":\"redis unavailable\"}")
    case Done{reply}:
      match reply:
        case Resp.Bulk{v}:
          http("200 OK", "{\"key\":\"" ++ esc(key) ++ "\",\"value\":\"" ++ esc(v) ++ "\"}")
        case Resp.Null{}:
          http("404 Not Found", "{\"error\":\"not found\"}")
        case _:
          http("502 Bad Gateway", "{\"error\":\"unexpected redis reply\"}")

# --- request handling -------------------------------------------------------

def key_from(lr: String & String) -> String:
  match lr:
    case (line, _):
      parts = String.split(line, ' ')
      String.drop(Maybe.default(&2, String, List.get(&2, String, parts, 1n), ""), 1n)

# "GET /foo HTTP/1.1\r\n..." -> "foo"
def key_of(text: String) -> String:
  key_from(Resp.take_line(text))

def close_sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(Unit):
  match r:
    case (s, _):
      Socket.close(s)

def send_close(sock: Socket, text: String) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, text)
    close_sent(r)

def fetch.done(r: Socket & Result<&1, &1, String, Resp.Reply>) ->
  IO(Result<&1, &1, String, Resp.Reply>):
  match r:
    case (s, res):
      do IO<Result<&1, &1, String, Resp.Reply>>:
        Redis.close(s)
        IO.pure(Result<&1, &1, String, Resp.Reply>, res)

def fetch.conn(c: Result<&1, &1, U32 & String, Socket>, key: String) ->
  IO(Result<&1, &1, String, Resp.Reply>):
  match c:
    case Fail{e}:
      IO.pure(Result<&1, &1, String, Resp.Reply>, Fail{"redis connect failed"})
    case Done{s}:
      do IO<Result<&1, &1, String, Resp.Reply>>:
        r : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.get(s, key)
        fetch.done(r)

# One short-lived Redis connection per request.
def fetch(rh: String, rp: U32, key: String) -> IO(Result<&1, &1, String, Resp.Reply>):
  do IO<Result<&1, &1, String, Resp.Reply>>:
    c : Result<&1, &1, U32 & String, Socket> <- Redis.connect(rh, rp)
    fetch.conn(c, key)

def route(rh: String, rp: U32, s: Socket, +key: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      send_close(s, http("400 Bad Request", "{\"error\":\"missing key\"}"))
    case False{}:
      do IO<Unit>:
        res : Result<&1, &1, String, Resp.Reply> <- fetch(rh, rp, key)
        send_close(s, render(key, res))

def handle(rh: String, rp: U32, s: Socket, +key: String) -> IO(Unit):
  route(rh, rp, s, key, String.is_empty(key))

def on_recv(rh: String, rp: U32, s: Socket,
  res: Result<&1, &1, U32 & String, Maybe<&1, String>>) -> IO(Unit):
  match res:
    case Fail{e}:
      Socket.close(s)
    case Done{m}:
      match m:
        case None{}:
          Socket.close(s)
        case Some{text}:
          handle(rh, rp, s, key_of(text))

def on_request(rh: String, rp: U32,
  r: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit>) -> IO(Unit):
  match r:
    case (s, poll):
      match poll:
        case Wait{u}:
          Socket.close(s)   # idle client: drop it after the timeout
        case Ready{res}:
          on_recv(rh, rp, s, res)

def reply(rh: String, rp: U32, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit> <- TCP.try_recv(sock, 4096, 5000)
    on_request(rh, rp, r)

# --- accept loop ------------------------------------------------------------

def on_accept(rh: String, rp: U32, r: Listener & Result<&1, &1, U32 & String, Socket>) ->
  IO(Listener):
  match r:
    case (l, res):
      match res:
        case Fail{e}:
          IO.pure(Listener, l)
        case Done{sock}:
          do IO<Listener>:
            IO.spawn(Unit, reply(rh, rp, sock))   # one task per connection
            IO.pure(Listener, l)

# Serves `fuel` connections, then shuts down (Bend loops need a decreasing argument).
def serve(fuel: Nat, +rh: String, +rp: U32, l: Listener) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
        l2 : Listener <- on_accept(rh, rp, r)
        serve(p, rh, rp, l2)

def main() -> IO(Unit):
  do IO<Unit>:
    +host : String <- env_or("HOST", "127.0.0.1")
    +port : U32 <- env_u32("PORT", 8080)
    +rh : String <- env_or("REDIS_HOST", "127.0.0.1")
    +rp : U32 <- env_u32("REDIS_PORT", 6379)
    max : U32 <- env_u32("MAX_REQUESTS", 1000000)
    l : Listener <- IO.try(Listener, TCP.listen(host, port))
    IO.print("Listening on " ++ host ++ ":" ++ U32.show(port) ++ ", Redis at " ++ rh ++ ":" ++ U32.show(rp))
    serve(U32.to_nat(max), rh, rp, l)
