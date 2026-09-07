///|
/// SSE streaming chat handler and super-task runner.

///|
/// Handle GET /api/chat - SSE streaming chat with an agent.
async fn handle_chat_sse(
  ctx : RuntimeContext,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  let query = match string_find(path, "?") {
    Some(pos) => path[pos + 1:].to_owned()
    None => ""
  }
  let agent_id = extract_query_param(query, "agent_id").unwrap_or("agent_001")
  let message = extract_query_param(query, "message").unwrap_or("Hello")

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
  // up to MAX_TOOL_ROUNDS times.
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
/// Handle GET /api/super_tasks/run?id=... - execute a super task.
/// Reuses the chat SSE pipeline: the task description becomes the user message,
/// and the agent autonomously calls tools until it reports back.
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
/// {"type":"object","properties":{...},"required":[...]}
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
/// Build the chat completion request body (stream=true).
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