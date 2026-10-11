import Base

# Maps (method, path segments) to a route. Id segments are returned raw;
# the caller validates them.

type Route is Data:
  RHealth{}
  RList{}
  RCreate{}
  RGet{id: String}
  RUpdate{id: String}
  RDelete{id: String}
  RNotFound{}
  RBadMethod{}

# 0 GET, 1 POST, 2 PUT, 3 DELETE, 4 anything else
def method_code.go(g: Bool, p: Bool, u: Bool, d: Bool) -> U32:
  match g:
    case True{}:
      0
    case False{}:
      match p:
        case True{}:
          1
        case False{}:
          match u:
            case True{}:
              2
            case False{}:
              match d:
                case True{}:
                  3
                case False{}:
                  4

def method_code(+m: String) -> U32:
  method_code.go(String.eq(m, "GET"), String.eq(m, "POST"), String.eq(m, "PUT"), String.eq(m, "DELETE"))

# 1 "health", 2 "people", 0 otherwise (or no segment)
def kind.pick(h: Bool, p: Bool) -> U32:
  match h:
    case True{}:
      1
    case False{}:
      match p:
        case True{}:
          2
        case False{}:
          0

def kind(segs: List<&2, String>) -> U32:
  match segs:
    case Nil{}:
      0
    case Con{+h, t}:
      kind.pick(String.eq(h, "health"), String.eq(h, "people"))

# segments after the first: 0 none, 1 exactly one, 2 more
def shape(segs: List<&2, String>) -> U32:
  match segs:
    case Nil{}:
      0
    case Con{h, Nil{}}:
      0
    case Con{h, Con{x, Nil{}}}:
      1
    case _:
      2

# the second segment, or ""
def id_of(segs: List<&2, String>) -> String:
  match segs:
    case Con{h, Con{x, t}}:
      x
    case _:
      ""

def by_id(m: U32, id: String) -> Route:
  match m:
    case 0:
      RGet{id}
    case 2:
      RUpdate{id}
    case 3:
      RDelete{id}
    case _:
      RBadMethod{}

def people_route(shape: U32, m: U32, id: String) -> Route:
  match shape:
    case 0:
      match m:
        case 0:
          RList{}
        case 1:
          RCreate{}
        case _:
          RBadMethod{}
    case 1:
      by_id(m, id)
    case _:
      RNotFound{}

def route.go(kind: U32, shape: U32, m: U32, id: String) -> Route:
  match kind:
    case 1:
      match shape:
        case 0:
          match m:
            case 0:
              RHealth{}
            case _:
              RBadMethod{}
        case _:
          RNotFound{}
    case 2:
      people_route(shape, m, id)
    case _:
      RNotFound{}

# route("GET", ["people", "<id>"]) -> RGet{id}
def route(method: String, +segs: List<&2, String>) -> Route:
  route.go(kind(segs), shape(segs), method_code(method), id_of(segs))
