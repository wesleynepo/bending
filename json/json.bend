import Base

# JSON values, builders, encoder, parser and accessors.
#
# Array elements and object members are chained inside the same type
# (End / Item / Member) so the encoder and getters are plain structural
# recursion. Build values with Json.array / Json.object, not with the chain
# constructors directly.
#
# Numbers are kept as their source text. \uXXXX escapes decode to one Char
# (surrogate pairs are not combined).

type Json is Data:
  Null{}
  Boolean{value: Bool}
  Num{text: String}
  Str{text: String}
  Arr{items: Json}                          # items is an End/Item chain
  Obj{members: Json}                        # members is an End/Member chain
  End{}
  Item{head: Json, tail: Json}
  Member{key: String, val: Json, tail: Json}

# --- builders ---------------------------------------------------------------

def null() -> Json:
  Null{}

def bool(b: Bool) -> Json:
  Boolean{b}

def str(s: String) -> Json:
  Str{s}

def u32(n: U32) -> Json:
  Num{U32.show(n)}

def array.chain(xs: List<&2, Json>) -> Json:
  match xs:
    case Nil{}:
      End{}
    case Con{h, t}:
      Item{h, array.chain(t)}

def array(xs: List<&2, Json>) -> Json:
  Arr{array.chain(xs)}

type Field is Data:
  Field{key: String, val: Json}

def field(key: String, val: Json) -> Field:
  Field{key, val}

def object.chain(xs: List<&2, Field>) -> Json:
  match xs:
    case Nil{}:
      End{}
    case Con{Field{k, v}, t}:
      Member{k, v, object.chain(t)}

# Json.object([Json.field("name", Json.str("x")), Json.field("n", Json.u32(1))])
def object(xs: List<&2, Field>) -> Json:
  Obj{object.chain(xs)}

# --- encoder ----------------------------------------------------------------

def esc.go(code: U32, h: Char, rest: String) -> String:
  match code:
    case 34:
      "\\\"" ++ rest
    case 92:
      "\\\\" ++ rest
    case 10:
      "\\n" ++ rest
    case 13:
      "\\r" ++ rest
    case 9:
      "\\t" ++ rest
    case _:
      SCon{h, rest}

def esc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      esc.go(Char.to_u32(h), h, esc(t))

def quote(s: String) -> String:
  "\"" ++ esc(s) ++ "\""

def is_end(j: Json) -> Bool:
  match j:
    case End{}:
      True{}
    case _:
      False{}

def comma(end: Bool) -> String:
  match end:
    case True{}:
      ""
    case False{}:
      ","

def encode(j: Json) -> String:
  match j:
    case Null{}:
      "null"
    case Boolean{b}:
      match b:
        case True{}:
          "true"
        case False{}:
          "false"
    case Num{t}:
      t
    case Str{s}:
      quote(s)
    case Arr{items}:
      "[" ++ encode(items) ++ "]"
    case Obj{members}:
      "{" ++ encode(members) ++ "}"
    case End{}:
      ""
    case Item{h, +t}:
      encode(h) ++ comma(is_end(t)) ++ encode(t)
    case Member{k, v, +t}:
      quote(k) ++ ":" ++ encode(v) ++ comma(is_end(t)) ++ encode(t)

# --- accessors --------------------------------------------------------------

def get.pick(hit: Bool, v: Json, rest: Maybe<&2, Json>) -> Maybe<&2, Json>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

# Json.get(obj, "key") -> Some value if obj is an object with that key
def get(j: Json, +key: String) -> Maybe<&2, Json>:
  match j:
    case Obj{members}:
      get(members, key)
    case Member{k, v, t}:
      get.pick(String.eq(k, key), v, get(t, key))
    case _:
      None{}

# Json.at(arr, 0) -> Some element
def at(j: Json, n: Nat) -> Maybe<&2, Json>:
  match j:
    case Arr{items}:
      at(items, n)
    case Item{h, t}:
      match n:
        case 0n:
          Some{h}
        case 1n+p:
          at(t, p)
    case _:
      None{}

def as_str(j: Json) -> Maybe<&2, String>:
  match j:
    case Str{s}:
      Some{s}
    case _:
      None{}

# --- parser -----------------------------------------------------------------
#
# Recursive descent in one recursive def (`parse.go`): Bend forbids mutual
# recursion, so `mode` selects value (0), array items (1), object members (2),
# or "fail" (9), and `code` is the first char of the (whitespace-skipped) input,
# because a match can't scrutinize a computed value. `fuel` bounds the depth;
# every level consumes at least one char, so length+1 is always enough.

type Parsed is Data:
  PJ{json: Json, rest: String}
  PNo{}

type PStr is Data:
  PS{text: String, rest: String}
  PSNo{}

def code_of(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{h, t}:
      Char.to_u32(h)

def drop1(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      t

def skip_ws.go(sp: Bool, h: Char, +t: String, rec: String) -> String:
  match sp:
    case True{}:
      rec
    case False{}:
      SCon{h, t}

def skip_ws(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      skip_ws.go(Char.is_space(h), h, t, skip_ws(t))

def rest_of(r: Parsed) -> String:
  match r:
    case PJ{j, rest}:
      rest
    case PNo{}:
      ""

def pstr_rest(r: PStr) -> String:
  match r:
    case PS{t, rest}:
      rest
    case PSNo{}:
      ""

def hex_val.go(d: Bool, u: Bool, l: Bool, c: U32) -> U32:
  match d:
    case True{}:
      (c - 48 : U32)
    case False{}:
      match u:
        case True{}:
          (c - 55 : U32)
        case False{}:
          match l:
            case True{}:
              (c - 87 : U32)
            case False{}:
              16

# the four hex digits after \u as a code point, or 16 * 65536 when invalid

# hex digit value, or 16 when not a hex digit
def hex_val(+c: U32) -> U32:
  hex_val.go((c >= 48 : U32) && (c <= 57 : U32), (c >= 65 : U32) && (c <= 70 : U32),
    (c >= 97 : U32) && (c <= 102 : U32), c)

def hex4.go(ok: Bool, v: U32) -> U32:
  match ok:
    case True{}:
      v
    case False{}:
      1048576

# is the char after the backslash a valid escape?

def hex4(+s: String) -> U32:
  +s1 = drop1(s)
  +s2 = drop1(s1)
  +s3 = drop1(s2)
  +a = hex_val(code_of(s))
  +b = hex_val(code_of(s1))
  +c = hex_val(code_of(s2))
  +d = hex_val(code_of(s3))
  hex4.go((a < 16 : U32) && (b < 16 : U32) && (c < 16 : U32) && (d < 16 : U32),
    (a * 4096 + b * 256 + c * 16 + d : U32))

def esc_ok(e: U32, rest: String) -> Bool:
  match e:
    case 0:
      False{}
    case 117:
      (hex4(rest) < 65536 : U32)
    case _:
      True{}

def esc_char(e: U32, rest: String) -> Char:
  match e:
    case 110:
      Char.from_u32(10)
    case 116:
      Char.from_u32(9)
    case 114:
      Char.from_u32(13)
    case 98:
      Char.from_u32(8)
    case 102:
      Char.from_u32(12)
    case 117:
      Char.from_u32(hex4(rest))
    case _:
      Char.from_u32(e)

# input after the escape letter: \u consumes four more chars
def esc_rest(e: U32, rest: String) -> String:
  match e:
    case 117:
      String.drop(rest, 4n)
    case _:
      rest

def str_cons(c: Char, r: PStr) -> PStr:
  match r:
    case PS{t, rest}:
      PS{SCon{c, t}, rest}
    case PSNo{}:
      PSNo{}

def str_esc(ok: Bool, e: U32, rest: String, r: PStr) -> PStr:
  match ok:
    case True{}:
      str_cons(esc_char(e, rest), r)
    case False{}:
      PSNo{}

# Body of a string literal (after the opening quote), up to the closing quote.
def str_body(fuel: Nat, code: U32, s: String) -> PStr:
  match fuel:
    case 0n:
      PSNo{}
    case 1n+p:
      match code:
        case 0:
          PSNo{}
        case 34:
          PS{"", drop1(s)}
        case 92:
          +t = drop1(s)
          +e = code_of(t)
          +rest = drop1(t)
          +after = esc_rest(e, rest)
          str_esc(esc_ok(e, rest), e, rest, str_body(p, code_of(after), after))
        case _:
          match s:
            case SNil{}:
              PSNo{}
            case SCon{h, t}:
              +t2 = t
              str_cons(h, str_body(p, code_of(t2), t2))

def str_val(r: PStr) -> Parsed:
  match r:
    case PS{t, rest}:
      PJ{Str{t}, rest}
    case PSNo{}:
      PNo{}

def lit.go(ok: Bool, +s: String, +w: String, v: Json) -> Parsed:
  match ok:
    case True{}:
      PJ{v, String.drop(s, String.length(w))}
    case False{}:
      PNo{}

def lit(+s: String, +w: String, v: Json) -> Parsed:
  lit.go(String.starts_with(s, w), s, w, v)

def is_num_char(+h: Char) -> Bool:
  Char.is_digit(h) || Char.is_eq(h, '-') || Char.is_eq(h, '+') || Char.is_eq(h, '.')
    || Char.is_eq(h, 'e') || Char.is_eq(h, 'E')

def num_span.step(more: Bool, h: Char, +t: String, r: PStr) -> PStr:
  match more:
    case True{}:
      str_cons(h, r)
    case False{}:
      PS{SNil{}, SCon{h, t}}

def num_span(s: String) -> PStr:
  match s:
    case SNil{}:
      PS{"", ""}
    case SCon{+h, +t}:
      num_span.step(is_num_char(h), h, t, num_span(t))

def num_val(ok: Bool, r: PStr) -> Parsed:
  match ok:
    case True{}:
      match r:
        case PS{t, rest}:
          PJ{Num{t}, rest}
        case PSNo{}:
          PNo{}
    case False{}:
      PNo{}

def is_num_start(+c: U32) -> Bool:
  ((c >= 48 : U32) && (c <= 57 : U32)) || U32.is_eq(c, 45)

def wrap_arr(r: Parsed) -> Parsed:
  match r:
    case PJ{j, rest}:
      PJ{Arr{j}, rest}
    case PNo{}:
      PNo{}

def wrap_obj(r: Parsed) -> Parsed:
  match r:
    case PJ{j, rest}:
      PJ{Obj{j}, rest}
    case PNo{}:
      PNo{}

def tail_mode.pick(closing: Bool, open: U32) -> U32:
  match closing:
    case True{}:
      9
    case False{}:
      open

# mode for the items after a separator: a trailing comma is an error
def tail_mode(sc: U32, tcode: U32, closer: U32, open: U32) -> U32:
  match sc:
    case 44:
      tail_mode.pick(U32.is_eq(tcode, closer), open)
    case _:
      9

def arr_join(item: Parsed, sc: U32, after: String, tail: Parsed) -> Parsed:
  match item:
    case PNo{}:
      PNo{}
    case PJ{v, _}:
      match sc:
        case 44:
          match tail:
            case PJ{tj, tr}:
              PJ{Item{v, tj}, tr}
            case PNo{}:
              PNo{}
        case 93:
          PJ{Item{v, End{}}, drop1(after)}
        case _:
          PNo{}

def obj_join.val(key: String, val: Parsed, sc: U32, after: String, tail: Parsed) -> Parsed:
  match val:
    case PNo{}:
      PNo{}
    case PJ{v, _}:
      match sc:
        case 44:
          match tail:
            case PJ{tj, tr}:
              PJ{Member{key, v, tj}, tr}
            case PNo{}:
              PNo{}
        case 125:
          PJ{Member{key, v, End{}}, drop1(after)}
        case _:
          PNo{}

def obj_join.colon(ks: PStr, c1: U32, val: Parsed, sc: U32, after: String, tail: Parsed) -> Parsed:
  match ks:
    case PSNo{}:
      PNo{}
    case PS{key, _}:
      match c1:
        case 58:
          obj_join.val(key, val, sc, after, tail)
        case _:
          PNo{}

def obj_join(code: U32, ks: PStr, c1: U32, val: Parsed, sc: U32, after: String, tail: Parsed) -> Parsed:
  match code:
    case 34:
      obj_join.colon(ks, c1, val, sc, after, tail)
    case _:
      PNo{}

def parse.go(+fuel: Nat, mode: U32, code: U32, +s: String) -> Parsed:
  match fuel:
    case 0n:
      PNo{}
    case 1n+p:
      match mode:
        case 0:
          match code:
            case 34:
              +r = drop1(s)
              str_val(str_body(p, code_of(r), r))
            case 91:
              +w = skip_ws(drop1(s))
              wrap_arr(parse.go(p, 1, code_of(w), w))
            case 123:
              +w = skip_ws(drop1(s))
              wrap_obj(parse.go(p, 2, code_of(w), w))
            case 116:
              lit(s, "true", Boolean{True{}})
            case 102:
              lit(s, "false", Boolean{False{}})
            case 110:
              lit(s, "null", Null{})
            case _:
              num_val(is_num_start(code), num_span(s))
        case 1:
          match code:
            case 93:
              PJ{End{}, drop1(s)}
            case 0:
              PNo{}
            case _:
              +item = parse.go(p, 0, code, s)
              +after = skip_ws(rest_of(item))
              +sc = code_of(after)
              +t0 = skip_ws(drop1(after))
              +tc = code_of(t0)
              +tail = parse.go(p, tail_mode(sc, tc, 93, 1), tc, t0)
              arr_join(item, sc, after, tail)
        case 2:
          match code:
            case 125:
              PJ{End{}, drop1(s)}
            case 0:
              PNo{}
            case _:
              +r = drop1(s)
              +ks = str_body(p, code_of(r), r)
              +a1 = skip_ws(pstr_rest(ks))
              +c1 = code_of(a1)
              +vs = skip_ws(drop1(a1))
              +val = parse.go(p, 0, code_of(vs), vs)
              +after = skip_ws(rest_of(val))
              +sc = code_of(after)
              +t0 = skip_ws(drop1(after))
              +tc = code_of(t0)
              +tail = parse.go(p, tail_mode(sc, tc, 125, 2), tc, t0)
              obj_join(code, ks, c1, val, sc, after, tail)
        case _:
          PNo{}

def parse.done(j: Json, trailing_ws_only: Bool) -> Maybe<&2, Json>:
  match trailing_ws_only:
    case True{}:
      Some{j}
    case False{}:
      None{}

def parse.top(r: Parsed) -> Maybe<&2, Json>:
  match r:
    case PJ{j, rest}:
      parse.done(j, String.is_empty(skip_ws(rest)))
    case PNo{}:
      None{}

# Json.parse("{\"a\":[1,true]}") -> Some value, or None if malformed
def parse(s: String) -> Maybe<&2, Json>:
  +w = skip_ws(s)
  parse.top(parse.go(1n+String.length(w), 0, code_of(w), w))
