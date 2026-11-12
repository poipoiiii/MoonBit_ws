///|
/// Core types for AI Agent Runtime

///|
/// Agent configuration
pub struct Agent {
  id : String
  name : String
  model : String
  instruction : String
  system_prompt : String
  max_tokens : Int32
  temperature : Float
  tool_ids : String
  mut conversation : Array[ChatMessage]
}

///|
/// Task status enum
pub enum TaskStatus {
  Pending
  Running
  Completed
  Failed(String)
}

///|
/// Task struct
pub struct Task {
  id : String
  agent_id : String
  description : String
  mut status : TaskStatus
  priority : Int32
  created_at : String
  mut updated_at : String
  duration_ms : Int32
}

///|
/// Tool definition
pub struct Tool {
  id : String
  name : String
  description : String
  input_schema : String
  enabled : Bool
  version : String
}

///|
/// Chat message for LLM API
pub struct ChatMessage {
  role : String
  content : String
}

///|
/// Agent usage statistics
pub struct AgentStats {
  agent_id : String
  mut total_conversations : Int32
  mut total_input_chars : Int32
  mut total_output_chars : Int32
  mut total_prompt_tokens : Int32
  mut total_completion_tokens : Int32
  mut last_active_at : String
}
