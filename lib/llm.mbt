///|
/// LLM Gateway - DeepSeek API client utilities

/// Simple string search for a substring
fn string_find(s : String, pat : String) -> Option[Int] {
  if pat.length() == 0 { return Some(0) }
  let max_start = s.length() - pat.length()
  let mut i = 0
  while i <= max_start {
    let mut matched = true
    let mut j = 0
    while j < pat.length() {
      if s[i + j] != pat[j] { matched = false; break }
      j = j + 1
    }
    if matched { return Some(i) }
    i = i + 1
  }
  None
}

/// Simple JSON content extraction from DeepSeek response
fn extract_content(json_str : String) -> Option[String] {
  let prefix = "\"content\":\""
  let start = string_find(json_str, prefix)
  match start {
    None => return None
    Some(s) => {
      let value_start = s + prefix.length()
      let mut result = ""
      let mut i = value_start
      while i < json_str.length() {
        let ch = json_str[i]
        if ch == '\\' && i + 1 < json_str.length() && json_str[i + 1] == '"' {
          result = result + "\""
          i = i + 2
        } else if ch == '"' {
          break
        } else {
          match ch.to_char() {
            Some(c) => result = result + c.to_string()
            None => ()
          }
          i = i + 1
        }
      }
      Some(result)
    }
  }
}

/// Create a chat message
fn ChatMessage::new(role : String, content : String) -> ChatMessage {
  { role: role, content: content }
}
