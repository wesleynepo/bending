import Base
import ./core.bend as C
import ../pg/client.bend as Pg

# Fixtures: A, B, Cm are reversible migrations 1..3; Bnd is migration 2 without a down script.
# Applied rows carry the checksum of their up script as the tool would store it.

law checksum_empty:
  {C.checksum("") == "fnv1a32:811c9dc5:0" : String}

law checksum_select:
  {C.checksum("select 1") == "fnv1a32:7677c032:8" : String}

law checksum_utf8_bytes:
  {C.checksum("é") == "fnv1a32:1e9de8c1:2" : String}

law checksum_edit_changes_value:
  {C.checksum("CREATE TABLE a();") == "fnv1a32:e2190fce:17" : String}

law checksum_edited_script:
  {C.checksum("CREATE TABLE b();") == "fnv1a32:e20b40c1:17" : String}

law manifest_basic:
  {C.parse_manifest("0001_a\n0002_b") == ["0001_a", "0002_b"] : List<&2, String>}

law manifest_crlf_comments_blank:
  {C.parse_manifest("0001_a\r\n# comment\n\n  0002_b  \n\t#x\n0003_c") == ["0001_a", "0002_b", "0003_c"] : List<&2, String>}

law manifest_empty:
  {C.parse_manifest("") == [] : List<&2, String>}

law manifest_only_comments:
  {C.parse_manifest("# a\n\n#b\n") == [] : List<&2, String>}

law base_ok:
  {C.parse_base("0001_create_people") == Some{C.Base{1, "create_people"}} : Maybe<&2, C.Base>}

law base_name_with_underscores:
  {C.parse_base("12_a_b") == Some{C.Base{12, "a_b"}} : Maybe<&2, C.Base>}

law base_version_zero:
  {C.parse_base("0000_x") == None{} : Maybe<&2, C.Base>}

law base_no_separator:
  {C.parse_base("abc") == None{} : Maybe<&2, C.Base>}

law base_empty_name:
  {C.parse_base("0001_") == None{} : Maybe<&2, C.Base>}

law base_upper_case_name:
  {C.parse_base("0001_Bad") == None{} : Maybe<&2, C.Base>}

law base_no_version_digits:
  {C.parse_base("_x") == None{} : Maybe<&2, C.Base>}

law base_no_name:
  {C.parse_base("0001") == None{} : Maybe<&2, C.Base>}

law up_file_name:
  {C.up_file("0001_a") == "0001_a.up.sql" : String}

law down_file_name:
  {C.down_file("0001_a") == "0001_a.down.sql" : String}

law valid_set_ok:
  {C.valid_set([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}]) == None{} : Maybe<&2, String>}

law valid_set_empty:
  {C.valid_set([]) == None{} : Maybe<&2, String>}

law valid_set_zero_version:
  {C.valid_set([C.Migration{0, "a", "u", ""}]) == Some{"migration 0 (a) has version 0; versions start at 1"} : Maybe<&2, String>}

law valid_set_not_increasing:
  {C.valid_set([C.Migration{2, "a", "u", ""}, C.Migration{2, "b", "u", ""}]) == Some{"migration 2 (b) is not after migration 2"} : Maybe<&2, String>}

law valid_set_duplicate_name:
  {C.valid_set([C.Migration{1, "a", "u", ""}, C.Migration{2, "a", "u", ""}]) == Some{"migration 1 (a) has a name used by another migration"} : Maybe<&2, String>}

law ensure_sql_text:
  {C.ensure_sql() == "CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, name text NOT NULL, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())" : String}

law select_sql_text:
  {C.select_sql() == "SELECT version, name, checksum FROM schema_migrations ORDER BY version" : String}

law lock_sql_text:
  {C.lock_sql() == "SELECT pg_advisory_lock(727274)" : String}

law unlock_sql_text:
  {C.unlock_sql() == "SELECT pg_advisory_unlock(727274)" : String}

law rollback_sql_text:
  {C.rollback_sql() == "ROLLBACK" : String}

law apply_sql_plain:
  {C.apply_sql(C.Migration{1, "a", "CREATE TABLE a();", "DROP TABLE a;"}) == "BEGIN;\nCREATE TABLE a();\n;\nINSERT INTO schema_migrations (version, name, checksum) VALUES (1, 'a', 'fnv1a32:e2190fce:17');\nCOMMIT;" : String}

law apply_sql_escapes_name:
  {C.apply_sql(C.Migration{7, "it's", "CREATE TABLE a();", "DROP TABLE a;"}) == "BEGIN;\nCREATE TABLE a();\n;\nINSERT INTO schema_migrations (version, name, checksum) VALUES (7, 'it''s', 'fnv1a32:e2190fce:17');\nCOMMIT;" : String}

law revert_sql_plain:
  {C.revert_sql(C.Migration{1, "a", "CREATE TABLE a();", "DROP TABLE a;"}) == "BEGIN;\nDROP TABLE a;\n;\nDELETE FROM schema_migrations WHERE version = 1;\nCOMMIT;" : String}

law applied_rows_ok:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{"1"}, Some{"a"}, Some{"c1"}], [Some{"12"}, Some{"b"}, Some{"c2"}]], "SELECT 2", ""}) == Some{[C.Applied{1, "a", "c1"}, C.Applied{12, "b", "c2"}]} : Maybe<&2, List<&2, C.Applied>>}

law applied_rows_none:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [], "SELECT 0", ""}) == Some{[]} : Maybe<&2, List<&2, C.Applied>>}

law applied_row_two_cells:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{"1"}, Some{"a"}]], "", ""}) == None{} : Maybe<&2, List<&2, C.Applied>>}

law applied_row_four_cells:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{"1"}, Some{"a"}, Some{"c"}, Some{"z"}]], "", ""}) == None{} : Maybe<&2, List<&2, C.Applied>>}

law applied_row_null_cell:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{"1"}, Some{"a"}, None{}]], "", ""}) == None{} : Maybe<&2, List<&2, C.Applied>>}

law applied_version_not_numeric:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{"x"}, Some{"a"}, Some{"c"}]], "", ""}) == None{} : Maybe<&2, List<&2, C.Applied>>}

law applied_version_empty:
  {C.parse_applied(Pg.Table{["version", "name", "checksum"], [[Some{""}, Some{"a"}, Some{"c"}]], "", ""}) == None{} : Maybe<&2, List<&2, C.Applied>>}

law pending_some_applied:
  {C.pending([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}], [C.Applied{1, "a", "x"}]) == [C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}] : List<&2, C.Migration>}

law pending_none_applied:
  {C.pending([], []) == [] : List<&2, C.Migration>}

law pending_all_applied:
  {C.pending([C.Migration{1, "a", "u", ""}], [C.Applied{1, "a", "x"}]) == [] : List<&2, C.Migration>}

law pending_out_of_order_kept:
  {C.pending([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}], [C.Applied{2, "b", "x"}]) == [C.Migration{1, "a", "u", ""}] : List<&2, C.Migration>}

law problems_clean:
  {C.problems([C.Migration{1, "a", "CREATE TABLE a();", ""}, C.Migration{2, "b", "CREATE TABLE b();", ""}], [C.Applied{1, "a", "fnv1a32:e2190fce:17"}, C.Applied{2, "b", "fnv1a32:e20b40c1:17"}]) == [] : List<&2, String>}

law problems_empty:
  {C.problems([], []) == [] : List<&2, String>}

law problems_modified:
  {C.problems([C.Migration{1, "a", "CREATE TABLE a();", ""}], [C.Applied{1, "a", "wrong"}]) == ["migration 1 (a) was modified after it was applied (checksum differs)"] : List<&2, String>}

law problems_applied_missing:
  {C.problems([C.Migration{1, "a", "CREATE TABLE a();", ""}], [C.Applied{1, "a", "fnv1a32:e2190fce:17"}, C.Applied{2, "b", "y"}]) == ["migration 2 (b) is applied but missing from the migrations list"] : List<&2, String>}

law problems_out_of_order:
  {C.problems([C.Migration{1, "a", "CREATE TABLE a();", ""}, C.Migration{2, "b", "CREATE TABLE b();", ""}], [C.Applied{2, "b", "fnv1a32:e20b40c1:17"}]) == ["migration 1 (a) is pending but older than the latest applied migration (out of order)"] : List<&2, String>}

law problems_version_order:
  {C.problems([C.Migration{1, "a", "CREATE TABLE a();", ""}, C.Migration{3, "c", "u", ""}], [C.Applied{1, "a", "fnv1a32:e2190fce:17"}, C.Applied{2, "b", "y"}]) == ["migration 2 (b) is applied but missing from the migrations list"] : List<&2, String>}

law problems_two_kinds_in_order:
  {C.problems([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}], [C.Applied{4, "d", "z"}]) == ["migration 1 (a) is pending but older than the latest applied migration (out of order)", "migration 2 (b) is pending but older than the latest applied migration (out of order)", "migration 4 (d) is applied but missing from the migrations list"] : List<&2, String>}

law status_empty:
  {C.status_lines([], []) == [] : List<&2, String>}

law status_mixed:
  {C.status_lines([C.Migration{1, "a", "CREATE TABLE a();", ""}, C.Migration{2, "b", "CREATE TABLE b();", ""}, C.Migration{3, "c", "CREATE TABLE c();", ""}], [C.Applied{1, "a", "fnv1a32:e2190fce:17"}, C.Applied{2, "b", "wrong"}]) == ["0001  a  applied", "0002  b  applied (MODIFIED)", "0003  c  pending"] : List<&2, String>}

law status_out_of_order_and_unknown:
  {C.status_lines([C.Migration{1, "a", "CREATE TABLE a();", ""}, C.Migration{2, "b", "CREATE TABLE b();", ""}, C.Migration{3, "c", "CREATE TABLE c();", ""}], [C.Applied{1, "a", "fnv1a32:e2190fce:17"}, C.Applied{2, "b", "fnv1a32:e20b40c1:17"}, C.Applied{5, "e", "z"}]) == ["0001  a  applied", "0002  b  applied", "0003  c  pending (OUT OF ORDER)", "0005  e  applied (MISSING from migrations list)"] : List<&2, String>}

law status_pending_out_of_order:
  {C.status_lines([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}], [C.Applied{2, "b", "x"}]) == ["0001  a  pending (OUT OF ORDER)", "0002  b  applied (MODIFIED)"] : List<&2, String>}

law plan_up_all:
  {C.plan_up([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}], [C.Applied{1, "a", "x"}], 0) == [C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}] : List<&2, C.Migration>}

law plan_up_limited:
  {C.plan_up([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}], [C.Applied{1, "a", "x"}], 1) == [C.Migration{2, "b", "u", ""}] : List<&2, C.Migration>}

law plan_up_limit_above_pending:
  {C.plan_up([C.Migration{1, "a", "u", ""}], [], 5) == [C.Migration{1, "a", "u", ""}] : List<&2, C.Migration>}

law plan_up_nothing_pending:
  {C.plan_up([C.Migration{1, "a", "u", ""}], [C.Applied{1, "a", "x"}], 0) == [] : List<&2, C.Migration>}

law plan_up_to_target:
  {C.plan_up_to([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}, C.Migration{3, "c", "u", ""}], [C.Applied{1, "a", "x"}], 2) == [C.Migration{2, "b", "u", ""}] : List<&2, C.Migration>}

law plan_up_to_below_pending:
  {C.plan_up_to([C.Migration{1, "a", "u", ""}, C.Migration{2, "b", "u", ""}], [], 0) == [] : List<&2, C.Migration>}

law plan_down_newest_first:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "d2", "d2"}, C.Migration{3, "c", "d3", "d3"}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}, C.Applied{3, "c", "x"}], 2) == Done{[C.Migration{3, "c", "d3", "d3"}, C.Migration{2, "b", "d2", "d2"}]} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_count_above_applied:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "d2", "d2"}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}], 9) == Done{[C.Migration{2, "b", "d2", "d2"}, C.Migration{1, "a", "d1", "d1"}]} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_count_zero:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}], [C.Applied{1, "a", "x"}], 0) == Fail{"count must be at least 1"} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_nothing_applied:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}], [], 1) == Fail{"nothing to revert: no migrations are applied"} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_no_down_script:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "u", ""}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}], 1) == Fail{"migration 2 (b) has no down script"} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_no_down_script_deeper:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "u", ""}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}], 2) == Fail{"migration 2 (b) has no down script"} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_applied_missing:
  {C.plan_down([C.Migration{1, "a", "d1", "d1"}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}], 2) == Fail{"migration 2 (b) is applied but missing from the migrations list"} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_to_newer_than_target:
  {C.plan_down_to([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "d2", "d2"}, C.Migration{3, "c", "d3", "d3"}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}, C.Applied{3, "c", "x"}], 1) == Done{[C.Migration{3, "c", "d3", "d3"}, C.Migration{2, "b", "d2", "d2"}]} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_to_already_at_target:
  {C.plan_down_to([C.Migration{1, "a", "d1", "d1"}, C.Migration{2, "b", "d2", "d2"}, C.Migration{3, "c", "d3", "d3"}], [C.Applied{1, "a", "x"}, C.Applied{2, "b", "x"}, C.Applied{3, "c", "x"}], 3) == Done{[]} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_to_zero:
  {C.plan_down_to([C.Migration{1, "a", "d1", "d1"}], [C.Applied{1, "a", "x"}], 0) == Done{[C.Migration{1, "a", "d1", "d1"}]} : Result<&1, &1, String, List<&2, C.Migration>>}

law plan_down_to_nothing_applied:
  {C.plan_down_to([C.Migration{1, "a", "d1", "d1"}], [], 0) == Done{[]} : Result<&1, &1, String, List<&2, C.Migration>>}
