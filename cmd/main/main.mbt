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
  let tasks_file = data_dir + "/tasks.csv"
  
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
  
  let task_manager = match @lib.TaskManager::load(tasks_file) {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} tasks")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load tasks: \{e}")
      @lib.TaskManager::new(Map([], capacity=0))
    }
  }
  
  // Initialize stats manager from agents
  let stats_manager = @lib.StatsManager::new(Map([], capacity=agent_manager.count()))
  stats_manager.init(agent_manager)
  println("Tracking stats for \{agent_manager.count()} agents")
  
  // Create runtime context
  let ctx = RuntimeContext::{
    api_key: api_key,
    model: model,
    agent_manager: agent_manager,
    tool_registry: tool_registry,
    task_manager: task_manager,
    stats_manager: stats_manager,
    cors_origin: cors_origin,
  }
  
  // Start HTTP server
  println("Server running at http://localhost:\{port}")
  let addr = @socket.Addr::resolve("0.0.0.0", port=port)
  @http.Server::new(addr).run_forever(
    async fn(request : @http.Request, body : &@io.Reader, conn : @http.ServerConnection) {
      handle_request(ctx, request, body, conn)
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
  task_manager : @lib.TaskManager
  stats_manager : @lib.StatsManager
  cors_origin : String
}

/// Build CORS headers for cross-origin requests
fn cors_headers(origin : String) -> Map[String, String] {
  Map([
    ("Access-Control-Allow-Origin", origin),
    ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
    ("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept"),
    ("Access-Control-Max-Age", "86400"),
  ])
}

/// Route requests to appropriate handlers
async fn handle_request(
  ctx : RuntimeContext,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection
) -> Unit {
  let path = request.path
  let meth = request.meth
  
  // Handle CORS preflight
  if meth is Options {
    conn.send_response(204, "No Content", extra_headers={
      "Access-Control-Allow-Origin": ctx.cors_origin,
      "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept",
      "Access-Control-Max-Age": "86400",
    })
    return
  }
  
  // Handle GET routes
  if meth is Get {
    if path == "/" || path == "" {
      handle_index(conn)
    } else if path == "/api/agents" {
      handle_agents_json(ctx, conn)
    } else if path.has_prefix("/api/agents/detail") {
      handle_agent_detail(ctx, path, conn)
    } else if path.has_prefix("/api/agents/stats") {
      handle_agent_stats(ctx, path, conn)
    } else if path == "/api/tools" {
      handle_tools_json(ctx, conn)
    } else if path.has_prefix("/api/tasks") {
      handle_tasks_list(ctx, path, conn)
    } else if path.has_prefix("/api/chat/history") {
      handle_chat_history(ctx, path, conn)
    } else if path.has_prefix("/api/chat/clear") {
      handle_chat_clear(ctx, path, conn)
    } else if path.has_prefix("/api/chat") {
      handle_chat_sse(ctx, path, conn)
    } else {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("404 Not Found")
    }
  } else if meth is Post {
    if path == "/api/tasks" {
      handle_task_create(ctx, body, conn)
    } else {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("404 Not Found")
    }
  } else if meth is Put {
    if path.has_prefix("/api/tasks") {
      handle_task_update(ctx, path, body, conn)
    } else {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("404 Not Found")
    }
  } else {
    conn.send_response(405, "Method Not Allowed", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
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
    let stats = ctx.stats_manager.get_stats(a.id)
    let stats_json = match stats {
      Some(s) => ",\"stats\":{\"total_conversations\":" + s.total_conversations.to_string() +
        ",\"total_input_chars\":" + s.total_input_chars.to_string() +
        ",\"total_output_chars\":" + s.total_output_chars.to_string() +
        ",\"total_prompt_tokens\":" + s.total_prompt_tokens.to_string() +
        ",\"total_completion_tokens\":" + s.total_completion_tokens.to_string() +
        ",\"last_active_at\":\"" + json_escape(s.last_active_at) + "\"}"
      None => ",\"stats\":null"
    }
    "{\"id\":\"" + json_escape(a.id) + "\",\"name\":\"" + json_escape(a.name) +
      "\",\"model\":\"" + json_escape(a.model) + "\",\"max_tokens\":" +
      a.max_tokens.to_string() + ",\"tool_ids\":\"" + json_escape(a.tool_ids) +
      "\"" + stats_json + "}"
  })
  let json = "[" + json_parts.join(",") + "]"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle /api/agents/detail - return detailed agent info with tools, tasks, and stats
async fn handle_agent_detail(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")
  
  if agent_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent_id parameter")
    return
  }
  
  // Find the agent
  let agent = match ctx.agent_manager.find(agent_id) {
    Some(a) => a
    None => {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Agent not found: " + agent_id)
      return
    }
  }
  
  // Get tools assigned to this agent
  let tools = agent.get_tools(ctx.tool_registry)
  let tools_json = tools.map(fn(t) {
    "{\"id\":\"" + json_escape(t.id) + "\",\"name\":\"" + json_escape(t.name) +
      "\",\"description\":\"" + json_escape(t.description) + "\",\"version\":\"" +
      json_escape(t.version) + "\",\"enabled\":" + (if t.enabled { "true" } else { "false" }) + "}"
  })
  let tools_array = "[" + tools_json.join(",") + "]"
  
  // Get tasks for this agent
  let tasks = ctx.task_manager.list_by_agent(agent_id)
  let tasks_json = tasks.map(fn(t) {
    let status_str = match t.status {
      @lib.Pending => "\"pending\""
      @lib.Running => "\"running\""
      @lib.Completed => "\"completed\""
      @lib.Failed(_) => "\"failed\""
    }
    "{\"id\":\"" + json_escape(t.id) + "\",\"description\":\"" + json_escape(t.description) +
      "\",\"status\":" + status_str + ",\"priority\":" + t.priority.to_string() +
      ",\"created_at\":\"" + json_escape(t.created_at) +
      "\",\"updated_at\":\"" + json_escape(t.updated_at) +
      "\",\"duration_ms\":" + t.duration_ms.to_string() + "}"
  })
  let tasks_array = "[" + tasks_json.join(",") + "]"
  
  // Get stats
  let stats = ctx.stats_manager.get_stats(agent_id)
  let stats_json = match stats {
    Some(s) => "{\"total_conversations\":" + s.total_conversations.to_string() +
      ",\"total_input_chars\":" + s.total_input_chars.to_string() +
      ",\"total_output_chars\":" + s.total_output_chars.to_string() +
      ",\"total_prompt_tokens\":" + s.total_prompt_tokens.to_string() +
      ",\"total_completion_tokens\":" + s.total_completion_tokens.to_string() +
      ",\"last_active_at\":\"" + json_escape(s.last_active_at) + "\"}"
    None => "null"
  }
  
  // Get conversation history summary (count only, to avoid large responses)
  let history = ctx.agent_manager.get_conversation(agent_id)
  let history_count = history.length()
  
  // Build the full response
  let json = "{\"id\":\"" + json_escape(agent.id) +
    "\",\"name\":\"" + json_escape(agent.name) +
    "\",\"model\":\"" + json_escape(agent.model) +
    "\",\"instruction\":\"" + json_escape(agent.instruction) +
    "\",\"system_prompt\":\"" + json_escape(agent.system_prompt) +
    "\",\"max_tokens\":" + agent.max_tokens.to_string() +
    ",\"temperature\":" + agent.temperature.to_string() +
    ",\"tool_ids\":\"" + json_escape(agent.tool_ids) +
    "\",\"tools\":" + tools_array +
    ",\"tasks\":" + tasks_array +
    ",\"stats\":" + stats_json +
    ",\"conversation_count\":" + history_count.to_string() + "}"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle /api/agents/stats - return agent statistics
async fn handle_agent_stats(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")
  
  let json = if agent_id.length() > 0 {
    // Return stats for specific agent
    match ctx.stats_manager.get_stats(agent_id) {
      Some(s) => "{\"agent_id\":\"" + json_escape(s.agent_id) +
        "\",\"total_conversations\":" + s.total_conversations.to_string() +
        ",\"total_input_chars\":" + s.total_input_chars.to_string() +
        ",\"total_output_chars\":" + s.total_output_chars.to_string() +
        ",\"total_prompt_tokens\":" + s.total_prompt_tokens.to_string() +
        ",\"total_completion_tokens\":" + s.total_completion_tokens.to_string() +
        ",\"last_active_at\":\"" + json_escape(s.last_active_at) + "\"}"
      None => "{\"error\":\"Agent not found: " + json_escape(agent_id) + "\"}"
    }
  } else {
    // Return all stats
    let all_stats = ctx.stats_manager.get_all_stats()
    let json_parts = all_stats.map(fn(s) {
      "{\"agent_id\":\"" + json_escape(s.agent_id) +
        "\",\"total_conversations\":" + s.total_conversations.to_string() +
        ",\"total_input_chars\":" + s.total_input_chars.to_string() +
        ",\"total_output_chars\":" + s.total_output_chars.to_string() +
        ",\"total_prompt_tokens\":" + s.total_prompt_tokens.to_string() +
        ",\"total_completion_tokens\":" + s.total_completion_tokens.to_string() +
        ",\"last_active_at\":\"" + json_escape(s.last_active_at) + "\"}"
    })
    "[" + json_parts.join(",") + "]"
  }
  
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

/// Handle /api/chat/history - return conversation history for an agent
async fn handle_chat_history(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")
  
  if agent_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent_id parameter")
    return
  }
  
  let history = ctx.agent_manager.get_conversation(agent_id)
  let json_parts = history.map(fn(msg) {
    "{\"role\":\"" + json_escape(msg.role) + "\",\"content\":\"" + json_escape(msg.content) + "\"}"
  })
  let json = "[" + json_parts.join(",") + "]"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle /api/chat/clear - clear conversation history for an agent
async fn handle_chat_clear(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")
  
  if agent_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent_id parameter")
    return
  }
  
  ctx.agent_manager.clear_conversation(agent_id)
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string("{\"status\":\"ok\",\"message\":\"Conversation cleared for " + agent_id + "\"}")
}

/// Handle /api/chat - SSE streaming chat with agent
async fn handle_chat_sse(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  // Parse query parameters from path
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("agent_001")
  let message = extract_query_param(query, "message").unwrap_or("Hello")
  
  // Find the agent
  let agent = match ctx.agent_manager.find(agent_id) {
    Some(a) => a
    None => {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Agent not found: " + agent_id)
      return
    }
  }
  
  // Build messages for DeepSeek API with stream=true
  let messages = agent.build_prompt(message, ctx.tool_registry, ctx.task_manager)
  let msgs = messages.map(fn(msg) {
    "{\"role\":\"" + json_escape(msg.role) + "\",\"content\":\"" + json_escape(msg.content) + "\"}"
  })
  let msg_json = "[" + msgs.join(",") + "]"
  let body_str = "{\"model\":\"" + json_escape(ctx.model) + "\",\"messages\":" + msg_json +
    ",\"max_tokens\":" + agent.max_tokens.to_string() +
    ",\"temperature\":" + agent.temperature.to_string() +
    ",\"stream\":true}"
  
  let url = "https://api.deepseek.com/v1/chat/completions"
  let req_headers = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " + ctx.api_key),
  ])
  
  // Send SSE response headers first
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  
  // Store user message in conversation history
  ctx.agent_manager.add_message(agent_id, "user", message)
  let input_chars = message.length()
  
  // Stream from DeepSeek API and forward chunks to client
  let mut full_response = ""
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
      conn.write_string("data: [DONE]\n\n")
      return
    }
    
    // Forward streaming chunks from DeepSeek to client
    while client.read_some() is Some(data) {
      let text = @utf8.decode(data) catch { _ => continue }
      let lines = text.split("\n")
      for line in lines {
        let owned = line.to_owned()
        if owned.has_prefix("data: ") {
          let payload = line[6:].to_owned()
          if payload == "[DONE]" {
            // Store assistant response in conversation history
            ctx.agent_manager.add_message(agent_id, "assistant", full_response)
            // Record stats with token usage if available
            let output_chars = full_response.length()
            ctx.stats_manager.record_conversation(
              agent_id, input_chars, output_chars,
              prompt_tokens=prompt_tokens, completion_tokens=completion_tokens,
            )
            conn.write_string("data: [DONE]\n\n")
          } else {
            // Check for usage info in the payload
            if string_find(payload, "\"usage\"") is Some(_) {
              match extract_usage_tokens(payload) {
                Some((pt, ct)) => {
                  prompt_tokens = pt
                  completion_tokens = ct
                }
                None => ()
              }
            }
            match extract_content(payload) {
              Some(content) => {
                full_response = full_response + content
                conn.write_string("data: " + content + "\n\n")
              }
              None => ()
            }
          }
        }
      }
      conn.flush()
    }
  } catch {
    _ => {
      conn.write_string("data: Error: Failed to connect to DeepSeek\n\n")
      conn.write_string("data: [DONE]\n\n")
    }
  }
}

/// Handle GET /api/tasks - list tasks, optionally filtered by agent_id
async fn handle_tasks_list(ctx : RuntimeContext, path : String, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")
  
  let tasks = if agent_id.length() > 0 {
    ctx.task_manager.list_by_agent(agent_id)
  } else {
    ctx.task_manager.list_all()
  }
  
  let json_parts = tasks.map(fn(t) {
    let status_str = match t.status {
      @lib.Pending => "\"pending\""
      @lib.Running => "\"running\""
      @lib.Completed => "\"completed\""
      @lib.Failed(_) => "\"failed\""
    }
    let duration_str = t.duration_ms.to_string()
    "{\"id\":\"" + json_escape(t.id) + "\",\"agent_id\":\"" + json_escape(t.agent_id) +
      "\",\"description\":\"" + json_escape(t.description) + "\",\"status\":" + status_str +
      ",\"priority\":" + t.priority.to_string() +
      ",\"created_at\":\"" + json_escape(t.created_at) +
      "\",\"updated_at\":\"" + json_escape(t.updated_at) +
      "\",\"duration_ms\":" + duration_str + "}"
  })
  let json = "[" + json_parts.join(",") + "]"
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

/// Handle POST /api/tasks - create a new task
async fn handle_task_create(ctx : RuntimeContext, body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  // Read body
  let body_data = body.read_all() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Cannot read request body")
      return
    }
  }
  let body_str = body_data.text() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Invalid UTF-8 in request body")
      return
    }
  }
  
  // Parse JSON fields (simple parsing)
  let id = extract_json_str(body_str, "id").unwrap_or("task_" + ctx.task_manager.count().to_string())
  let agent_id = extract_json_str(body_str, "agent_id").unwrap_or("")
  let description = extract_json_str(body_str, "description").unwrap_or("")
  let priority_str = extract_json_str(body_str, "priority").unwrap_or("0")
  let priority = @lib.parse_int(priority_str)
  
  if agent_id.length() == 0 || description.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing required fields: agent_id, description")
    return
  }
  
  let _task = ctx.task_manager.create_task(id, agent_id, description, priority)
  
  conn.send_response(201, "Created", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string("{\"status\":\"ok\",\"task_id\":\"" + json_escape(id) + "\"}")
}

/// Handle PUT /api/tasks - update task status
async fn handle_task_update(ctx : RuntimeContext, path : String, body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos+1:].to_string()
    None => ""
  }
  let task_id = extract_query_param(query, "id").unwrap_or("")
  
  // Also try to read from body
  let body_data = body.read_all() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Cannot read request body")
      return
    }
  }
  let body_str = body_data.text() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Invalid UTF-8 in request body")
      return
    }
  }
  
  let actual_id = if task_id.length() > 0 { task_id } else { extract_json_str(body_str, "id").unwrap_or("") }
  let status_str = extract_json_str(body_str, "status").unwrap_or("")
  
  if actual_id.length() == 0 || status_str.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing required fields: id, status")
    return
  }
  
  let new_status = @lib.parse_status(status_str)
  
  let _ignore = ctx.task_manager.update_status(actual_id, new_status)
  
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string("{\"status\":\"ok\",\"task_id\":\"" + json_escape(actual_id) + "\"}")
}

/// Extract a simple string value from a JSON string by key
fn extract_json_str(json : String, key : String) -> Option[String] {
  // Try with space after colon first, then without
  let search1 = "\"" + key + "\": \""
  let search2 = "\"" + key + "\":\""
  let start = match string_find(json, search1) {
    Some(s) => Some(s)
    None => string_find(json, search2)
  }
  match start {
    None => None
    Some(s) => {
      let search = if string_find(json, search1) is Some(_) { search1 } else { search2 }
      let value_start = s + search.length()
      let mut result = ""
      let mut i = value_start
      while i < json.length() {
        let ch = json[i]
        if ch == '\\' && i + 1 < json.length() && json[i + 1] == '"' {
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

/// Escape string for JSON (handle quotes, backslash, and control characters)
fn json_escape(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let ch = s[i]
    if ch == 34 { // "
      result = result + "\\\""
    } else if ch == 92 { // \
      result = result + "\\\\"
    } else if ch == 10 { // \n
      result = result + "\\n"
    } else if ch == 13 { // \r
      result = result + "\\r"
    } else if ch == 9 { // \t
      result = result + "\\t"
    } else if ch < 32 {
      // Skip other control chars
      result = result
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

/// Extract token usage from DeepSeek response JSON
/// Returns (prompt_tokens, completion_tokens) or None
fn extract_usage_tokens(json_str : String) -> Option[(Int, Int)] {
  // Find "prompt_tokens": XX
  let pt_prefix = "\"prompt_tokens\":"
  let ct_prefix = "\"completion_tokens\":"
  
  let pt_start = match string_find(json_str, pt_prefix) {
    Some(s) => s + pt_prefix.length()
    None => return None
  }
  let ct_start = match string_find(json_str, ct_prefix) {
    Some(s) => s + ct_prefix.length()
    None => return None
  }
  
  let prompt_tokens = parse_int_at(json_str, pt_start)
  let completion_tokens = parse_int_at(json_str, ct_start)
  
  Some((prompt_tokens, completion_tokens))
}

/// Parse an integer starting at a given position in a string
fn parse_int_at(s : String, start : Int) -> Int {
  let mut result = 0
  let mut i = start
  // Skip whitespace
  while i < s.length() && s[i] == ' ' { i = i + 1 }
  // Skip leading digits
  let mut neg = false
  if i < s.length() && s[i] == '-' { neg = true; i = i + 1 }
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
      i = i + 1
    } else {
      break
    }
  }
  if neg { -result } else { result }
}

/// Simple JSON content extraction from DeepSeek response (handles JSON escapes)
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
        if ch == '\\' && i + 1 < json_str.length() {
          let next = json_str[i + 1]
          if next == '"' {
            result = result + "\""
            i = i + 2
          } else if next == 'n' {
            result = result + "\n"
            i = i + 2
          } else if next == 'r' {
            result = result + "\r"
            i = i + 2
          } else if next == 't' {
            result = result + "\t"
            i = i + 2
          } else if next == '\\' {
            result = result + "\\"
            i = i + 2
          } else {
            match ch.to_char() {
              Some(c) => result = result + c.to_string()
              None => ()
            }
            i = i + 1
          }
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
