///|
/// Super task manager - user-defined complex tasks executed by an agent.
/// A super task is a named, reusable instruction (e.g. "research these stock
/// indices"); running it sends the description to an agent which autonomously
/// calls tools to complete it. Users can create their own tasks.

/// A super task definition
pub struct SuperTask {
  id : String
  name : String
  description : String
  agent_id : String
  created_at : String
}

/// Super task manager
pub struct SuperTaskManager {
  tasks : Map[String, SuperTask]
}

/// Create a new super task manager
pub fn SuperTaskManager::new(tasks : Map[String, SuperTask]) -> SuperTaskManager {
  { tasks: tasks }
}

/// Load super task manager from CSV file
/// Expected columns: id,name,description,agent_id,created_at
pub async fn SuperTaskManager::load(file_path : String) -> Result[SuperTaskManager, String] {
  let rows = match read_csv(file_path) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let tasks : Map[String, SuperTask] = Map([], capacity=rows.length())
  for row in rows {
    if row.length() >= 5 {
      let st = SuperTask::{
        id: row[0],
        name: row[1],
        description: row[2],
        agent_id: row[3],
        created_at: row[4],
      }
      tasks[st.id] = st
    }
  }
  Ok(SuperTaskManager::new(tasks))
}

/// Find a super task by ID
pub fn SuperTaskManager::find(self : SuperTaskManager, id : String) -> Option[SuperTask] {
  self.tasks.get(id)
}

/// List all super tasks
pub fn SuperTaskManager::list_all(self : SuperTaskManager) -> Array[SuperTask] {
  let result : Array[SuperTask] = []
  for st in self.tasks.values() {
    result.push(st)
  }
  result
}

/// Count number of super tasks
pub fn SuperTaskManager::count(self : SuperTaskManager) -> Int {
  self.tasks.length()
}

/// Create a new super task and add it to the manager
pub fn SuperTaskManager::create(
  self : SuperTaskManager,
  id : String,
  name : String,
  description : String,
  agent_id : String
) -> SuperTask {
  let st = SuperTask::{
    id: id,
    name: name,
    description: description,
    agent_id: agent_id,
    created_at: now_str(),
  }
  self.tasks[id] = st
  st
}

/// Delete a super task by ID, returns false if not found
pub fn SuperTaskManager::delete(self : SuperTaskManager, id : String) -> Bool {
  let exists = self.tasks.get(id) is Some(_)
  if exists {
    self.tasks.remove(id)
    true
  } else {
    false
  }
}

/// Save super tasks to CSV file
pub async fn SuperTaskManager::save(self : SuperTaskManager, file_path : String) -> Result[Unit, String] {
  let mut content = "id,name,description,agent_id,created_at\n"
  for st in self.tasks.values() {
    content = content + st.id + ","
    content = content + csv_escape(st.name) + ","
    content = content + csv_escape(st.description) + ","
    content = content + csv_escape(st.agent_id) + ","
    content = content + st.created_at + "\n"
  }
  @fs.write_file(file_path, content, create_mode=@fs.CreateOrTruncate) catch {
    _ => return Err("Cannot write file: " + file_path)
  }
  Ok(())
}
