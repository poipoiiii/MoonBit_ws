///|
/// Agent manager - load, find, and manage agents

/// Agent manager
pub struct AgentManager {
  agents : Map[String, Agent]
}

/// Create a new agent manager from loaded agents
pub fn AgentManager::new(agents : Map[String, Agent]) -> AgentManager {
  { agents: agents }
}

/// Load agent manager from CSV file
pub async fn AgentManager::load(file_path : String) -> Result[AgentManager, String] {
  let result = load_agents(file_path)
  let agents = match result {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  Ok(AgentManager::new(agents))
}

/// Find an agent by ID
pub fn AgentManager::find(self : AgentManager, id : String) -> Option[Agent] {
  self.agents.get(id)
}

/// List all agents
pub fn AgentManager::list_all(self : AgentManager) -> Array[Agent] {
  let result : Array[Agent] = []
  for agent in self.agents.values() {
    result.push(agent)
  }
  result
}

/// Get number of agents
pub fn AgentManager::count(self : AgentManager) -> Int {
  self.agents.size()
}

/// Get tools assigned to this agent from the registry
pub fn Agent::get_tools(self : Agent, registry : ToolRegistry) -> Array[Tool] {
  if self.tool_ids.length() == 0 {
    return []
  }
  let ids_iter = self.tool_ids.split(",")
  let result : Array[Tool] = []
  for tid_view in ids_iter {
    let tid = tid_view.trim().to_owned()
    if tid.length() > 0 {
      match registry.find(tid) {
        Some(t) => {
          if t.enabled { result.push(t) }
        }
        None => ()
      }
    }
  }
  result
}

/// Build system prompt with tool information injected
pub fn Agent::build_prompt(
  self : Agent,
  user_input : String,
  registry : ToolRegistry,
) -> Array[ChatMessage] {
  let mut system_text = self.system_prompt
  
  // Inject tool information if agent has assigned tools
  let tools = self.get_tools(registry)
  if tools.length() > 0 {
    system_text = system_text + "\n\n## 可用工具\n你可以使用以下工具来完成任务：\n"
    for tool in tools {
      system_text = system_text + "- " + tool.name + ": " + tool.description + "\n"
    }
    system_text = system_text + "\n使用工具时，请以JSON格式返回工具调用："
    system_text = system_text + " {\"tool\": \"工具名\", \"args\": {...}}"
  }
  
  let system = ChatMessage::new("system", system_text)
  let instruction = ChatMessage::new("user", self.instruction + "\n\n" + user_input)
  [system, instruction]
}
