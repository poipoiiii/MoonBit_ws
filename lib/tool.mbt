///|
/// Tool registry - manage and execute tools

/// Tool registry
pub struct ToolRegistry {
  tools : Map[String, Tool]
}

/// Create new tool registry
pub fn ToolRegistry::new(tools : Map[String, Tool]) -> ToolRegistry {
  { tools: tools }
}

/// Load tool registry from CSV file
pub async fn ToolRegistry::load(file_path : String) -> Result[ToolRegistry, String] {
  let result = load_tools(file_path)
  let tools = match result {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  Ok(ToolRegistry::new(tools))
}

/// Find a tool by ID
pub fn ToolRegistry::find(self : ToolRegistry, id : String) -> Option[Tool] {
  self.tools.get(id)
}

/// List all enabled tools
pub fn ToolRegistry::list_enabled(self : ToolRegistry) -> Array[Tool] {
  let result : Array[Tool] = []
  for tool in self.tools.values() {
    if tool.enabled {
      result.push(tool)
    }
  }
  result
}

/// List all tools
pub fn ToolRegistry::list_all(self : ToolRegistry) -> Array[Tool] {
  let result : Array[Tool] = []
  for tool in self.tools.values() {
    result.push(tool)
  }
  result
}

/// Get tool as JSON array string for LLM function calling
pub fn ToolRegistry::to_function_json(self : ToolRegistry) -> String {
  let enabled_tools = self.list_enabled()
  let tool_jsons = enabled_tools.map(fn(t) {
    "{\"type\":\"function\",\"function\":{\"name\":\"\{t.name}\",\"description\":\"\{t.description}\",\"parameters\":\{t.input_schema}}}"
  })
  "[" + tool_jsons.join(",") + "]"
}
