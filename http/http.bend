import Base
import ../pg/wire.bend as W

# HTTP/1.1 server-side helpers: read one request from a TCP socket, parse it,
# and write one response with `Connection: close`. Bytes are List<&2, U32>.
# Header names are matched case-insensitively. Loops are fuel-based.

type Request is Data:
  Request{method: String, path: String, query: String, body: String, ok: Bool, status: U32}

# state: 0 = reading, 1 = complete, 2 = failed (status is the answer to send)
type Reader is Type:
  Reader{sock: Socket, buf: List<&2, U32>, st: U32, status: U32}

# Content-Length: absent, malformed, too large (over 1 MiB), or a number
type Clen is Data:
  NoCl{}
  BadCl{}
  TooBig{}
  Cl{n: U32}

# request line: method and target (the version is checked, then dropped)
type RL is Data:
  RL{method: String, target: String}

def Reply() -> Type:
  Socket & Request

def Got() -> Type:
  Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>

# --- head and body framing (bytes) ------------------------------------------

def is_crlf2(+bs: List<&2, U32>) -> Bool:
  U32.is_eq(W.byte_at(bs, 0n), 13) && U32.is_eq(W.byte_at(bs, 1n), 10)
    && U32.is_eq(W.byte_at(bs, 2n), 13) && U32.is_eq(W.byte_at(bs, 3n), 10)

def hdr_scan.pick(hit: Bool, +i: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      rest

# index of the first "\r\n\r\n", i.e. where the body starts minus 4
def hdr_scan(+bs: List<&2, U32>, +i: Nat) -> Maybe<&2, Nat>:
  match bs:
    case Nil{}:
      None{}
    case Con{h, t}:
      hdr_scan.pick(is_crlf2(bs), i, hdr_scan(t, Nat.add(i, 1n)))

def hdr_end(bs: List<&2, U32>) -> Maybe<&2, Nat>:
  hdr_scan(bs, 0n)

# --- header fields (text) ---------------------------------------------------

def first_of(xs: List<&2, String>) -> String:
  match xs:
    case Con{h, t}:
      h
    case Nil{}:
      ""

# everything after the first piece, rejoined with sep
def join_rest(xs: List<&2, String>, sep: String) -> String:
  match xs:
    case Con{h, t}:
      String.join(t, sep)
    case Nil{}:
      ""

def name_of(line: String) -> String:
  String.to_lower(String.trim(first_of(String.split(line, ':'))))

def value_of(line: String) -> String:
  String.trim(join_rest(String.split(line, ':'), ":"))

def cl_pick(hit: Bool, v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

# raw value of the first Content-Length header, if any
def cl_raw(hs: List<&2, String>) -> Maybe<&2, String>:
  match hs:
    case Nil{}:
      None{}
    case Con{+h, t}:
      cl_pick(String.eq(name_of(h), "content-length"), value_of(h), cl_raw(t))

def clen_big(big: Bool, +n: U32) -> Clen:
  match big:
    case True{}:
      TooBig{}
    case False{}:
      Cl{n}

def clen_read(r: Maybe<&2, U32>) -> Clen:
  match r:
    case None{}:
      BadCl{}
    case Some{+n}:
      clen_big(U32.is_gt(n, 1048576), n)

def clen_len(long: Bool, +s: String) -> Clen:
  match long:
    case True{}:
      TooBig{}
    case False{}:
      clen_read(U32.read(s))

def clen_of(m: Maybe<&2, String>) -> Clen:
  match m:
    case None{}:
      NoCl{}
    case Some{+s}:
      clen_len(Nat.is_gt(String.length(s), 9n), s)

def hdrs_of(lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Con{h, t}:
      t
    case Nil{}:
      []

# --- request line -----------------------------------------------------------

def rl_pick(ok: Bool, m: String, tg: String) -> Maybe<&2, RL>:
  match ok:
    case True{}:
      Some{RL{m, tg}}
    case False{}:
      None{}

# "METHOD target HTTP/x.y" -> RL
def rl_of(parts: List<&2, String>) -> Maybe<&2, RL>:
  match parts:
    case Nil{}:
      None{}
    case Con{m, r}:
      match r:
        case Nil{}:
          None{}
        case Con{tg, v}:
          match v:
            case Nil{}:
              None{}
            case Con{ver, rest}:
              rl_pick(List.is_empty(&2, String, rest) && String.starts_with(ver, "HTTP/"), m, tg)

# --- request assembly -------------------------------------------------------

def bad() -> Request:
  Request{"", "", "", "", False{}, 400}

def too_big() -> Request:
  Request{"", "", "", "", False{}, 413}

def mk(m: String, +tg: String, body: String) -> Request:
  Request{m, first_of(String.split(tg, '?')), join_rest(String.split(tg, '?'), "?"), body, True{}, 200}

def head_cl(m: String, +tg: String, cl: Clen, body: List<&2, U32>) -> Request:
  match cl:
    case NoCl{}:
      mk(m, tg, "")
    case Cl{+n}:
      mk(m, tg, W.decode(List.take(&2, U32, body, U32.to_nat(n))))
    case BadCl{}:
      bad()
    case TooBig{}:
      too_big()

def head_go(r: RL, cl: Clen, body: List<&2, U32>) -> Request:
  match r:
    case RL{m, +tg}:
      head_cl(m, tg, cl, body)

def head_rl(rl: Maybe<&2, RL>, hs: List<&2, String>, body: List<&2, U32>) -> Request:
  match rl:
    case None{}:
      bad()
    case Some{+r}:
      head_go(r, clen_of(cl_raw(hs)), body)

def head_req(lines: List<&2, String>, body: List<&2, U32>) -> Request:
  match lines:
    case Nil{}:
      bad()
    case Con{h, t}:
      head_rl(rl_of(String.split(String.trim(h), ' ')), t, body)

def parse_head(head: String, body: List<&2, U32>) -> Request:
  head_req(String.split(head, '\n'), body)

def parse_at(m: Maybe<&2, Nat>, +bs: List<&2, U32>) -> Request:
  match m:
    case None{}:
      bad()
    case Some{+i}:
      parse_head(W.decode(List.take(&2, U32, bs, i)), List.drop(&2, U32, bs, Nat.add(i, 4n)))

# pure: parse a COMPLETE raw request (head + body)
def parse_request(+bs: List<&2, U32>) -> Request:
  parse_at(hdr_end(bs), bs)

# --- completeness -----------------------------------------------------------

def complete_need(c: Clen, have: Nat) -> Bool:
  match c:
    case NoCl{}:
      True{}
    case BadCl{}:
      True{}
    case TooBig{}:
      True{}
    case Cl{+n}:
      Nat.is_ge(have, U32.to_nat(n))

def complete_at(m: Maybe<&2, Nat>, +bs: List<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+i}:
      complete_need(
        clen_of(cl_raw(hdrs_of(String.split(W.decode(List.take(&2, U32, bs, i)), '\n')))),
        Nat.sub(List.length(&2, U32, bs), Nat.add(i, 4n)))

# pure: True when the headers ended and at least Content-Length body bytes arrived
def complete(+bs: List<&2, U32>) -> Bool:
  complete_at(hdr_end(bs), bs)

# --- reading from the socket ------------------------------------------------

def rd_done(done: Bool, s: Socket, nb: List<&2, U32>) -> Reader:
  match done:
    case True{}:
      Reader{s, nb, 1, 0}
    case False{}:
      Reader{s, nb, 0, 0}

def rd_next(over: Bool, done: Bool, s: Socket, nb: List<&2, U32>) -> Reader:
  match over:
    case True{}:
      Reader{s, nb, 2, 413}
    case False{}:
      rd_done(done, s, nb)

def rd_absorb(s: Socket, buf: List<&2, U32>, bytes: List<&2, U32>) -> Reader:
  +nb = W.append(buf, bytes)
  rd_next(Nat.is_gt(List.length(&2, U32, nb), 1048576n), complete(nb), s, nb)

def rd_step(p: Got, buf: List<&2, U32>) -> IO(Reader):
  match p:
    case (s, poll):
      match poll:
        case Wait{u}:
          IO.pure(Reader, Reader{s, buf, 2, 408})
        case Ready{res}:
          match res:
            case Fail{e}:
              IO.pure(Reader, Reader{s, buf, 2, 400})
            case Done{m}:
              match m:
                case None{}:
                  IO.pure(Reader, Reader{s, buf, 2, 400})
                case Some{bytes}:
                  IO.pure(Reader, rd_absorb(s, buf, bytes))

# reads chunks until complete; fuel = max bytes + 1 (each chunk adds at least one byte)
def rd_loop(fuel: Nat, r: Reader) -> IO(Reader):
  match fuel:
    case 0n:
      match r:
        case Reader{s, buf, st, status}:
          IO.pure(Reader, Reader{s, buf, 2, 413})
    case 1n+p:
      match r:
        case Reader{s, buf, st, status}:
          match st:
            case 0:
              do IO<Reader>:
                g : Got <- TCP.try_recv_bytes(s, 65536, 5000)
                r2 : Reader <- rd_step(g, buf)
                rd_loop(p, r2)
            case _:
              IO.pure(Reader, Reader{s, buf, st, status})

def finish(r: Reader) -> IO(Reply):
  match r:
    case Reader{s, buf, st, status}:
      match st:
        case 1:
          IO.pure(Reply, (s, parse_request(buf)))
        case _:
          IO.pure(Reply, (s, Request{"", "", "", "", False{}, status}))

# Reads one request. Failures answer ok=False with the status to send
# (413 too large, 408 silent for 5 s, 400 closed early or malformed).
def read_request(sock: Socket) -> IO(Reply):
  do IO<Reply>:
    r : Reader <- rd_loop(1048577n, Reader{sock, [], 0, 0})
    finish(r)

# --- writing ----------------------------------------------------------------

def reason(+status: U32) -> String:
  match status:
    case 200:
      "OK"
    case 201:
      "Created"
    case 204:
      "No Content"
    case 400:
      "Bad Request"
    case 404:
      "Not Found"
    case 405:
      "Method Not Allowed"
    case 408:
      "Request Timeout"
    case 413:
      "Payload Too Large"
    case 422:
      "Unprocessable Entity"
    case 500:
      "Internal Server Error"
    case 502:
      "Bad Gateway"
    case _:
      "Status"

def head_text(+status: U32, length: U32) -> String:
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ reason(status)
    ++ "\r\nContent-Type: application/json\r\nContent-Length: " ++ U32.show(length)
    ++ "\r\nConnection: close\r\n\r\n"

def response.full(+status: U32, +body: String) -> List<&2, U32>:
  W.append(W.utf8(head_text(status, W.len32(W.utf8(body)))), W.utf8(body))

def response.pick(is204: Bool, +status: U32, +body: String) -> List<&2, U32>:
  match is204:
    case True{}:
      W.utf8("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    case False{}:
      response.full(status, body)

# full HTTP/1.1 response bytes; 204 has no Content-Type and no body
def response(+status: U32, +body: String) -> List<&2, U32>:
  response.pick(U32.is_eq(status, 204), status, body)

def close_sent(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> IO(Unit):
  match r:
    case (s, _):
      Socket.close(s)

def send_response(sock: Socket, status: U32, body: String) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send_bytes(sock, response(status, body))
    close_sent(r)

# --- routing helpers --------------------------------------------------------

def keep.one(empty: Bool, +h: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      h <> rest

def keep(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      keep.one(String.is_empty(h), h, keep(t))

# "/people/abc" -> ["people", "abc"]; "/" -> []
def segments(path: String) -> List<&2, String>:
  keep(String.split(path, '/'))

def pair_key(p: String) -> String:
  first_of(String.split(p, '='))

def pair_val(p: String) -> String:
  join_rest(String.split(p, '='), "=")

def qp_pick(hit: Bool, v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def qp_hit(k: String, +key: String, +p: String) -> Bool:
  String.eq(k, key) && Nat.is_gt(String.length(p), 0n)

def qp_find(ps: List<&2, String>, +key: String) -> Maybe<&2, String>:
  match ps:
    case Nil{}:
      None{}
    case Con{+p, t}:
      qp_pick(qp_hit(pair_key(p), key, p), pair_val(p), qp_find(t, key))

# query_param("limit=5&offset=2", "limit") -> Some{"5"}
def query_param(query: String, +key: String) -> Maybe<&2, String>:
  qp_find(String.split(query, '&'), key)
