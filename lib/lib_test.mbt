///|
test "parse_int handles valid and invalid input" {
  assert_eq(@lib.parse_int("123"), 123)
  assert_eq(@lib.parse_int("-42"), -42)
  assert_eq(@lib.parse_int("0"), 0)
  assert_eq(@lib.parse_int("abc"), 0)
  assert_eq(@lib.parse_int(""), 0)
}

///|
test "parse_float preserves fractional temperature values" {
  assert_true(@lib.parse_float("0.3") > 0.2 && @lib.parse_float("0.3") < 0.4)
  assert_true(@lib.parse_float("0.5") > 0.4 && @lib.parse_float("0.5") < 0.6)
  assert_eq(@lib.parse_float("0"), 0.0)
  assert_eq(@lib.parse_float(""), 0.0)
  assert_eq(@lib.parse_float("abc"), 0.0)
}

///|
test "parse_status maps strings to TaskStatus" {
  assert_true(@lib.parse_status("completed") is @lib.Completed)
  assert_true(@lib.parse_status("running") is @lib.Running)
  assert_true(@lib.parse_status("pending") is @lib.Pending)
  assert_true(@lib.parse_status("failed") is @lib.Failed(_))
  assert_true(@lib.parse_status("unknown") is @lib.Pending)
}

///|
test "url_encode encodes spaces and keeps safe characters" {
  assert_eq(@lib.url_encode("hello"), "hello")
  assert_eq(@lib.url_encode("hello world"), "hello+world")
  assert_eq(@lib.url_encode("中"), "%E4%B8%AD")
}

///|
test "TaskManager create/list/delete" {
  let tm = @lib.TaskManager::new(Map([], capacity=0))
  let _t = tm.create_task("t1", "agent1", "do something", 1)
  assert_eq(tm.count(), 1)
  assert_true(tm.find("t1") is Some(_))
  assert_eq(tm.list_by_agent("agent1").length(), 1)
  assert_eq(tm.list_by_agent("agent2").length(), 0)
  let _ = tm.update_status("t1", @lib.parse_status("running"))
  assert_true(tm.delete_task("t1"))
  assert_eq(tm.count(), 0)
}

///|
test "AgentManager create/message/clear/delete" {
  let am = @lib.AgentManager::new(Map([], capacity=0))
  let _a = am.create_agent("a1", "Alice", "gpt", "instr", "sys", 100, 0.5, "")
  assert_eq(am.count(), 1)
  assert_true(am.find("a1") is Some(_))
  am.add_message("a1", "user", "hello")
  assert_eq(am.get_conversation("a1").length(), 1)
  am.clear_conversation("a1")
  assert_eq(am.get_conversation("a1").length(), 0)
  assert_true(am.delete_agent("a1"))
  assert_eq(am.count(), 0)
}

///|
test "SuperTaskManager create/find/delete" {
  let stm = @lib.SuperTaskManager::new(Map([], capacity=0))
  let _st = stm.create("s1", "research", "do research", "a1")
  assert_eq(stm.count(), 1)
  assert_true(stm.find("s1") is Some(_))
  assert_true(stm.delete("s1"))
  assert_eq(stm.count(), 0)
}

///|
test "parse_tool_call extracts tool name and args" {
  let response = "{\"tool\": \"search_web\", \"args\": {\"query\": \"hello\"}}"
  match @lib.parse_tool_call(response) {
    Some((name, args)) => {
      assert_eq(name, "search_web")
      assert_eq(args, "{\"query\": \"hello\"}")
    }
    None => assert_true(false)
  }
}

///|
test "resolve_safe_path rejects traversal and absolute paths" {
  assert_true(@lib.resolve_safe_path("data", "../../etc/passwd") is Err(_))
  assert_true(
    @lib.resolve_safe_path("data", "/etc/passwd") is Err(@lib.Absolute),
  )
  assert_true(
    @lib.resolve_safe_path("data", "\\etc\\passwd") is Err(@lib.Absolute),
  )
  assert_true(
    @lib.resolve_safe_path("data", "C:\\windows\\system32")
    is Err(@lib.DriveLetter),
  )
  assert_true(@lib.resolve_safe_path("data", "~/secret") is Err(@lib.Absolute))
  assert_true(@lib.resolve_safe_path("data", "") is Err(@lib.Empty))
  assert_true(@lib.resolve_safe_path("data", "..") is Err(@lib.Traversal))
  assert_true(
    @lib.resolve_safe_path("data", "a/b/../../c") is Err(@lib.Traversal),
  )
}

///|
test "resolve_safe_path keeps valid paths inside data_dir" {
  match @lib.resolve_safe_path("data", "report.txt") {
    Ok(p) => assert_true(p == "data/report.txt")
    Err(_) => assert_true(false)
  }
  match @lib.resolve_safe_path("data/", "sub/notes.md") {
    Ok(p) => assert_true(p == "data/sub/notes.md")
    Err(_) => assert_true(false)
  }
  match @lib.resolve_safe_path("data", "./top/./file.csv") {
    Ok(p) => assert_true(p == "data/top/file.csv")
    Err(_) => assert_true(false)
  }
}

///|
test "truncate_conversation keeps the recent tail within budget" {
  let hist = [
    @lib.ChatMessage::new("user", "one"),
    @lib.ChatMessage::new("assistant", "two"),
    @lib.ChatMessage::new("user", "three"),
  ]
  // Large budget keeps everything.
  assert_eq(@lib.truncate_conversation(hist, 1000).length(), 3)
  // Small budget keeps only the last message.
  assert_eq(@lib.truncate_conversation(hist, 6).length(), 1)
  // An over-budget single message is still returned.
  assert_eq(@lib.truncate_conversation(hist, 1).length(), 1)
  // Empty stays empty.
  assert_eq(@lib.truncate_conversation([], 10).length(), 0)
}

///|
test "tool engine registers and looks up specs" {
  let engine = @lib.ToolEngine::new()
  engine.register(
    @lib.ToolSpec::new("ping", "echo", "{}", [], async fn(_, _) { "pong" }),
  )
  engine.register(
    @lib.ToolSpec::new(
      "need_arg",
      "requires arg",
      "{\"x\":\"string\"}",
      ["x"],
      async fn(args, _) { "got:" + args },
    ),
  )
  assert_true(engine.find("ping") is Some(_))
  assert_true(engine.find("missing") is None)
  assert_eq(engine.names().length(), 2)
}

///|
async test "builtin engine registers and runs the new tools" {
  let engine = @lib.ToolEngine::builtin()
  assert_true(engine.find("json_format") is Some(_))
  assert_true(engine.find("text_stats") is Some(_))
  let ok = engine.execute("json_format", "{\"json\":\"{\\\"a\\\":1}\"}", ".") catch {
    _ => "ERR"
  }
  assert_true(ok.contains("格式化结果"))
  let bad = engine.execute("json_format", "{\"json\":\"not json\"}", ".") catch {
    _ => "ERR"
  }
  assert_true(bad.contains("解析失败"))
  let stats = engine.execute("text_stats", "{\"text\":\"hello world\\nfoo\"}", ".") catch {
    _ => "ERR"
  }
  assert_true(stats.contains("词数=3"))
  assert_true(stats.contains("行数=2"))
}
