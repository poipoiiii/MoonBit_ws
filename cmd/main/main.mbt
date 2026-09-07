///|
/// AI Agent Runtime - executable entry point.
/// Loads configuration, wires up the domain managers, and starts the HTTP
/// server. All request handling lives in the lib/server package.

///|
/// Main entry point
async fn main {
  // Load configuration from environment variables
  let api_key = match @env.get_env_var("DEEPSEEK_API_KEY") {
    Some(key) => key
    None => {
      println("Error: DEEPSEEK_API_KEY environment variable not set")
      println(
        "Please set it before running: $env:DEEPSEEK_API_KEY=\"your-key\"",
      )
      return
    }
  }

  let model = @env.get_env_var("DEEPSEEK_MODEL").unwrap_or("deepseek-chat")
  let port_str = @env.get_env_var("PORT").unwrap_or("8080")
  let port = @server.parse_port(port_str)
  let data_dir = @env.get_env_var("DATA_DIR").unwrap_or("static/data")
  let cors_origin = @env.get_env_var("CORS_ORIGIN").unwrap_or("*")

  println("Starting AI Agent Runtime...")
  println("Model: \{model}")
  println("Port: \{port}")
  println("Data: \{data_dir}")

  // Load data from CSV files
  let agent_manager = match @lib.AgentManager::load(data_dir + "/agents.csv") {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} agents")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load agents: \{e}")
      @lib.AgentManager::new(Map([], capacity=0))
    }
  }

  let tool_registry = match @lib.ToolRegistry::load(data_dir + "/tools.csv") {
    Ok(reg) => {
      let all = reg.list_all()
      println(
        "Loaded \{all.length()} tools (enabled: \{reg.list_enabled().length()})",
      )
      reg
    }
    Err(e) => {
      println("Warning: Failed to load tools: \{e}")
      @lib.ToolRegistry::new(Map([], capacity=0))
    }
  }

  let task_manager = match @lib.TaskManager::load(data_dir + "/tasks.csv") {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} tasks")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load tasks: \{e}")
      @lib.TaskManager::new(Map([], capacity=0))
    }
  }

  let super_task_manager = match
    @lib.SuperTaskManager::load(data_dir + "/super_tasks.csv") {
    Ok(mgr) => {
      println("Loaded \{mgr.count()} super tasks")
      mgr
    }
    Err(e) => {
      println("Warning: Failed to load super tasks: \{e}")
      @lib.SuperTaskManager::new(Map([], capacity=0))
    }
  }

  // Initialize stats manager from agents
  let stats_manager = @lib.StatsManager::new(
    Map([], capacity=agent_manager.count()),
  )
  stats_manager.init(agent_manager)
  println("Tracking stats for \{agent_manager.count()} agents")

  // Query system info for the runtime monitor (used by /api/runtime)
  let total_memory_mb = @server.system_info()
  println("System memory: \{total_memory_mb} MB")

  // Create runtime context
  let ctx = @server.RuntimeContext::new(
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
  )

  // Start HTTP server
  println("Server running at http://localhost:\{port}")
  let addr = @socket.Addr::resolve("0.0.0.0", port~)
  @http.Server::Server(addr).run_forever(
    async fn(
      request : @http.Request,
      body : &@io.Reader,
      conn : @http.ServerConnection,
    ) {
      @server.handle_request(ctx, request, body, conn)
    },
    allow_failure=true,
  )
}