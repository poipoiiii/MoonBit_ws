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

/// Build system prompt for an agent
pub fn Agent::build_prompt(self : Agent, user_input : String) -> Array[ChatMessage] {
  let system = ChatMessage::new("system", self.system_prompt)
  let instruction = ChatMessage::new("user", self.instruction + "\n\n" + user_input)
  [system, instruction]
}
