import Base
import ./resp.bend as Resp

# Minimal Redis client over TCP. One command at a time per connection.
# A reply must fit in a single 64KB read; arrays are reported as Bad{}.

def Out() -> Type:
  Socket & Result<&1, &1, String, Resp.Reply>

def connect(host: String, port: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  TCP.connect(host, port)

def close(sock: Socket) -> IO(Unit):
  Socket.close(sock)

def got(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>) -> IO(Out):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(Out, (s, Fail{"recv failed"}))
        case Done{m}:
          match m:
            case None{}:
              IO.pure(Out, (s, Fail{"connection closed"}))
            case Some{text}:
              IO.pure(Out, (s, Done{Resp.parse(text)}))

def sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(Out):
  match r:
    case (s, res):
      match res:
        case Fail{e}:
          IO.pure(Out, (s, Fail{"send failed"}))
        case Done{u}:
          do IO<Out>:
            r2 : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(s, 65536)
            got(r2)

# Sends one command, e.g. command(sock, ["GET", "key"]), and returns its reply.
def command(sock: Socket, args: List<&2, String>) -> IO(Out):
  do IO<Out>:
    r : Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(sock, Resp.encode(args))
    sent(r)

def ping(sock: Socket) -> IO(Out):
  command(sock, ["PING"])

def set(sock: Socket, key: String, value: String) -> IO(Out):
  command(sock, ["SET", key, value])

def get(sock: Socket, key: String) -> IO(Out):
  command(sock, ["GET", key])

def del(sock: Socket, key: String) -> IO(Out):
  command(sock, ["DEL", key])

def incr(sock: Socket, key: String) -> IO(Out):
  command(sock, ["INCR", key])
