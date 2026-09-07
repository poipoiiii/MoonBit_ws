///|
/// Pluggable tool engine.
///
/// Instead of a hard-coded `match tool_name` dispatch, tools are registered as
/// `ToolSpec` entries (name, description, input schema, required args and an
/// executor). Adding a new tool only requires registering a new spec; the
/// engine handles lookup, argument validation and error reporting uniformly.

///|
/// A single tool definition with its executor.
pub struct ToolSpec {
  name : String
  description : String
  input_schema : String
  required : Array[String]
  execute : async (String, String) -> String
}

///|
/// Create a tool spec. `execute(args, data_dir) -> result`.
pub fn ToolSpec::new(
  name : String,
  description : String,
  input_schema : String,
  required : Array[String],
  execute : async (String, String) -> String,
) -> ToolSpec {
  { name, description, input_schema, required, execute }
}

///|
/// Tool engine holding registered specs, with lookup and execution.
pub struct ToolEngine {
  specs : Map[String, ToolSpec]
}

///|
/// Create an empty tool engine.
pub fn ToolEngine::new() -> ToolEngine {
  { specs: Map([], capacity=0) }
}

///|
/// Register (or overwrite) a tool spec by name.
pub fn ToolEngine::register(self : ToolEngine, spec : ToolSpec) -> Unit {
  self.specs[spec.name] = spec
}

///|
/// Find a registered spec by name.
pub fn ToolEngine::find(self : ToolEngine, name : String) -> ToolSpec? {
  self.specs.get(name)
}

///|
/// List all registered tool names.
pub fn ToolEngine::names(self : ToolEngine) -> Array[String] {
  let result : Array[String] = []
  for name in self.specs.keys() {
    result.push(name)
  }
  result
}

///|
/// Execute a registered tool by name after validating its required arguments.
pub async fn ToolEngine::execute(
  self : ToolEngine,
  name : String,
  args : String,
  data_dir : String,
) -> String {
  match self.specs.get(name) {
    None => "Error: Unknown tool: \{name}"
    Some(spec) =>
      match missing_arg_error(args, spec.required) {
        Some(e) => "Error: " + e
        None => (spec.execute)(args, data_dir)
      }
  }
}
