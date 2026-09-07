///|
/// Conversation persistence and memory window management.
///
/// Conversations are persisted per agent to a single JSON file under the data
/// directory (`chat_history.json`) so multi-turn chat survives restarts.
/// History is stored as a JSON object mapping `agent_id` to an array of
/// `{ "role", "content" }` messages.
///
/// A char-budget memory window (`MAX_HISTORY_CHARS`) keeps the tail of each
/// agent's history within budget when building the LLM prompt, replacing the
/// previous fixed-size last-10-messages cutoff.

///|
/// Max total characters of conversation history fed into the model prompt.
pub const MAX_HISTORY_CHARS : Int = 8000

///|
/// Persist every agent's non-empty conversation to `file_path` as JSON.
pub async fn AgentManager::save_chat_history(
  self : AgentManager,
  file_path : String,
) -> Result[Unit, String] {
  let obj : Map[String, Json] = Map([], capacity=0)
  for agent in self.agents.values() {
    if agent.conversation.length() > 0 {
      obj[agent.id] = conversation_to_json(agent.conversation)
    }
  }
  let json = Json::object(obj)
  @fs.write_file(file_path, json.to_string(), create_mode=@fs.CreateOrTruncate) catch {
    _ => return Err("Cannot write conversation history file: " + file_path)
  }
  Ok(())
}

///|
/// Load persisted conversations from `file_path`, attaching history to each
/// known agent. Missing or corrupt files are ignored so startup never fails.
pub async fn AgentManager::load_chat_history(
  self : AgentManager,
  file_path : String,
) -> Unit {
  let file_result = @fs.open(file_path, mode=@fs.Mode::ReadOnly) catch {
    _ => return
  }
  defer file_result.close()
  let data = file_result.read_all() catch {
    _ => return
  }
  let content = data.text() catch {
    _ => return
  }
  let json = try {
    @json.parse(content)
  } catch {
    _ => return
  }
  match json {
    Object(obj) =>
      for agent_id in obj.keys() {
        match obj.get(agent_id) {
          Some(arr_json) => {
            match arr_json {
              Array(arr) => {
                let history = messages_from_json(arr)
                match self.agents.get(agent_id) {
                  Some(agent) => agent.conversation = history
                  None => ()
                }
              }
              _ => ()
            }
          }
          None => ()
        }
      }
    _ => ()
  }
}

///|
/// Truncate a conversation to the most recent messages whose total content fits
/// within `max_chars`. Always returns the tail of the history.
pub fn truncate_conversation(
  history : Array[ChatMessage],
  max_chars : Int,
) -> Array[ChatMessage] {
  if history.length() == 0 {
    return history
  }
  let mut total = 0
  let mut from = history.length()
  let mut i = history.length() - 1
  while i >= 0 {
    total = total + history[i].content.length() + history[i].role.length()
    if total > max_chars {
      break
    }
    from = i
    i = i - 1
  }
  // Always keep at least the last message even when it alone overruns the budget.
  if from == history.length() {
    from = history.length() - 1
  }
  let result : Array[ChatMessage] = []
  let mut j = from
  while j < history.length() {
    result.push(history[j])
    j = j + 1
  }
  result
}

///|
/// Serialize an array of chat messages to a JSON array.
fn conversation_to_json(history : Array[ChatMessage]) -> Json {
  let arr : Array[Json] = []
  for msg in history {
    arr.push(
      Json::object({
        "role": Json::string(msg.role),
        "content": Json::string(msg.content),
      }),
    )
  }
  Json::array(arr)
}

///|
/// Deserialize a JSON array of { role, content } into chat messages.
fn messages_from_json(arr : Array[Json]) -> Array[ChatMessage] {
  let result : Array[ChatMessage] = []
  for m in arr {
    match m {
      Object(obj) => {
        let role = match obj.get("role") {
          Some(String(s)) => s
          _ => ""
        }
        let content = match obj.get("content") {
          Some(String(c)) => c
          _ => ""
        }
        result.push(ChatMessage::new(role, content))
      }
      _ => ()
    }
  }
  result
}