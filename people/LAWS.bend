import Base
import ./domain.bend as D
import ./types.bend as T
import ../json/json.bend as J

law uuid_lower:
  {D.valid_uuid("123e4567-e89b-12d3-a456-426614174000") == True{} : Bool}

law uuid_upper:
  {D.valid_uuid("123E4567-E89B-12D3-A456-426614174000") == True{} : Bool}

law uuid_mixed_case:
  {D.valid_uuid("123e4567-E89b-12D3-a456-426614174000") == True{} : Bool}

law uuid_no_dashes:
  {D.valid_uuid("123e4567e89b12d3a456426614174000") == False{} : Bool}

law uuid_underscore_at_dash:
  {D.valid_uuid("123e4567_e89b-12d3-a456-426614174000") == False{} : Bool}

law uuid_non_hex:
  {D.valid_uuid("123e4567-e89b-12d3-a456-42661417400g") == False{} : Bool}

law uuid_too_short:
  {D.valid_uuid("123e4567-e89b-12d3-a456-42661417400") == False{} : Bool}

law uuid_too_long:
  {D.valid_uuid("123e4567-e89b-12d3-a456-4266141740000") == False{} : Bool}

law uuid_empty:
  {D.valid_uuid("") == False{} : Bool}

law date_leap_2024:
  {D.valid_date("2024-02-29") == True{} : Bool}

law date_nonleap_2023:
  {D.valid_date("2023-02-29") == False{} : Bool}

law date_leap_century_2000:
  {D.valid_date("2000-02-29") == True{} : Bool}

law date_century_1900:
  {D.valid_date("1900-02-29") == False{} : Bool}

law date_april_31:
  {D.valid_date("2021-04-31") == False{} : Bool}

law date_month_13:
  {D.valid_date("2021-13-01") == False{} : Bool}

law date_unpadded_month:
  {D.valid_date("2021-1-01") == False{} : Bool}

law date_plain_ok:
  {D.valid_date("2021-12-31") == True{} : Bool}

law date_year_lower_bound:
  {D.valid_date("1900-01-01") == True{} : Bool}

law date_year_below_range:
  {D.valid_date("1899-12-31") == False{} : Bool}

law date_year_upper_bound:
  {D.valid_date("2999-12-31") == True{} : Bool}

law date_year_above_range:
  {D.valid_date("3000-01-01") == False{} : Bool}

law date_day_zero:
  {D.valid_date("2021-01-00") == False{} : Bool}

law date_no_separators:
  {D.valid_date("20210101") == False{} : Bool}

law date_non_digit:
  {D.valid_date("2021-01-1a") == False{} : Bool}

law name_simple:
  {D.valid_name("Ana") == True{} : Bool}

law name_blank:
  {D.valid_name("   ") == False{} : Bool}

law name_empty:
  {D.valid_name("") == False{} : Bool}

law name_max_200:
  {D.valid_name(String.repeat("a", 200n)) == True{} : Bool}

law name_over_200:
  {D.valid_name(String.repeat("a", 201n)) == False{} : Bool}

law name_trimmed_length:
  {D.valid_name(String.repeat(" ", 3n) ++ "x" ++ String.repeat(" ", 3n)) == True{} : Bool}

law parse_new_ok:
  {D.parse_new("{\"name\":\"  Ana Maria  \",\"birthdate\":\"1990-05-17\",\"extra\":1}")
    == Done{T.NewPerson{"Ana Maria", "1990-05-17"}} : Result<&1, &1, String, T.NewPerson>}

law parse_new_not_json:
  {D.parse_new("{") == Fail{"body is not valid JSON"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_not_object:
  {D.parse_new("[1]") == Fail{"body must be a JSON object"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_missing_name:
  {D.parse_new("{\"birthdate\":\"1990-05-17\"}")
    == Fail{"name is required and must be a string"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_name_not_string:
  {D.parse_new("{\"name\":1,\"birthdate\":\"1990-05-17\"}")
    == Fail{"name is required and must be a string"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_blank_name:
  {D.parse_new("{\"name\":\"   \",\"birthdate\":\"1990-05-17\"}")
    == Fail{"name must be 1 to 200 characters"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_missing_birthdate:
  {D.parse_new("{\"name\":\"Ana\"}")
    == Fail{"birthdate is required and must be a string"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_birthdate_not_string:
  {D.parse_new("{\"name\":\"Ana\",\"birthdate\":19900517}")
    == Fail{"birthdate is required and must be a string"} : Result<&1, &1, String, T.NewPerson>}

law parse_new_bad_date:
  {D.parse_new("{\"name\":\"Ana\",\"birthdate\":\"2023-02-29\"}")
    == Fail{"birthdate must be a valid YYYY-MM-DD date"} : Result<&1, &1, String, T.NewPerson>}

law person_json_encoded:
  {J.encode(D.person_json(T.Person{"id-1", "Ana", "1990-05-17"}))
    == "{\"id\":\"id-1\",\"name\":\"Ana\",\"birthdate\":\"1990-05-17\"}" : String}

law people_json_encoded:
  {J.encode(D.people_json([T.Person{"id-1", "Ana", "1990-05-17"}, T.Person{"id-2", "Bo", "2000-02-29"}]))
    == "[{\"id\":\"id-1\",\"name\":\"Ana\",\"birthdate\":\"1990-05-17\"},{\"id\":\"id-2\",\"name\":\"Bo\",\"birthdate\":\"2000-02-29\"}]" : String}

law people_json_empty:
  {J.encode(D.people_json(Nil{})) == "[]" : String}

law error_json_encoded:
  {J.encode(D.error_json("bad \"x\"")) == "{\"error\":\"bad \\\"x\\\"\"}" : String}

law limit_absent:
  {D.parse_limit(None{}, 20, 100) == Some{20} : Maybe<&2, U32>}

law limit_plain:
  {D.parse_limit(Some{"5"}, 20, 100) == Some{5} : Maybe<&2, U32>}

law limit_zero:
  {D.parse_limit(Some{"0"}, 20, 100) == Some{0} : Maybe<&2, U32>}

law limit_clamped:
  {D.parse_limit(Some{"500"}, 20, 100) == Some{100} : Maybe<&2, U32>}

law limit_empty:
  {D.parse_limit(Some{""}, 20, 100) == None{} : Maybe<&2, U32>}

law limit_negative:
  {D.parse_limit(Some{"-1"}, 20, 100) == None{} : Maybe<&2, U32>}

law limit_trailing_junk:
  {D.parse_limit(Some{"1x"}, 20, 100) == None{} : Maybe<&2, U32>}

law limit_leading_space:
  {D.parse_limit(Some{" 5"}, 20, 100) == None{} : Maybe<&2, U32>}

law limit_u32_max_exact:
  {D.parse_limit(Some{"4294967295"}, 20, 4294967295) == Some{4294967295} : Maybe<&2, U32>}

law limit_u32_overflow_saturates:
  {D.parse_limit(Some{"4294967296"}, 20, 4294967295) == Some{4294967295} : Maybe<&2, U32>}

law limit_huge_saturates:
  {D.parse_limit(Some{"99999999999999999999"}, 20, 100) == Some{100} : Maybe<&2, U32>}
