import Base
import ./router.bend as R

law route_health_get:
  {R.route("GET", ["health"]) == R.RHealth{} : R.Route}

law route_health_post:
  {R.route("POST", ["health"]) == R.RBadMethod{} : R.Route}

law route_health_put:
  {R.route("PUT", ["health"]) == R.RBadMethod{} : R.Route}

law route_health_delete:
  {R.route("DELETE", ["health"]) == R.RBadMethod{} : R.Route}

law route_health_extra:
  {R.route("GET", ["health", "x"]) == R.RNotFound{} : R.Route}

law route_root_get:
  {R.route("GET", []) == R.RNotFound{} : R.Route}

law route_unknown_get:
  {R.route("GET", ["unknown"]) == R.RNotFound{} : R.Route}

law route_path_case_sensitive:
  {R.route("GET", ["People"]) == R.RNotFound{} : R.Route}

law route_people_get:
  {R.route("GET", ["people"]) == R.RList{} : R.Route}

law route_people_post:
  {R.route("POST", ["people"]) == R.RCreate{} : R.Route}

law route_people_put:
  {R.route("PUT", ["people"]) == R.RBadMethod{} : R.Route}

law route_people_delete:
  {R.route("DELETE", ["people"]) == R.RBadMethod{} : R.Route}

law route_people_patch:
  {R.route("PATCH", ["people"]) == R.RBadMethod{} : R.Route}

law route_person_get:
  {R.route("GET", ["people", "abc"]) == R.RGet{"abc"} : R.Route}

law route_person_put:
  {R.route("PUT", ["people", "abc"]) == R.RUpdate{"abc"} : R.Route}

law route_person_delete:
  {R.route("DELETE", ["people", "abc"]) == R.RDelete{"abc"} : R.Route}

law route_person_post:
  {R.route("POST", ["people", "abc"]) == R.RBadMethod{} : R.Route}

law route_person_patch:
  {R.route("PATCH", ["people", "abc"]) == R.RBadMethod{} : R.Route}

law route_person_extra:
  {R.route("GET", ["people", "abc", "extra"]) == R.RNotFound{} : R.Route}

law route_method_lowercase:
  {R.route("get", ["health"]) == R.RBadMethod{} : R.Route}

law method_code_get:
  {R.method_code("GET") == 0 : U32}

law method_code_post:
  {R.method_code("POST") == 1 : U32}

law method_code_put:
  {R.method_code("PUT") == 2 : U32}

law method_code_delete:
  {R.method_code("DELETE") == 3 : U32}

law method_code_patch:
  {R.method_code("PATCH") == 4 : U32}

law method_code_lowercase:
  {R.method_code("get") == 4 : U32}

law kind_empty:
  {R.kind([]) == 0 : U32}

law kind_health:
  {R.kind(["health"]) == 1 : U32}

law kind_people:
  {R.kind(["people"]) == 2 : U32}

law kind_other:
  {R.kind(["unknown"]) == 0 : U32}

law shape_none:
  {R.shape([]) == 0 : U32}

law shape_head_only:
  {R.shape(["people"]) == 0 : U32}

law shape_one_segment:
  {R.shape(["people", "abc"]) == 1 : U32}

law shape_two_segments:
  {R.shape(["people", "abc", "extra"]) == 2 : U32}

law id_of_present:
  {R.id_of(["people", "abc"]) == "abc" : String}

law id_of_absent:
  {R.id_of(["people"]) == "" : String}
