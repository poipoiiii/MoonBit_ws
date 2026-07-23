///|
/// Task manager - create, schedule, and track tasks

/// Task manager
pub struct TaskManager {
  tasks : Map[String, Task]
}

/// Create a new task manager
pub fn TaskManager::new(tasks : Map[String, Task]) -> TaskManager {
  { tasks: tasks }
}

/// Load task manager from CSV file
pub async fn TaskManager::load(file_path : String) -> Result[TaskManager, String] {
  let result = load_tasks(file_path)
  let tasks = match result {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  Ok(TaskManager::new(tasks))
}

/// Find a task by ID
pub fn TaskManager::find(self : TaskManager, id : String) -> Option[Task] {
  self.tasks.get(id)
}

/// List tasks filtered by agent_id
pub fn TaskManager::list_by_agent(self : TaskManager, agent_id : String) -> Array[Task] {
  let result : Array[Task] = []
  for task in self.tasks.values() {
    if task.agent_id == agent_id {
      result.push(task)
    }
  }
  result
}

/// List all tasks
pub fn TaskManager::list_all(self : TaskManager) -> Array[Task] {
  let result : Array[Task] = []
  for task in self.tasks.values() {
    result.push(task)
  }
  result
}

/// Count number of tasks
pub fn TaskManager::count(self : TaskManager) -> Int {
  self.tasks.length()
}

/// Get pending and running tasks for a specific agent
pub fn TaskManager::pending_tasks(self : TaskManager, agent_id : String) -> Array[Task] {
  let result : Array[Task] = []
  for task in self.tasks.values() {
    if task.agent_id == agent_id {
      match task.status {
        Pending | Running => result.push(task)
        _ => ()
      }
    }
  }
  result
}

/// Create a new task
pub fn TaskManager::create_task(
  self : TaskManager,
  id : String,
  agent_id : String,
  description : String,
  priority : Int
) -> Task {
  let task = Task::{
    id: id,
    agent_id: agent_id,
    description: description,
    status: Pending,
    priority: priority,
    created_at: now_str(),
    updated_at: now_str(),
    duration_ms: 0,
  }
  self.tasks[id] = task
  task
}

/// Update task status
pub fn TaskManager::update_status(self : TaskManager, id : String, status : TaskStatus) -> Option[Task] {
  let opt_task = self.tasks.get(id)
  let task = match opt_task {
    Some(t) => t
    None => return None
  }
  task.status = status
  task.updated_at = now_str()
  Some(task)
}

/// Delete a task by ID
pub fn TaskManager::delete_task(self : TaskManager, id : String) -> Bool {
  let exists = self.tasks.get(id) is Some(_)
  if exists {
    self.tasks.remove(id)
    true
  } else {
    false
  }
}

/// Save tasks to CSV file
pub async fn TaskManager::save(self : TaskManager, file_path : String) -> Result[Unit, String] {
  save_tasks_csv(self.tasks, file_path)
}

/// Get all pending tasks (unfiltered, sorted by priority)
fn TaskManager::get_pending_tasks(self : TaskManager) -> Array[Task] {
  let result : Array[Task] = []
  for task in self.tasks.values() {
    if task.status is Pending {
      result.push(task)
    }
  }
  result.sort_by(fn(a, b) { b.priority - a.priority })
  result
}

/// Get current timestamp string
pub fn now_str() -> String {
  // Simple timestamp - in production use proper time formatting
  "2026-07-23 12:00:00"
}
