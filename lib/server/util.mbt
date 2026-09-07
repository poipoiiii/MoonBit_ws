///|
/// Shared string / JSON helpers for the HTTP layer.
/// JSON body and SSE payload parsing is done via the standard library @json
/// package instead of hand-written scanners.

///|
/// Find the first occurrence of a substring (byte index), or None.
fn string_find(s : String, pat : String) -> Int? {
  if pat.length() == 0 {
    return Some(0)
  }
  let max_start = s.length() - pat.length()
  let mut i = 0
  while i <= max_start {
    let mut matched = true
    let mut j = 0
    while j < pat.length() {
      if s[i + j] != pat[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Escape string for JSON (handle quotes, backslash, and control characters).
/// Returns the escaped content WITHOUT surrounding quotes, matching the
/// concatenation-based builders used by the response handlers.
fn json_escape(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let ch = s[i]
    if ch == 34 {
      result = result + "\\\""
    } else if ch == 92 {
      result = result + "\\\\"
    } else if ch == 10 {
      result = result + "\\n"
    } else if ch == 13 {
      result = result + "\\r"
    } else if ch == 9 {
      result = result + "\\t"
    } else if ch < 32 {
      ()
    } else {
      match ch.to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
    }
    i = i + 1
  }
  result
}

///|
/// Parse a complete JSON text into a Json value, returning None on invalid input.
fn try_parse_json(s : String) -> @builtin.Json? {
  Some(@json.parse(s)) catch {
    _ => None
  }
}

///|
/// Read a field from a request body JSON object as a string.
/// Handles both string and number JSON fields. Returns None on parse error,
/// missing key, or a value that is neither a string nor a number.
fn json_field_string(body : String, key : String) -> String? {
  match try_parse_json(body) {
    None => None
    Some(json) =>
      match json {
        Object(obj) =>
          match obj.get(key) {
            None => None
            Some(v) =>
              match v {
                String(str) => Some(str)
                Number(n, ..) => Some(n.to_string())
                _ => None
              }
          }
        _ => None
      }
  }
}

///|
/// Parse hex char to int (0-15)
fn hex_to_int(ch : UInt16) -> Int {
  if ch >= 48 && ch <= 57 {
    ch.to_int() - 48
  } else if ch >= 97 && ch <= 102 {
    ch.to_int() - 87
  } else if ch >= 65 && ch <= 70 {
    ch.to_int() - 55
  } else {
    0
  }
}

///|
/// Extract query parameter value from a query string.
fn extract_query_param(query : String, param : String) -> String? {
  let pairs : Array[String] = []
  for p in query.split("&") {
    pairs.push(p.to_owned())
  }
  for pair in pairs {
    let eq_pos = string_find(pair, "=")
    match eq_pos {
      None => continue
      Some(pos) => {
        let key = pair[:pos].to_owned()
        if key == param {
          let value = pair[pos + 1:].to_owned()
          return Some(decode_url(value))
        }
      }
    }
  }
  None
}

///|
/// Simple URL decode (handles %XX and +), preserving UTF-8 multi-byte sequences.
fn decode_url(s : String) -> String {
  let bytes : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int()
    if ch == 43 {
      bytes.push((32 : Byte))
      i = i + 1
    } else if ch == 37 && i + 2 < s.length() {
      let code = hex_to_int(s[i + 1]) * 16 + hex_to_int(s[i + 2])
      bytes.push(code.to_byte())
      i = i + 3
    } else {
      bytes.push(ch.to_byte())
      i = i + 1
    }
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => s
  }
}

///|
/// Parse temperature string to float.
fn parse_temperature(s : String) -> Float {
  let parts = s.split(".")
  let mut int_val = 0
  let int_part = match parts.next() {
    Some(p) => p.to_owned()
    None => return Float::from_int(0)
  }
  let mut neg = false
  let mut j = 0
  if int_part.length() > 0 && int_part[0] == '-' {
    neg = true
    j = 1
  }
  while j < int_part.length() {
    let c = int_part[j]
    if c >= '0' && c <= '9' {
      int_val = int_val * 10 + (c.to_int() - 48)
    } else {
      return Float::from_int(0)
    }
    j = j + 1
  }
  match parts.next() {
    Some(frac) => {
      let frac_owned = frac.to_owned()
      let mut divisor = 1
      let mut frac_val = 0
      let mut k = 0
      while k < frac_owned.length() {
        let c = frac_owned[k]
        if c >= '0' && c <= '9' {
          divisor = divisor * 10
          frac_val = frac_val * 10 + (c.to_int() - 48)
        }
        k = k + 1
      }
      let result = Float::from_int(int_val) +
        Float::from_int(frac_val) / Float::from_int(divisor)
      if neg {
        -result
      } else {
        result
      }
    }
    None => {
      let result = Float::from_int(int_val)
      if neg {
        -result
      } else {
        result
      }
    }
  }
}
