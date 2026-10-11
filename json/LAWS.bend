import Base
import ./json.bend as J

law encode_object:
  {J.encode(J.object([J.field("a", J.u32(1)), J.field("b", J.str("x\"y"))])) == "{\"a\":1,\"b\":\"x\\\"y\"}" : String}

law encode_array:
  {J.encode(J.array([J.u32(1), J.bool(True{}), J.null()])) == "[1,true,null]" : String}

law parse_array:
  {J.parse(" [1, true , null] ") == Some{J.array([J.u32(1), J.bool(True{}), J.null()])} : Maybe<&2, J.Json>}

law parse_nested:
  {J.parse("{\"a\":{\"b\":[]}}") == Some{J.object([J.field("a", J.object([J.field("b", J.array([]))]))])} : Maybe<&2, J.Json>}

law parse_escapes:
  {J.parse("\"a\\n\\\"\\u0041\"") == Some{J.str("a\n\"A")} : Maybe<&2, J.Json>}

law parse_rejects_trailing_comma:
  {J.parse("[1,]") == None{} : Maybe<&2, J.Json>}

law parse_rejects_trailing_garbage:
  {J.parse("1 2") == None{} : Maybe<&2, J.Json>}

law roundtrip:
  {J.parse(J.encode(J.object([J.field("k", J.array([J.str("v\"\\"), J.null()]))]))) == Some{J.object([J.field("k", J.array([J.str("v\"\\"), J.null()]))])} : Maybe<&2, J.Json>}

law get_member:
  {J.get(J.object([J.field("a", J.u32(1)), J.field("b", J.u32(2))]), "b") == Some{J.u32(2)} : Maybe<&2, J.Json>}
