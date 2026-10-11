import Base
import ./client.bend as Pg
import ../json/json.bend as Json

# Configuration: PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD

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

def tag_of(t: Pg.Table) -> String:
  match t:
    case Pg.Table{cols, rows, tag, error}:
      tag

def describe(+t: Pg.Table) -> String:
  tag_of(t) ++ "  " ++ Json.encode(Pg.to_json(t))

def print_out(o: Pg.Out) -> IO(Pg.Conn):
  match o:
    case (c, res):
      match res:
        case Fail{e}:
          do IO<Pg.Conn>:
            IO.print("error: " ++ e)
            IO.pure(Pg.Conn, c)
        case Done{t}:
          do IO<Pg.Conn>:
            IO.print(describe(t))
            IO.pure(Pg.Conn, c)

def run(c: Pg.Conn, sql: String) -> IO(Pg.Conn):
  do IO<Pg.Conn>:
    o : Pg.Out <- Pg.query(c, sql)
    print_out(o)

def session(r: Result<&1, &1, String, Pg.Conn>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("connect failed: " ++ e)
    case Done{c}:
      do IO<Unit>:
        c1 : Pg.Conn <- run(c, "SELECT 1 AS n, 'héllo \"wörld\"' AS s, NULL AS missing")
        c2 : Pg.Conn <- run(c1, "CREATE TEMP TABLE people (id int, name text)")
        c3 : Pg.Conn <- run(c2, "INSERT INTO people VALUES (1, 'Ana'), (2, 'Bob'), (3, NULL)")
        c4 : Pg.Conn <- run(c3, "SELECT id, name FROM people ORDER BY id")
        c5 : Pg.Conn <- run(c4, "SELECT * FROM does_not_exist")
        c6 : Pg.Conn <- run(c5, "SELECT count(*) AS n FROM people")
        Pg.close(c6)

def main() -> IO(Unit):
  do IO<Unit>:
    host : String <- env_or("PGHOST", "127.0.0.1")
    port : String <- env_or("PGPORT", "5432")
    user : String <- env_or("PGUSER", "postgres")
    db : String <- env_or("PGDATABASE", "postgres")
    pw : String <- env_or("PGPASSWORD", "")
    r : Result<&1, &1, String, Pg.Conn> <- Pg.connect(host, Maybe.default(&2, U32, U32.read(port), 5432), user, db, pw)
    session(r)
