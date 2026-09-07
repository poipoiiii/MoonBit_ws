///|
/// DeepSeek chat completion streaming. Replaces hand-written JSON scanning with
/// the standard library @json parser: every SSE `data:` payload is a complete
/// JSON object, so each line is parsed independently. A function-call arguments
/// string is streamed across many chunks; each chunk's arguments fragment is a
/// valid JSON string (@json unescapes it), so we concatenate the unescaped
/// fragments instead of buffering raw escaped text.
///
/// The Json value type lives in the core builtin package, so it is referenced
/// as @builtin.Json; values are inspected with direct ADT pattern matching.

///|
/// One SSE chat-completion payload's tool-call contribution.
priv struct ToolCallFrag {
  id : String
  name : String
  args : String
  has : Bool
}

///|
/// Select between the "delta" and "message" keys of a choice object.
fn get_message(choice : @builtin.Json) -> @builtin.Json? {
  match choice {
    Object(obj) =>
      match obj.get("delta") {
        Some(d) => Some(d)
        None => obj.get("message")
      }
    _ => None
  }
}

///|
/// Convert a Json value to an int when it is a number.
fn num_of(v : @builtin.Json?) -> Int? {
  match v {
    None => None
    Some(x) =>
      match x {
        Number(n, ..) => Some(n.to_int())
        _ => None
      }
  }
}

///|
/// Extract token usage from a streamed payload, or None.
fn stream_usage(j : @builtin.Json) -> (Int, Int)? {
  match j {
    Object(obj) =>
      match obj.get("usage") {
        None => None
        Some(u) =>
          match u {
            Object(uo) => {
              let pt = num_of(uo.get("prompt_tokens"))
              let ct = num_of(uo.get("completion_tokens"))
              match (pt, ct) {
                (Some(p), Some(c)) => Some((p, c))
                _ => None
              }
            }
            _ => None
          }
      }
    _ => None
  }
}

///|
/// Extract the streamed text content from a single choice object.
fn choice_content(choice : @builtin.Json) -> String? {
  match get_message(choice) {
    None => None
    Some(m) =>
      match m {
        Object(mo) =>
          match mo.get("content") {
            None => None
            Some(v) =>
              match v {
                String(s) => Some(s)
                _ => None
              }
          }
        _ => None
      }
  }
}

///|
/// Extract the streamed text content from a payload, or None.
fn stream_content(j : @builtin.Json) -> String? {
  match j {
    Object(obj) =>
      match obj.get("choices") {
        None => None
        Some(c) =>
          match c {
            Array(a) =>
              if a.length() == 0 {
                None
              } else {
                choice_content(a[0])
              }
            _ => None
          }
      }
    _ => None
  }
}

///|
/// Read a JSON string value, or "".
fn str_of(v : @builtin.Json?) -> String {
  match v {
    None => ""
    Some(x) =>
      match x {
        String(s) => s
        _ => ""
      }
  }
}

///|
/// Extract any tool-call fragments present in a payload.
fn stream_tool_calls(j : @builtin.Json) -> ToolCallFrag {
  let mut id = ""
  let mut name = ""
  let mut args = ""
  let mut has = false
  let choices : Array[@builtin.Json] = match j {
    Object(obj) =>
      match obj.get("choices") {
        None => []
        Some(c) =>
          match c {
            Array(a) => a
            _ => []
          }
      }
    _ => []
  }
  for choice in choices {
    match get_message(choice) {
      None => continue
      Some(m) =>
        match m {
          Object(mo) =>
            match mo.get("tool_calls") {
              None => ()
              Some(tcs) =>
                match tcs {
                  Array(list) =>
                    for tc in list {
                      has = true
                      match tc {
                        Object(tco) => {
                          let tid = str_of(tco.get("id"))
                          if tid.length() > 0 && id.length() == 0 {
                            id = tid
                          }
                          match tco.get("function") {
                            None => ()
                            Some(f) =>
                              match f {
                                Object(fo) => {
                                  let fname = str_of(fo.get("name"))
                                  if fname.length() > 0 && name.length() == 0 {
                                    name = fname
                                  }
                                  args = args + str_of(fo.get("arguments"))
                                }
                                _ => ()
                              }
                          }
                        }
                        _ => ()
                      }
                    }
                  _ => ()
                }
            }
          _ => ()
        }
    }
  }
  { id, name, args, has }
}

///|
/// Stream one completion request from DeepSeek, forwarding content to the client.
/// Returns (full_response, tool_name, tool_args, tool_call_id, prompt_tokens, completion_tokens).
/// tool_name/tool_args/tool_call_id are non-empty when the model issued a native function call.
async fn stream_completion(
  ctx : RuntimeContext,
  body_str : String,
  conn : @http.ServerConnection,
) -> (String, String, String, String, Int, Int) {
  let url = "https://api.deepseek.com/v1/chat/completions"
  let req_headers = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " + ctx.api_key),
  ])

  let mut full_response = ""
  let mut tool_name = ""
  let mut tool_args = ""
  let mut tool_call_id = ""
  let mut prompt_tokens = 0
  let mut completion_tokens = 0

  try {
    let client = @http.post_stream(url, headers=req_headers)
    defer client.close()

    client.write(body_str)
    client.flush()
    let resp = client.end_request()

    if resp.code != 200 {
      conn.write_string("data: Error: DeepSeek returned \{resp.code}\n\n")
      return (
        full_response, tool_name, tool_args, tool_call_id, prompt_tokens, completion_tokens,
      )
    }

    // Forward streaming chunks from DeepSeek to client. SSE events can be split
    // across read_some() calls and multi-byte UTF-8 chars can be split at buffer
    // boundaries, so decode lossy and line-buffer.
    let mut buf = ""
    while client.read_some() is Some(data) {
      buf = buf + @utf8.decode_lossy(data)
      while true {
        match string_find(buf, "\n") {
          None => break
          Some(pos) => {
            let line = buf[0:pos].to_owned()
            buf = buf[pos + 1:].to_owned()
            if line.has_prefix("data: ") {
              let payload = line[6:].to_owned()
              if payload == "[DONE]" {
                return (
                  full_response, tool_name, tool_args, tool_call_id, prompt_tokens,
                  completion_tokens,
                )
              }
              match try_parse_json(payload) {
                None => ()
                Some(j) => {
                  // Token usage
                  match stream_usage(j) {
                    Some((pt, ct)) => {
                      prompt_tokens = pt
                      completion_tokens = ct
                    }
                    None => ()
                  }
                  // Streamed content
                  match stream_content(j) {
                    Some(content) => {
                      full_response = full_response + content
                      conn.write_string("data: " + content + "\n\n")
                    }
                    None => ()
                  }
                  // Tool-call fragments
                  let tc = stream_tool_calls(j)
                  if tc.has {
                    if tool_call_id.length() == 0 && tc.id.length() > 0 {
                      tool_call_id = tc.id
                    }
                    if tool_name.length() == 0 && tc.name.length() > 0 {
                      tool_name = tc.name
                    }
                    tool_args = tool_args + tc.args
                  }
                }
              }
            }
          }
        }
      }
      conn.flush()
    }
    // Stream ended without [DONE]: process the final partial line, if any
    if buf.length() > 0 && buf.has_prefix("data: ") {
      let payload = buf[6:].to_owned()
      match try_parse_json(payload) {
        None => ()
        Some(j) => {
          match stream_content(j) {
            Some(content) => {
              full_response = full_response + content
              conn.write_string("data: " + content + "\n\n")
            }
            None => ()
          }
          let tc = stream_tool_calls(j)
          if tc.has {
            if tool_call_id.length() == 0 && tc.id.length() > 0 {
              tool_call_id = tc.id
            }
            if tool_name.length() == 0 && tc.name.length() > 0 {
              tool_name = tc.name
            }
            tool_args = tool_args + tc.args
          }
        }
      }
    }
  } catch {
    _ => conn.write_string("data: Error: Failed to connect to DeepSeek\n\n")
  }
  (
    full_response, tool_name, tool_args, tool_call_id, prompt_tokens, completion_tokens,
  )
}
