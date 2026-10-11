import Base

# PostgreSQL frontend/backend protocol v3: pure encoding of client messages and
# parsing of server messages. Bytes are List<&2, U32> (each element 0..255).
# Text is UTF-8. Only the simple query protocol is covered.

# --- bytes ------------------------------------------------------------------

def be32(+n: U32) -> List<&2, U32>:
  [((n / 16777216 : U32) % 256 : U32), ((n / 65536 : U32) % 256 : U32),
   ((n / 256 : U32) % 256 : U32), (n % 256 : U32)]

def append(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, xs, ys)

def len32(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

# byte at index i, 0 when absent
def byte_at(xs: List<&2, U32>, i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, i), 0)

def read16(+xs: List<&2, U32>) -> U32:
  (byte_at(xs, 0n) * 256 + byte_at(xs, 1n) : U32)

def read32(+xs: List<&2, U32>) -> U32:
  (byte_at(xs, 0n) * 16777216 + byte_at(xs, 1n) * 65536 + byte_at(xs, 2n) * 256 + byte_at(xs, 3n) : U32)

# --- UTF-8 ------------------------------------------------------------------

def utf8_char.go(one: Bool, two: Bool, three: Bool, +c: U32) -> List<&2, U32>:
  match one:
    case True{}:
      [c]
    case False{}:
      match two:
        case True{}:
          [(192 + c / 64 : U32), (128 + c % 64 : U32)]
        case False{}:
          match three:
            case True{}:
              [(224 + c / 4096 : U32), (128 + (c / 64 : U32) % 64 : U32), (128 + c % 64 : U32)]
            case False{}:
              [(240 + c / 262144 : U32), (128 + (c / 4096 : U32) % 64 : U32),
               (128 + (c / 64 : U32) % 64 : U32), (128 + c % 64 : U32)]

def utf8_char(+c: U32) -> List<&2, U32>:
  utf8_char.go((c < 128 : U32), (c < 2048 : U32), (c < 65536 : U32), c)

def utf8(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      []
    case SCon{h, t}:
      append(utf8_char(Char.to_u32(h)), utf8(t))

# bytes in the sequence that starts with lead byte b
def seq_len.go(one: Bool, two: Bool, three: Bool) -> Nat:
  match one:
    case True{}:
      1n
    case False{}:
      match two:
        case True{}:
          2n
        case False{}:
          match three:
            case True{}:
              3n
            case False{}:
              4n

def seq_len(+b: U32) -> Nat:
  seq_len.go((b < 192 : U32), (b < 224 : U32), (b < 240 : U32))

def code_point.go(n: Nat, +b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  match n:
    case 1n:
      b0
    case 2n:
      ((b0 % 32 : U32) * 64 + b1 % 64 : U32)
    case 3n:
      ((b0 % 16 : U32) * 4096 + (b1 % 64 : U32) * 64 + b2 % 64 : U32)
    case _:
      ((b0 % 8 : U32) * 262144 + (b1 % 64 : U32) * 4096 + (b2 % 64 : U32) * 64 + b3 % 64 : U32)

def code_point(+bs: List<&2, U32>) -> U32:
  +b0 = byte_at(bs, 0n)
  code_point.go(seq_len(b0), b0, byte_at(bs, 1n), byte_at(bs, 2n), byte_at(bs, 3n))

# fuel = number of bytes, which bounds the number of characters
def decode.go(+fuel: Nat, +bs: List<&2, U32>) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n+p:
      match bs:
        case Nil{}:
          SNil{}
        case Con{b, t}:
          SCon{Char.from_u32(code_point(bs)), decode.go(p, List.drop(&2, U32, bs, seq_len(b)))}

def decode(+bs: List<&2, U32>) -> String:
  decode.go(List.length(&2, U32, bs), bs)

# --- client messages --------------------------------------------------------

def zstr(s: String) -> List<&2, U32>:
  append(utf8(s), [0])

# type byte, then Int32 length (counting itself), then the body
def frame(kind: U32, +body: List<&2, U32>) -> List<&2, U32>:
  kind <> append(be32((4 + len32(body) : U32)), body)

# StartupMessage: no type byte, protocol 3.0, user and database parameters
def startup(user: String, db: String) -> List<&2, U32>:
  +body = append(be32(196608), append(zstr("user"), append(zstr(user),
    append(zstr("database"), append(zstr(db), [0])))))
  append(be32((4 + len32(body) : U32)), body)

def query(sql: String) -> List<&2, U32>:
  frame(81, zstr(sql))

def password(pw: String) -> List<&2, U32>:
  frame(112, zstr(pw))

def terminate() -> List<&2, U32>:
  frame(88, [])

# --- server messages --------------------------------------------------------

type Frame is Data:
  Frame{kind: U32, payload: List<&2, U32>}

type Split is Data:
  Split{frames: List<&2, Frame>, rest: List<&2, U32>}

type CStr is Data:
  CStr{text: List<&2, U32>, rest: List<&2, U32>}

type Field is Data:
  Field{tag: U32, text: String}

type Msg is Data:
  MAuth{code: U32, data: List<&2, U32>}
  MParam{name: String, value: String}
  MKey{pid: U32, secret: U32}
  MReady{status: U32}
  MErr{severity: String, code: String, message: String}
  MNotice{message: String}
  MRowDesc{names: List<&2, String>}
  MRow{cols: List<&2, Maybe<&2, String>>}
  MComplete{tag: String}
  MEmpty{}
  MOther{kind: U32}

def enough(n: Nat, bs: List<&2, U32>) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      match bs:
        case Nil{}:
          False{}
        case Con{h, t}:
          enough(p, t)

def has_frame.go(header: Bool, +bs: List<&2, U32>) -> Bool:
  match header:
    case False{}:
      False{}
    case True{}:
      enough(1n+U32.to_nat(read32(List.drop(&2, U32, bs, 1n))), bs)

# is a whole [type][length][payload] frame buffered?
def has_frame(+bs: List<&2, U32>) -> Bool:
  has_frame.go(enough(5n, bs), bs)

def split.cons(f: Frame, r: Split) -> Split:
  match r:
    case Split{fs, rest}:
      Split{f <> fs, rest}

# Splits the buffer into complete frames plus the unconsumed tail.
# fuel = byte count: every frame takes at least 5 bytes.
def split.go(+fuel: Nat, ready: Bool, +bs: List<&2, U32>) -> Split:
  match fuel:
    case 0n:
      Split{[], bs}
    case 1n+p:
      match ready:
        case False{}:
          Split{[], bs}
        case True{}:
          +l = read32(List.drop(&2, U32, bs, 1n))
          +rest = List.drop(&2, U32, bs, 1n+U32.to_nat(l))
          split.cons(
            Frame{byte_at(bs, 0n),
              List.take(&2, U32, List.drop(&2, U32, bs, 5n), U32.to_nat((l - 4 : U32)))},
            split.go(p, has_frame(rest), rest))

def split(+bs: List<&2, U32>) -> Split:
  split.go(List.length(&2, U32, bs), has_frame(bs), bs)

def read_cstr.fin(zero: Bool, b: U32, t: List<&2, U32>, rec: CStr) -> CStr:
  match zero:
    case True{}:
      CStr{[], t}
    case False{}:
      match rec:
        case CStr{x, r}:
          CStr{b <> x, r}

def read_cstr(bs: List<&2, U32>) -> CStr:
  match bs:
    case Nil{}:
      CStr{[], []}
    case Con{+b, +t}:
      read_cstr.fin(U32.is_eq(b, 0), b, t, read_cstr(t))

def cstr_text(c: CStr) -> String:
  match c:
    case CStr{x, r}:
      decode(x)

def cstr_rest(c: CStr) -> List<&2, U32>:
  match c:
    case CStr{x, r}:
      r

def fields(+fuel: Nat, bs: List<&2, U32>) -> List<&2, Field>:
  match fuel:
    case 0n:
      []
    case 1n+p:
      match bs:
        case Nil{}:
          []
        case Con{tag, t}:
          match tag:
            case 0:
              []
            case _:
              +c = read_cstr(t)
              Field{tag, cstr_text(c)} <> fields(p, cstr_rest(c))

def find_pick(hit: Bool, x: String, rest: String) -> String:
  match hit:
    case True{}:
      x
    case False{}:
      rest

def find_field(fs: List<&2, Field>, +tag: U32) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{Field{t, x}, rest}:
      find_pick(U32.is_eq(t, tag), x, find_field(rest, tag))

def col_val(null: Bool, +len: U32, +bs: List<&2, U32>) -> Maybe<&2, String>:
  match null:
    case True{}:
      None{}
    case False{}:
      Some{decode(List.take(&2, U32, List.drop(&2, U32, bs, 4n), U32.to_nat(len)))}

def col_rest(null: Bool, +len: U32, +bs: List<&2, U32>) -> List<&2, U32>:
  match null:
    case True{}:
      List.drop(&2, U32, bs, 4n)
    case False{}:
      List.drop(&2, U32, bs, 4n+U32.to_nat(len))

def cols(n: Nat, +bs: List<&2, U32>) -> List<&2, Maybe<&2, String>>:
  match n:
    case 0n:
      []
    case 1n+p:
      +len = read32(bs)
      +null = U32.is_eq(len, 4294967295)
      col_val(null, len, bs) <> cols(p, col_rest(null, len, bs))

def col_names(n: Nat, bs: List<&2, U32>) -> List<&2, String>:
  match n:
    case 0n:
      []
    case 1n+p:
      +c = read_cstr(bs)
      cstr_text(c) <> col_names(p, List.drop(&2, U32, cstr_rest(c), 18n))

def parse_msg(kind: U32, +p: List<&2, U32>) -> Msg:
  match kind:
    case 82:
      MAuth{read32(p), List.drop(&2, U32, p, 4n)}
    case 83:
      +c = read_cstr(p)
      MParam{cstr_text(c), cstr_text(read_cstr(cstr_rest(c)))}
    case 75:
      MKey{read32(p), read32(List.drop(&2, U32, p, 4n))}
    case 90:
      MReady{byte_at(p, 0n)}
    case 69:
      +fs = fields(List.length(&2, U32, p), p)
      MErr{find_field(fs, 83), find_field(fs, 67), find_field(fs, 77)}
    case 78:
      MNotice{find_field(fields(List.length(&2, U32, p), p), 77)}
    case 84:
      MRowDesc{col_names(U32.to_nat(read16(p)), List.drop(&2, U32, p, 2n))}
    case 68:
      MRow{cols(U32.to_nat(read16(p)), List.drop(&2, U32, p, 2n))}
    case 67:
      MComplete{cstr_text(read_cstr(p))}
    case 73:
      MEmpty{}
    case _:
      MOther{kind}

def to_msgs(fs: List<&2, Frame>) -> List<&2, Msg>:
  match fs:
    case Nil{}:
      []
    case Con{Frame{k, p}, t}:
      parse_msg(k, p) <> to_msgs(t)

def frames_of(sp: Split) -> List<&2, Frame>:
  match sp:
    case Split{fs, rest}:
      fs

def rest_of(sp: Split) -> List<&2, U32>:
  match sp:
    case Split{fs, rest}:
      rest
