import Base

def response() -> String:
  "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 27\r\nConnection: close\r\n\r\n{\"message\":\"Hello, World!\"}"

def close_sent(r: Socket & Result<&1, &1, (U32 & String) & String, Unit>) -> IO(Unit):
  match r:
    case (s, _):
      Socket.close(s)

# Sends the JSON reply, then closes the socket.
def send_reply(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>) -> IO(Unit):
  match r:
    case (s, _):
      do IO<Unit>:
        r2 : Socket & Result<&1, &1, (U32 & String) & String, Unit> <- TCP.send(s, response())
        close_sent(r2)

# Reads the request (ignored), replies, closes.
def reply(sock: Socket) -> IO(Unit):
  do IO<Unit>:
    r : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(sock, 4096)
    send_reply(r)

# Handles one accepted connection (if any) and hands the listener back.
def on_accept(r: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Listener):
  match r:
    case (l, res):
      match res:
        case Fail{e}:
          IO.pure(Listener, l)
        case Done{sock}:
          do IO<Listener>:
            reply(sock)
            IO.pure(Listener, l)

# Serves `fuel` connections, then shuts down (Bend loops need a decreasing argument).
def serve(fuel: Nat, l: Listener) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+p:
      do IO<Unit>:
        r : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(l)
        l2 : Listener <- on_accept(r)
        serve(p, l2)

def main() -> IO(Unit):
  do IO<Unit>:
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", 8080))
    IO.print("Listening on http://127.0.0.1:8080")
    serve(1000000n, l)
