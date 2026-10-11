import Base
import ./wire.bend as W
import ../json/json.bend as Json

# Minimal PostgreSQL client over TCP (simple query protocol, text results).
#
# Authentication: trust and cleartext password. MD5 and SCRAM-SHA-256 are not
# implemented yet and are reported as an error. One query at a time per
# connection; results are fully buffered.

# state: 0 = reading, 1 = ready for query, 2 = failed (err says why)
type Conn is Type:
  Conn{sock: Socket, buf: List<&2, U32>, state: U32, err: String, acc: List<&2, W.Msg>}

# One query result. Values are text (None is SQL NULL).
type Table is Data:
  Table{columns: List<&2, String>, rows: List<&2, List<&2, Maybe<&2, String>>>, tag: String, error: String}

type Outcome is Data:
  OReady{}
  ONeedPw{}
  OAgain{}
  OFail{message: String}

def Out() -> Type:
  Conn & Result<&1, &1, String, Table>

# --- receiving --------------------------------------------------------------

def absorb(s: Socket, st: U32, err: String, acc: List<&2, W.Msg>, sp: W.Split) -> Conn:
  match sp:
    case W.Split{fs, rest}:
      Conn{s, rest, st, err, List.append(&2, W.Msg, acc, W.to_msgs(fs))}

def got_bytes(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>,
  buf: List<&2, U32>, st: U32, err: String, acc: List<&2, W.Msg>) -> IO(Conn):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(Conn, Conn{s, buf, 2, "receive failed", acc})
        case Done{m}:
          match m:
            case None{}:
              IO.pure(Conn, Conn{s, buf, 2, "connection closed by server", acc})
            case Some{bytes}:
              IO.pure(Conn, absorb(s, st, err, acc, W.split(W.append(buf, bytes))))

# Reads once from the socket and parses every complete message into `acc`.
def recv_into(c: Conn) -> IO(Conn):
  match c:
    case Conn{sock, buf, st, err, acc}:
      do IO<Conn>:
        r : Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>> <- TCP.recv_bytes(sock, 65536)
        got_bytes(r, buf, st, err, acc)

# --- handshake --------------------------------------------------------------

def outcome_of(m: W.Msg) -> Outcome:
  match m:
    case W.MErr{sev, code, message}:
      OFail{code ++ ": " ++ message}
    case W.MAuth{code, data}:
      match code:
        case 0:
          OAgain{}
        case 3:
          ONeedPw{}
        case 10:
          OFail{"server requires SCRAM-SHA-256, which this client does not support yet"}
        case 5:
          OFail{"server requires MD5 password authentication, which this client does not support"}
        case _:
          OFail{"unsupported authentication method"}
    case W.MReady{status}:
      OReady{}
    case _:
      OAgain{}

def scan.pick(first: Outcome, rest: Outcome) -> Outcome:
  match first:
    case OAgain{}:
      rest
    case _:
      first

# The first decisive message in the batch.
def scan(ms: List<&2, W.Msg>) -> Outcome:
  match ms:
    case Nil{}:
      OAgain{}
    case Con{m, t}:
      scan.pick(outcome_of(m), scan(t))

def sent_pw(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>,
  buf: List<&2, U32>) -> IO(Conn):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(Conn, Conn{s, buf, 2, "send failed", []})
        case Done{u}:
          IO.pure(Conn, Conn{s, buf, 0, "", []})

def hs_act(o: Outcome, s: Socket, buf: List<&2, U32>, pw: String) -> IO(Conn):
  match o:
    case OReady{}:
      IO.pure(Conn, Conn{s, buf, 1, "", []})
    case OAgain{}:
      IO.pure(Conn, Conn{s, buf, 0, "", []})
    case OFail{m}:
      IO.pure(Conn, Conn{s, buf, 2, m, []})
    case ONeedPw{}:
      do IO<Conn>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, W.password(pw))
        sent_pw(r, buf)

def hs_after(c: Conn, pw: String) -> IO(Conn):
  match c:
    case Conn{s, buf, st, err, acc}:
      match st:
        case 0:
          hs_act(scan(acc), s, buf, pw)
        case _:
          IO.pure(Conn, Conn{s, buf, st, err, acc})

def hs_step(c: Conn, pw: String) -> IO(Conn):
  do IO<Conn>:
    c2 : Conn <- recv_into(c)
    hs_after(c2, pw)

def hs_loop(fuel: Nat, c: Conn, +pw: String) -> IO(Conn):
  match fuel:
    case 0n:
      match c:
        case Conn{s, buf, st, err, acc}:
          IO.pure(Conn, Conn{s, buf, 2, "handshake did not finish", acc})
    case 1n+p:
      match c:
        case Conn{s, buf, st, err, acc}:
          match st:
            case 0:
              do IO<Conn>:
                c2 : Conn <- hs_step(Conn{s, buf, 0, err, acc}, pw)
                hs_loop(p, c2, pw)
            case _:
              IO.pure(Conn, Conn{s, buf, st, err, acc})

def hs_finish(c: Conn) -> IO(Result<&1, &1, String, Conn>):
  match c:
    case Conn{s, buf, st, err, acc}:
      match st:
        case 1:
          IO.pure(Result<&1, &1, String, Conn>, Done{Conn{s, buf, 1, "", []}})
        case _:
          do IO<Result<&1, &1, String, Conn>>:
            Socket.close(s)
            IO.pure(Result<&1, &1, String, Conn>, Fail{err})

def sent_startup(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>,
  pw: String) -> IO(Result<&1, &1, String, Conn>):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          do IO<Result<&1, &1, String, Conn>>:
            Socket.close(s)
            IO.pure(Result<&1, &1, String, Conn>, Fail{"send failed"})
        case Done{u}:
          do IO<Result<&1, &1, String, Conn>>:
            c : Conn <- hs_loop(1000n, Conn{s, [], 0, "", []}, pw)
            hs_finish(c)

def connect_sock(r: Result<&1, &1, U32 & String, Socket>, user: String, db: String,
  pw: String) -> IO(Result<&1, &1, String, Conn>):
  match r:
    case Fail{e}:
      IO.pure(Result<&1, &1, String, Conn>, Fail{"connect failed"})
    case Done{s}:
      do IO<Result<&1, &1, String, Conn>>:
        r2 : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, W.startup(user, db))
        sent_startup(r2, pw)

# connect("127.0.0.1", 5432, "postgres", "postgres", "secret")
def connect(host: String, port: U32, user: String, db: String, pw: String) ->
  IO(Result<&1, &1, String, Conn>):
  do IO<Result<&1, &1, String, Conn>>:
    r : Result<&1, &1, U32 & String, Socket> <- TCP.connect(host, port)
    connect_sock(r, user, db, pw)

# --- queries ----------------------------------------------------------------

def has_ready(ms: List<&2, W.Msg>) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case Con{m, t}:
      match m:
        case W.MReady{status}:
          True{}
        case _:
          has_ready(t)

def mark.go(ready: Bool, s: Socket, buf: List<&2, U32>, err: String, acc: List<&2, W.Msg>) -> Conn:
  match ready:
    case True{}:
      Conn{s, buf, 1, err, acc}
    case False{}:
      Conn{s, buf, 0, err, acc}

def mark(c: Conn) -> Conn:
  match c:
    case Conn{s, buf, st, err, +acc}:
      match st:
        case 0:
          mark.go(has_ready(acc), s, buf, err, acc)
        case _:
          Conn{s, buf, st, err, acc}

def q_loop(fuel: Nat, c: Conn) -> IO(Conn):
  match fuel:
    case 0n:
      match c:
        case Conn{s, buf, st, err, acc}:
          IO.pure(Conn, Conn{s, buf, 2, "query did not finish", acc})
    case 1n+p:
      match c:
        case Conn{s, buf, st, err, acc}:
          match st:
            case 0:
              do IO<Conn>:
                c2 : Conn <- recv_into(Conn{s, buf, 0, err, acc})
                q_loop(p, mark(c2))
            case _:
              IO.pure(Conn, Conn{s, buf, st, err, acc})

def add(t: Table, m: W.Msg) -> Table:
  match t:
    case Table{cols, rows, tag, error}:
      match m:
        case W.MRowDesc{names}:
          Table{names, rows, tag, error}
        case W.MRow{vals}:
          Table{cols, vals <> rows, tag, error}
        case W.MComplete{tg}:
          Table{cols, rows, tg, error}
        case W.MErr{sev, code, message}:
          Table{cols, rows, tag, code ++ ": " ++ message}
        case _:
          Table{cols, rows, tag, error}

def build(ms: List<&2, W.Msg>) -> Table:
  match ms:
    case Nil{}:
      Table{[], [], "", ""}
    case Con{m, t}:
      add(build(t), m)

def table_result.go(ok: Bool, t: Table, error: String) -> Result<&1, &1, String, Table>:
  match ok:
    case True{}:
      Done{t}
    case False{}:
      Fail{error}

def table_result(t: Table) -> Result<&1, &1, String, Table>:
  match t:
    case Table{cols, rows, tag, +error}:
      table_result.go(String.is_empty(error), Table{cols, rows, tag, error}, error)

def q_finish(c: Conn) -> IO(Out):
  match c:
    case Conn{s, buf, st, +err, acc}:
      match st:
        case 1:
          IO.pure(Out, (Conn{s, buf, 0, "", []}, table_result(build(acc))))
        case _:
          IO.pure(Out, (Conn{s, buf, 2, err, []}, Fail{err}))

def q_sent(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>,
  buf: List<&2, U32>) -> IO(Conn):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(Conn, Conn{s, buf, 2, "send failed", []})
        case Done{u}:
          IO.pure(Conn, Conn{s, buf, 0, "", []})

# query(conn, "SELECT 1") -> (conn, Done{table}) or (conn, Fail{message})
def query(c: Conn, sql: String) -> IO(Out):
  match c:
    case Conn{s, buf, st, err, acc}:
      do IO<Out>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, W.query(sql))
        c1 : Conn <- q_sent(r, buf)
        c2 : Conn <- q_loop(100000n, c1)
        q_finish(c2)

def close_sent(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  match r:
    case (s, _):
      Socket.close(s)

def close(c: Conn) -> IO(Unit):
  match c:
    case Conn{s, buf, st, err, acc}:
      do IO<Unit>:
        r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(s, W.terminate())
        close_sent(r)

# --- JSON -------------------------------------------------------------------

def cell(m: Maybe<&2, String>) -> Json.Json:
  match m:
    case None{}:
      Json.null()
    case Some{v}:
      Json.str(v)

def row_fields(cols: List<&2, String>, vals: List<&2, Maybe<&2, String>>) -> List<&2, Json.Field>:
  match cols vals:
    case Con{c, ct} Con{v, vt}:
      Json.field(c, cell(v)) <> row_fields(ct, vt)
    case _ _:
      []

def rows_json(+cols: List<&2, String>, rows: List<&2, List<&2, Maybe<&2, String>>>) -> List<&2, Json.Json>:
  match rows:
    case Nil{}:
      []
    case Con{r, t}:
      Json.object(row_fields(cols, r)) <> rows_json(cols, t)

# A table as a JSON array of {column: value} objects (all values are strings or null).
def to_json(t: Table) -> Json.Json:
  match t:
    case Table{cols, rows, tag, error}:
      Json.array(rows_json(cols, rows))
