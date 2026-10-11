import Base
import ../pg/wire.bend as W
import ./http.bend as H

law segments_nested:
  {H.segments("/people/abc") == ["people", "abc"] : List<&2, String>}

law segments_root:
  {H.segments("/") == [] : List<&2, String>}

law segments_trailing_slash:
  {H.segments("/people/") == ["people"] : List<&2, String>}

law query_param_first:
  {H.query_param("limit=5&offset=2", "limit") == Some{"5"} : Maybe<&2, String>}

law query_param_second:
  {H.query_param("limit=5&offset=2", "offset") == Some{"2"} : Maybe<&2, String>}

law query_param_missing:
  {H.query_param("limit=5", "offset") == None{} : Maybe<&2, String>}

law parse_get:
  {H.parse_request(W.utf8("GET /people?limit=5 HTTP/1.1\r\nHost: x\r\n\r\n")) == H.Request{"GET", "/people", "limit=5", "", True{}, 200} : H.Request}

law parse_post_body:
  {H.parse_request(W.utf8("POST /people HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 16\r\n\r\n{\"name\":\"João\"}")) == H.Request{"POST", "/people", "", "{\"name\":\"João\"}", True{}, 200} : H.Request}

law parse_lowercase_content_length:
  {H.parse_request(W.utf8("POST /people HTTP/1.1\r\ncontent-length: 16\r\n\r\n{\"name\":\"João\"}")) == H.Request{"POST", "/people", "", "{\"name\":\"João\"}", True{}, 200} : H.Request}

law parse_bad_content_length:
  {H.parse_request(W.utf8("POST /p HTTP/1.1\r\nContent-Length: abc\r\n\r\n")) == H.Request{"", "", "", "", False{}, 400} : H.Request}

law parse_too_large_content_length:
  {H.parse_request(W.utf8("POST /p HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n")) == H.Request{"", "", "", "", False{}, 413} : H.Request}

law complete_short_body:
  {H.complete(W.utf8("POST /p HTTP/1.1\r\nContent-Length: 16\r\n\r\n{\"name\"")) == False{} : Bool}

law complete_full_body:
  {H.complete(W.utf8("POST /p HTTP/1.1\r\nContent-Length: 16\r\n\r\n{\"name\":\"João\"}")) == True{} : Bool}

law complete_no_headers_end:
  {H.complete(W.utf8("GET / HTTP/1.1\r\nHost: x\r\n")) == False{} : Bool}

law complete_no_body:
  {H.complete(W.utf8("GET / HTTP/1.1\r\nHost: x\r\n\r\n")) == True{} : Bool}

law response_404:
  {W.decode(H.response(404, "{}")) == "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}" : String}

law response_length_is_bytes:
  {W.decode(H.response(200, "João")) == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 5\r\nConnection: close\r\n\r\nJoão" : String}

law response_204:
  {W.decode(H.response(204, "")) == "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" : String}
