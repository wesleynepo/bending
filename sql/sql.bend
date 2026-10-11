import Base

# Safe construction of PostgreSQL statements: quoting, parameter binding and a
# small query builder. Pure; nothing here talks to a server.
#
# Assumes standard_conforming_strings = on (the PostgreSQL default since 9.1),
# so a backslash inside '...' is an ordinary character. NUL characters cannot
# be stored by PostgreSQL and are dropped from quoted text and identifiers.

# --- quoting ----------------------------------------------------------------

# s with every `q` doubled; NUL dropped
def dbl.go(nul: Bool, dq: Bool, +h: Char, rest: String) -> String:
  match nul:
    case True{}:
      rest
    case False{}:
      match dq:
        case True{}:
          SCon{h, SCon{h, rest}}
        case False{}:
          SCon{h, rest}

def dbl(+q: U32, s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      dbl.go(U32.is_eq(Char.to_u32(h), 0), U32.is_eq(Char.to_u32(h), q), h, dbl(q, t))

# "weird ""name""" - an identifier (table or column name)
def quote_ident(s: String) -> String:
  "\"" ++ dbl(34, s) ++ "\""

# 'it''s' - a text literal
def quote_str(s: String) -> String:
  "'" ++ dbl(39, s) ++ "'"

def lit_str(s: String) -> String:
  quote_str(s)

def lit_u32(n: U32) -> String:
  U32.show(n)

def lit_bool(b: Bool) -> String:
  match b:
    case True{}:
      "TRUE"
    case False{}:
      "FALSE"

def lit_null() -> String:
  "NULL"

# --- values -----------------------------------------------------------------

type Value is Data:
  Null{}
  Boolean{value: Bool}
  Num{text: String}        # numeric text such as "42", "-1.5", "2e10"
  Text{text: String}

def null() -> Value:
  Null{}

def bool(b: Bool) -> Value:
  Boolean{b}

def u32(n: U32) -> Value:
  Num{U32.show(n)}

def text(s: String) -> Value:
  Text{s}

def is_num_char(+h: Char) -> Bool:
  Char.is_digit(h) || Char.is_eq(h, '-') || Char.is_eq(h, '+') || Char.is_eq(h, '.')
    || Char.is_eq(h, 'e') || Char.is_eq(h, 'E')

def all_num(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      is_num_char(h) && all_num(t)

def valid_num(+s: String) -> Bool:
  all_num(s) && Bool.not(String.is_empty(s))

def render.num(ok: Bool, t: String) -> String:
  match ok:
    case True{}:
      t
    case False{}:
      quote_str(t)

# SQL text for a value. A Num whose text is not plainly numeric is quoted
# instead (a type error at the server, never an injection).
def render(v: Value) -> String:
  match v:
    case Null{}:
      "NULL"
    case Boolean{b}:
      lit_bool(b)
    case Num{+t}:
      render.num(valid_num(t), t)
    case Text{t}:
      quote_str(t)

# --- parameter binding ------------------------------------------------------
#
# bind("SELECT * FROM t WHERE a = $1 AND b = $2", [text("x"), u32(3)])
#   == Some{"SELECT * FROM t WHERE a = 'x' AND b = 3"}
#
# $n inside '...' or "..." is left alone. Not understood: dollar-quoted strings
# ($$...$$), E'...' escapes, and comments - a $n there is substituted.

type Digits is Data:
  Digits{text: String, rest: String}

def digits.fin(more: Bool, h: Char, +t: String, r: Digits) -> Digits:
  match more:
    case True{}:
      match r:
        case Digits{d, rest}:
          Digits{SCon{h, d}, rest}
    case False{}:
      Digits{SNil{}, SCon{h, t}}

def take_digits(s: String) -> Digits:
  match s:
    case SNil{}:
      Digits{"", ""}
    case SCon{+h, +t}:
      digits.fin(Char.is_digit(h), h, t, take_digits(t))

def digits_text(d: Digits) -> String:
  match d:
    case Digits{x, r}:
      x

# the text after the placeholder: after the digits, or after the `$` if none
def digits_next(empty: Bool, d: Digits, t: String) -> String:
  match empty:
    case True{}:
      t
    case False{}:
      match d:
        case Digits{x, r}:
          r

def code_of(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{h, t}:
      Char.to_u32(h)

# $1 is the first parameter
def lookup(idx: Maybe<&2, Nat>, params: List<&2, Value>) -> Maybe<&2, Value>:
  match idx:
    case None{}:
      None{}
    case Some{n}:
      match n:
        case 0n:
          None{}
        case 1n+k:
          List.get(&2, Value, params, k)

def cons_m(h: Char, m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{r}:
      Some{SCon{h, r}}

def ph_join.val(v: Maybe<&2, Value>, rec: Maybe<&2, String>) -> Maybe<&2, String>:
  match v:
    case None{}:
      None{}
    case Some{x}:
      match rec:
        case None{}:
          None{}
        case Some{r}:
          Some{render(x) ++ r}

def ph_join(empty: Bool, v: Maybe<&2, Value>, rec: Maybe<&2, String>) -> Maybe<&2, String>:
  match empty:
    case True{}:
      cons_m('$', rec)
    case False{}:
      ph_join.val(v, rec)

# 0 = plain text, 1 = inside '...', 2 = inside "..."
def next_mode(mode: U32, code: U32) -> U32:
  match mode:
    case 0:
      match code:
        case 39:
          1
        case 34:
          2
        case _:
          0
    case 1:
      match code:
        case 39:
          0
        case _:
          1
    case _:
      match code:
        case 34:
          0
        case _:
          2

# fuel = length + 1: every step consumes at least one char
def bind.go(+fuel: Nat, s: String, mode: U32, code: U32, +params: List<&2, Value>) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match s:
        case SNil{}:
          Some{""}
        case SCon{h, +t}:
          match mode:
            case 0:
              match code:
                case 36:
                  +d = take_digits(t)
                  +ds = digits_text(d)
                  +empty = String.is_empty(ds)
                  +cont = digits_next(empty, d, t)
                  ph_join(empty, lookup(Nat.read(ds), params),
                    bind.go(p, cont, 0, code_of(cont), params))
                case _:
                  +t2 = t
                  cons_m(h, bind.go(p, t2, next_mode(0, code), code_of(t2), params))
            case 1:
              +t2 = t
              cons_m(h, bind.go(p, t2, next_mode(1, code), code_of(t2), params))
            case _:
              +t2 = t
              cons_m(h, bind.go(p, t2, next_mode(2, code), code_of(t2), params))

# None when a placeholder refers to a missing parameter ($0 included)
def bind(+template: String, params: List<&2, Value>) -> Maybe<&2, String>:
  bind.go(1n+String.length(template), template, 0, code_of(template), params)

# --- conditions -------------------------------------------------------------

type Cond is Data:
  Always{}                                  # no restriction
  Eq{col: String, val: Value}
  Ne{col: String, val: Value}
  Lt{col: String, val: Value}
  Gt{col: String, val: Value}
  Le{col: String, val: Value}
  Ge{col: String, val: Value}
  IsNull{col: String}
  And{left: Cond, right: Cond}
  Or{left: Cond, right: Cond}
  Not{cond: Cond}

def is_null_val(v: Value) -> Bool:
  match v:
    case Null{}:
      True{}
    case _:
      False{}

def cmp(+col: String, op: String, v: Value) -> String:
  quote_ident(col) ++ " " ++ op ++ " " ++ render(v)

# col = NULL is never true in SQL, so Eq/Ne against Null mean IS [NOT] NULL
def eq_sql(isnull: Bool, col: String, v: Value) -> String:
  match isnull:
    case True{}:
      quote_ident(col) ++ " IS NULL"
    case False{}:
      cmp(col, "=", v)

def ne_sql(isnull: Bool, col: String, v: Value) -> String:
  match isnull:
    case True{}:
      quote_ident(col) ++ " IS NOT NULL"
    case False{}:
      cmp(col, "<>", v)

def render_cond(c: Cond) -> String:
  match c:
    case Always{}:
      "TRUE"
    case Eq{col, +val}:
      eq_sql(is_null_val(val), col, val)
    case Ne{col, +val}:
      ne_sql(is_null_val(val), col, val)
    case Lt{col, val}:
      cmp(col, "<", val)
    case Gt{col, val}:
      cmp(col, ">", val)
    case Le{col, val}:
      cmp(col, "<=", val)
    case Ge{col, val}:
      cmp(col, ">=", val)
    case IsNull{col}:
      quote_ident(col) ++ " IS NULL"
    case And{l, r}:
      "(" ++ render_cond(l) ++ " AND " ++ render_cond(r) ++ ")"
    case Or{l, r}:
      "(" ++ render_cond(l) ++ " OR " ++ render_cond(r) ++ ")"
    case Not{x}:
      "(NOT " ++ render_cond(x) ++ ")"

# --- statements -------------------------------------------------------------
#
# `table` and column names are single identifiers (no schema.table splitting).
# Every identifier is quoted and every value rendered, so callers never
# concatenate user input into SQL themselves.

type Order is Data:
  Asc{col: String}
  Desc{col: String}

type Assign is Data:
  Assign{col: String, val: Value}

def quote_all(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      quote_ident(h) <> quote_all(t)

def render_all(xs: List<&2, Value>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      render(h) <> render_all(t)

def order_sql(o: Order) -> String:
  match o:
    case Asc{c}:
      quote_ident(c) ++ " ASC"
    case Desc{c}:
      quote_ident(c) ++ " DESC"

def order_all(xs: List<&2, Order>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      order_sql(h) <> order_all(t)

def set_sql(s: Assign) -> String:
  match s:
    case Assign{c, v}:
      quote_ident(c) ++ " = " ++ render(v)

def set_all(xs: List<&2, Assign>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      set_sql(h) <> set_all(t)

def cols_sql.go(empty: Bool, cols: List<&2, String>) -> String:
  match empty:
    case True{}:
      "*"
    case False{}:
      String.join(quote_all(cols), ", ")

def cols_sql(+cols: List<&2, String>) -> String:
  cols_sql.go(List.is_empty(&2, String, cols), cols)

def where_opt(c: Cond) -> String:
  match c:
    case Always{}:
      ""
    case _:
      " WHERE " ++ render_cond(c)

def order_opt.go(empty: Bool, xs: List<&2, Order>) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      " ORDER BY " ++ String.join(order_all(xs), ", ")

def order_opt(+xs: List<&2, Order>) -> String:
  order_opt.go(List.is_empty(&2, Order, xs), xs)

def limit_opt(n: Maybe<&2, U32>) -> String:
  match n:
    case None{}:
      ""
    case Some{k}:
      " LIMIT " ++ U32.show(k)

# select("users", ["id", "name"], Eq{"id", u32(1)}, [Asc{"id"}], Some{10})
#   == "SELECT \"id\", \"name\" FROM \"users\" WHERE \"id\" = 1 ORDER BY \"id\" ASC LIMIT 10"
# No columns means *; Always{} omits the WHERE clause.
def select(table: String, cols: List<&2, String>, cond: Cond, order: List<&2, Order>,
  limit: Maybe<&2, U32>) -> String:
  "SELECT " ++ cols_sql(cols) ++ " FROM " ++ quote_ident(table) ++ where_opt(cond)
    ++ order_opt(order) ++ limit_opt(limit)

def insert.go(same: Bool, table: String, cols: List<&2, String>, values: List<&2, Value>) ->
  Maybe<&2, String>:
  match same:
    case True{}:
      Some{"INSERT INTO " ++ quote_ident(table) ++ " (" ++ String.join(quote_all(cols), ", ")
        ++ ") VALUES (" ++ String.join(render_all(values), ", ") ++ ")"}
    case False{}:
      None{}

# None when the columns and values differ in number or are empty
def insert(table: String, +cols: List<&2, String>, +values: List<&2, Value>) -> Maybe<&2, String>:
  insert.go(Nat.is_eq(List.length(&2, String, cols), List.length(&2, Value, values))
    && Bool.not(List.is_empty(&2, String, cols)), table, cols, values)

def update.go(empty: Bool, table: String, sets: List<&2, Assign>, cond: Cond) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{"UPDATE " ++ quote_ident(table) ++ " SET " ++ String.join(set_all(sets), ", ")
        ++ " WHERE " ++ render_cond(cond)}

# None when there is nothing to set. WHERE is always emitted: pass Always{} to
# mean every row.
def update(table: String, +sets: List<&2, Assign>, cond: Cond) -> Maybe<&2, String>:
  update.go(List.is_empty(&2, Assign, sets), table, sets, cond)

def delete(table: String, cond: Cond) -> String:
  "DELETE FROM " ++ quote_ident(table) ++ " WHERE " ++ render_cond(cond)
