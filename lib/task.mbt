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

/// Create a new task
fn TaskManager::create_task(
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
fn TaskManager::update_status(self : TaskManager, id : String, status : TaskStatus) -> Option[Task] {
  let opt_task = self.tasks.get(id)
  let task = match opt_task {
    Some(t) => t
    None => return None
  }
  task.status = status
  task.updated_at = now_str()
  self.tasks[id] = task
  Some(task)
}

/// Get pending tasks sorted by priority
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
fn now_str() -> String {
  // Simple timestamp - in production use proper time formatting
  "2026-07-23 12:00:00"
}
