import Base
import ../pg/client.bend as Pg
import ../sql/sql.bend as Sql
import ../people/types.bend as T

# Persistence for people in PostgreSQL. Every IO function hands the connection
# back beside its result. Values are quoted with Sql.quote_str / Sql.lit_u32;
# identifiers and keywords are literal text in this file.

# --- pure SQL ---------------------------------------------------------------

def migrate_sql() -> String:
  "CREATE TABLE IF NOT EXISTS people (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK (length(btrim(name)) > 0), birthdate date NOT NULL, created_at timestamptz NOT NULL DEFAULT now())"

def create_sql(p: T.NewPerson) -> String:
  match p:
    case T.NewPerson{name, birthdate}:
      "INSERT INTO people (name, birthdate) VALUES (" ++ Sql.quote_str(name) ++ ", " ++ Sql.quote_str(birthdate) ++ ") RETURNING id::text, name, birthdate::text"

def get_sql(id: String) -> String:
  "SELECT id::text, name, birthdate::text FROM people WHERE id = " ++ Sql.quote_str(id) ++ "::uuid"

def list_sql(limit: U32, offset: U32) -> String:
  "SELECT id::text, name, birthdate::text FROM people ORDER BY name, id LIMIT " ++ Sql.lit_u32(limit) ++ " OFFSET " ++ Sql.lit_u32(offset)

def update_sql(id: String, p: T.NewPerson) -> String:
  match p:
    case T.NewPerson{name, birthdate}:
      "UPDATE people SET name = " ++ Sql.quote_str(name) ++ ", birthdate = " ++ Sql.quote_str(birthdate) ++ " WHERE id = " ++ Sql.quote_str(id) ++ "::uuid RETURNING id::text, name, birthdate::text"

def delete_sql(id: String) -> String:
  "DELETE FROM people WHERE id = " ++ Sql.quote_str(id) ++ "::uuid RETURNING id::text"

# --- table -> Person mapping --------------------------------------------------

def person_of3(i: Maybe<&2, String>, n: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, T.Person>:
  match i:
    case None{}:
      None{}
    case Some{id}:
      match n:
        case None{}:
          None{}
        case Some{name}:
          match b:
            case None{}:
              None{}
            case Some{bd}:
              Some{T.Person{id, name, bd}}

# A row must have exactly three cells: id, name, birthdate.
def person_of_row(r: List<&2, Maybe<&2, String>>) -> Maybe<&2, T.Person>:
  match r:
    case Con{i, r1}:
      match r1:
        case Con{n, r2}:
          match r2:
            case Con{b, r3}:
              match r3:
                case Nil{}:
                  person_of3(i, n, b)
                case _:
                  None{}
            case _:
              None{}
        case _:
          None{}
    case _:
      None{}

def people_cons(p: Maybe<&2, T.Person>, rest: Maybe<&2, List<&2, T.Person>>) -> Maybe<&2, List<&2, T.Person>>:
  match p:
    case None{}:
      None{}
    case Some{x}:
      match rest:
        case None{}:
          None{}
        case Some{xs}:
          Some{x <> xs}

def people_of(rows: List<&2, List<&2, Maybe<&2, String>>>) -> Maybe<&2, List<&2, T.Person>>:
  match rows:
    case Nil{}:
      Some{[]}
    case Con{r, t}:
      people_cons(person_of_row(r), people_of(t))

def list_result(m: Maybe<&2, List<&2, T.Person>>) -> Result<&1, &1, String, List<&2, T.Person>>:
  match m:
    case None{}:
      Fail{"malformed row from server"}
    case Some{xs}:
      Done{xs}

def rows_people(t: Pg.Table) -> Result<&1, &1, String, List<&2, T.Person>>:
  match t:
    case Pg.Table{cols, rows, tag, error}:
      list_result(people_of(rows))

def one_of(xs: List<&2, T.Person>) -> Result<&1, &1, String, Maybe<&2, T.Person>>:
  match xs:
    case Nil{}:
      Done{None{}}
    case Con{p, rest}:
      match rest:
        case Nil{}:
          Done{Some{p}}
        case _:
          Fail{"more than one row"}

def single_of(xs: List<&2, T.Person>) -> Result<&1, &1, String, T.Person>:
  match xs:
    case Nil{}:
      Fail{"no row returned"}
    case Con{p, rest}:
      match rest:
        case Nil{}:
          Done{p}
        case _:
          Fail{"more than one row"}

def one_result(r: Result<&1, &1, String, List<&2, T.Person>>) -> Result<&1, &1, String, Maybe<&2, T.Person>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      one_of(xs)

def single_result(r: Result<&1, &1, String, List<&2, T.Person>>) -> Result<&1, &1, String, T.Person>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{xs}:
      single_of(xs)

def has_row(rows: List<&2, List<&2, Maybe<&2, String>>>) -> Bool:
  match rows:
    case Nil{}:
      False{}
    case _:
      True{}

def table_has_row(t: Pg.Table) -> Bool:
  match t:
    case Pg.Table{cols, rows, tag, error}:
      has_row(rows)

# --- effects ------------------------------------------------------------------

def migrate_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, Unit>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Unit>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Unit>, (c, Done{Unit{}}))

# Idempotent: CREATE TABLE IF NOT EXISTS.
def migrate(c: Pg.Conn) -> IO(Pg.Conn & Result<&1, &1, String, Unit>):
  do IO<Pg.Conn & Result<&1, &1, String, Unit>>:
    o : Pg.Out <- Pg.query(c, migrate_sql())
    migrate_out(o)

def create_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, T.Person>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, T.Person>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, T.Person>, (c, single_result(rows_people(t))))

def create(c: Pg.Conn, p: T.NewPerson) -> IO(Pg.Conn & Result<&1, &1, String, T.Person>):
  do IO<Pg.Conn & Result<&1, &1, String, T.Person>>:
    o : Pg.Out <- Pg.query(c, create_sql(p))
    create_out(o)

def get_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, (c, one_result(rows_people(t))))

# Done{None} when no such row.
def get(c: Pg.Conn, id: String) -> IO(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>):
  do IO<Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>>:
    o : Pg.Out <- Pg.query(c, get_sql(id))
    get_out(o)

def list_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>, (c, rows_people(t)))

def list(c: Pg.Conn, limit: U32, offset: U32) -> IO(Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>):
  do IO<Pg.Conn & Result<&1, &1, String, List<&2, T.Person>>>:
    o : Pg.Out <- Pg.query(c, list_sql(limit, offset))
    list_out(o)

def update_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>, (c, one_result(rows_people(t))))

# Done{None} when no such row.
def update(c: Pg.Conn, id: String, p: T.NewPerson) -> IO(Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>):
  do IO<Pg.Conn & Result<&1, &1, String, Maybe<&2, T.Person>>>:
    o : Pg.Out <- Pg.query(c, update_sql(id, p))
    update_out(o)

def delete_out(o: Pg.Out) -> IO(Pg.Conn & Result<&1, &1, String, Bool>):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Bool>, (c, Fail{e}))
        case Done{t}:
          IO.pure(Pg.Conn & Result<&1, &1, String, Bool>, (c, Done{table_has_row(t)}))

# True when a row was deleted.
def delete(c: Pg.Conn, id: String) -> IO(Pg.Conn & Result<&1, &1, String, Bool>):
  do IO<Pg.Conn & Result<&1, &1, String, Bool>>:
    o : Pg.Out <- Pg.query(c, delete_sql(id))
    delete_out(o)
