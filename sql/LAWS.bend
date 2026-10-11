import Base
import ./sql.bend as Q

law quote_str_plain:
  {Q.quote_str("abc") == "'abc'" : String}

law quote_str_doubles_quotes:
  {Q.quote_str("it's") == "'it''s'" : String}

law quote_str_keeps_backslash:
  {Q.quote_str("a\\b") == "'a\\b'" : String}

law quote_str_drops_nul:
  {Q.quote_str("a\0b") == "'ab'" : String}

law quote_ident_doubles_quotes:
  {Q.quote_ident("we\"ird") == "\"we\"\"ird\"" : String}

law render_values:
  {String.join([Q.render(Q.null()), Q.render(Q.bool(True{})), Q.render(Q.u32(7)), Q.render(Q.text("x'y"))], "|") == "NULL|TRUE|7|'x''y'" : String}

law render_bad_number_is_quoted:
  {Q.render(Q.Num{"1; DROP TABLE t"}) == "'1; DROP TABLE t'" : String}

law bind_substitutes:
  {Q.bind("SELECT * FROM t WHERE a = $1 AND b = $2", [Q.text("x"), Q.u32(3)]) == Some{"SELECT * FROM t WHERE a = 'x' AND b = 3"} : Maybe<&2, String>}

law bind_reuses_placeholder:
  {Q.bind("$1 $1", [Q.u32(1)]) == Some{"1 1"} : Maybe<&2, String>}

law bind_quotes_hostile_param:
  {Q.bind("SELECT $1", [Q.text("'; DROP TABLE t; --")]) == Some{"SELECT '''; DROP TABLE t; --'"} : Maybe<&2, String>}

law bind_skips_quoted_placeholder:
  {Q.bind("SELECT '$1', \"$1\", $1", [Q.u32(5)]) == Some{"SELECT '$1', \"$1\", 5"} : Maybe<&2, String>}

law bind_out_of_range:
  {Q.bind("SELECT $2", [Q.u32(1)]) == None{} : Maybe<&2, String>}

law bind_zero_index:
  {Q.bind("SELECT $0", [Q.u32(1)]) == None{} : Maybe<&2, String>}

law bind_lone_dollar:
  {Q.bind("SELECT '$' || $1", [Q.text("a")]) == Some{"SELECT '$' || 'a'"} : Maybe<&2, String>}

law select_all:
  {Q.select("users", [], Q.Always{}, [], None{}) == "SELECT * FROM \"users\"" : String}

law select_full:
  {Q.select("users", ["id", "name"], Q.And{Q.Eq{"id", Q.u32(1)}, Q.Not{Q.IsNull{"name"}}}, [Q.Asc{"id"}, Q.Desc{"name"}], Some{10}) == "SELECT \"id\", \"name\" FROM \"users\" WHERE (\"id\" = 1 AND (NOT \"name\" IS NULL)) ORDER BY \"id\" ASC, \"name\" DESC LIMIT 10" : String}

law eq_null_is_is_null:
  {Q.render_cond(Q.Or{Q.Eq{"a", Q.null()}, Q.Ne{"b", Q.null()}}) == "(\"a\" IS NULL OR \"b\" IS NOT NULL)" : String}

law insert_row:
  {Q.insert("users", ["name", "age"], [Q.text("O'Neil"), Q.u32(40)]) == Some{"INSERT INTO \"users\" (\"name\", \"age\") VALUES ('O''Neil', 40)"} : Maybe<&2, String>}

law insert_length_mismatch:
  {Q.insert("users", ["name", "age"], [Q.text("x")]) == None{} : Maybe<&2, String>}

law update_row:
  {Q.update("users", [Q.Assign{"name", Q.text("x")}, Q.Assign{"age", Q.null()}], Q.Lt{"id", Q.u32(5)}) == Some{"UPDATE \"users\" SET \"name\" = 'x', \"age\" = NULL WHERE \"id\" < 5"} : Maybe<&2, String>}

law update_nothing_to_set:
  {Q.update("users", [], Q.Always{}) == None{} : Maybe<&2, String>}

law delete_row:
  {Q.delete("users", Q.Gt{"age", Q.u32(90)}) == "DELETE FROM \"users\" WHERE \"age\" > 90" : String}

law delete_everything_is_explicit:
  {Q.delete("users", Q.Always{}) == "DELETE FROM \"users\" WHERE TRUE" : String}
