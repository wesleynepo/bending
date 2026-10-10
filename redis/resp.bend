import Base

# RESP2 (Redis wire protocol): pure encoding of commands and parsing of replies.
# Lengths are counted in characters, so keys/values must be ASCII.

type Reply is Data:
  Simple{text: String}   # +OK
  Err{text: String}      # -ERR ...
  Int{text: String}      # :42   (kept as text, may be negative)
  Bulk{text: String}     # $5\r\nhello
  Null{}                 # $-1
  Bad{}                  # unparsable or unsupported (e.g. arrays)

def bulk(+s: String) -> String:
  "$" ++ Nat.show(String.length(s)) ++ "\r\n" ++ s ++ "\r\n"

def encode.args(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      bulk(h) ++ encode.args(t)

# A command is an array of bulk strings: encode(["SET", "k", "v"]).
def encode(+args: List<&2, String>) -> String:
  "*" ++ Nat.show(List.length(&2, String, args)) ++ "\r\n" ++ encode.args(args)

# Splits at the first CR: (line, text after the CR).
def take_line.fin(cr: Bool, h: Char, t: String, rec: String & String) -> String & String:
  match cr:
    case True{}:
      (SNil{}, t)
    case False{}:
      match rec:
        case (l, r):
          (SCon{h, l}, r)

def take_line(s: String) -> String & String:
  match s:
    case SNil{}:
      (SNil{}, SNil{})
    case SCon{+h, t}:
      +t2 = t
      take_line.fin(Char.is_eq(h, '\r'), h, t2, take_line(t2))

def parse.bulk.body(rest: String, len: Maybe<&2, Nat>) -> Reply:
  match len:
    case None{}:
      Bad{}
    case Some{n}:
      Bulk{String.take(String.drop(rest, 1n), n)}

def parse.bulk(line: String, rest: String, neg: Bool) -> Reply:
  match neg:
    case True{}:
      Null{}
    case False{}:
      parse.bulk.body(rest, Nat.read(line))

def parse.tag(+line: String, rest: String, tag: U32) -> Reply:
  match tag:
    case 43:
      Simple{line}
    case 45:
      Err{line}
    case 58:
      Int{line}
    case 36:
      parse.bulk(line, rest, String.starts_with(line, "-"))
    case _:
      Bad{}

def parse.line(h: Char, lr: String & String) -> Reply:
  match lr:
    case (line, rest):
      parse.tag(line, rest, Char.to_u32(h))

# Parses one reply from the text received from the server.
def parse(s: String) -> Reply:
  match s:
    case SNil{}:
      Bad{}
    case SCon{h, t}:
      parse.line(h, take_line(t))
