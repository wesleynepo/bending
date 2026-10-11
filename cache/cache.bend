import Base
import ../json/json.bend as Json
import ../people/types.bend as T
import ../people/domain.bend as D
import ../redis/client.bend as Redis
import ../redis/resp.bend as Resp

# Redis cache for people. Entries live under "person:<id>" and hold the person as JSON.
#
# ASCII-only wire format. The Redis client counts bulk lengths in characters, so the stored
# JSON must be pure ASCII. encode() post-processes the JSON text:
#   - a non-ASCII code point up to 0xFFFF becomes \uXXXX (lowercase hex), valid JSON;
#   - a code point above 0xFFFF becomes \UXXXXXXXX (8 hex digits). This is NOT valid JSON.
#     UTF-16 surrogate pairs were rejected: the Bend runtime refuses to build a Char from a
#     surrogate ("is not a Unicode scalar value"), so Json.parse cannot yield them.
# The JSON encoder's own escaping (\" \\ \n ...) is left as it is, because the escaping is
# applied to the finished JSON text. decode() first rewrites every \UXXXXXXXX into the raw
# character (a backslash pair is copied whole, so an escaped backslash followed by U is not
# mistaken for the escape), then parses with json/json.bend.

def GetOut() -> Type:
  Socket & Result<&1, &1, String, Maybe<&2, T.Person>>

def PutOut() -> Type:
  Socket & Result<&1, &1, String, Unit>

def DelOut() -> Type:
  Socket & Result<&1, &1, String, Unit>

# --- keys -------------------------------------------------------------------

def key(id: String) -> String:
  "person:" ++ id

# --- small helpers ----------------------------------------------------------

def first(+s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{h, t}:
      Char.to_u32(h)

def drop1(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      t

# --- escaping (encode side) -------------------------------------------------

# one lowercase hex digit for a value 0..15
def hex.ch(lt10: Bool, +d: U32) -> Char:
  match lt10:
    case True{}:
      Char.from_u32((d + 48 : U32))
    case False{}:
      Char.from_u32((d + 87 : U32))

def hex(+d: U32) -> Char:
  hex.ch((d < 10 : U32), d)

# four hex digits of a value up to 0xFFFF
def hex4(+c: U32) -> String:
  SCon{hex(U32.div(c, 4096)),
    SCon{hex(U32.mod(U32.div(c, 256), 16)),
      SCon{hex(U32.mod(U32.div(c, 16), 16)),
        SCon{hex(U32.mod(c, 16)), SNil{}}}}}

def esc.wide(bmp: Bool, +c: U32) -> String:
  match bmp:
    case True{}:
      "\\u" ++ hex4(c)
    case False{}:
      "\\U" ++ hex4(U32.div(c, 65536)) ++ hex4(U32.mod(c, 65536))

def esc.one(ascii: Bool, +c: U32, +h: Char, rest: String) -> String:
  match ascii:
    case True{}:
      SCon{h, rest}
    case False{}:
      esc.wide((c < 65536 : U32), c) ++ rest

def esc.all(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      esc.one((Char.to_u32(h) < 128 : U32), Char.to_u32(h), h, esc.all(t))

# --- unescaping (decode side) -----------------------------------------------
#
# mode 0: plain char; mode 1: backslash plus the next char, copied as is;
# mode 2: \U followed by 8 hex digits, replaced by the raw character.

def is_hex(+c: U32) -> Bool:
  ((c >= 48 : U32) && (c <= 57 : U32)) || ((c >= 65 : U32) && (c <= 70 : U32))
    || ((c >= 97 : U32) && (c <= 102 : U32))

def hex_run(fuel: Nat, s: String) -> Bool:
  match fuel:
    case 0n:
      True{}
    case 1n+p:
      match s:
        case SNil{}:
          False{}
        case SCon{h, t}:
          is_hex(Char.to_u32(h)) && hex_run(p, t)

# t holds the text after a backslash: is it U followed by 8 hex digits?
def astral_at(+t: String) -> Bool:
  match t:
    case SNil{}:
      False{}
    case SCon{u, r}:
      Char.is_eq(u, 'U') && hex_run(8n, r)

def hexval.go(dig: Bool, lower: Bool, c: U32) -> U32:
  match dig:
    case True{}:
      (c - 48 : U32)
    case False{}:
      match lower:
        case True{}:
          (c - 87 : U32)
        case False{}:
          (c - 55 : U32)

def hexval(+c: U32) -> U32:
  hexval.go((c <= 57 : U32), (c >= 97 : U32), c)

def hex_val_run(fuel: Nat, acc: U32, s: String) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match s:
        case SNil{}:
          acc
        case SCon{h, t}:
          hex_val_run(p, (acc * 16 + hexval(Char.to_u32(h)) : U32), t)

def is_bs(+h: Char) -> Bool:
  Char.is_eq(h, '\\')

def unesc.mode(bs: Bool, ua: Bool) -> U32:
  match bs:
    case True{}:
      match ua:
        case True{}:
          2
        case False{}:
          1
    case False{}:
      0

# the code emitted for modes 1 and 2 (the char after the backslash, or the astral value)
def unesc.code(+m: U32, +t: String) -> U32:
  match m:
    case 0:
      0
    case 1:
      first(t)
    case _:
      hex_val_run(8n, 0, String.drop(t, 1n))

def unesc.skip(+m: U32, +t: String) -> String:
  match m:
    case 0:
      t
    case 1:
      String.drop(t, 1n)
    case _:
      String.drop(t, 9n)

def unesc.emit(m: U32, h: Char, c: U32, rest: String) -> String:
  match m:
    case 0:
      SCon{h, rest}
    case 1:
      SCon{h, SCon{Char.from_u32(c), rest}}
    case _:
      SCon{Char.from_u32(c), rest}

# fuel is the input length plus one; every step consumes at least one char
def unesc.go(fuel: Nat, s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n+p:
      match s:
        case SNil{}:
          SNil{}
        case SCon{+h, +t}:
          +m = unesc.mode(is_bs(h), astral_at(t))
          unesc.emit(m, h, unesc.code(m, t), unesc.go(p, unesc.skip(m, t)))

def unesc(+s: String) -> String:
  unesc.go((1n + String.length(s) : Nat), s)

# --- codec ------------------------------------------------------------------

# JSON text of a person, ASCII only.
def encode(p: T.Person) -> String:
  esc.all(Json.encode(D.person_json(p)))

def opt_str(m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{+v}:
      Json.as_str(v)

def decode.build(i: Maybe<&2, String>, n: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, T.Person>:
  match i:
    case None{}:
      None{}
    case Some{+iv}:
      match n:
        case None{}:
          None{}
        case Some{+nv}:
          match b:
            case None{}:
              None{}
            case Some{+bv}:
              Some{T.Person{iv, nv, bv}}

def decode.person(+j: Json.Json) -> Maybe<&2, T.Person>:
  decode.build(opt_str(Json.get(j, "id")), opt_str(Json.get(j, "name")),
    opt_str(Json.get(j, "birthdate")))

def decode.from(m: Maybe<&2, Json.Json>) -> Maybe<&2, T.Person>:
  match m:
    case None{}:
      None{}
    case Some{+j}:
      decode.person(j)

# Person from the text produced by encode; None when the text is not JSON or lacks a
# string id, name or birthdate.
def decode(text: String) -> Maybe<&2, T.Person>:
  decode.from(Json.parse(unesc(text)))

# --- GET / SET / DEL --------------------------------------------------------

def get.value(s: Socket, rep: Resp.Reply) -> IO(GetOut):
  match rep:
    case Resp.Bulk{text}:
      IO.pure(GetOut, (s, Done{decode(text)}))
    case Resp.Null{}:
      IO.pure(GetOut, (s, Done{None{}}))
    case Resp.Err{t}:
      IO.pure(GetOut, (s, Fail{t}))
    case _:
      IO.pure(GetOut, (s, Fail{"unexpected GET reply"}))

def get.reply(r: Socket & Result<&1, &1, String, Resp.Reply>) -> IO(GetOut):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(GetOut, (s, Fail{e}))
        case Done{rep}:
          get.value(s, rep)

# GET person:<id>. Done{None} on a miss or an undecodable value.
def get(s: Socket, id: String) -> IO(Socket & Result<&1, &1, String, Maybe<&2, T.Person>>):
  do IO<GetOut>:
    r : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.command(s, ["GET", key(id)])
    get.reply(r)

def put.args(plain: Bool, k: String, v: String, +ttl: U32) -> List<&2, String>:
  match plain:
    case True{}:
      ["SET", k, v]
    case False{}:
      ["SET", k, v, "EX", U32.show(ttl)]

def put.simple(s: Socket, ok: Bool) -> IO(PutOut):
  match ok:
    case True{}:
      IO.pure(PutOut, (s, Done{Unit{}}))
    case False{}:
      IO.pure(PutOut, (s, Fail{"SET did not return OK"}))

def put.value(s: Socket, rep: Resp.Reply) -> IO(PutOut):
  match rep:
    case Resp.Simple{t}:
      put.simple(s, String.eq(t, "OK"))
    case Resp.Err{t}:
      IO.pure(PutOut, (s, Fail{t}))
    case _:
      IO.pure(PutOut, (s, Fail{"unexpected SET reply"}))

def put.reply(r: Socket & Result<&1, &1, String, Resp.Reply>) -> IO(PutOut):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(PutOut, (s, Fail{e}))
        case Done{rep}:
          put.value(s, rep)

# SET <key> <json> EX <ttl>; ttl 0 sends a plain SET (no expiry).
def put.run(s: Socket, k: String, v: String, +ttl: U32) -> IO(PutOut):
  do IO<PutOut>:
    r : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.command(s, put.args(U32.is_eq(ttl, 0), k, v, ttl))
    put.reply(r)

def put(s: Socket, p: T.Person, ttl: U32) -> IO(Socket & Result<&1, &1, String, Unit>):
  match p:
    case T.Person{+id, name, birthdate}:
      put.run(s, key(id), encode(T.Person{id, name, birthdate}), ttl)

def del.value(s: Socket, rep: Resp.Reply) -> IO(DelOut):
  match rep:
    case Resp.Int{t}:
      IO.pure(DelOut, (s, Done{Unit{}}))
    case Resp.Err{t}:
      IO.pure(DelOut, (s, Fail{t}))
    case _:
      IO.pure(DelOut, (s, Fail{"unexpected DEL reply"}))

def del.reply(r: Socket & Result<&1, &1, String, Resp.Reply>) -> IO(DelOut):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(DelOut, (s, Fail{e}))
        case Done{rep}:
          del.value(s, rep)

# DEL person:<id>. Done whether or not the key existed.
def del(s: Socket, id: String) -> IO(Socket & Result<&1, &1, String, Unit>):
  do IO<DelOut>:
    r : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.command(s, ["DEL", key(id)])
    del.reply(r)
