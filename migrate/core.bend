import Base
import ../pg/client.bend as Pg
import ../pg/wire.bend as W
import ../sql/sql.bend as Sql

# Pure core of the migration tool: manifest and file names, checksums, SQL text,
# and the planning rules (what to apply, what to revert, what is out of order).
# No IO and no Docker. Migrations are expected in ascending version order.

type Migration is Data:
  Migration{version: U32, name: String, up: String, down: String}   # down == "" means irreversible

type Applied is Data:
  Applied{version: U32, name: String, checksum: String}

type Base is Data:
  Base{version: U32, name: String}

# --- field access -------------------------------------------------------------

def mver(m: Migration) -> U32:
  match m:
    case Migration{v, n, u, d}:
      v

def mname(m: Migration) -> String:
  match m:
    case Migration{v, n, u, d}:
      n

def appver(a: Applied) -> U32:
  match a:
    case Applied{v, n, c}:
      v

# --- checksum ---------------------------------------------------------------
# FNV-1a 32-bit over the UTF-8 bytes. NOT cryptographic: it only detects
# accidental edits to a migration after it was applied.

def hexd(n: U32) -> String:
  match n:
    case 0:
      "0"
    case 1:
      "1"
    case 2:
      "2"
    case 3:
      "3"
    case 4:
      "4"
    case 5:
      "5"
    case 6:
      "6"
    case 7:
      "7"
    case 8:
      "8"
    case 9:
      "9"
    case 10:
      "a"
    case 11:
      "b"
    case 12:
      "c"
    case 13:
      "d"
    case 14:
      "e"
    case 15:
      "f"
    case _:
      "0"

# hex digit whose place value is div
def hx.at(+h: U32, div: U32) -> String:
  hexd(((h / div : U32) % 16 : U32))

def hex8(+h: U32) -> String:
  hx.at(h, 268435456) ++ hx.at(h, 16777216) ++ hx.at(h, 1048576) ++ hx.at(h, 65536)
    ++ hx.at(h, 4096) ++ hx.at(h, 256) ++ hx.at(h, 16) ++ hx.at(h, 1)

def fnv.step(h: U32, b: U32) -> U32:
  (U32.xor(h, b) * 16777619 : U32)

def fnv.fold(bs: List<&2, U32>, h: U32) -> U32:
  match bs:
    case Nil{}:
      h
    case Con{b, t}:
      fnv.fold(t, fnv.step(h, b))

def checksum(sql: String) -> String:
  +bs = W.utf8(sql)
  "fnv1a32:" ++ hex8(fnv.fold(bs, 2166136261)) ++ ":" ++ U32.show(W.len32(bs))

# --- manifest -----------------------------------------------------------------

def manifest.keep(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && Bool.not(String.starts_with(s, "#"))

def manifest.pick(keep: Bool, line: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      Con{line, rest}
    case False{}:
      rest

def manifest.go(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      manifest.pick(manifest.keep(String.trim(h)), String.trim(h), manifest.go(t))

# one base name per line; lines are trimmed; blank and '#' lines are skipped
def parse_manifest(text: String) -> List<&2, String>:
  manifest.go(String.split(text, '\n'))

# --- base names ---------------------------------------------------------------

def bd.all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Char.is_digit(h) && bd.all(t)

def bd.val(s: String, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      bd.val(t, (acc * 10 + (Char.to_u32(h) - 48 : U32) : U32))

def nm.ok_char(+c: U32) -> Bool:
  ((c >= 97 : U32) && (c <= 122 : U32)) || ((c >= 48 : U32) && (c <= 57 : U32))
    || U32.is_eq(c, 95)

def nm.all(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      nm.ok_char(Char.to_u32(h)) && nm.all(t)

def base.good(+d: String, +name: String) -> Bool:
  Bool.not(String.is_empty(d)) && bd.all(d) && (bd.val(d, 0) > 0 : U32)
    && Bool.not(String.is_empty(name)) && nm.all(name)

def base.mk(ok: Bool, v: U32, name: String) -> Maybe<&2, Base>:
  match ok:
    case True{}:
      Some{Base{v, name}}
    case False{}:
      None{}

def base.from(empty: Bool, +d: String, +rest: List<&2, String>) -> Maybe<&2, Base>:
  match empty:
    case True{}:
      None{}
    case False{}:
      +name = String.join(rest, "_")
      base.mk(base.good(d, name), bd.val(d, 0), name)

# the part before the first '_' must be the version; everything after it is the name
def base.of_parts(parts: List<&2, String>) -> Maybe<&2, Base>:
  match parts:
    case Nil{}:
      None{}
    case Con{+d, +rest}:
      base.from(List.is_empty(&2, String, rest), d, rest)

# "0001_create_people" -> Base{1, "create_people"}
def parse_base(s: String) -> Maybe<&2, Base>:
  base.of_parts(String.split(s, '_'))

def up_file(b: String) -> String:
  b ++ ".up.sql"

def down_file(b: String) -> String:
  b ++ ".down.sql"

# --- set validation -----------------------------------------------------------

def vs.bad(zero: Bool, +m: Migration, +prev: U32) -> Maybe<&2, String>:
  match zero:
    case True{}:
      Some{"migration " ++ U32.show(mver(m)) ++ " (" ++ mname(m) ++ ") has version 0; versions start at 1"}
    case False{}:
      Some{"migration " ++ U32.show(mver(m)) ++ " (" ++ mname(m) ++ ") is not after migration " ++ U32.show(prev)}

def vs.check(good: Bool, zero: Bool, +m: Migration, +prev: U32, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match good:
    case True{}:
      rest
    case False{}:
      vs.bad(zero, m, prev)

def vs.order(ms: List<&2, Migration>, +prev: U32) -> Maybe<&2, String>:
  match ms:
    case Nil{}:
      None{}
    case Con{+m, t}:
      vs.check((mver(m) > prev : U32), U32.is_eq(mver(m), 0), m, prev, vs.order(t, mver(m)))

def has_name(xs: List<&2, Migration>, +n: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+m, t}:
      String.eq(mname(m), n) || has_name(t, n)

def vs.dupck(dup: Bool, +m: Migration, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match dup:
    case True{}:
      Some{"migration " ++ U32.show(mver(m)) ++ " (" ++ mname(m) ++ ") has a name used by another migration"}
    case False{}:
      rest

def vs.dup(ms: List<&2, Migration>) -> Maybe<&2, String>:
  match ms:
    case Nil{}:
      None{}
    case Con{+m, +t}:
      vs.dupck(has_name(t, mname(m)), m, vs.dup(t))

def vs.first(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a:
    case None{}:
      b
    case Some{s}:
      Some{s}

# None if OK; otherwise the first problem found
def valid_set(+ms: List<&2, Migration>) -> Maybe<&2, String>:
  vs.first(vs.order(ms, 0), vs.dup(ms))

# --- SQL text -----------------------------------------------------------------

def ensure_sql() -> String:
  "CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, name text NOT NULL, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())"

def select_sql() -> String:
  "SELECT version, name, checksum FROM schema_migrations ORDER BY version"

def lock_sql() -> String:
  "SELECT pg_advisory_lock(727274)"

def unlock_sql() -> String:
  "SELECT pg_advisory_unlock(727274)"

def rollback_sql() -> String:
  "ROLLBACK"

def apply_sql(m: Migration) -> String:
  match m:
    case Migration{v, n, +u, d}:
      "BEGIN;\n" ++ u ++ "\n;\nINSERT INTO schema_migrations (version, name, checksum) VALUES ("
        ++ Sql.lit_u32(v) ++ ", " ++ Sql.quote_str(n) ++ ", " ++ Sql.quote_str(checksum(u)) ++ ");\nCOMMIT;"

def revert_sql(m: Migration) -> String:
  match m:
    case Migration{v, n, u, +d}:
      "BEGIN;\n" ++ d ++ "\n;\nDELETE FROM schema_migrations WHERE version = " ++ Sql.lit_u32(v)
        ++ ";\nCOMMIT;"

# --- reading applied rows -----------------------------------------------------

def ap.ok_digits(+s: String) -> Bool:
  Bool.not(String.is_empty(s)) && bd.all(s)

def ap.mk(ok: Bool, +vs: String, ns: String, cs: String) -> Maybe<&2, Applied>:
  match ok:
    case True{}:
      Some{Applied{bd.val(vs, 0), ns, cs}}
    case False{}:
      None{}

def ap.cells(v: Maybe<&2, String>, n: Maybe<&2, String>, c: Maybe<&2, String>) -> Maybe<&2, Applied>:
  match v:
    case None{}:
      None{}
    case Some{+vs}:
      match n:
        case None{}:
          None{}
        case Some{ns}:
          match c:
            case None{}:
              None{}
            case Some{cs}:
              ap.mk(ap.ok_digits(vs), vs, ns, cs)

def ap.one4(v: Maybe<&2, String>, n: Maybe<&2, String>, c: Maybe<&2, String>, r3: List<&2, Maybe<&2, String>>) -> Maybe<&2, Applied>:
  match r3:
    case Nil{}:
      ap.cells(v, n, c)
    case _:
      None{}

def ap.one3(v: Maybe<&2, String>, n: Maybe<&2, String>, r2: List<&2, Maybe<&2, String>>) -> Maybe<&2, Applied>:
  match r2:
    case Con{c, r3}:
      ap.one4(v, n, c, r3)
    case _:
      None{}

def ap.one2(v: Maybe<&2, String>, r1: List<&2, Maybe<&2, String>>) -> Maybe<&2, Applied>:
  match r1:
    case Con{n, r2}:
      ap.one3(v, n, r2)
    case _:
      None{}

# a row must have exactly three non-null cells: version, name, checksum
def ap.one(r: List<&2, Maybe<&2, String>>) -> Maybe<&2, Applied>:
  match r:
    case Con{v, r1}:
      ap.one2(v, r1)
    case _:
      None{}

def ap.join(one: Maybe<&2, Applied>, rest: Maybe<&2, List<&2, Applied>>) -> Maybe<&2, List<&2, Applied>>:
  match one:
    case None{}:
      None{}
    case Some{a}:
      match rest:
        case None{}:
          None{}
        case Some{xs}:
          Some{Con{a, xs}}

def ap.all(rows: List<&2, List<&2, Maybe<&2, String>>>) -> Maybe<&2, List<&2, Applied>>:
  match rows:
    case Nil{}:
      Some{[]}
    case Con{r, t}:
      ap.join(ap.one(r), ap.all(t))

def parse_applied(t: Pg.Table) -> Maybe<&2, List<&2, Applied>>:
  match t:
    case Pg.Table{cols, rows, tg, er}:
      ap.all(rows)

# --- planning -----------------------------------------------------------------

def fa.pick(hit: Bool, +a: Applied, rest: Maybe<&2, Applied>) -> Maybe<&2, Applied>:
  match hit:
    case True{}:
      Some{a}
    case False{}:
      rest

def find_app(+xs: List<&2, Applied>, +v: U32) -> Maybe<&2, Applied>:
  match xs:
    case Nil{}:
      None{}
    case Con{+a, t}:
      fa.pick(U32.is_eq(appver(a), v), a, find_app(t, v))

def fm.pick(hit: Bool, +m: Migration, rest: Maybe<&2, Migration>) -> Maybe<&2, Migration>:
  match hit:
    case True{}:
      Some{m}
    case False{}:
      rest

def find_mig(+xs: List<&2, Migration>, +v: U32) -> Maybe<&2, Migration>:
  match xs:
    case Nil{}:
      None{}
    case Con{+m, t}:
      fm.pick(U32.is_eq(mver(m), v), m, find_mig(t, v))

def pl.pick(applied: Bool, +m: Migration, rest: List<&2, Migration>) -> List<&2, Migration>:
  match applied:
    case True{}:
      rest
    case False{}:
      Con{m, rest}

def pending(all: List<&2, Migration>, +applied: List<&2, Applied>) -> List<&2, Migration>:
  match all:
    case Nil{}:
      []
    case Con{+m, t}:
      pl.pick(Maybe.is_some(&2, Applied, find_app(applied, mver(m))), m, pending(t, applied))

# --- problems and status (one merge over both version-sorted lists) -----------
# mode 0: problems (only the messages); mode 1: status lines (one per entry)
# kind 0: pending migration, flag = out of order
# kind 1: both present, flag = checksum unchanged
# kind 2: applied but missing from the list

def pad.pick(a: Bool, b: Bool, c: Bool, s: String) -> String:
  match a:
    case True{}:
      "000" ++ s
    case False{}:
      match b:
        case True{}:
          "00" ++ s
        case False{}:
          match c:
            case True{}:
              "0" ++ s
            case False{}:
              s

def pad4(+n: U32) -> String:
  pad.pick((n < 10 : U32), (n < 100 : U32), (n < 1000 : U32), U32.show(n))

def ln.opt(show: Bool, msg: String) -> Maybe<&2, String>:
  match show:
    case True{}:
      Some{msg}
    case False{}:
      None{}

def ln.pick_s(b: Bool, yes: String, no: String) -> String:
  match b:
    case True{}:
      yes
    case False{}:
      no

def ln.status(kind: U32, flag: Bool) -> String:
  match kind:
    case 0:
      ln.pick_s(flag, "pending (OUT OF ORDER)", "pending")
    case 1:
      ln.pick_s(flag, "applied", "applied (MODIFIED)")
    case _:
      "applied (MISSING from migrations list)"

def ln.problem(kind: U32, flag: Bool, +v: U32, +n: String) -> Maybe<&2, String>:
  match kind:
    case 0:
      ln.opt(flag, "migration " ++ U32.show(v) ++ " (" ++ n
        ++ ") is pending but older than the latest applied migration (out of order)")
    case 1:
      ln.opt(Bool.not(flag), "migration " ++ U32.show(v) ++ " (" ++ n
        ++ ") was modified after it was applied (checksum differs)")
    case _:
      Some{"migration " ++ U32.show(v) ++ " (" ++ n ++ ") is applied but missing from the migrations list"}

def ln.line(mode: U32, kind: U32, flag: Bool, +v: U32, +n: String) -> Maybe<&2, String>:
  match mode:
    case 0:
      ln.problem(kind, flag, v, n)
    case _:
      Some{pad4(v) ++ "  " ++ n ++ "  " ++ ln.status(kind, flag)}

def match_up(m: Migration) -> String:
  match m:
    case Migration{v, n, u, d}:
      u

def appchk(a: Applied) -> String:
  match a:
    case Applied{v, n, c}:
      c

def ln.pending(mode: U32, +m: Migration, +top: U32) -> Maybe<&2, String>:
  ln.line(mode, 0, (mver(m) < top : U32), mver(m), mname(m))

def ln.both(mode: U32, +m: Migration, +a: Applied) -> Maybe<&2, String>:
  ln.line(mode, 1, String.eq(checksum(match_up(m)), appchk(a)), mver(m), mname(m))

def appname(a: Applied) -> String:
  match a:
    case Applied{v, n, c}:
      n

def ln.gone(mode: U32, +a: Applied) -> Maybe<&2, String>:
  ln.line(mode, 2, False{}, appver(a), appname(a))

# 0 = migration below applied (pending), 1 = same version, 2 = applied is below
def ln.rel(lt: Bool, eq: Bool) -> U32:
  match lt:
    case True{}:
      0
    case False{}:
      match eq:
        case True{}:
          1
        case False{}:
          2

def ln.rel_v(+mv: U32, +av: U32) -> U32:
  ln.rel((mv < av : U32), U32.is_eq(mv, av))

def pr.msg_pair(mode: U32, rel: U32, +m: Migration, +a: Applied, +top: U32) -> Maybe<&2, String>:
  match rel:
    case 0:
      ln.pending(mode, m, top)
    case 1:
      ln.both(mode, m, a)
    case _:
      ln.gone(mode, a)

def pr.msg_app(mode: U32, applied: List<&2, Applied>) -> Maybe<&2, String>:
  match applied:
    case Nil{}:
      None{}
    case Con{a, t}:
      ln.gone(mode, a)

def pr.msg_m(mode: U32, +m: Migration, applied: List<&2, Applied>, +top: U32) -> Maybe<&2, String>:
  match applied:
    case Nil{}:
      ln.pending(mode, m, top)
    case Con{+a, t}:
      pr.msg_pair(mode, ln.rel_v(mver(m), appver(a)), m, a, top)

def pr.msg(mode: U32, +all: List<&2, Migration>, +applied: List<&2, Applied>, +top: U32) -> Maybe<&2, String>:
  match all:
    case Nil{}:
      pr.msg_app(mode, applied)
    case Con{+m, t}:
      pr.msg_m(mode, m, applied, top)

def pr.pick_all(rel: U32, rest: List<&2, Migration>, all: List<&2, Migration>) -> List<&2, Migration>:
  match rel:
    case 2:
      all
    case _:
      rest

def pr.pick_app(rel: U32, at: List<&2, Applied>, applied: List<&2, Applied>) -> List<&2, Applied>:
  match rel:
    case 0:
      applied
    case _:
      at

def pr.tail_app(xs: List<&2, Applied>) -> List<&2, Applied>:
  match xs:
    case Nil{}:
      []
    case Con{a, t}:
      t

def pr.rest_all(+all: List<&2, Migration>, +applied: List<&2, Applied>) -> List<&2, Migration>:
  match all:
    case Nil{}:
      []
    case Con{+m, t}:
      match applied:
        case Nil{}:
          t
        case Con{+a, at}:
          pr.pick_all(ln.rel_v(mver(m), appver(a)), t, all)

def pr.rest_app(+all: List<&2, Migration>, +applied: List<&2, Applied>) -> List<&2, Applied>:
  match all:
    case Nil{}:
      pr.tail_app(applied)
    case Con{+m, t}:
      match applied:
        case Nil{}:
          []
        case Con{+a, at}:
          pr.pick_app(ln.rel_v(mver(m), appver(a)), at, applied)

def pr.cons(m: Maybe<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      rest
    case Some{s}:
      Con{s, rest}

def pr.merge(fuel: Nat, +all: List<&2, Migration>, +applied: List<&2, Applied>, +top: U32, +mode: U32) -> List<&2, String>:
  match fuel:
    case 0n:
      []
    case 1n+p:
      pr.cons(pr.msg(mode, all, applied, top),
        pr.merge(p, pr.rest_all(all, applied), pr.rest_app(all, applied), top, mode))

def pr.max_pick(lt: Bool, +x: U32, +y: U32) -> U32:
  match lt:
    case True{}:
      y
    case False{}:
      x

def pr.top_go(xs: List<&2, Applied>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{+a, t}:
      pr.top_go(t, pr.max_pick((acc < appver(a) : U32), acc, appver(a)))

# latest applied version (0 when none)
def pr.top(xs: List<&2, Applied>) -> U32:
  pr.top_go(xs, 0)

def pr.run(+all: List<&2, Migration>, +applied: List<&2, Applied>, +mode: U32) -> List<&2, String>:
  pr.merge(Nat.add(Nat.add(List.length(&2, Migration, all), List.length(&2, Applied, applied)), 1n),
    all, applied, pr.top(applied), mode)

# human messages in version order; empty when the applied state matches the list
def problems(all: List<&2, Migration>, applied: List<&2, Applied>) -> List<&2, String>:
  pr.run(all, applied, 0)

def status_lines(all: List<&2, Migration>, applied: List<&2, Applied>) -> List<&2, String>:
  pr.run(all, applied, 1)

# --- plans --------------------------------------------------------------------

def pu.keep(within: Bool, m: Migration, rest: List<&2, Migration>) -> List<&2, Migration>:
  match within:
    case True{}:
      Con{m, rest}
    case False{}:
      rest

def pu.upto(xs: List<&2, Migration>, +target: U32) -> List<&2, Migration>:
  match xs:
    case Nil{}:
      []
    case Con{+m, t}:
      pu.keep((mver(m) <= target : U32), m, pu.upto(t, target))

def pu.stop(stop: Bool, m: Migration, rest: List<&2, Migration>) -> List<&2, Migration>:
  match stop:
    case True{}:
      []
    case False{}:
      Con{m, rest}

def pu.cap(xs: List<&2, Migration>, +n: U32) -> List<&2, Migration>:
  match xs:
    case Nil{}:
      []
    case Con{m, t}:
      pu.stop(U32.is_eq(n, 0), m, pu.cap(t, (n - 1 : U32)))

def pu.limit(unbounded: Bool, +n: U32, xs: List<&2, Migration>) -> List<&2, Migration>:
  match unbounded:
    case True{}:
      xs
    case False{}:
      pu.cap(xs, n)

# limit 0 means no limit
def pu.start(+limit: U32, xs: List<&2, Migration>) -> List<&2, Migration>:
  pu.limit(U32.is_eq(limit, 0), limit, xs)

def plan_up(all: List<&2, Migration>, applied: List<&2, Applied>, limit: U32) -> List<&2, Migration>:
  pu.start(limit, pending(all, applied))

def plan_up_to(all: List<&2, Migration>, applied: List<&2, Applied>, target: U32) -> List<&2, Migration>:
  pu.upto(pending(all, applied), target)

def pdn.keep(within: Bool, +a: Applied, rest: List<&2, Applied>) -> List<&2, Applied>:
  match within:
    case True{}:
      Con{a, rest}
    case False{}:
      rest

def pdn.above(xs: List<&2, Applied>, +target: U32) -> List<&2, Applied>:
  match xs:
    case Nil{}:
      []
    case Con{+a, t}:
      pdn.keep((appver(a) > target : U32), a, pdn.above(t, target))

def pdn.stop(stop: Bool, a: Applied, rest: List<&2, Applied>) -> List<&2, Applied>:
  match stop:
    case True{}:
      []
    case False{}:
      Con{a, rest}

def pdn.cap(xs: List<&2, Applied>, +n: U32) -> List<&2, Applied>:
  match xs:
    case Nil{}:
      []
    case Con{a, t}:
      pdn.stop(U32.is_eq(n, 0), a, pdn.cap(t, (n - 1 : U32)))

def rv.nodown(m: Migration) -> Bool:
  match m:
    case Migration{v, n, u, d}:
      String.is_empty(d)

def rv.gone(+a: Applied) -> Result<&1, &1, String, List<&2, Migration>>:
  Fail{"migration " ++ U32.show(appver(a)) ++ " (" ++ appname(a) ++ ") is applied but missing from the migrations list"}

def rv.nodown_fail(+a: Applied) -> Result<&1, &1, String, List<&2, Migration>>:
  Fail{"migration " ++ U32.show(appver(a)) ++ " (" ++ appname(a) ++ ") has no down script"}

def rv.join(+m: Migration, rest: Result<&1, &1, String, List<&2, Migration>>) -> Result<&1, &1, String, List<&2, Migration>>:
  match rest:
    case Fail{e}:
      Fail{e}
    case Done{ms}:
      Done{Con{m, ms}}

def rv.check(nodown: Bool, +m: Migration, +a: Applied, rest: Result<&1, &1, String, List<&2, Migration>>) -> Result<&1, &1, String, List<&2, Migration>>:
  match nodown:
    case True{}:
      rv.nodown_fail(a)
    case False{}:
      rv.join(m, rest)

def rv.step(found: Maybe<&2, Migration>, +a: Applied, rest: Result<&1, &1, String, List<&2, Migration>>) -> Result<&1, &1, String, List<&2, Migration>>:
  match found:
    case None{}:
      rv.gone(a)
    case Some{+m}:
      rv.check(rv.nodown(m), m, a, rest)

# migrations for the given applied rows, which must be newest first
def rv.build(+all: List<&2, Migration>, sel: List<&2, Applied>) -> Result<&1, &1, String, List<&2, Migration>>:
  match sel:
    case Nil{}:
      Done{[]}
    case Con{+a, t}:
      rv.step(find_mig(all, appver(a)), a, rv.build(all, t))

def pd.nonempty(empty: Bool, +count: U32, +all: List<&2, Migration>, +applied: List<&2, Applied>) -> Result<&1, &1, String, List<&2, Migration>>:
  match empty:
    case True{}:
      Fail{"nothing to revert: no migrations are applied"}
    case False{}:
      rv.build(all, pdn.cap(List.reverse(&2, Applied, applied), count))

def pd.guard(zero: Bool, empty: Bool, +count: U32, +all: List<&2, Migration>, +applied: List<&2, Applied>) -> Result<&1, &1, String, List<&2, Migration>>:
  match zero:
    case True{}:
      Fail{"count must be at least 1"}
    case False{}:
      pd.nonempty(empty, count, all, applied)

def pd.start(+count: U32, +all: List<&2, Migration>, +applied: List<&2, Applied>) -> Result<&1, &1, String, List<&2, Migration>>:
  pd.guard(U32.is_eq(count, 0), List.is_empty(&2, Applied, applied), count, all, applied)

# the last `count` applied migrations, newest first
def plan_down(all: List<&2, Migration>, applied: List<&2, Applied>, count: U32) -> Result<&1, &1, String, List<&2, Migration>>:
  pd.start(count, all, applied)

# every applied migration with version > target, newest first
def plan_down_to(all: List<&2, Migration>, applied: List<&2, Applied>, target: U32) -> Result<&1, &1, String, List<&2, Migration>>:
  rv.build(all, pdn.above(List.reverse(&2, Applied, applied), target))
