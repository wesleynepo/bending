import Base
import ./types.bend as T
import ../json/json.bend as Json

# Pure validation and JSON shaping for the people API. No IO.

# --- uuid -------------------------------------------------------------------

def uuid.hex(+c: U32) -> Bool:
  ((c >= 48 : U32) && (c <= 57 : U32)) || ((c >= 65 : U32) && (c <= 70 : U32))
    || ((c >= 97 : U32) && (c <= 102 : U32))

# dashes sit at 0-based positions 8, 13, 18, 23 of the 36-char form
def uuid.is_dash(pos: U32) -> Bool:
  match pos:
    case 8:
      True{}
    case 13:
      True{}
    case 18:
      True{}
    case 23:
      True{}
    case _:
      False{}

def uuid.char_ok(dash: Bool, h: Char) -> Bool:
  match dash:
    case True{}:
      Char.is_eq(h, '-')
    case False{}:
      uuid.hex(Char.to_u32(h))

def uuid.go(s: String, +pos: U32) -> Bool:
  match s:
    case SNil{}:
      U32.is_eq(pos, 36)
    case SCon{h, t}:
      uuid.char_ok(uuid.is_dash(pos), h) && uuid.go(t, (pos + 1 : U32))

def valid_uuid(s: String) -> Bool:
  uuid.go(s, 0)

# --- digits -----------------------------------------------------------------

def dig.all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Char.is_digit(h) && dig.all(t)

def dig.step(acc: U32, c: U32) -> U32:
  (acc * 10 + (c - 48 : U32) : U32)

# value of a digit string; only meaningful after dig.all succeeded
def dig.val(s: String, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      dig.val(t, dig.step(acc, Char.to_u32(h)))

# --- date -------------------------------------------------------------------

def date.leap(+y: U32) -> Bool:
  (U32.is_zero(U32.mod(y, 4)) && Bool.not(U32.is_zero(U32.mod(y, 100))))
    || U32.is_zero(U32.mod(y, 400))

def date.feb_days(leap: Bool) -> U32:
  match leap:
    case True{}:
      29
    case False{}:
      28

def date.days(+y: U32, month: U32) -> U32:
  match month:
    case 1:
      31
    case 2:
      date.feb_days(date.leap(y))
    case 3:
      31
    case 4:
      30
    case 5:
      31
    case 6:
      30
    case 7:
      31
    case 8:
      31
    case 9:
      30
    case 10:
      31
    case 11:
      30
    case 12:
      31
    case _:
      0

def date.in_range(+y: U32, +m: U32, +d: U32) -> Bool:
  (y >= 1900 : U32) && (y <= 2999 : U32) && (m >= 1 : U32) && (m <= 12 : U32)
    && (d >= 1 : U32) && (d <= date.days(y, m) : U32)

def date.ok(shape: Bool, y: U32, m: U32, d: U32) -> Bool:
  match shape:
    case True{}:
      date.in_range(y, m, d)
    case False{}:
      False{}

def date.shape(+y: String, +m: String, +d: String) -> Bool:
  U32.is_eq(U32.from_nat(String.length(y)), 4)
    && U32.is_eq(U32.from_nat(String.length(m)), 2)
    && U32.is_eq(U32.from_nat(String.length(d)), 2)
    && dig.all(y) && dig.all(m) && dig.all(d)

def date.check(+y: String, +m: String, +d: String) -> Bool:
  date.ok(date.shape(y, m, d), dig.val(y, 0), dig.val(m, 0), dig.val(d, 0))

# split on '-' gives exactly three parts: year, month, day
def date.parts(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{y, r1}:
      match r1:
        case Nil{}:
          False{}
        case Con{m, r2}:
          match r2:
            case Nil{}:
              False{}
            case Con{d, r3}:
              match r3:
                case Nil{}:
                  date.check(y, m, d)
                case Con{x, r4}:
                  False{}

def valid_date(s: String) -> Bool:
  date.parts(String.split(s, '-'))

# --- name -------------------------------------------------------------------

def name.len_ok(+n: U32) -> Bool:
  (n >= 1 : U32) && (n <= 200 : U32)

def valid_name(s: String) -> Bool:
  name.len_ok(U32.from_nat(String.length(String.trim(s))))

# --- parse_new --------------------------------------------------------------

def opt_str(m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{+v}:
      Json.as_str(v)

def is_object(j: Json.Json) -> Bool:
  match j:
    case Json.Obj{members}:
      True{}
    case _:
      False{}

def birth.check(ok: Bool, name: String, b: String) -> Result<&1, &1, String, T.NewPerson>:
  match ok:
    case True{}:
      Done{T.NewPerson{name, b}}
    case False{}:
      Fail{"birthdate must be a valid YYYY-MM-DD date"}

def birth.step(bd: Maybe<&2, String>, name: String) -> Result<&1, &1, String, T.NewPerson>:
  match bd:
    case None{}:
      Fail{"birthdate is required and must be a string"}
    case Some{+b}:
      birth.check(valid_date(b), name, b)

def name.step(ok: Bool, n: String, bd: Maybe<&2, String>) -> Result<&1, &1, String, T.NewPerson>:
  match ok:
    case True{}:
      birth.step(bd, String.trim(n))
    case False{}:
      Fail{"name must be 1 to 200 characters"}

def fields.step(nm: Maybe<&2, String>, bd: Maybe<&2, String>) -> Result<&1, &1, String, T.NewPerson>:
  match nm:
    case None{}:
      Fail{"name is required and must be a string"}
    case Some{+n}:
      name.step(valid_name(n), n, bd)

def from_json(obj: Bool, +j: Json.Json) -> Result<&1, &1, String, T.NewPerson>:
  match obj:
    case True{}:
      fields.step(opt_str(Json.get(j, "name")), opt_str(Json.get(j, "birthdate")))
    case False{}:
      Fail{"body must be a JSON object"}

def from_parse(m: Maybe<&2, Json.Json>) -> Result<&1, &1, String, T.NewPerson>:
  match m:
    case None{}:
      Fail{"body is not valid JSON"}
    case Some{+j}:
      from_json(is_object(j), j)

def parse_new(body: String) -> Result<&1, &1, String, T.NewPerson>:
  from_parse(Json.parse(body))

# --- JSON shaping -----------------------------------------------------------

def person_json(p: T.Person) -> Json.Json:
  match p:
    case T.Person{id, name, birthdate}:
      Json.object([
        Json.field("id", Json.str(id)),
        Json.field("name", Json.str(name)),
        Json.field("birthdate", Json.str(birthdate))
      ])

def persons.map(ps: List<&2, T.Person>) -> List<&2, Json.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{person_json(h), persons.map(t)}

def people_json(ps: List<&2, T.Person>) -> Json.Json:
  Json.array(persons.map(ps))

def error_json(msg: String) -> Json.Json:
  Json.object([Json.field("error", Json.str(msg))])

# --- limit parsing ----------------------------------------------------------

# Saturating step: acc*10+d, capped at max, without U32 overflow.
# over: acc > max/10 (result would exceed max); exact: acc == max/10.
def lim.next(over: Bool, exact: Bool, fits: Bool, acc: U32, d: U32, max: U32) -> U32:
  match over:
    case True{}:
      max
    case False{}:
      match exact:
        case True{}:
          match fits:
            case True{}:
              (acc * 10 + d : U32)
            case False{}:
              max
        case False{}:
          (acc * 10 + d : U32)

def lim.go(s: String, +acc: U32, +max: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      +d = (Char.to_u32(h) - 48 : U32)
      lim.go(t, lim.next(U32.is_gt(acc, U32.div(max, 10)), U32.is_eq(acc, U32.div(max, 10)),
        U32.is_le(d, U32.mod(max, 10)), acc, d, max), max)

def lim.is_num(+t: String) -> Bool:
  Bool.not(String.is_empty(t)) && dig.all(t)

def lim.gate(ok: Bool, v: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{v}
    case False{}:
      None{}

# absent -> default; present but not digits -> None; otherwise clamped to max
def parse_limit(s: Maybe<&2, String>, default: U32, max: U32) -> Maybe<&2, U32>:
  match s:
    case None{}:
      Some{default}
    case Some{+t}:
      lim.gate(lim.is_num(t), lim.go(t, 0, max))
