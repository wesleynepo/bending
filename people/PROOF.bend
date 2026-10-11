import Base
import ./domain.bend as D
import ./LAWS.bend as Laws

def Laws.uuid_lower():
  {==}

def Laws.uuid_upper():
  {==}

def Laws.uuid_mixed_case():
  {==}

def Laws.uuid_no_dashes():
  {==}

def Laws.uuid_underscore_at_dash():
  {==}

def Laws.uuid_non_hex():
  {==}

def Laws.uuid_too_short():
  {==}

def Laws.uuid_too_long():
  {==}

def Laws.uuid_empty():
  {==}

def Laws.date_leap_2024():
  {==}

def Laws.date_nonleap_2023():
  {==}

def Laws.date_leap_century_2000():
  {==}

def Laws.date_century_1900():
  {==}

def Laws.date_april_31():
  {==}

def Laws.date_month_13():
  {==}

def Laws.date_unpadded_month():
  {==}

def Laws.date_plain_ok():
  {==}

def Laws.date_year_lower_bound():
  {==}

def Laws.date_year_below_range():
  {==}

def Laws.date_year_upper_bound():
  {==}

def Laws.date_year_above_range():
  {==}

def Laws.date_day_zero():
  {==}

def Laws.date_no_separators():
  {==}

def Laws.date_non_digit():
  {==}

def Laws.name_simple():
  {==}

def Laws.name_blank():
  {==}

def Laws.name_empty():
  {==}

def Laws.name_max_200():
  {==}

def Laws.name_over_200():
  {==}

def Laws.name_trimmed_length():
  {==}

def Laws.parse_new_ok():
  {==}

def Laws.parse_new_not_json():
  {==}

def Laws.parse_new_not_object():
  {==}

def Laws.parse_new_missing_name():
  {==}

def Laws.parse_new_name_not_string():
  {==}

def Laws.parse_new_blank_name():
  {==}

def Laws.parse_new_missing_birthdate():
  {==}

def Laws.parse_new_birthdate_not_string():
  {==}

def Laws.parse_new_bad_date():
  {==}

def Laws.person_json_encoded():
  {==}

def Laws.people_json_encoded():
  {==}

def Laws.people_json_empty():
  {==}

def Laws.error_json_encoded():
  {==}

def Laws.limit_absent():
  {==}

def Laws.limit_plain():
  {==}

def Laws.limit_zero():
  {==}

def Laws.limit_clamped():
  {==}

def Laws.limit_empty():
  {==}

def Laws.limit_negative():
  {==}

def Laws.limit_trailing_junk():
  {==}

def Laws.limit_leading_space():
  {==}

def Laws.limit_u32_max_exact():
  {==}

def Laws.limit_u32_overflow_saturates():
  {==}

def Laws.limit_huge_saturates():
  {==}
