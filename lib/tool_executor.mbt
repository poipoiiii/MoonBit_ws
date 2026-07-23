///|
/// Tool executor - execute tool calls from AI responses
/// Supports: calc_expression, read_file, write_file, search_web, analyze_csv

/// Execute a tool call and return the result
pub async fn execute_tool(tool_name : String, args_json : String, data_dir : String) -> String {
  match tool_name {
    "calc_expression" => execute_calc(args_json)
    "search_web" => execute_search(args_json)
    "read_file" => execute_read_file(args_json)
    "write_file" => execute_write_file(args_json, data_dir)
    "analyze_csv" => execute_analyze_csv(args_json, data_dir)
    _ => "Error: Unknown tool: \{tool_name}"
  }
}

/// Extract a string value from JSON by key (simple parser)
fn extract_str(json : String, key : String) -> Option[String] {
  let search = "\"" + key + "\": \""
  let start = string_find(json, search)
  match start {
    None => None
    Some(s) => {
      let value_start = s + search.length()
      let mut result = ""
      let mut i = value_start
      while i < json.length() {
        let ch = json[i]
        if ch == '\\' {
          if i + 1 < json.length() {
            let next = json[i + 1]
            if next == '"' { result = result + "\""; i = i + 2 }
            else if next == 'n' { result = result + "\n"; i = i + 2 }
            else if next == '\\' { result = result + "\\"; i = i + 2 }
            else { match ch.to_char() { Some(c) => result = result + c.to_string(); None => () }; i = i + 1 }
          } else { i = i + 1 }
        } else if ch == '"' {
          break
        } else {
          match ch.to_char() { Some(c) => result = result + c.to_string(); None => () }
          i = i + 1
        }
      }
      Some(result)
    }
  }
}

/// Extract a path string from JSON (handles both "path" and "file_path" keys)
fn extract_path(json : String) -> String {
  match extract_str(json, "file_path") {
    Some(p) => p
    None => extract_str(json, "path").unwrap_or("")
  }
}

/// Execute calc_expression - evaluate basic arithmetic expression using integer math
fn execute_calc(args : String) -> String {
  let expr = extract_str(args, "expression").unwrap_or(args)
  // Simple evaluation using integer arithmetic
  let mut result_int = 0
  let mut result_frac = 0
  let mut result_div = 1
  let mut op = '+'
  let mut i = 0
  while i < expr.length() {
    let c = expr[i]
    if (c >= '0' && c <= '9') || c == '.' {
      let mut num_int = 0
      let mut num_frac = 0
      let mut num_div = 1
      let mut is_frac = false
      while i < expr.length() {
        let dc = expr[i]
        if dc >= '0' && dc <= '9' {
          if is_frac {
            num_div = num_div * 10
            num_frac = num_frac * 10 + (dc.to_int() - 48)
          } else {
            num_int = num_int * 10 + (dc.to_int() - 48)
          }
        } else if dc == '.' {
          is_frac = true
        } else {
          break
        }
        i = i + 1
      }
      // Apply operator with the parsed number
      match op {
        '+' => { result_int = result_int + num_int; result_frac = result_frac * num_div + num_frac * result_div; result_div = result_div * num_div }
        '-' => { result_int = result_int - num_int; result_frac = result_frac * num_div - num_frac * result_div; result_div = result_div * num_div }
        '*' => {
          // Simple multiplication (may overflow for complex cases)
          result_int = result_int * num_int
        }
        '/' => if num_int != 0 { result_int = result_int / num_int }
        _ => ()
      }
    } else if c == '+' || c == '-' || c == '*' || c == '/' {
      op = c.to_char().unwrap_or('+')
      i = i + 1
    } else {
      i = i + 1
    }
  }
  let result = Float::from_int(result_int) + Float::from_int(result_frac) / Float::from_int(result_div)
  "计算结果: " + result.to_string()
}

/// Execute search_web - simulated search result
fn execute_search(args : String) -> String {
  let query = extract_str(args, "query").unwrap_or(args)
  "搜索结果: 关于\"\{query}\"的搜索结果暂不可用。\n提示: 当前搜索功能为模拟模式，未连接真实搜索引擎。"
}

/// Execute read_file - read local file content
async fn execute_read_file(args : String) -> String {
  let path = extract_str(args, "path").unwrap_or(args)
  let file_result = @fs.open(path, mode=@fs.Mode::ReadOnly) catch {
    _ => return "Error: Cannot open file: \{path}"
  }
  defer file_result.close()
  let data = file_result.read_all() catch {
    _ => return "Error: Cannot read file: \{path}"
  }
  let content = data.text() catch {
    _ => return "Error: File is not valid UTF-8: \{path}"
  }
  "文件内容 (" + path + "):\n" + content
}

/// Execute write_file - write content to local file
async fn execute_write_file(args : String, data_dir : String) -> String {
  let path = extract_str(args, "path").unwrap_or("output.txt")
  let content = extract_str(args, "content").unwrap_or("")
  let full_path = data_dir + "/" + path
  @fs.write_file(full_path, content, create_mode=@fs.CreateOrTruncate) catch {
    _ => return "Error: Cannot write file: \{full_path}"
  }
  "文件已写入: " + full_path + " (大小: " + content.length().to_string() + " 字符)"
}

/// Execute analyze_csv - parse and analyze CSV file
async fn execute_analyze_csv(args : String, data_dir : String) -> String {
  let file_path = extract_path(args)
  let operation = extract_str(args, "operation").unwrap_or("summary")
  let full_path = if file_path.has_prefix("/") || file_path.has_prefix(".") {
    file_path
  } else {
    data_dir + "/" + file_path
  }
  
  let file_result = @fs.open(full_path, mode=@fs.Mode::ReadOnly) catch {
    _ => return "Error: Cannot open file: \{full_path}"
  }
  defer file_result.close()
  let data = file_result.read_all() catch {
    _ => return "Error: Cannot read file: \{full_path}"
  }
  let content = data.text() catch {
    _ => return "Error: File is not valid UTF-8: \{full_path}"
  }
  
  let lines_iter = content.split("\n")
  let lines : Array[String] = []
  for line_view in lines_iter {
    let line = line_view.to_owned()
    if line.length() > 0 { lines.push(line) }
  }
  
  if lines.length() < 2 {
    return "CSV 文件为空或只有标题行"
  }
  
  let num_rows = lines.length() - 1
  let num_cols = parse_csv_line(lines[0]).length()
  
  match operation {
    "summary" => "CSV 分析结果:\n- 文件: " + full_path + "\n- 列数: " + num_cols.to_string() + "\n- 数据行数: " + num_rows.to_string()
    "columns" => {
      let header = parse_csv_line(lines[0])
      "CSV 列名: [" + header.join(", ") + "] (" + num_cols.to_string() + " 列, " + num_rows.to_string() + " 行)"
    }
    _ => "CSV 分析完成: " + num_rows.to_string() + " 行, " + num_cols.to_string() + " 列"
  }
}

/// Parse tool call from AI response - extract {"tool": "...", "args": {...}} pattern
pub fn parse_tool_call(response : String) -> Option[(String, String)] {
  let tool_prefix = "\"tool\": \""
  
  let tool_start = string_find(response, tool_prefix)
  match tool_start {
    None => {
      // Try alternative patterns
      let alt_prefix = "{\"tool\":\""
      match string_find(response, alt_prefix) {
        None => {
          let tool_key = "\"tool\""
          match string_find(response, tool_key) {
            None => None
            Some(pos) => {
              let colon_pos = find_char_from(response, ':', pos + tool_key.length())
              match colon_pos {
                None => None
                Some(cp) => {
                  let quote1 = find_char_from(response, '"', cp + 1)
                  match quote1 {
                    None => None
                    Some(q1) => {
                      let quote2 = find_char_from(response, '"', q1 + 1)
                      match quote2 {
                        None => None
                        Some(q2) => {
                          let tool_name = response[q1 + 1 : q2].to_owned()
                          let args_start = string_find(response, "\"args\":")
                          match args_start {
                            None => None
                            Some(asp) => {
                              let brace_start = find_char_from(response, '{', asp + 7)
                              match brace_start {
                                None => None
                                Some(bs) => {
                                  let args_end = find_matching_brace(response, bs)
                                  match args_end {
                                    None => None
                                    Some(ae) => {
                                      let args_str = response[bs : ae + 1].to_owned()
                                      Some((tool_name, args_str))
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        Some(pos) => {
          let start = pos + alt_prefix.length()
          let end_quote = find_char_from(response, '"', start)
          match end_quote {
            None => None
            Some(eq) => {
              let tool_name = response[start : eq].to_owned()
              let args_start = string_find(response, "\"args\":")
              match args_start {
                None => None
                Some(asp) => {
                  let brace_start = find_char_from(response, '{', asp + 7)
                  match brace_start {
                    None => None
                    Some(bs) => {
                      let args_end = find_matching_brace(response, bs)
                      match args_end {
                        None => None
                        Some(ae) => {
                          let args_str = response[bs : ae + 1].to_owned()
                          Some((tool_name, args_str))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    Some(start) => {
      let name_start = start + tool_prefix.length()
      let name_end = find_char_from(response, '"', name_start)
      match name_end {
        None => None
        Some(ne) => {
          let tool_name = response[name_start : ne].to_owned()
          // Find args JSON object
          let args_start = find_char_from(response, '{', ne)
          match args_start {
            None => None
            Some(asp) => {
              let end_brace = find_matching_brace(response, asp)
              match end_brace {
                None => None
                Some(ae) => {
                  let args_str = response[asp : ae + 1].to_owned()
                  Some((tool_name, args_str))
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Find a character starting from position (ch is UInt16)
fn find_char_from(s : String, ch : Int, start : Int) -> Option[Int] {
  let mut i = start
  while i < s.length() {
    if s[i].to_int() == ch { return Some(i) }
    i = i + 1
  }
  None
}

/// Find matching closing brace for an opening brace at position
fn find_matching_brace(s : String, open_pos : Int) -> Option[Int] {
  if open_pos >= s.length() || s[open_pos] != '{' { return None }
  let mut depth = 1
  let mut i = open_pos + 1
  while i < s.length() {
    let ch = s[i]
    if ch == '{' {
      depth = depth + 1
    } else if ch == '}' {
      depth = depth - 1
      if depth == 0 { return Some(i) }
    } else if ch == '"' {
      // Skip string literals
      i = i + 1
      while i < s.length() {
        if s[i] == '\\' { i = i + 2 }
        else if s[i] == '"' { break }
        else { i = i + 1 }
      }
    }
    i = i + 1
  }
  None
}
