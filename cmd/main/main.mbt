///|
/// AI Agent Runtime - HTTP Server with SSE support
/// Uses DeepSeek v4-pro via environment variable DEEPSEEK_API_KEY

/// Main entry point
async fn main {
  // Load configuration from environment variables
  let api_key = match @env.get_env_var("DEEPSEEK_API_KEY") {
    Some(key) => key
    None => {
      println("Error: DEEPSEEK_API_KEY environment variable not set")
      println("Please set it before running: $env:DEEPSEEK_API_KEY=\"your-key\"")
      return
    }
  }
  
  let model = @env.get_env_var("DEEPSEEK_MODEL").unwrap_or("deepseek-chat")
  let port_str = @env.get_env_var("PORT").unwrap_or("8080")
  let port = parse_port(port_str)
  let data_dir = @env.get_env_var("DATA_DIR").unwrap_or("static/data")
  let cors_origin = @env.get_env_var("CORS_ORIGIN").unwrap_or("*")
  
  // Build data file paths
  let agents_file = data_dir + "/agents.csv"
  let tools_file = data_dir + "/tools.csv"
  
  println("Starting AI Agent Runtime...")
  println("Model: \{model}")
  println("Port: \{port}")
  println("Data: \{data_dir}")
  
  // Load data from CSV files
  let agent_manager = match @lib.AgentManager::load(agents_file) {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} agents")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load agents: \{e}")
      @lib.AgentManager::new(Map([], capacity=0))
    }
  }
  
  let tool_registry = match @lib.ToolRegistry::load(tools_file) {
    Ok(reg) => {
      let all = reg.list_all()
      println("Loaded \{all.length()} tools (enabled: \{reg.list_enabled().length()})")
      reg
    }
    Err(e) => {
      println("Warning: Failed to load tools: \{e}")
      @lib.ToolRegistry::new(Map([], capacity=0))
    }
  }
  
  // Create runtime context
  let ctx = RuntimeContext::{
    api_key: api_key,
    model: model,
    agent_manager: agent_manager,
    tool_registry: tool_registry,
    cors_origin: cors_origin,
  }
  
  // Start HTTP server
  println("Server running at http://localhost:\{port}")
  let addr = @socket.Addr::resolve("0.0.0.0", port=port)
  @http.Server::new(addr).run_forever(
    async fn(request : @http.Request, _body : &@io.Reader, conn : @http.ServerConnection) {
      handle_request(ctx, request, conn)
    },
    allow_failure=true,
  )
}

/// Runtime context shared across requests
struct RuntimeContext {
  api_key : String
  model : String
  agent_manager : @lib.AgentManager
  tool_registry : @lib.ToolRegistry
  cors_origin : String
}

/// Route requests to appropriate handlers
async fn handle_request(
  ctx : RuntimeContext,
  request : @http.Request,
  conn : @http.ServerConnection
) -> Unit {
  let path = request.path
  let meth = request.meth
  
  // Simple routing
  if meth is Get {
    if path == "/" || path == "" {
      handle_index(conn)
    } else if path == "/api/agents" {
      handle_agents_json(ctx, conn)
    } else if path == "/api/tools" {
      handle_tools_json(ctx, conn)
    } else if path.starts_with("/api/chat") {
      handle_chat_sse(ctx, path, conn)
    } else {
      conn.send_response(404, "Not Found", extra_headers={ "Content-Type": "text/plain" })
      conn.write_string("404 Not Found")
    }
  } else {
    conn.send_response(405, "Method Not Allowed", extra_headers={ "Content-Type": "text/plain" })
    conn.write_string("405 Method Not Allowed")
  }
}

/// Serve the main HTML page
async fn handle_index(conn : @http.ServerConnection) -> Unit {
  conn.send_response(200, "OK", extra_headers={ "Content-Type": "text/html; charset=utf-8" })
  conn.write_string(index_html())
}

/// Handle /api/agents - return JSON list of agents
async fn handle_agents_json(ctx : RuntimeContext, conn : @http.ServerConnection) -> Unit {
  let agents = ctx.agent_manager.list_all()
  let json_parts = agents.map(fn(a) {
    "{\"id\":\"" + a.id + "\",\"name\":\"" + a.name + "\",\"model\":\"" + a.model + "\",\"max_tokens\":" + a.max_tokens.to_string() + "}"
  })
  let json = "[" + json_parts.join(",") + "]"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle /api/tools - return JSON list of tools
async fn handle_tools_json(ctx : RuntimeContext, conn : @http.ServerConnection) -> Unit {
  let tools = ctx.tool_registry.list_enabled()
  let json_parts = tools.map(fn(t) {
    "{\"id\":\"" + t.id + "\",\"name\":\"" + t.name + "\",\"description\":\"" + t.description + "\",\"enabled\":true}"
  })
  let json = "[" + json_parts.join(",") + "]"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle /api/chat - SSE streaming chat with agent
async fn handle_chat_sse(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  // Parse query parameters from path
  let query = match string_find(path, "?") {
    Some(pos) => path.substring(start=pos+1, end=path.length())
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("agent_001")
  let message = extract_query_param(query, "message").unwrap_or("Hello")
  
  // Find the agent
  let agent = match ctx.agent_manager.find(agent_id) {
    Some(a) => a
    None => {
      conn.send_response(404, "Not Found", extra_headers={ "Content-Type": "text/plain" })
      conn.write_string("Agent not found: " + agent_id)
      return
    }
  }
  
  // Set SSE headers and send response
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  
  // Build messages
  let messages = agent.build_prompt(message)
  
  // Call DeepSeek API via @http.post
  let msgs = messages.map(fn(msg) {
    "{\"role\":\"" + msg.role + "\",\"content\":\"" + msg.content + "\"}"
  })
  let msg_json = "[" + msgs.join(",") + "]"
  let body_str = "{\"model\":\"" + ctx.model + "\",\"messages\":" + msg_json +
    ",\"max_tokens\":" + agent.max_tokens.to_string() + ",\"temperature\":" + agent.temperature.to_string() + "}"
  
  let url = "https://api.deepseek.com/v1/chat/completions"
  let headers = Map([("Content-Type", "application/json"), ("Authorization", "Bearer " + ctx.api_key)])
  
  // Make HTTP POST request - String implements Data trait
  let (response, data) = @http.post(url, body_str, headers=headers)
  
  if response.code == 200 {
    let text = data.text() catch { _ => "Error: Invalid UTF-8" }
    let content = extract_content(text)
    match content {
      Some(c) => {
        conn.write_string("data: " + c + "\n\n")
      }
      None => {
        conn.write_string("data: Error: Failed to parse response\n\n")
      }
    }
  } else {
    conn.write_string("data: Error: API error " + response.code.to_string() + "\n\n")
  }
  
  conn.close()
}

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

/// Parse hex char to int (0-15)
fn hex_to_int(ch : UInt16) -> Int {
  if ch >= 48 && ch <= 57 { ch.to_int() - 48 }
  else if ch >= 97 && ch <= 102 { ch.to_int() - 87 }
  else if ch >= 65 && ch <= 70 { ch.to_int() - 55 }
  else { 0 }
}

/// Parse port string to int
fn parse_port(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
    } else {
      return 8080
    }
    i = i + 1
  }
  if result <= 0 || result > 65535 { 8080 } else { result }
}

/// Extract query parameter value from query string
fn extract_query_param(query : String, param : String) -> Option[String] {
  let pairs_iter = query.split("&")
  let pairs : Array[String] = []
  for p in pairs_iter {
    pairs.push(p.to_owned())
  }
  for pair in pairs {
    let eq_pos = string_find(pair, "=")
    match eq_pos {
      None => continue
      Some(pos) => {
        let key = pair.substring(start=0, end=pos)
        if key == param {
          let value = pair.substring(start=pos+1, end=pair.length())
          return Some(decode_url(value))
        }
      }
    }
  }
  None
}

/// Simple URL decode (handles %XX and +)
fn decode_url(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let ch = s[i]
    if ch == 43 {
      // '+'
      result = result + " "
    } else if ch == 37 && i + 2 < s.length() {
      // '%'
      let hi = hex_to_int(s[i + 1])
      let lo = hex_to_int(s[i + 2])
      let code = hi * 16 + lo
      match code.to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
      i = i + 2
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

/// Simple HTML page for the web UI
fn index_html() -> String {
  "<!DOCTYPE html>" +
  "<html lang=\"zh-CN\">" +
  "<head>" +
  "<meta charset=\"UTF-8\">" +
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" +
  "<title>AI Agent Runtime</title>" +
  "<style>" +
  "body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }" +
  ".container { background: white; border-radius: 8px; padding: 20px; }" +
  "h1 { color: #333; text-align: center; }" +
  ".chat-box { border: 1px solid #ddd; border-radius: 8px; padding: 16px; height: 400px; overflow-y: auto; }" +
  ".message { margin: 8px 0; padding: 8px 12px; border-radius: 8px; }" +
  ".user-msg { background: #e3f2fd; text-align: right; }" +
  ".ai-msg { background: #f3e5f5; text-align: left; }" +
  ".input-area { display: flex; gap: 8px; }" +
  "input { flex: 1; padding: 10px; border: 1px solid #ddd; }" +
  "button { padding: 10px 20px; background: #7c3aed; color: white; border: none; cursor: pointer; }" +
  "button:hover { background: #6d28d9; }" +
  "</style>" +
  "</head>" +
  "<body>" +
  "<div class=\"container\">" +
  "<h1>AI Agent Runtime</h1>" +
  "<div class=\"chat-box\" id=\"chatBox\"></div>" +
  "<div class=\"input-area\">" +
  "<input type=\"text\" id=\"messageInput\" placeholder=\"Enter your message...\" />" +
  "<button onclick=\"sendMessage()\">Send</button>" +
  "</div>" +
  "<div class=\"status\" id=\"status\">Ready</div>" +
  "</div>" +
  "<script>" +
  "const chatBox = document.getElementById(\"chatBox\");" +
  "const status = document.getElementById(\"status\");" +
  "async function sendMessage() {" +
  "const input = document.getElementById(\"messageInput\");" +
  "const msg = input.value.trim(); if (!msg) return; input.value = \"\";" +
  "addMessage(msg, \"user-msg\");" +
  "status.textContent = \"Waiting...\";" +
  "try {" +
  "const resp = await fetch(\"/api/chat?message=\" + encodeURIComponent(msg));" +
  "const reader = resp.body.getReader();" +
  "const decoder = new TextDecoder();" +
  "while (true) { const { done, value } = await reader.read(); if (done) break;" +
  "const text = decoder.decode(value);" +
  "const lines = text.split(String.fromCharCode(10));" +
  "for (const line of lines) { if (line.startsWith(\"data: \")) {" +
  "addMessage(line.slice(6), \"ai-msg\");" +
  "} } }" +
  "} catch (e) { addMessage(\"Error: \" + e.message, \"ai-msg\"); }" +
  "}" +
  "function addMessage(text, cls) {" +
  "const div = document.createElement(\"div\");" +
  "div.className = \"message \" + cls;" +
  "div.textContent = text;" +
  "chatBox.appendChild(div);" +
  "}" +
  "</script>" +
  "</body>" +
  "</html>"
}
