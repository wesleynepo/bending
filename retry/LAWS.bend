import Base
import ./policy.bend as P

law delay_exp_1:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 1) == 100 : U32}

law delay_exp_2:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 2) == 200 : U32}

law delay_exp_3:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 3) == 400 : U32}

law delay_exp_4:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 4) == 800 : U32}

law delay_exp_5:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 5) == 1600 : U32}

law delay_exp_6_capped:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 6) == 2000 : U32}

law delay_exp_7_capped:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 7) == 2000 : U32}

law delay_exp_8_capped:
  {P.delay(P.Policy{5, 100, 2000, 2, False{}, 0}, 8) == 2000 : U32}

law delay_const_1:
  {P.delay(P.Policy{5, 100, 2000, 1, False{}, 0}, 1) == 100 : U32}

law delay_const_4:
  {P.delay(P.Policy{5, 100, 2000, 1, False{}, 0}, 4) == 100 : U32}

law delay_const_8:
  {P.delay(P.Policy{5, 100, 2000, 1, False{}, 0}, 8) == 100 : U32}

law delay_factor3_1:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 1) == 10 : U32}

law delay_factor3_2:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 2) == 30 : U32}

law delay_factor3_3:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 3) == 90 : U32}

law delay_factor3_4:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 4) == 270 : U32}

law delay_factor3_5:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 5) == 810 : U32}

law delay_factor3_6_capped:
  {P.delay(P.Policy{5, 10, 1000, 3, False{}, 0}, 6) == 1000 : U32}

law delay_base_above_cap_1:
  {P.delay(P.Policy{5, 5000, 2000, 2, False{}, 0}, 1) == 2000 : U32}

law delay_base_above_cap_2:
  {P.delay(P.Policy{5, 5000, 2000, 2, False{}, 0}, 2) == 2000 : U32}

law delay_factor0_1:
  {P.delay(P.Policy{5, 100, 2000, 0, False{}, 0}, 1) == 100 : U32}

law delay_factor0_2:
  {P.delay(P.Policy{5, 100, 2000, 0, False{}, 0}, 2) == 0 : U32}

law delay_factor0_3:
  {P.delay(P.Policy{5, 100, 2000, 0, False{}, 0}, 3) == 0 : U32}

law delay_huge_1:
  {P.delay(P.Policy{5, 4000000000, 4294967295, 4000000000, False{}, 0}, 1) == 4000000000 : U32}

law delay_huge_2_capped:
  {P.delay(P.Policy{5, 4000000000, 4294967295, 4000000000, False{}, 0}, 2) == 4294967295 : U32}

law delay_huge_3_capped:
  {P.delay(P.Policy{5, 4000000000, 4294967295, 4000000000, False{}, 0}, 3) == 4294967295 : U32}

law delay_max_factor_max_base_2:
  {P.delay(P.Policy{5, 1, 4294967295, 4294967295, False{}, 0}, 2) == 4294967295 : U32}

law delay_max_factor_max_base_3:
  {P.delay(P.Policy{5, 1, 4294967295, 4294967295, False{}, 0}, 3) == 4294967295 : U32}

law default_delay_1:
  {P.delay(P.default(), 1) == 100 : U32}

law default_delay_3:
  {P.delay(P.default(), 3) == 400 : U32}

law default_delay_6_capped:
  {P.delay(P.default(), 6) == 2000 : U32}

law jittered_d0:
  {P.jittered(0, 12345) == 0 : U32}

law jittered_d100_r250:
  {P.jittered(100, 250) == 48 : U32}

law jittered_d100_r100:
  {P.jittered(100, 100) == 100 : U32}

law jittered_d100_r0:
  {P.jittered(100, 0) == 0 : U32}

law jittered_d_max_returns_r:
  {P.jittered(4294967295, 12345) == 12345 : U32}

law sleep_for_jitter_on:
  {P.sleep_for(P.Policy{5, 100, 2000, 2, True{}, 0}, 2, 250) == 49 : U32}

law sleep_for_jitter_on_r0:
  {P.sleep_for(P.Policy{5, 100, 2000, 2, True{}, 0}, 1, 0) == 0 : U32}

law sleep_for_jitter_off:
  {P.sleep_for(P.Policy{5, 100, 2000, 2, False{}, 0}, 2, 250) == 200 : U32}

law sleep_for_jitter_off_ignores_r:
  {P.sleep_for(P.Policy{5, 100, 2000, 2, False{}, 0}, 1, 0) == 100 : U32}

law default_sleep_for_jittered:
  {P.sleep_for(P.default(), 1, 50) == 50 : U32}

law jitter_on_default:
  {P.jitter_on(P.default()) == True{} : Bool}

law jitter_off_policy:
  {P.jitter_on(P.Policy{5, 100, 2000, 2, False{}, 0}) == False{} : Bool}

law exhausted_below_max:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 0}, 4, 0) == False{} : Bool}

law exhausted_at_max:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 0}, 5, 0) == True{} : Bool}

law exhausted_above_max:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 0}, 6, 0) == True{} : Bool}

law exhausted_max_1_no_retry:
  {P.exhausted(P.Policy{1, 100, 2000, 2, False{}, 0}, 1, 0) == True{} : Bool}

law exhausted_no_budget_huge_elapsed:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 0}, 1, 4294967295) == False{} : Bool}

law exhausted_budget_not_reached:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 1000}, 1, 999) == False{} : Bool}

law exhausted_budget_reached:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 1000}, 1, 1000) == True{} : Bool}

law exhausted_budget_exceeded:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 1000}, 1, 5000) == True{} : Bool}

law exhausted_attempts_before_budget:
  {P.exhausted(P.Policy{5, 100, 2000, 2, False{}, 1000}, 5, 0) == True{} : Bool}

law default_exhausted_4:
  {P.exhausted(P.default(), 4, 0) == False{} : Bool}

law default_exhausted_5:
  {P.exhausted(P.default(), 5, 0) == True{} : Bool}

law default_exhausted_no_budget:
  {P.exhausted(P.default(), 4, 4294967295) == False{} : Bool}

law transient_connect_failed:
  {P.is_transient("connect failed") == True{} : Bool}

law transient_send_failed:
  {P.is_transient("send failed") == True{} : Bool}

law transient_receive_failed:
  {P.is_transient("receive failed") == True{} : Bool}

law transient_connection_closed:
  {P.is_transient("connection closed by server") == True{} : Bool}

law transient_sqlstate_08:
  {P.is_transient("08006: connection failure") == True{} : Bool}

law transient_sqlstate_57p03:
  {P.is_transient("57P03: the database system is starting up") == True{} : Bool}

law transient_sqlstate_53300:
  {P.is_transient("53300: too many connections") == True{} : Bool}

law transient_sqlstate_40001:
  {P.is_transient("40001: could not serialize") == True{} : Bool}

law transient_sqlstate_40p01:
  {P.is_transient("40P01: deadlock detected") == True{} : Bool}

law transient_request_timed_out:
  {P.is_transient("request timed out") == True{} : Bool}

law permanent_password:
  {P.is_transient("28P01: password authentication failed") == False{} : Bool}

law permanent_relation_missing:
  {P.is_transient("42P01: relation \"x\" does not exist") == False{} : Bool}

law permanent_duplicate_key:
  {P.is_transient("23505: duplicate key") == False{} : Bool}

law permanent_empty:
  {P.is_transient("") == False{} : Bool}

law permanent_not_found:
  {P.is_transient("not found") == False{} : Bool}

law always_true:
  {P.always("anything") == True{} : Bool}

law always_true_empty:
  {P.always("") == True{} : Bool}

law never_false:
  {P.never("anything") == False{} : Bool}

law never_false_empty:
  {P.never("") == False{} : Bool}
