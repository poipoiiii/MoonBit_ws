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

/// Add a message to an agent's conversation history
pub fn AgentManager::add_message(self : AgentManager, agent_id : String, role : String, content : String) -> Unit {
  match self.agents.get(agent_id) {
    Some(agent) => {
      agent.conversation.push(ChatMessage::new(role, content))
    }
    None => ()
  }
}

/// Get an agent's conversation history
pub fn AgentManager::get_conversation(self : AgentManager, agent_id : String) -> Array[ChatMessage] {
  match self.agents.get(agent_id) {
    Some(agent) => agent.conversation
    None => []
  }
}

/// Clear an agent's conversation history
pub fn AgentManager::clear_conversation(self : AgentManager, agent_id : String) -> Unit {
  match self.agents.get(agent_id) {
    Some(agent) => { agent.conversation = [] }
    None => ()
  }
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

/// Build system prompt with tool information, tasks and conversation history injected
pub fn Agent::build_prompt(
  self : Agent,
  user_input : String,
  registry : ToolRegistry,
  task_manager : TaskManager,
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
  
  // Inject pending/running tasks if any
  let pending = task_manager.pending_tasks(self.id)
  if pending.length() > 0 {
    system_text = system_text + "\n\n## 待处理任务\n以下是分配给当前 Agent 的待处理任务：\n"
    for task in pending {
      let status_str = match task.status {
        Pending => "待处理"
        Running => "进行中"
        _ => ""
      }
      system_text = system_text + "- [" + status_str + "] " + task.id + ": " + task.description + "\n"
    }
    system_text = system_text + "\n请优先处理上述任务。完成任务后，使用更新任务状态工具标记任务完成。"
  }
  
  let system = ChatMessage::new("system", system_text)
  
  // Build message list: system + conversation history + current instruction
  let messages : Array[ChatMessage] = [system]
  
  // Add conversation history (limit to last 10 messages to avoid token overflow)
  let history = self.conversation
  let start_idx = if history.length() > 10 { history.length() - 10 } else { 0 }
  let mut i = start_idx
  while i < history.length() {
    messages.push(history[i])
    i = i + 1
  }
  
  // Add current user instruction
  let instruction = ChatMessage::new("user", self.instruction + "\n\n" + user_input)
  messages.push(instruction)
  
  messages
}
