import Base
import ./policy.bend as P

# IO retry loop. The action `f` is a template so it can run many times (closures
# are affine). `f` takes a reusable context value and answers a Result; `retryable`
# is a template that says which error messages are worth another attempt.
#
# Attempts are numbered from 1. After a retryable failure of attempt n the loop
# sleeps P.sleep_for(policy, n, r) ms before attempt n+1, unless the attempt limit
# or the time budget (checked against the sleep too) says to give up.

# Loop state. Pending: attempt `attempt` runs next, after sleeping `wait` ms.
# Settled: the final answer.
type RetrySt<-A: Type> is Type:
  RetryPending{attempt: U32, start: Nat, pol: P.Policy, wait: U32}
  RetrySettled{res: Result<&1, &1, String, A>}

# What to do after a failed attempt.
type RetryVerdict is Data:
  RetryStop{}          # not retryable: return the error unchanged
  RetryGive{}          # attempts or budget exhausted
  RetryPause{ms: U32}  # sleep ms, then try again

# Elapsed milliseconds (IO.now answers ms), saturating at the U32 maximum.
def elapsed_ms(now: Nat, start: Nat) -> U32:
  U32.from_nat(Nat.min(Nat.sub(now, start), 4294967295n))

# Random value for jitter; a failed random read counts as 0.
def rnd_value.pick(rr: Result<&1, &1, U32 & String, U32>) -> U32:
  match rr:
    case Done{v}:
      v
    case Fail{e}:
      0

def rnd_value(rr: Result<&1, &1, U32 & String, U32>) -> U32:
  rnd_value.pick(rr)

# True when sleeping `delay` after `elapsed` would overrun the budget.
def overruns(+pol: P.Policy, elapsed: U32, delay: U32) -> Bool:
  match pol:
    case P.Policy{maxa, base, cap, factor, jit, budget}:
      (budget > 0 : U32) && ((elapsed + delay : U32) > budget : U32)

def pause.go(over: Bool, delay: U32) -> RetryVerdict:
  match over:
    case True{}:
      RetryGive{}
    case False{}:
      RetryPause{delay}

def after_ok.go(ex: Bool, +pol: P.Policy, attempt: U32, elapsed: U32, rnd: U32) -> RetryVerdict:
  match ex:
    case True{}:
      RetryGive{}
    case False{}:
      +delay = P.sleep_for(pol, attempt, rnd)
      pause.go(overruns(pol, elapsed, delay), delay)

def verdict.go(ok: Bool, ex: Bool, +pol: P.Policy, attempt: U32, elapsed: U32, rnd: U32) -> RetryVerdict:
  match ok:
    case True{}:
      after_ok.go(ex, pol, attempt, elapsed, rnd)
    case False{}:
      RetryStop{}

# ok: the error is retryable. ex: P.exhausted (attempt limit or budget already spent).
def verdict(ok: Bool, ex: Bool, +pol: P.Policy, attempt: U32, elapsed: U32, rnd: U32) -> RetryVerdict:
  verdict.go(ok, ex, pol, attempt, elapsed, rnd)

# Turns a verdict on a failed attempt into the next state.
def settle_fail(-A: Type, v: RetryVerdict, e: String, attempt: U32, start: Nat, pol: P.Policy) -> RetrySt<A>:
  match v:
    case RetryStop{}:
      RetrySettled{Fail{e}}
    case RetryGive{}:
      RetrySettled{Fail{"gave up after " ++ U32.show(attempt) ++ " attempts: " ++ e}}
    case RetryPause{ms}:
      RetryPending{(attempt + 1 : U32), start, pol, ms}

# Pure step: judges attempt `attempt` (its result r, the random value rr, the clock now).
def step(~A: Type, ~retryable: String -> Bool, st: RetrySt<A>, r: Result<&1, &1, String, A>,
  rr: Result<&1, &1, U32 & String, U32>, +now: Nat) -> RetrySt<A>:
  match st:
    case RetrySettled{res}:
      RetrySettled{res}
    case RetryPending{+attempt, +start, +pol, wait}:
      match r:
        case Done{a}:
          RetrySettled{Done{a}}
        case Fail{+e}:
          settle_fail(A, verdict(retryable(e), P.exhausted(pol, attempt, elapsed_ms(now, start)),
            pol, attempt, elapsed_ms(now, start), rnd_value(rr)), e, attempt, start, pol)

# The loop. Fuel = max attempts. Sleeps happen at the top of each pending attempt,
# so the first attempt runs with wait = 0.
def go(~A: Type, ~C: Data, ~f: C -> IO(Result<&1, &1, String, A>), ~retryable: String -> Bool,
  fuel: Nat, +ctx: C, st: RetrySt<A>) -> IO(Result<&1, &1, String, A>):
  match fuel:
    case 0n:
      match st:
        case RetrySettled{res}:
          IO.pure(Result<&1, &1, String, A>, res)
        case RetryPending{attempt, start, pol, wait}:
          IO.pure(Result<&1, &1, String, A>, Fail{"retry: no attempts left"})
    case 1n+k:
      match st:
        case RetrySettled{res}:
          IO.pure(Result<&1, &1, String, A>, res)
        case RetryPending{+attempt, +start, +pol, +wait}:
          do IO<Result<&1, &1, String, A>>:
            IO.sleep(wait)
            r : Result<&1, &1, String, A> <- f(ctx)
            rr : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
            now : Nat <- IO.now()
            next : RetrySt<A> = step(~A, ~retryable, RetryPending{attempt, start, pol, 0}, r, rr, now)
            go(~A, ~C, ~f, ~retryable, k, ctx, next)

# Attempt limit as fuel; at least one attempt always runs.
def fuel_of.go(n: U32) -> Nat:
  match n:
    case 0:
      1n
    case _:
      U32.to_nat(n)

def fuel_of(+pol: P.Policy) -> Nat:
  match pol:
    case P.Policy{maxa, base, cap, factor, jit, budget}:
      fuel_of.go(maxa)

# Retries f(ctx) per `policy` until it answers Done, a non-retryable error occurs,
# or the policy is exhausted (then Fail "gave up after N attempts: <last error>").
def run(~A: Type, ~C: Data, ~f: C -> IO(Result<&1, &1, String, A>), ~retryable: String -> Bool,
  +policy: P.Policy, +ctx: C) -> IO(Result<&1, &1, String, A>):
  do IO<Result<&1, &1, String, A>>:
    t0 : Nat <- IO.now()
    go(~A, ~C, ~f, ~retryable, fuel_of(policy), ctx, RetryPending{1, t0, policy, 0})

# P.is_transient with a plain (non-affine) argument, so it can serve as ~retryable.
def transient(msg: String) -> Bool:
  P.is_transient(msg)

# run with P.default() and P.is_transient.
def run_default(~A: Type, ~C: Data, ~f: C -> IO(Result<&1, &1, String, A>), +ctx: C) -> IO(Result<&1, &1, String, A>):
  run(~A, ~C, ~f, ~transient, P.default(), ctx)
