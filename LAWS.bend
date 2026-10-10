import Base
import ./pow2.bend as P

law pow2_zero:
  {P.pow2(0n) == 1 : U32}

law pow2_three:
  {P.pow2(3n) == 8 : U32}
