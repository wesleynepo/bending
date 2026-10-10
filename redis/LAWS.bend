import Base
import ./resp.bend as Resp

law encode_ping:
  {Resp.encode(["PING"]) == "*1\r\n$4\r\nPING\r\n" : String}

law encode_set:
  {Resp.encode(["SET", "k", "v"]) == "*3\r\n$3\r\nSET\r\n$1\r\nk\r\n$1\r\nv\r\n" : String}

law parse_ok:
  {Resp.parse("+OK\r\n") == Resp.Simple{"OK"} : Resp.Reply}

law parse_error:
  {Resp.parse("-ERR unknown\r\n") == Resp.Err{"ERR unknown"} : Resp.Reply}

law parse_int:
  {Resp.parse(":42\r\n") == Resp.Int{"42"} : Resp.Reply}

law parse_bulk:
  {Resp.parse("$5\r\nhello\r\n") == Resp.Bulk{"hello"} : Resp.Reply}

law parse_null:
  {Resp.parse("$-1\r\n") == Resp.Null{} : Resp.Reply}
