///|
/// LLM Gateway - DeepSeek API client utilities

///|
/// Simple string search for a substring
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
/// Create a chat message
pub fn ChatMessage::new(role : String, content : String) -> ChatMessage {
  { role, content, }
}
