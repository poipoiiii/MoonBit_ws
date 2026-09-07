///|
/// RuntimeContext - immutable config shared across HTTP request handlers.
pub struct RuntimeContext {
  api_key : String
  model : String
  agent_manager : @lib.AgentManager
  tool_registry : @lib.ToolRegistry
  task_manager : @lib.TaskManager
  super_task_manager : @lib.SuperTaskManager
  stats_manager : @lib.StatsManager
  data_dir : String
  cors_origin : String
  total_memory_mb : Int
}

///|
/// Construct a runtime context (used by the executable entry point).
pub fn RuntimeContext::new(
  api_key : String,
  model : String,
  agent_manager : @lib.AgentManager,
  tool_registry : @lib.ToolRegistry,
  task_manager : @lib.TaskManager,
  super_task_manager : @lib.SuperTaskManager,
  stats_manager : @lib.StatsManager,
  data_dir : String,
  cors_origin : String,
  total_memory_mb : Int,
) -> RuntimeContext {
  {
    api_key,
    model,
    agent_manager,
    tool_registry,
    task_manager,
    super_task_manager,
    stats_manager,
    data_dir,
    cors_origin,
    total_memory_mb,
  }
}

///|
/// Parse a port string to int, falling back to 8080 on invalid input.
pub fn parse_port(s : String) -> Int {
  let mut result = 0
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
    } else {
      return 8080
    }
    i = i + 1
  }
  if result <= 0 || result > 65535 {
    8080
  } else {
    result
  }
}

///|
/// Query total physical memory in MB via PowerShell (called once at startup)
pub async fn system_info() -> Int {
  let script = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $os=Get-CimInstance Win32_OperatingSystem; Write-Output ([math]::Round($os.TotalVisibleMemorySize*1KB/1MB).ToString())"
  let (_, output) = @process.collect_stdout("powershell", [
    "-NoProfile", "-NonInteractive", "-Command", script,
  ]) catch {
    _ => return 0
  }
  let raw = output.text() catch { _ => return 0 }
  parse_clean_int(raw)
}

///|
/// Query the runtime process working set (MB) and CPU time (ms) via PowerShell
pub async fn process_stats() -> (Int, Int) {
  let script = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $p=Get-Process -Name main -ErrorAction SilentlyContinue; if($p){Write-Output ([math]::Round($p.WorkingSet64/1MB).ToString() + ';' + [math]::Round($p.CPU*1000).ToString())}else{Write-Output '0;0'}"
  let (_, output) = @process.collect_stdout("powershell", [
    "-NoProfile", "-NonInteractive", "-Command", script,
  ]) catch {
    _ => return (0, 0)
  }
  let raw = output.text() catch { _ => return (0, 0) }
  parse_pair_clean(raw)
}

///|
/// Keep only ASCII digit bytes (tolerates BOM/UTF-16 nulls/whitespace) and parse as int
fn parse_clean_int(s : String) -> Int {
  let mut cleaned = ""
  let mut i = 0
  while i < s.length() {
    let b = s[i]
    if b >= 48 && b <= 57 {
      cleaned = cleaned + (b.to_int() - 48).to_string()
    }
    i = i + 1
  }
  @lib.parse_int(cleaned)
}

///|
/// Parse "a;b" output into a pair of ints, tolerating BOM/UTF-16 nulls/whitespace
fn parse_pair_clean(s : String) -> (Int, Int) {
  let mut cleaned = ""
  let mut i = 0
  while i < s.length() {
    let b = s[i]
    if b >= 48 && b <= 57 {
      cleaned = cleaned + (b.to_int() - 48).to_string()
    } else if b == 59 {
      cleaned = cleaned + ";"
    }
    i = i + 1
  }
  let parts = cleaned.split(";").to_array()
  if parts.length() >= 2 {
    (@lib.parse_int(parts[0].to_owned()), @lib.parse_int(parts[1].to_owned()))
  } else {
    (0, 0)
  }
}