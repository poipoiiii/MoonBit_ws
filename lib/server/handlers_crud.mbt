///|
/// HTTP request routing and CRUD handlers (agents / tasks / tools / runtime /
/// super tasks / chat history). Request-body JSON parsing uses @json.

///|
/// Route requests to the appropriate handler.
pub async fn handle_request(
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
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "text/html; charset=utf-8",
      })
      conn.write_string(index_html())
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
/// Read the full request body as a UTF-8 string, writing a 400 on failure.
/// Returns the body string, or None if the request should be short-circuited.
async fn read_body(
  conn : @http.ServerConnection,
  ctx : RuntimeContext,
  body : &@io.Reader,
) -> String? {
  let body_data = body.read_all() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Cannot read request body")
      return None
    }
  }
  let body_str = body_data.text() catch {
    _ => {
      conn.send_response(400, "Bad Request", extra_headers={
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": ctx.cors_origin,
      })
      conn.write_string("Invalid UTF-8 in request body")
      return None
    }
  }
  Some(body_str)
}

///|
/// Handle GET /api/agents - return JSON list of agents
async fn handle_agents_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let agents = ctx.agent_manager.list_all()
  let json_parts = agents.map(fn(a) {
    let stats_json = match ctx.stats_manager.get_stats(a.id) {
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
  let body_str = match read_body(conn, ctx, body) {
    Some(b) => b
    None => return
  }

  let id = json_field_string(body_str, "id").unwrap_or("")
  let name = json_field_string(body_str, "name").unwrap_or("")
  let model = json_field_string(body_str, "model").unwrap_or(ctx.model)
  let instruction = json_field_string(body_str, "instruction").unwrap_or("")
  let system_prompt = json_field_string(body_str, "system_prompt").unwrap_or("")
  let max_tokens_str = json_field_string(body_str, "max_tokens").unwrap_or(
    "4096",
  )
  let temperature_str = json_field_string(body_str, "temperature").unwrap_or(
    "0.3",
  )
  let tool_ids = json_field_string(body_str, "tool_ids").unwrap_or("")

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
  let _ = ctx.agent_manager.save(ctx.data_dir + "/agents.csv") catch {
    _ => Ok(())
  }

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

  let body_str = match read_body(conn, ctx, body) {
    Some(b) => b
    None => return
  }

  // Use query param id first, then fall back to body id
  let actual_id = if agent_id.length() > 0 {
    agent_id
  } else {
    json_field_string(body_str, "id").unwrap_or("")
  }

  if actual_id.length() == 0 {
    conn.send_response(400, "Bad Request", extra_headers={
      "Content-Type": "text/plain",
      "Access-Control-Allow-Origin": ctx.cors_origin,
    })
    conn.write_string("Missing agent id")
    return
  }

  let name = json_field_string(body_str, "name").unwrap_or("")
  let model = json_field_string(body_str, "model").unwrap_or("")
  let instruction = json_field_string(body_str, "instruction").unwrap_or("")
  let system_prompt = json_field_string(body_str, "system_prompt").unwrap_or("")
  let max_tokens_str = json_field_string(body_str, "max_tokens").unwrap_or("")
  let temperature_str = json_field_string(body_str, "temperature").unwrap_or("")
  let tool_ids = json_field_string(body_str, "tool_ids").unwrap_or("")

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
      let _ = ctx.agent_manager.save(ctx.data_dir + "/agents.csv") catch {
        _ => Ok(())
      }

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
    let _ = ctx.agent_manager.save(ctx.data_dir + "/agents.csv") catch {
      _ => Ok(())
    }

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
/// Handle GET /api/agents/detail - detailed agent info with tools, tasks, stats
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

  // Tools assigned to this agent
  let tools = agent.get_tools(ctx.tool_registry)
  let tools_array = "[" +
    tools
      .map(fn(t) {
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
      .join(",") +
    "]"

  // Tasks for this agent
  let tasks = ctx.task_manager.list_by_agent(agent_id)
  let tasks_array = "[" +
    tasks
      .map(fn(t) {
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
      .join(",") +
    "]"

  // Stats
  let stats_json = match ctx.stats_manager.get_stats(agent_id) {
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

  let history_count = ctx.agent_manager.get_conversation(agent_id).length()

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
/// Handle GET /api/agents/stats - return agent statistics
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
    let all_stats = ctx.stats_manager.get_all_stats()
    "[" +
    all_stats
      .map(fn(s) {
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
      .join(",") +
    "]"
  }

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle GET /api/tools - return JSON list of enabled tools
async fn handle_tools_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let tools = ctx.tool_registry.list_enabled()
  let json = "[" +
    tools
      .map(fn(t) {
        "{\"id\":\"" +
        t.id +
        "\",\"name\":\"" +
        t.name +
        "\",\"description\":\"" +
        t.description +
        "\",\"enabled\":true}"
      })
      .join(",") +
    "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle GET /api/runtime - return process memory and CPU usage
async fn handle_runtime_json(
  ctx : RuntimeContext,
  conn : @http.ServerConnection,
) -> Unit {
  let (memory_mb, cpu_ms) = process_stats()
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
/// Handle GET /api/chat/history - return conversation history for an agent
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
  let json = "[" +
    history
      .map(fn(msg) {
        "{\"role\":\"" +
        json_escape(msg.role) +
        "\",\"content\":\"" +
        json_escape(msg.content) +
        "\"}"
      })
      .join(",") +
    "]"

  conn.send_response(200, "OK", extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": ctx.cors_origin,
  })
  conn.write_string(json)
}

///|
/// Handle GET /api/chat/clear - clear conversation history for an agent
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

  let json = "[" +
    tasks
      .map(fn(t) {
        let status_str = match t.status {
          @lib.Pending => "\"pending\""
          @lib.Running => "\"running\""
          @lib.Completed => "\"completed\""
          @lib.Failed(_) => "\"failed\""
        }
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
        t.duration_ms.to_string() +
        "}"
      })
      .join(",") +
    "]"

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
  let body_str = match read_body(conn, ctx, body) {
    Some(b) => b
    None => return
  }

  let id = json_field_string(body_str, "id").unwrap_or(
    "task_" + ctx.task_manager.count().to_string(),
  )
  let agent_id = json_field_string(body_str, "agent_id").unwrap_or("")
  let description = json_field_string(body_str, "description").unwrap_or("")
  let priority = @lib.parse_int(
    json_field_string(body_str, "priority").unwrap_or("0"),
  )

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
  let json = "[" +
    tasks
      .map(fn(st) {
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
      .join(",") +
    "]"

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
  let body_str = match read_body(conn, ctx, body) {
    Some(b) => b
    None => return
  }

  let name = json_field_string(body_str, "name").unwrap_or("")
  let description = json_field_string(body_str, "description").unwrap_or("")
  let agent_id = json_field_string(body_str, "agent_id").unwrap_or("agent_005")

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

  let body_str = match read_body(conn, ctx, body) {
    Some(b) => b
    None => return
  }

  let actual_id = if task_id.length() > 0 {
    task_id
  } else {
    json_field_string(body_str, "id").unwrap_or("")
  }
  let status_str = json_field_string(body_str, "status").unwrap_or("")

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