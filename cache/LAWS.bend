import Base
import ./cache.bend as C
import ../people/types.bend as T

law key_prefix:
  {C.key("abc") == "person:abc" : String}

law encode_plain:
  {C.encode(T.Person{"id-1", "Ana", "1990-05-17"})
    == "{\"id\":\"id-1\",\"name\":\"Ana\",\"birthdate\":\"1990-05-17\"}" : String}

law encode_non_ascii:
  {C.encode(T.Person{"id-2", "é😀", "1990-05-17"})
    == "{\"id\":\"id-2\",\"name\":\"\\u00e9\\U0001f600\",\"birthdate\":\"1990-05-17\"}" : String}

law decode_plain_round_trip:
  {C.decode(C.encode(T.Person{"id-1", "Ana", "1990-05-17"}))
    == Some{T.Person{"id-1", "Ana", "1990-05-17"}} : Maybe<&2, T.Person>}

law decode_non_ascii_round_trip:
  {C.decode(C.encode(T.Person{"id-3", "João Ñandú 日本 😀", "1990-05-17"}))
    == Some{T.Person{"id-3", "João Ñandú 日本 😀", "1990-05-17"}} : Maybe<&2, T.Person>}

law decode_backslash_u_round_trip:
  {C.decode(C.encode(T.Person{"id-4", "\\U0001f600 é", "1990-05-17"}))
    == Some{T.Person{"id-4", "\\U0001f600 é", "1990-05-17"}} : Maybe<&2, T.Person>}

law decode_astral_escape:
  {C.decode("{\"id\":\"x\",\"name\":\"\\U0001f600\",\"birthdate\":\"1990-05-17\"}")
    == Some{T.Person{"x", "😀", "1990-05-17"}} : Maybe<&2, T.Person>}

law decode_garbage:
  {C.decode("not json") == None{} : Maybe<&2, T.Person>}

law decode_missing_field:
  {C.decode("{\"id\":\"id-1\",\"name\":\"Ana\"}") == None{} : Maybe<&2, T.Person>}

law decode_wrong_type:
  {C.decode("{\"id\":\"id-1\",\"name\":1,\"birthdate\":\"1990-05-17\"}") == None{} : Maybe<&2, T.Person>}
