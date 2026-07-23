///|
/// Core types for AI Agent Runtime

/// Agent configuration
pub struct Agent {
  id : String
  name : String
  model : String
  instruction : String
  system_prompt : String
  max_tokens : Int
  temperature : Float
  tool_ids : String
  mut conversation : Array[ChatMessage]
}

/// Task status enum
pub enum TaskStatus {
  Pending
  Running
  Completed
  Failed(String)
}

/// Task struct
pub struct Task {
  id : String
  agent_id : String
  description : String
  mut status : TaskStatus
  priority : Int
  created_at : String
  mut updated_at : String
  duration_ms : Int
}

/// Tool definition
pub struct Tool {
  id : String
  name : String
  description : String
  input_schema : String
  enabled : Bool
  version : String
}

/// Chat message for LLM API
pub struct ChatMessage {
  role : String
  content : String
}

/// LLM response
pub struct LlmResponse {
  content : String
  tool_calls : Array[ToolCall]
}

/// Tool call from LLM
pub struct ToolCall {
  id : String
  function_name : String
  arguments : String
}

/// Runtime config loaded from env
pub struct RuntimeConfig {
  api_key : String
  api_base_url : String
  model : String
  port : Int
  data_dir : String
}

/// SSE event for streaming
pub struct SseEvent {
  event : String
  data : String
}

/// Agent usage statistics
pub struct AgentStats {
  agent_id : String
  mut total_conversations : Int
  mut total_input_chars : Int
  mut total_output_chars : Int
  mut total_prompt_tokens : Int
  mut total_completion_tokens : Int
  mut last_active_at : String
}
