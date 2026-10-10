import Base
import ./pow2.bend as P

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("Hello, Bend!")
    IO.print(U32.show(P.pow2!(20n)))
