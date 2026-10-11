import Base
import ./wire.bend as W

law utf8_ascii:
  {W.utf8("Hi") == [72, 105] : List<&2, U32>}

law utf8_two_bytes:
  {W.utf8("é") == [195, 169] : List<&2, U32>}

law utf8_four_bytes:
  {W.utf8("😀") == [240, 159, 152, 128] : List<&2, U32>}

law utf8_roundtrip:
  {W.decode(W.utf8("a é € 😀")) == "a é € 😀" : String}

law query_message:
  {W.query("SELECT 1") == [81, 0, 0, 0, 13, 83, 69, 76, 69, 67, 84, 32, 49, 0] : List<&2, U32>}

law terminate_message:
  {W.terminate() == [88, 0, 0, 0, 4] : List<&2, U32>}

law password_message:
  {W.password("pw") == [112, 0, 0, 0, 7, 112, 119, 0] : List<&2, U32>}

law startup_message:
  {W.startup("u", "d") == [0, 0, 0, 27, 0, 3, 0, 0, 117, 115, 101, 114, 0, 117, 0, 100, 97, 116, 97, 98, 97, 115, 101, 0, 100, 0, 0] : List<&2, U32>}

law split_ready:
  {W.to_msgs(W.frames_of(W.split([90, 0, 0, 0, 5, 73]))) == [W.MReady{73}] : List<&2, W.Msg>}

law split_keeps_partial_frame:
  {W.rest_of(W.split([90, 0, 0, 0, 5, 73, 90, 0, 0])) == [90, 0, 0] : List<&2, U32>}

law parse_data_row:
  {W.parse_msg(68, [0, 2, 0, 0, 0, 2, 104, 105, 255, 255, 255, 255]) == W.MRow{[Some{"hi"}, None{}]} : W.Msg}

law parse_complete:
  {W.parse_msg(67, [73, 78, 83, 69, 82, 84, 32, 48, 32, 49, 0]) == W.MComplete{"INSERT 0 1"} : W.Msg}

law parse_error:
  {W.parse_msg(69, [83, 69, 82, 82, 79, 82, 0, 67, 52, 50, 80, 48, 49, 0, 77, 111, 112, 115, 0, 0]) == W.MErr{"ERROR", "42P01", "ops"} : W.Msg}
