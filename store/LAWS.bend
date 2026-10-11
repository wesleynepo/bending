import Base
import ./store.bend as S
import ../people/types.bend as T

law migrate_sql_text:
  {S.migrate_sql() == "CREATE TABLE IF NOT EXISTS people (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK (length(btrim(name)) > 0), birthdate date NOT NULL, created_at timestamptz NOT NULL DEFAULT now())" : String}

law create_sql_quotes_name:
  {S.create_sql(T.NewPerson{"O'Brien", "1990-05-17"}) == "INSERT INTO people (name, birthdate) VALUES ('O''Brien', '1990-05-17') RETURNING id::text, name, birthdate::text" : String}

law create_sql_hostile_name:
  {S.create_sql(T.NewPerson{"'); DROP TABLE people;--", "2000-01-01"}) == "INSERT INTO people (name, birthdate) VALUES ('''); DROP TABLE people;--', '2000-01-01') RETURNING id::text, name, birthdate::text" : String}

law get_sql_uuid:
  {S.get_sql("0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f") == "SELECT id::text, name, birthdate::text FROM people WHERE id = '0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f'::uuid" : String}

law list_sql_page:
  {S.list_sql(10, 20) == "SELECT id::text, name, birthdate::text FROM people ORDER BY name, id LIMIT 10 OFFSET 20" : String}

law update_sql_row:
  {S.update_sql("0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f", T.NewPerson{"Ana", "1985-02-03"}) == "UPDATE people SET name = 'Ana', birthdate = '1985-02-03' WHERE id = '0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f'::uuid RETURNING id::text, name, birthdate::text" : String}

law delete_sql_row:
  {S.delete_sql("0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f") == "DELETE FROM people WHERE id = '0b3c1f2e-9d4a-4e6b-8c7d-1a2b3c4d5e6f'::uuid RETURNING id::text" : String}

law person_of_row_maps_cells:
  {S.person_of_row([Some{"id1"}, Some{"Bob"}, Some{"2001-09-09"}]) == Some{T.Person{"id1", "Bob", "2001-09-09"}} : Maybe<&2, T.Person>}

law person_of_row_rejects_null:
  {S.person_of_row([Some{"id1"}, None{}, Some{"2001-09-09"}]) == None{} : Maybe<&2, T.Person>}

law person_of_row_rejects_short:
  {S.person_of_row([Some{"id1"}, Some{"Bob"}]) == None{} : Maybe<&2, T.Person>}

law people_of_two_rows:
  {S.people_of([[Some{"a"}, Some{"A"}, Some{"2000-01-01"}], [Some{"b"}, Some{"B"}, Some{"2000-01-02"}]]) == Some{[T.Person{"a", "A", "2000-01-01"}, T.Person{"b", "B", "2000-01-02"}]} : Maybe<&2, List<&2, T.Person>>}

law people_of_empty:
  {S.people_of([]) == Some{[]} : Maybe<&2, List<&2, T.Person>>}
