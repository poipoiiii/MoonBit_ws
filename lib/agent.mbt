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

/// Create a new agent
pub fn AgentManager::create_agent(
  self : AgentManager,
  id : String,
  name : String,
  model : String,
  instruction : String,
  system_prompt : String,
  max_tokens : Int,
  temperature : Float,
  tool_ids : String,
) -> Agent {
  let agent = Agent::{
    id: id,
    name: name,
    model: model,
    instruction: instruction,
    system_prompt: system_prompt,
    max_tokens: max_tokens,
    temperature: temperature,
    tool_ids: tool_ids,
    conversation: [],
  }
  self.agents[id] = agent
  agent
}

/// Update an existing agent's mutable fields
pub fn AgentManager::update_agent(
  self : AgentManager,
  id : String,
  name~ : String = "",
  model~ : String = "",
  instruction~ : String = "",
  system_prompt~ : String = "",
  max_tokens~ : Int = 0,
  temperature~ : Float = 0.0,
  tool_ids~ : String = "",
) -> Option[Agent] {
  match self.agents.get(id) {
    None => None
    Some(existing) => {
      let new_name = if name.length() > 0 { name } else { existing.name }
      let new_model = if model.length() > 0 { model } else { existing.model }
      let new_instruction = if instruction.length() > 0 { instruction } else { existing.instruction }
      let new_system_prompt = if system_prompt.length() > 0 { system_prompt } else { existing.system_prompt }
      let new_max_tokens = if max_tokens > 0 { max_tokens } else { existing.max_tokens }
      let new_temperature = if temperature > 0.0 { temperature } else { existing.temperature }
      let new_tool_ids = if tool_ids.length() > 0 { tool_ids } else { existing.tool_ids }
      
      let updated = Agent::{
        id: existing.id,
        name: new_name,
        model: new_model,
        instruction: new_instruction,
        system_prompt: new_system_prompt,
        max_tokens: new_max_tokens,
        temperature: new_temperature,
        tool_ids: new_tool_ids,
        conversation: existing.conversation,
      }
      self.agents[id] = updated
      Some(updated)
    }
  }
}

/// Delete an agent by ID
pub fn AgentManager::delete_agent(self : AgentManager, id : String) -> Bool {
  let exists = self.agents.get(id) is Some(_)
  if exists {
    self.agents.remove(id)
    true
  } else {
    false
  }
}

/// Save agents to CSV file
pub async fn AgentManager::save(self : AgentManager, file_path : String) -> Result[Unit, String] {
  save_agents_csv(self.agents, file_path)
}

/// Get underlying agents map
pub fn AgentManager::get_agents(self : AgentManager) -> Map[String, Agent] {
  self.agents
}

/// Get agents file path from data directory
pub fn agents_file_path(data_dir : String) -> String {
  data_dir + "/agents.csv"
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

/// Stats manager - track agent usage statistics
pub struct StatsManager {
  stats : Map[String, AgentStats]
}

/// Create a new stats manager
pub fn StatsManager::new(stats : Map[String, AgentStats]) -> StatsManager {
  { stats: stats }
}

/// Initialize stats from agent manager
pub fn StatsManager::init(self : StatsManager, agent_manager : AgentManager) -> Unit {
  let agents = agent_manager.list_all()
  for agent in agents {
    if self.stats.get(agent.id) is None {
      self.stats[agent.id] = AgentStats::{
        agent_id: agent.id,
        total_conversations: 0,
        total_input_chars: 0,
        total_output_chars: 0,
        total_prompt_tokens: 0,
        total_completion_tokens: 0,
        last_active_at: "",
      }
    }
  }
}

/// Record a conversation for an agent
pub fn StatsManager::record_conversation(
  self : StatsManager,
  agent_id : String,
  input_chars : Int,
  output_chars : Int,
  prompt_tokens~ : Int = 0,
  completion_tokens~ : Int = 0
) -> Unit {
  match self.stats.get(agent_id) {
    Some(s) => {
      s.total_conversations = s.total_conversations + 1
      s.total_input_chars = s.total_input_chars + input_chars
      s.total_output_chars = s.total_output_chars + output_chars
      s.total_prompt_tokens = s.total_prompt_tokens + prompt_tokens
      s.total_completion_tokens = s.total_completion_tokens + completion_tokens
      s.last_active_at = now_str()
    }
    None => {
      self.stats[agent_id] = AgentStats::{
        agent_id: agent_id,
        total_conversations: 1,
        total_input_chars: input_chars,
        total_output_chars: output_chars,
        total_prompt_tokens: prompt_tokens,
        total_completion_tokens: completion_tokens,
        last_active_at: now_str(),
      }
    }
  }
}

/// Get stats for a specific agent
pub fn StatsManager::get_stats(self : StatsManager, agent_id : String) -> Option[AgentStats] {
  self.stats.get(agent_id)
}

/// Get stats for all agents
pub fn StatsManager::get_all_stats(self : StatsManager) -> Array[AgentStats] {
  let result : Array[AgentStats] = []
  for s in self.stats.values() {
    result.push(s)
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
