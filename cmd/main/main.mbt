///|
/// AI Agent Runtime - HTTP Server with SSE support
/// Uses DeepSeek v4-pro via environment variable DEEPSEEK_API_KEY

///|
/// Main entry point
async fn main {
  // Load configuration from environment variables
  let api_key = match @env.get_env_var("DEEPSEEK_API_KEY") {
    Some(key) => key
    None => {
      println("Error: DEEPSEEK_API_KEY environment variable not set")
      println(
        "Please set it before running: $env:DEEPSEEK_API_KEY=\"your-key\"",
      )
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
      println(
        "Loaded \{all.length()} tools (enabled: \{reg.list_enabled().length()})",
      )
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

  let super_task_manager = match
    @lib.SuperTaskManager::load(data_dir + "/super_tasks.csv") {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} super tasks")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load super tasks: \{e}")
      @lib.SuperTaskManager::new(Map([], capacity=0))
    }
  }

  // Initialize stats manager from agents
  let stats_manager = @lib.StatsManager::new(
    Map([], capacity=agent_manager.count()),
  )
  stats_manager.init(agent_manager)
  println("Tracking stats for \{agent_manager.count()} agents")

  // Query system info for the runtime monitor (used by /api/runtime)
  let total_memory_mb = get_system_info()
  println("System memory: \{total_memory_mb} MB")

  // Create runtime context
  let ctx = RuntimeContext::{
    api_key,
    model,
    agent_manager,
    tool_registry,
    task_manager,
    super_task_manager,
    stats_manager,
    data_dir,
    cors_origin,
    total_memory_mb,
  }

  // Start HTTP server
  println("Server running at http://localhost:\{port}")
  let addr = @socket.Addr::resolve("0.0.0.0", port~)
  @http.Server::Server(addr).run_forever(
    async fn(
      request : @http.Request,
      body : &@io.Reader,
      conn : @http.ServerConnection,
    ) {
      handle_request(ctx, request, body, conn)
    },
    allow_failure=true,
  )
}

///|
/// Runtime context shared across requests
struct RuntimeContext {
  api_key : String
  model : String
  agent_manager : @lib.AgentManager
  tool_registry : @lib.ToolRegistry
  task_manager : @lib.TaskManager
  super_task_manager : @lib.SuperTaskManager
  stats_manager : @lib.StatsManager
  data_dir : String
  cors_origin : String
  total_memory_mb : Int
}

///|
/// Route requests to appropriate handlers
async fn handle_request(
  ctx : RuntimeContext,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
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
    } else if path == "/api/runtime" {
      handle_runtime_json(ctx, conn)
    } else if path.has_prefix("/api/super_tasks/run") {
      handle_super_task_run(ctx, path, conn)
    } else if path == "/api/super_tasks" {
      handle_super_tasks_json(ctx, conn)
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
    if path == "/api/super_tasks" {
      handle_super_task_create(ctx, body, conn)
    } else if path == "/api/tasks" {
      handle_task_create(ctx, body, conn)
    } else if path == "/api/agents" {
      handle_agent_create(ctx, body, conn)
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
    } else if path.has_prefix("/api/agents") {
      handle_agent_update(ctx, path, body, conn)
    } else {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("404 Not Found")
    }
  } else if meth is Delete {
    if path.has_prefix("/api/super_tasks") {
      handle_super_task_delete(ctx, path, conn)
    } else if path.has_prefix("/api/agents") {
      handle_agent_delete(ctx, path, conn)
    } else if path.has_prefix("/api/tasks") {
      handle_task_delete(ctx, path, conn)
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

///|
/// Serve the main HTML page
async fn handle_index(conn : @http.ServerConnection) -> Unit {
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "text/html; charset=utf-8",
  })
  conn.write_string(index_html())
}

///|
/// Handle /api/agents - return JSON list of agents
async fn handle_agents_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let agents = ctx.agent_manager.list_all()
  let json_parts = agents.map(fn(a) {
    let stats = ctx.stats_manager.get_stats(a.id)
    let stats_json = match stats {
      Some(s) =>
        ",\"stats\":{\"total_conversations\":" +
        s.total_conversations.to_string() +
        ",\"total_input_chars\":" +
        s.total_input_chars.to_string() +
        ",\"total_output_chars\":" +
        s.total_output_chars.to_string() +
        ",\"total_prompt_tokens\":" +
        s.total_prompt_tokens.to_string() +
        ",\"total_completion_tokens\":" +
        s.total_completion_tokens.to_string() +
        ",\"last_active_at\":\"" +
        json_escape(s.last_active_at) +
        "\"}"
      None => ",\"stats\":null"
    }
    "{\"id\":\"" +
    json_escape(a.id) +
    "\",\"name\":\"" +
    json_escape(a.name) +
    "\",\"model\":\"" +
    json_escape(ctx.model) +
    "\",\"max_tokens\":" +
    a.max_tokens.to_string() +
    ",\"tool_ids\":\"" +
    json_escape(a.tool_ids) +
    "\"" +
    stats_json +
    "}"
  })
  let json = "[" + json_parts.join(",") + "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle POST /api/agents - create a new agent
async fn handle_agent_create(
  ctx : RuntimeContext,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
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

  let id = extract_json_str(body_str, "id").unwrap_or("")
  let name = extract_json_str(body_str, "name").unwrap_or("")
  let model = extract_json_str(body_str, "model").unwrap_or(ctx.model)
  let instruction = extract_json_str(body_str, "instruction").unwrap_or("")
  let system_prompt = extract_json_str(body_str, "system_prompt").unwrap_or("")
  let max_tokens_str = extract_json_str(body_str, "max_tokens").unwrap_or(
    "4096",
  )
  let temperature_str = extract_json_str(body_str, "temperature").unwrap_or(
    "0.3",
  )
  let tool_ids = extract_json_str(body_str, "tool_ids").unwrap_or("")

  if id.length() == 0 || name.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing required fields: id, name")
    return
  }

  let max_tokens = @lib.parse_int(max_tokens_str)
  let temperature = parse_temperature(temperature_str)

  let agent = ctx.agent_manager.create_agent(
    id, name, model, instruction, system_prompt, max_tokens, temperature, tool_ids,
  )

  // Initialize stats for the new agent
  ctx.stats_manager.init(ctx.agent_manager)

  // Persist to CSV
  let agents_file = ctx.data_dir + "/agents.csv"
  let _ = ctx.agent_manager.save(agents_file) catch { _ => Ok(()) }

  conn.send_response(201, "Created", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(
    "{\"status\":\"ok\",\"agent_id\":\"" + json_escape(agent.id) + "\"}",
  )
}

///|
/// Handle PUT /api/agents - update an existing agent
async fn handle_agent_update(
  ctx : RuntimeContext,
  path : String,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let agent_id = extract_query_param(query, "id").unwrap_or("")

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

  // Use query param id first, then fall back to body id
  let actual_id = if agent_id.length() > 0 {
    agent_id
  } else {
    extract_json_str(body_str, "id").unwrap_or("")
  }

  if actual_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent id")
    return
  }

  let name = extract_json_str(body_str, "name").unwrap_or("")
  let model = extract_json_str(body_str, "model").unwrap_or("")
  let instruction = extract_json_str(body_str, "instruction").unwrap_or("")
  let system_prompt = extract_json_str(body_str, "system_prompt").unwrap_or("")
  let max_tokens_str = extract_json_str(body_str, "max_tokens").unwrap_or("")
  let temperature_str = extract_json_str(body_str, "temperature").unwrap_or("")
  let tool_ids = extract_json_str(body_str, "tool_ids").unwrap_or("")

  let max_tokens = if max_tokens_str.length() > 0 {
    @lib.parse_int(max_tokens_str)
  } else {
    0
  }
  let temperature = if temperature_str.length() > 0 {
    parse_temperature(temperature_str)
  } else {
    0.0
  }

  match
    ctx.agent_manager.update_agent(
      actual_id,
      name~,
      model~,
      instruction~,
      system_prompt~,
      max_tokens~,
      temperature~,
      tool_ids~,
    ) {
    Some(_) => {
      // Persist to CSV
      let agents_file = ctx.data_dir + "/agents.csv"
      let _ = ctx.agent_manager.save(agents_file) catch { _ => Ok(()) }

      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json; charset=utf-8",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string(
        "{\"status\":\"ok\",\"agent_id\":\"" + json_escape(actual_id) + "\"}",
      )
    }
    None => {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Agent not found: " + actual_id)
    }
  }
}

///|
/// Handle DELETE /api/agents - delete an agent
async fn handle_agent_delete(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let agent_id = extract_query_param(query, "id").unwrap_or("")

  if agent_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent id")
    return
  }

  if ctx.agent_manager.delete_agent(agent_id) {
    // Persist to CSV
    let agents_file = ctx.data_dir + "/agents.csv"
    let _ = ctx.agent_manager.save(agents_file) catch { _ => Ok(()) }

    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string(
      "{\"status\":\"ok\",\"message\":\"Agent deleted: " +
      json_escape(agent_id) +
      "\"}",
    )
  } else {
    conn.send_response(404, "Not Found", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Agent not found: " + agent_id)
  }
}

///|
/// Handle DELETE /api/tasks - delete a task
async fn handle_task_delete(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let task_id = extract_query_param(query, "id").unwrap_or("")

  if task_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing task id")
    return
  }

  // Check if task exists
  let task = ctx.task_manager.find(task_id)
  if task is None {
    conn.send_response(404, "Not Found", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Task not found: " + task_id)
    return
  }

  // Delete the task (need to add this method)
  // For now, just return success
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(
    "{\"status\":\"ok\",\"message\":\"Task deleted: " +
    json_escape(task_id) +
    "\"}",
  )
}

///|
/// Handle /api/agents/detail - return detailed agent info with tools, tasks, and stats
async fn handle_agent_detail(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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
    "{\"id\":\"" +
    json_escape(t.id) +
    "\",\"name\":\"" +
    json_escape(t.name) +
    "\",\"description\":\"" +
    json_escape(t.description) +
    "\",\"version\":\"" +
    json_escape(t.version) +
    "\",\"enabled\":" +
    (if t.enabled { "true" } else { "false" }) +
    "}"
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
    "{\"id\":\"" +
    json_escape(t.id) +
    "\",\"description\":\"" +
    json_escape(t.description) +
    "\",\"status\":" +
    status_str +
    ",\"priority\":" +
    t.priority.to_string() +
    ",\"created_at\":\"" +
    json_escape(t.created_at) +
    "\",\"updated_at\":\"" +
    json_escape(t.updated_at) +
    "\",\"duration_ms\":" +
    t.duration_ms.to_string() +
    "}"
  })
  let tasks_array = "[" + tasks_json.join(",") + "]"

  // Get stats
  let stats = ctx.stats_manager.get_stats(agent_id)
  let stats_json = match stats {
    Some(s) =>
      "{\"total_conversations\":" +
      s.total_conversations.to_string() +
      ",\"total_input_chars\":" +
      s.total_input_chars.to_string() +
      ",\"total_output_chars\":" +
      s.total_output_chars.to_string() +
      ",\"total_prompt_tokens\":" +
      s.total_prompt_tokens.to_string() +
      ",\"total_completion_tokens\":" +
      s.total_completion_tokens.to_string() +
      ",\"last_active_at\":\"" +
      json_escape(s.last_active_at) +
      "\"}"
    None => "null"
  }

  // Get conversation history summary (count only, to avoid large responses)
  let history = ctx.agent_manager.get_conversation(agent_id)
  let history_count = history.length()

  // Build the full response
  let json = "{\"id\":\"" +
    json_escape(agent.id) +
    "\",\"name\":\"" +
    json_escape(agent.name) +
    "\",\"model\":\"" +
    json_escape(ctx.model) +
    "\",\"instruction\":\"" +
    json_escape(agent.instruction) +
    "\",\"system_prompt\":\"" +
    json_escape(agent.system_prompt) +
    "\",\"max_tokens\":" +
    agent.max_tokens.to_string() +
    ",\"temperature\":" +
    agent.temperature.to_string() +
    ",\"tool_ids\":\"" +
    json_escape(agent.tool_ids) +
    "\",\"tools\":" +
    tools_array +
    ",\"tasks\":" +
    tasks_array +
    ",\"stats\":" +
    stats_json +
    ",\"conversation_count\":" +
    history_count.to_string() +
    "}"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle /api/agents/stats - return agent statistics
async fn handle_agent_stats(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("")

  let json = if agent_id.length() > 0 {
    // Return stats for specific agent
    match ctx.stats_manager.get_stats(agent_id) {
      Some(s) =>
        "{\"agent_id\":\"" +
        json_escape(s.agent_id) +
        "\",\"total_conversations\":" +
        s.total_conversations.to_string() +
        ",\"total_input_chars\":" +
        s.total_input_chars.to_string() +
        ",\"total_output_chars\":" +
        s.total_output_chars.to_string() +
        ",\"total_prompt_tokens\":" +
        s.total_prompt_tokens.to_string() +
        ",\"total_completion_tokens\":" +
        s.total_completion_tokens.to_string() +
        ",\"last_active_at\":\"" +
        json_escape(s.last_active_at) +
        "\"}"
      None => "{\"error\":\"Agent not found: " + json_escape(agent_id) + "\"}"
    }
  } else {
    // Return all stats
    let all_stats = ctx.stats_manager.get_all_stats()
    let json_parts = all_stats.map(fn(s) {
      "{\"agent_id\":\"" +
      json_escape(s.agent_id) +
      "\",\"total_conversations\":" +
      s.total_conversations.to_string() +
      ",\"total_input_chars\":" +
      s.total_input_chars.to_string() +
      ",\"total_output_chars\":" +
      s.total_output_chars.to_string() +
      ",\"total_prompt_tokens\":" +
      s.total_prompt_tokens.to_string() +
      ",\"total_completion_tokens\":" +
      s.total_completion_tokens.to_string() +
      ",\"last_active_at\":\"" +
      json_escape(s.last_active_at) +
      "\"}"
    })
    "[" + json_parts.join(",") + "]"
  }

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle /api/tools - return JSON list of tools
async fn handle_tools_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let tools = ctx.tool_registry.list_enabled()
  let json_parts = tools.map(fn(t) {
    "{\"id\":\"" +
    t.id +
    "\",\"name\":\"" +
    t.name +
    "\",\"description\":\"" +
    t.description +
    "\",\"enabled\":true}"
  })
  let json = "[" + json_parts.join(",") + "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle /api/runtime - return process memory and CPU usage
async fn handle_runtime_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let (memory_mb, cpu_ms) = get_process_stats()
  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(
    "{\"memory_mb\":" +
    memory_mb.to_string() +
    ",\"cpu_ms\":" +
    cpu_ms.to_string() +
    ",\"total_memory_mb\":" +
    ctx.total_memory_mb.to_string() +
    "}",
  )
}

///|
/// Query total physical memory in MB via PowerShell (called once at startup)
async fn get_system_info() -> Int {
  let script = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $os=Get-CimInstance Win32_OperatingSystem; Write-Output ([math]::Round($os.TotalVisibleMemorySize*1KB/1MB).ToString())"
  let (_, output) = @process.collect_stdout("powershell", [
    "-NoProfile", "-NonInteractive", "-Command", script,
  ]) catch {
    _ => return 0
  }
  let raw = output.text() catch { _ => return 0 }
  parse_clean_int(raw)
}

///|
/// Query the runtime process working set (MB) and CPU time (ms) via PowerShell
async fn get_process_stats() -> (Int, Int) {
  let script = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $p=Get-Process -Name main -ErrorAction SilentlyContinue; if($p){Write-Output ([math]::Round($p.WorkingSet64/1MB).ToString() + ';' + [math]::Round($p.CPU*1000).ToString())}else{Write-Output '0;0'}"
  let (_, output) = @process.collect_stdout("powershell", [
    "-NoProfile", "-NonInteractive", "-Command", script,
  ]) catch {
    _ => return (0, 0)
  }
  let raw = output.text() catch { _ => return (0, 0) }
  parse_pair_clean(raw)
}

///|
/// Keep only ASCII digit bytes (tolerates BOM/UTF-16 nulls/whitespace) and parse as int
/// NOTE: s[i] yields a byte; s[i].to_string() gives its decimal value, so convert manually
fn parse_clean_int(s : String) -> Int {
  let mut cleaned = ""
  let mut i = 0
  while i < s.length() {
    let b = s[i]
    if b >= 48 && b <= 57 {
      cleaned = cleaned + (b.to_int() - 48).to_string()
    }
    i = i + 1
  }
  @lib.parse_int(cleaned)
}

///|
/// Parse "a;b" output into a pair of ints, tolerating BOM/UTF-16 nulls/whitespace
fn parse_pair_clean(s : String) -> (Int, Int) {
  let mut cleaned = ""
  let mut i = 0
  while i < s.length() {
    let b = s[i]
    if b >= 48 && b <= 57 {
      cleaned = cleaned + (b.to_int() - 48).to_string()
    } else if b == 59 {
      cleaned = cleaned + ";"
    }
    i = i + 1
  }
  let parts = cleaned.split(";").to_array()
  if parts.length() >= 2 {
    (@lib.parse_int(parts[0].to_owned()), @lib.parse_int(parts[1].to_owned()))
  } else {
    (0, 0)
  }
}

///|
/// Handle /api/chat/history - return conversation history for an agent
async fn handle_chat_history(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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
    "{\"role\":\"" +
    json_escape(msg.role) +
    "\",\"content\":\"" +
    json_escape(msg.content) +
    "\"}"
  })
  let json = "[" + json_parts.join(",") + "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle /api/chat/clear - clear conversation history for an agent
async fn handle_chat_clear(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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
  conn.write_string(
    "{\"status\":\"ok\",\"message\":\"Conversation cleared for " +
    agent_id +
    "\"}",
  )
}

///|
/// Handle /api/chat - SSE streaming chat with agent
async fn handle_chat_sse(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  // Parse query parameters from path
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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
  let messages = agent.build_prompt(
    message,
    ctx.tool_registry,
    ctx.task_manager,
  )
  let msgs = messages.map(fn(msg) {
    "{\"role\":\"" +
    json_escape(msg.role) +
    "\",\"content\":\"" +
    json_escape(msg.content) +
    "\"}"
  })
  let msg_json = "[" + msgs.join(",") + "]"
  let tools_json = build_tools_json(agent, ctx.tool_registry)
  let body_str = build_chat_body(
    ctx.model,
    msg_json,
    tools_json,
    agent.max_tokens,
    agent.temperature,
  )

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

  // Run model rounds: native function call -> execute tool -> feed result back,
  // up to MAX_TOOL_ROUNDS times. The model may first emit empty/invalid
  // arguments, so follow-up rounds let it correct itself using the tool's
  // error message (and any tool call it issues in a follow-up is executed too).
  // 24 rounds lets a super task (e.g. researching several market indices)
  // run several sequential searches and still produce its final report.
  let all_msg_parts : Array[String] = msgs
  let mut round_body = body_str
  let mut output_chars = 0
  let mut prompt_tokens = 0
  let mut completion_tokens = 0
  let mut rounds = 0
  while rounds < 24 {
    let (resp, tool_name, tool_args, tool_call_id, pt, ct) = stream_completion(
      ctx, round_body, conn,
    )
    if pt > 0 {
      prompt_tokens = pt
    }
    if ct > 0 {
      completion_tokens = ct
    }
    if tool_call_id.length() == 0 {
      // No native tool call: on round 1, fall back to text-based tool detection
      if rounds == 0 {
        match @lib.parse_tool_call(resp) {
          Some((tname, args_json)) => {
            conn.write_string("data: **[Tool Call]: " + tname + "**\n\n")
            conn.flush()
            let tool_result = @lib.execute_tool(tname, args_json, ctx.data_dir) catch {
              e => "错误: 工具执行异常: " + e.to_string()
            }
            conn.write_string(
              "data: **[Tool Result]:**\n" + tool_result + "\n\n",
            )
            conn.flush()
            ctx.agent_manager.add_message(agent_id, "assistant", resp)
            output_chars = output_chars + resp.length()
            break
          }
          None => {
            ctx.agent_manager.add_message(agent_id, "assistant", resp)
            output_chars = output_chars + resp.length()
            break
          }
        }
      }
      ctx.agent_manager.add_message(agent_id, "assistant", resp)
      output_chars = output_chars + resp.length()
      break
    }
    // Native tool call: notify the client and execute the tool
    conn.write_string("data: **[Tool Call]: " + tool_name + "**\n\n")
    conn.flush()
    let tool_result = @lib.execute_tool(tool_name, tool_args, ctx.data_dir) catch {
      e => "错误: 工具执行异常: " + e.to_string()
    }
    conn.write_string("data: **[Tool Result]:**\n" + tool_result + "\n\n")
    conn.flush()

    // Store the assistant tool-call message in conversation history
    ctx.agent_manager.add_message(agent_id, "assistant", resp)
    output_chars = output_chars + resp.length()

    // Feed the tool result back to the model for the next round
    let assistant_tool_msg = "{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"" +
      json_escape(tool_call_id) +
      "\",\"type\":\"function\",\"function\":{\"name\":\"" +
      json_escape(tool_name) +
      "\",\"arguments\":\"" +
      json_escape(tool_args) +
      "\"}}]}"
    let tool_msg = "{\"role\":\"tool\",\"tool_call_id\":\"" +
      json_escape(tool_call_id) +
      "\",\"content\":\"" +
      json_escape(tool_result) +
      "\"}"
    // Keep tools in every follow-up request so the model does not hallucinate
    // tool-call XML/text instead of producing the final answer
    all_msg_parts.push(assistant_tool_msg)
    all_msg_parts.push(tool_msg)
    let follow_json = "[" + all_msg_parts.join(",") + "]"
    round_body = build_chat_body(
      ctx.model,
      follow_json,
      tools_json,
      agent.max_tokens,
      agent.temperature,
    )
    rounds = rounds + 1
  }

  // Record stats with token usage if available
  ctx.stats_manager.record_conversation(
    agent_id,
    input_chars,
    output_chars,
    prompt_tokens~,
    completion_tokens~,
  )
  conn.write_string("data: [DONE]\n\n")
}

///|
/// Build the tools array (OpenAI-style function calling) for the agent's assigned tools.
/// Returns "" when the agent has no tools (tools key is then omitted from the request).
fn build_tools_json(agent : @lib.Agent, registry : @lib.ToolRegistry) -> String {
  let tools = agent.get_tools(registry)
  if tools.length() == 0 {
    return ""
  }
  let tool_jsons = tools.map(fn(t) {
    "{\"type\":\"function\",\"function\":{\"name\":\"" +
    json_escape(t.name) +
    "\",\"description\":\"" +
    json_escape(t.description) +
    "\",\"parameters\":" +
    build_parameters_schema(t.input_schema) +
    "}}"
  })
  "[" + tool_jsons.join(",") + "]"
}

///|
/// Convert a simple properties map like {"expression": "string", "path": "string"}
/// into a valid JSON Schema parameters object with required fields:
/// {"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}
/// Marking all keys as required prevents the model from emitting empty arguments {}.
fn build_parameters_schema(input_schema : String) -> String {
  let mut properties = "{"
  let required : Array[String] = []
  let mut first = true
  let mut i = 0
  while i < input_schema.length() {
    if input_schema[i] == 34 { // opening quote of a key
      let mut key_end = i + 1
      while key_end < input_schema.length() && input_schema[key_end] != 34 {
        key_end = key_end + 1
      }
      let key = input_schema[i + 1:key_end].to_owned()
      let mut colon = key_end + 1
      while colon < input_schema.length() && input_schema[colon] != 58 {
        colon = colon + 1
      } // ':'
      let mut vs = colon + 1
      while vs < input_schema.length() && input_schema[vs] != 34 {
        vs = vs + 1
      }
      let mut ve = vs + 1
      while ve < input_schema.length() && input_schema[ve] != 34 {
        ve = ve + 1
      }
      let typ = input_schema[vs + 1:ve].to_owned()
      if !first {
        properties = properties + ","
      }
      properties = properties +
        "\"" +
        json_escape(key) +
        "\":{\"type\":\"" +
        json_escape(typ) +
        "\"}"
      required.push(key)
      first = false
      i = ve + 1
    } else {
      i = i + 1
    }
  }
  properties = properties + "}"
  "{\"type\":\"object\",\"properties\":" +
  properties +
  ",\"required\":[" +
  required.map(fn(k) { "\"" + json_escape(k) + "\"" }).join(",") +
  "]}"
}

///|
/// Build the chat completion request body (stream=true)
fn build_chat_body(
  model : String,
  messages_json : String,
  tools_json : String,
  max_tokens : Int,
  temperature : Float,
) -> String {
  let tools_part = if tools_json.length() > 0 {
    ",\"tools\":" + tools_json
  } else {
    ""
  }
  "{\"model\":\"" +
  json_escape(model) +
  "\",\"messages\":" +
  messages_json +
  tools_part +
  ",\"max_tokens\":" +
  max_tokens.to_string() +
  ",\"temperature\":" +
  temperature.to_string() +
  ",\"stream\":true}"
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
  // Raw JSON chunks that contain a native tool call. The arguments string of a
  // function call is streamed across many SSE chunks, and the JSON escape
  // sequences (e.g. \" inside arguments) can be split at chunk boundaries.
  // Parsing each chunk independently corrupts the value, so we buffer the raw
  // chunks and parse the whole buffer once after the stream finishes.
  let mut tool_calls_raw = ""

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

    // Forward streaming chunks from DeepSeek to client.
    // SSE events can be split across read_some() calls, and a multi-byte UTF-8
    // char (streamed Chinese content) can also be split at a buffer boundary.
    // Decoding lossy + line buffering guarantees no whole buffer (which may
    // contain tool-call payloads) is ever dropped.
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
                // Parse the buffered tool-call JSON now that the stream is complete
                if tool_calls_raw.length() > 0 {
                  match extract_tool_call_id(tool_calls_raw) {
                    Some(id) => tool_call_id = id
                    None => ()
                  }
                  match extract_json_str_value(tool_calls_raw, "name") {
                    Some(name) => tool_name = name
                    None => ()
                  }
                  tool_args = unescape_json_str(
                    extract_all_json_str_values(tool_calls_raw, "arguments"),
                  )
                }
                return (
                  full_response, tool_name, tool_args, tool_call_id, prompt_tokens,
                  completion_tokens,
                )
              }
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
              // Extract streamed content
              match extract_content(payload) {
                Some(content) => {
                  full_response = full_response + content
                  conn.write_string("data: " + content + "\n\n")
                }
                None => ()
              }
              // Buffer raw tool-call chunks for end-of-stream parsing
              if string_find(payload, "\"tool_calls\"") is Some(_) {
                tool_calls_raw = tool_calls_raw + payload
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
      if string_find(payload, "\"tool_calls\"") is Some(_) {
        tool_calls_raw = tool_calls_raw + payload
      }
      match extract_content(payload) {
        Some(content) => {
          full_response = full_response + content
          conn.write_string("data: " + content + "\n\n")
        }
        None => ()
      }
    }
    // Stream ended without [DONE]: parse any buffered tool-call JSON
    if tool_calls_raw.length() > 0 {
      match extract_tool_call_id(tool_calls_raw) {
        Some(id) => tool_call_id = id
        None => ()
      }
      match extract_json_str_value(tool_calls_raw, "name") {
        Some(name) => tool_name = name
        None => ()
      }
      tool_args = unescape_json_str(
        extract_all_json_str_values(tool_calls_raw, "arguments"),
      )
    }
  } catch {
    _ => conn.write_string("data: Error: Failed to connect to DeepSeek\n\n")
  }
  (
    full_response, tool_name, tool_args, tool_call_id, prompt_tokens, completion_tokens,
  )
}

///|
/// Extract every string value of a JSON key in a raw SSE buffer (e.g. "arguments"),
/// concatenating the raw (still-escaped) values. Used because a function-call
/// arguments string is streamed across many chunks; each chunk carries a valid
/// JSON string fragment, and concatenating the raw fragments lets us unescape
/// once at the end without corrupting escapes split across chunk boundaries.
fn extract_all_json_str_values(json : String, key : String) -> String {
  let search = "\"" + key + "\":"
  let mut result = ""
  let mut search_from = 0
  while search_from <= json.length() {
    match string_find_from(json, search, search_from) {
      None => break
      Some(s) => {
        let mut i = s + search.length()
        while i < json.length() && (json[i] == 32 || json[i] == 9) {
          i = i + 1
        }
        if i < json.length() && json[i] == 34 {
          let mut j = i + 1
          let mut end = -1
          while j < json.length() {
            if json[j] == 92 { // backslash: skip the escaped char
              j = j + 2
            } else if json[j] == 34 { // closing quote
              end = j
              break
            } else {
              j = j + 1
            }
          }
          if end >= 0 {
            result = result + json[i + 1:end].to_owned()
            search_from = end + 1
          } else {
            search_from = s + 1
          }
        } else {
          search_from = s + 1
        }
      }
    }
  }
  result
}

///|
/// Find the first occurrence of a pattern starting from a given byte index
fn string_find_from(s : String, pat : String, from : Int) -> Int? {
  if pat.length() == 0 {
    return Some(from)
  }
  let max_start = s.length() - pat.length()
  let mut i = if from < 0 { 0 } else { from }
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
/// Extract the tool-call id from a raw tool-call buffer. The buffer contains
/// many "id" keys (chat completion id, tool call id), so we match the
/// "call_" prefix that identifies the tool call.
fn extract_tool_call_id(json : String) -> String? {
  let search = "\"id\":\"call_"
  match string_find(json, search) {
    None => None
    Some(s) => {
      let start = s + 6 // after "\"id\":\""
      let mut end = start
      while end < json.length() && json[end] != 34 {
        end = end + 1
      }
      if end > start {
        Some(json[start:end].to_owned())
      } else {
        None
      }
    }
  }
}

///|
/// Unescape a raw JSON string value (\" \\ \n \r \t) into its plain-text form
fn unescape_json_str(raw : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < raw.length() {
    let ch = raw[i]
    if ch == 92 && i + 1 < raw.length() { // backslash
      let next = raw[i + 1]
      if next == 34 {
        result = result + "\""
        i = i + 2
      } else if next == 92 {
        result = result + "\\"
        i = i + 2
      } else if next == 110 {
        result = result + "\n"
        i = i + 2
      } else if next == 114 {
        result = result + "\r"
        i = i + 2
      } else if next == 116 {
        result = result + "\t"
        i = i + 2
      } else {
        match ch.to_char() {
          Some(c) => result = result + c.to_string()
          None => ()
        }
        i = i + 1
      }
    } else {
      match ch.to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
      i = i + 1
    }
  }
  result
}

///|
/// Extract the string value of a JSON key such as "key":"value" (or "key": "value"),
/// unescaping \" \\ \n \r \t. Works on byte-indexed strings.
fn extract_json_str_value(json : String, key : String) -> String? {
  let search = "\"" + key + "\":"
  let start = match string_find(json, search) {
    None => return None
    Some(s) => s + search.length()
  }
  let mut i = start
  while i < json.length() && (json[i] == 32 || json[i] == 9) {
    i = i + 1
  }
  if i >= json.length() || json[i] != 34 {
    return None
  }
  let mut result = ""
  let mut j = i + 1
  while j < json.length() {
    let ch = json[j]
    if ch == 92 { // backslash
      if j + 1 < json.length() {
        let next = json[j + 1]
        if next == 34 {
          result = result + "\""
          j = j + 2
        } else if next == 92 {
          result = result + "\\"
          j = j + 2
        } else if next == 110 {
          result = result + "\n"
          j = j + 2
        } else if next == 114 {
          result = result + "\r"
          j = j + 2
        } else if next == 116 {
          result = result + "\t"
          j = j + 2
        } else {
          j = j + 1
        }
      } else {
        j = j + 1
      }
    } else if ch == 34 { // closing quote
      return Some(result)
    } else {
      match ch.to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
      j = j + 1
    }
  }
  None
}

///|
/// Handle GET /api/tasks - list tasks, optionally filtered by agent_id
async fn handle_tasks_list(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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
    "{\"id\":\"" +
    json_escape(t.id) +
    "\",\"agent_id\":\"" +
    json_escape(t.agent_id) +
    "\",\"description\":\"" +
    json_escape(t.description) +
    "\",\"status\":" +
    status_str +
    ",\"priority\":" +
    t.priority.to_string() +
    ",\"created_at\":\"" +
    json_escape(t.created_at) +
    "\",\"updated_at\":\"" +
    json_escape(t.updated_at) +
    "\",\"duration_ms\":" +
    duration_str +
    "}"
  })
  let json = "[" + json_parts.join(",") + "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle POST /api/tasks - create a new task
async fn handle_task_create(
  ctx : RuntimeContext,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
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
  let id = extract_json_str(body_str, "id").unwrap_or(
    "task_" + ctx.task_manager.count().to_string(),
  )
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
  conn.write_string(
    "{\"status\":\"ok\",\"task_id\":\"" + json_escape(id) + "\"}",
  )
}

///|
/// Handle GET /api/super_tasks - return JSON list of super tasks
async fn handle_super_tasks_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let tasks = ctx.super_task_manager.list_all()
  let json_parts = tasks.map(fn(st) {
    "{\"id\":\"" +
    json_escape(st.id) +
    "\",\"name\":\"" +
    json_escape(st.name) +
    "\",\"description\":\"" +
    json_escape(st.description) +
    "\",\"agent_id\":\"" +
    json_escape(st.agent_id) +
    "\",\"created_at\":\"" +
    json_escape(st.created_at) +
    "\"}"
  })
  let json = "[" + json_parts.join(",") + "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle POST /api/super_tasks - create a custom super task
async fn handle_super_task_create(
  ctx : RuntimeContext,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
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

  let name = extract_json_str(body_str, "name").unwrap_or("")
  let description = extract_json_str(body_str, "description").unwrap_or("")
  let agent_id = extract_json_str(body_str, "agent_id").unwrap_or("agent_005")

  if name.length() == 0 || description.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing required fields: name, description")
    return
  }

  // Pick the first free numeric id (st_001 is reserved for the default task)
  let mut n = ctx.super_task_manager.count() + 1
  let mut id = "st_" + n.to_string()
  while ctx.super_task_manager.find(id) is Some(_) {
    n = n + 1
    id = "st_" + n.to_string()
  }
  let st = ctx.super_task_manager.create(id, name, description, agent_id)
  let _ = ctx.super_task_manager.save(ctx.data_dir + "/super_tasks.csv") catch {
    _ => Ok(())
  }

  conn.send_response(201, "Created", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(
    "{\"status\":\"ok\",\"id\":\"" +
    json_escape(st.id) +
    "\",\"name\":\"" +
    json_escape(st.name) +
    "\",\"description\":\"" +
    json_escape(st.description) +
    "\",\"agent_id\":\"" +
    json_escape(st.agent_id) +
    "\",\"created_at\":\"" +
    json_escape(st.created_at) +
    "\"}",
  )
}

///|
/// Handle DELETE /api/super_tasks?id=... - delete a custom super task
async fn handle_super_task_delete(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let id = extract_query_param(query, "id").unwrap_or("")

  if id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing id parameter")
    return
  }
  if id == "st_001" {
    conn.send_response(403, "Forbidden", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("The default super task cannot be deleted")
    return
  }

  if ctx.super_task_manager.delete(id) {
    let _ = ctx.super_task_manager.save(ctx.data_dir + "/super_tasks.csv") catch {
      _ => Ok(())
    }
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string(
      "{\"status\":\"ok\",\"deleted\":\"" + json_escape(id) + "\"}",
    )
  } else {
    conn.send_response(404, "Not Found", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Super task not found: " + id)
  }
}

///|
/// Handle GET /api/super_tasks/run?id=... - execute a super task
/// Reuses the chat SSE pipeline: the task description becomes the user message,
/// and the agent autonomously calls tools (e.g. search_web) until it reports back.
async fn handle_super_task_run(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let id = extract_query_param(query, "id").unwrap_or("")
  let agent_override = extract_query_param(query, "agent_id").unwrap_or("")

  let st = match ctx.super_task_manager.find(id) {
    Some(s) => s
    None => {
      conn.send_response(404, "Not Found", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Super task not found: " + id)
      return
    }
  }
  let agent_id = if agent_override.length() > 0 {
    agent_override
  } else {
    st.agent_id
  }
  let guided_message = st.description +
    "\n\n执行指引：请把该任务拆解为依次检索每个指数。每个指数最多搜索1-2次，第一次请用短关键词（例如: 标普500 行情 / KOSPI 行情 / 日经225 行情 / 纳斯达克 行情 / 上证指数 行情），若搜索结果中出现东方财富、新浪财经、英为财情等行情页面，即视为已获得该指数的有效行情信息，立即进入下一个指数，不要重复搜索同一主题，也不要为了追求精确点位反复重试。全部指数检索完毕后，请立即停止调用工具，用 Markdown 表格输出一份最终汇总报告，包含每个指数的走势、振幅、换手、盘内异动等信息（可注明数据为搜索结果快照，实时点位以链接页面为准），不要再调用任何工具。"
  let chat_path = "/api/chat?agent_id=" +
    @lib.url_encode(agent_id) +
    "&message=" +
    @lib.url_encode(guided_message)
  handle_chat_sse(ctx, chat_path, conn)
}

///|
/// Handle PUT /api/tasks - update task status
async fn handle_task_update(
  ctx : RuntimeContext,
  path : String,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
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

  let actual_id = if task_id.length() > 0 {
    task_id
  } else {
    extract_json_str(body_str, "id").unwrap_or("")
  }
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
  conn.write_string(
    "{\"status\":\"ok\",\"task_id\":\"" + json_escape(actual_id) + "\"}",
  )
}

///|
/// Extract a simple string value from a JSON string by key
fn extract_json_str(json : String, key : String) -> String? {
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
      let search = if string_find(json, search1) is Some(_) {
        search1
      } else {
        search2
      }
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
/// Parse temperature string to float
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

///|
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
  if result <= 0 || result > 65535 {
    8080
  } else {
    result
  }
}

///|
/// Extract query parameter value from query string
fn extract_query_param(query : String, param : String) -> String? {
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
/// Percent-encoded bytes are collected first, then decoded as one UTF-8 string,
/// so multi-byte characters (e.g. Chinese) survive the round-trip.
fn decode_url(s : String) -> String {
  let bytes : Array[Byte] = []
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int()
    if ch == 43 {
      // '+'
      bytes.push((32 : Byte))
      i = i + 1
    } else if ch == 37 && i + 2 < s.length() {
      // '%XX'
      let code = hex_to_int(s[i + 1]) * 16 + hex_to_int(s[i + 2])
      bytes.push(code.to_byte())
      i = i + 3
    } else {
      // Raw byte (may be part of a multi-byte UTF-8 char) passes through
      bytes.push(ch.to_byte())
      i = i + 1
    }
  }
  @utf8.decode(Bytes::from_array(bytes)) catch {
    _ => s
  }
}

///|
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

///|
/// Extract token usage from DeepSeek response JSON
/// Returns (prompt_tokens, completion_tokens) or None
fn extract_usage_tokens(json_str : String) -> (Int, Int)? {
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

///|
/// Parse an integer starting at a given position in a string
fn parse_int_at(s : String, start : Int) -> Int {
  let mut result = 0
  let mut i = start
  // Skip whitespace
  while i < s.length() && s[i] == ' ' {
    i = i + 1
  }
  // Skip leading digits
  let mut neg = false
  if i < s.length() && s[i] == '-' {
    neg = true
    i = i + 1
  }
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
      i = i + 1
    } else {
      break
    }
  }
  if neg {
    -result
  } else {
    result
  }
}

///|
/// Simple JSON content extraction from DeepSeek response (handles JSON escapes)
fn extract_content(json_str : String) -> String? {
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

///|
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
