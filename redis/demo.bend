import Base
import ./client.bend as Redis
import ./resp.bend as Resp

def show(r: Resp.Reply) -> String:
  match r:
    case Resp.Simple{t}:
      "+" ++ t
    case Resp.Err{t}:
      "-" ++ t
    case Resp.Int{t}:
      ":" ++ t
    case Resp.Bulk{t}:
      "\"" ++ t ++ "\""
    case Resp.Null{}:
      "(nil)"
    case Resp.Bad{}:
      "(unparsed)"

def print_out(r: Socket & Result<&1, &1, String, Resp.Reply>) -> IO(Socket):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          do IO<Socket>:
            IO.print("error: " ++ e)
            IO.pure(Socket, s)
        case Done{reply}:
          do IO<Socket>:
            IO.print(show(reply))
            IO.pure(Socket, s)

def main() -> IO(Unit):
  do IO<Unit>:
    s0 : Socket <- IO.try(Socket, Redis.connect("127.0.0.1", 6379))
    r1 : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.ping(s0)
    s1 : Socket <- print_out(r1)
    r2 : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.set(s1, "greeting", "hello")
    s2 : Socket <- print_out(r2)
    r3 : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.get(s2, "greeting")
    s3 : Socket <- print_out(r3)
    r4 : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.incr(s3, "counter")
    s4 : Socket <- print_out(r4)
    r5 : Socket & Result<&1, &1, String, Resp.Reply> <- Redis.get(s4, "missing")
    s5 : Socket <- print_out(r5)
    Redis.close(s5)
