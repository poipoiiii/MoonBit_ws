///|
/// CSV utility functions for reading agent/task/tool data

/// Read a CSV file and return rows as array of string arrays
async fn read_csv(file_path : String) -> Result[Array[Array[String]], String] {
  let file = @fs.open(file_path, mode=@fs.Mode::ReadOnly) catch {
    _ => return Err("Cannot open file: \{file_path}")
  }
  let data = file.read_all() catch {
    _ => { file.close(); return Err("Cannot read file: \{file_path}") }
  }
  file.close()
  let content = data.text() catch {
    _ => return Err("Invalid UTF-8 in file: \{file_path}")
  }
  
  // Split into lines and filter empty ones
  let lines_iter = content.split("\n")
  let lines : Array[String] = []
  for line_view in lines_iter {
    let line = line_view.to_owned()
    if line.length() > 0 {
      lines.push(line)
    }
  }
  
  if lines.length() < 2 {
    return Err("CSV file has no data rows")
  }
  
  // Skip header row
  let rows : Array[Array[String]] = []
  let mut j = 1
  while j < lines.length() {
    rows.push(parse_csv_line(lines[j]))
    j = j + 1
  }
  
  Ok(rows)
}

/// Parse a single CSV line into fields (handles quoted fields)
fn parse_csv_line(line : String) -> Array[String] {
  let fields : Array[String] = []
  let mut current = ""
  let mut in_quotes = false
  let mut i = 0
  while i < line.length() {
    let ch = line[i]
    if ch == '"' {
      in_quotes = !in_quotes
    } else if ch == ',' && !in_quotes {
      fields.push(current.trim().to_owned())
      current = ""
    } else {
      match ch.to_char() {
        Some(c) => current = current + c.to_string()
        None => ()
      }
    }
    i = i + 1
  }
  fields.push(current.trim().to_owned())
  fields
}

/// Parse status string to TaskStatus
fn parse_status(s : String) -> TaskStatus {
  match s {
    "completed" => Completed
    "running" => Running
    "pending" => Pending
    _ => Pending
  }
}

/// Convert priority string to int
fn priority_to_int(p : String) -> Int {
  match p {
    "high" => 3
    "medium" => 2
    "low" => 1
    _ => 0
  }
}

/// Parse string to int, default to 0 on failure
fn parse_int(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  let mut neg = false
  if s.length() == 0 { return 0 }
  if s[0] == '-' { neg = true; i = 1 }
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
    } else {
      return 0
    }
    i = i + 1
  }
  if neg { -result } else { result }
}

/// Parse string to float, default to 0.0 on failure
fn parse_float(s : String) -> Float {
  let result = parse_int(s)
  Float::from_int(result)
}

/// Load agents from CSV file
/// Expected columns: id,name,model,instruction,system_prompt,max_tokens,temperature,tool_ids
async fn load_agents(file_path : String) -> Result[Map[String, Agent], String] {
  let rows_result = read_csv(file_path)
  let rows = match rows_result {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  
  let agents : Map[String, Agent] = Map([], capacity=rows.length())
  for row in rows {
    if row.length() >= 8 {
      let agent = Agent::{
        id: row[0],
        name: row[1],
        model: row[2],
        instruction: row[3],
        system_prompt: row[4],
        max_tokens: parse_int(row[5]),
        temperature: parse_float(row[6]),
        tool_ids: row[7],
      }
      agents[agent.id] = agent
    } else if row.length() >= 7 {
      // Backward compat: no tool_ids column
      let agent = Agent::{
        id: row[0],
        name: row[1],
        model: row[2],
        instruction: row[3],
        system_prompt: row[4],
        max_tokens: parse_int(row[5]),
        temperature: parse_float(row[6]),
        tool_ids: "",
      }
      agents[agent.id] = agent
    }
  }
  Ok(agents)
}

/// Load tools from CSV file
async fn load_tools(file_path : String) -> Result[Map[String, Tool], String] {
  let rows_result = read_csv(file_path)
  let rows = match rows_result {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  
  // Debug: count rows
  let row_count = rows.length()
  println("DEBUG load_tools: rows=" + row_count.to_string())
  
  let tools : Map[String, Tool] = Map([], capacity=rows.length())
  for row in rows {
    let field_count = row.length()
    if field_count >= 6 {
      let enabled_val = row[4]
      let is_enabled = enabled_val == "true"
      // Debug: print raw field 4 content length
      println("DEBUG tool: fields=" + field_count.to_string() + " enabled_raw_len=" + enabled_val.length().to_string())
      let tool = Tool::{
        id: row[0],
        name: row[1],
        description: row[2],
        input_schema: row[3],
        enabled: is_enabled,
        version: row[5],
      }
      tools[tool.id] = tool
    } else {
      println("DEBUG tool: SKIP fields=" + field_count.to_string())
    }
  }
  
  let loaded_count = tools.length()
  println("DEBUG load_tools: loaded=" + loaded_count.to_string())
  Ok(tools)
}

/// Load tasks from CSV file
async fn load_tasks(file_path : String) -> Result[Map[String, Task], String] {
  let rows_result = read_csv(file_path)
  let rows = match rows_result {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  
  let tasks : Map[String, Task] = Map([], capacity=rows.length())
  for row in rows {
    if row.length() >= 8 {
      let status = parse_status(row[3])
      let task = Task::{
        id: row[0],
        agent_id: row[1],
        description: row[2],
        status: status,
        priority: priority_to_int(row[4]),
        created_at: row[5],
        updated_at: row[6],
        duration_ms: parse_int(row[7]),
      }
      tasks[task.id] = task
    }
  }
  Ok(tasks)
}
