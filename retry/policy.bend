import Base

# Pure part of the retry library: policy, backoff schedule, jitter, and which
# errors count as transient. The IO loop lives in retry.bend.
#
# Attempts are numbered from 1. After failed attempt n the caller sleeps
# `delay(p, n)` (optionally jittered) before attempt n+1.

type Policy is Data:
  Policy{
    max_attempts: U32,   # total tries including the first; 1 = no retry
    base_ms: U32,        # delay after the first failure
    max_ms: U32,         # delays never exceed this
    factor: U32,         # multiplier per attempt (2 = exponential doubling, 1 = constant)
    jitter: Bool,        # full jitter: sleep a uniform-ish value in 0..delay
    budget_ms: U32       # give up once this much time has elapsed (0 = no time limit)
  }

def default() -> Policy:
  Policy{5, 100, 2000, 2, True{}, 0}

def min_u32.go(lt: Bool, a: U32, b: U32) -> U32:
  match lt:
    case True{}:
      a
    case False{}:
      b

def min_u32(+a: U32, +b: U32) -> U32:
  min_u32.go((a < b : U32), a, b)

# a * f, saturating at cap
def mul_cap.go(over: Bool, a: U32, f: U32, cap: U32) -> U32:
  match over:
    case True{}:
      cap
    case False{}:
      min_u32((a * f : U32), cap)

def mul_cap(+a: U32, +f: U32, +cap: U32) -> U32:
  mul_cap.go((f > 0 : U32) && (a > (cap / f : U32) : U32), a, f, cap)

def grow(n: Nat, d: U32, +f: U32, +cap: U32) -> U32:
  match n:
    case 0n:
      min_u32(d, cap)
    case 1n+p:
      grow(p, mul_cap(d, f, cap), f, cap)

# Delay after failed attempt n (n >= 1): min(max_ms, base_ms * factor^(n-1)), never overflowing.
def delay(p: Policy, attempt: U32) -> U32:
  match p:
    case Policy{maxa, base, cap, factor, jit, budget}:
      grow(U32.to_nat((attempt - 1 : U32)), base, factor, cap)

def jittered.go(max: Bool, +d: U32, r: U32) -> U32:
  match max:
    case True{}:
      r
    case False{}:
      (r % (d + 1 : U32) : U32)

# Full jitter: map a random 32-bit value r into 0..d inclusive.
def jittered(+d: U32, r: U32) -> U32:
  jittered.go(U32.is_eq(d, 4294967295), d, r)

def sleep_ms.go(jit: Bool, d: U32, r: U32) -> U32:
  match jit:
    case True{}:
      jittered(d, r)
    case False{}:
      d

# What to actually sleep after failed attempt n, given a random value r.
def sleep_for.go(p: Policy, jit: Bool, attempt: U32, r: U32) -> U32:
  sleep_ms.go(jit, delay(p, attempt), r)

def jitter_on(p: Policy) -> Bool:
  match p:
    case Policy{maxa, base, cap, factor, jit, budget}:
      jit

def sleep_for(+p: Policy, attempt: U32, r: U32) -> U32:
  sleep_for.go(p, jitter_on(p), attempt, r)

def over_budget(+budget: U32, elapsed: U32) -> Bool:
  (budget > 0 : U32) && (elapsed >= budget : U32)

# Should we stop after failed attempt n with `elapsed` ms spent so far?
def exhausted(p: Policy, attempt: U32, elapsed_ms: U32) -> Bool:
  match p:
    case Policy{maxa, base, cap, factor, jit, budget}:
      (attempt >= maxa : U32) || over_budget(budget, elapsed_ms)

# Errors worth retrying, judged from the message our clients produce:
# connection-level failures and transient PostgreSQL SQLSTATE classes.
def is_transient(+msg: String) -> Bool:
  String.contains(msg, "connect failed") || String.contains(msg, "send failed")
    || String.contains(msg, "receive failed") || String.contains(msg, "connection closed")
    || String.contains(msg, "timed out") || String.contains(msg, "timeout")
    || String.starts_with(msg, "08") || String.starts_with(msg, "57P0")
    || String.starts_with(msg, "53300") || String.starts_with(msg, "40001")
    || String.starts_with(msg, "40P01")

def always(msg: String) -> Bool:
  True{}

def never(msg: String) -> Bool:
  False{}
