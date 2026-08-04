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

/// Extract a string value from JSON by key (simple parser, handles both
/// `"key": "value"` and `"key":"value"` formats)
fn extract_str(json : String, key : String) -> Option[String] {
  let search1 = "\"" + key + "\": \""
  let search2 = "\"" + key + "\":\""
  let start = match string_find(json, search1) {
    Some(s) => Some(s)
    None => string_find(json, search2)
  }
  match start {
    None => None
    Some(s) => {
      let search = if string_find(json, search1) is Some(_) { search1 } else { search2 }
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

/// Extract the "query" argument from tool-call arguments, tolerating the
/// wrappers the model sometimes emits when it issues parallel tool calls,
/// e.g. {"arguments": "{\"query\": ...}"} or deeply nested {"arguments":
/// {"arguments": ...}}. Unwraps "arguments" layers until a non-empty "query"
/// is found.
fn extract_search_query(args : String) -> String {
  let mut current = args
  let mut depth = 0
  while depth < 12 {
    match extract_str(current, "query") {
      Some(q) => {
        let t = q.trim(chars=" \t\r\n").to_string()
        if t.length() > 0 { return t }
      }
      None => ()
    }
    match extract_str(current, "arguments") {
      Some(inner) => {
        let t = inner.trim(chars=" \t\r\n").to_string()
        if t.length() == 0 { break }
        current = t
        depth = depth + 1
      }
      None => break
    }
  }
  // Fall back to the raw args only when it is not a JSON object
  let trimmed = args.trim(chars=" \t\r\n").to_string()
  if trimmed.length() > 0 && trimmed[0].to_int() == 123 { "" } else { trimmed }
}

/// Execute search_web - real web search via Bing RSS
async fn execute_search(args : String) -> String {
  let query = extract_search_query(args)
  if query.length() == 0 {
    return "错误: search_web 未收到有效的 query 参数 (收到: " + args + ")，请提供具体的搜索关键词后重试"
  }
  let cleaned_query = sanitize_query(query)
  let url = "https://www.bing.com/search?format=rss&q=" + url_encode(cleaned_query)
  let headers = Map([
    ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
    ("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8"),
  ])
  // Retry once if the connection drops mid-read (Bing occasionally closes the
  // connection on repeated requests, raising ReaderClosed).
  let mut attempt = 0
  while attempt < 2 {
    let result = try {
      do_search(cleaned_query, url, headers)
    } catch {
      e => "错误: 搜索连接异常: " + e.to_string()
    }
    if result.has_prefix("错误: 搜索连接异常:") {
      attempt = attempt + 1
    } else {
      return result
    }
  }
  "错误: 搜索连接异常: 两次尝试均失败, query=[" + cleaned_query + "], url=" + url
}

/// Perform one Bing RSS search request and format the results.
async fn do_search(cleaned_query : String, url : String, headers : Map[String, String]) -> String {
  // Request with a timeout; the http client does not follow redirects automatically
  let request_result = match @async.with_timeout_opt(15000, () => @http.get(url, headers=headers)) {
    Some(result) => result
    None => return "错误: 搜索请求超时(15秒)"
  }
  let mut response = request_result.0
  let mut body = request_result.1
  // Follow up to 3 redirects manually (e.g. www.bing.com -> cn.bing.com)
  let mut redirects = 0
  while redirects < 3 && (response.code == 301 || response.code == 302 || response.code == 303 || response.code == 307) {
    match response.headers.get("location") {
      None => break
      Some(loc) => {
        let next_url = if loc.has_prefix("http") { loc } else { "https://www.bing.com" + loc }
        let result = @http.get(next_url, headers=headers)
        response = result.0
        body = result.1
        redirects = redirects + 1
      }
    }
  }
  if response.code != 200 {
    return "错误: 搜索请求失败, HTTP 状态码 " + response.code.to_string() + ", query=[" + cleaned_query + "], url=" + url
  }
  let xml = body.text() catch {
    _ => return "错误: 无法解码搜索结果页面"
  }
  parse_bing_rss(xml, cleaned_query)
}

/// Percent-encode a string for use in a URL query (UTF-8 safe)
pub fn url_encode(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let cp = s[i].to_int()
    if (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || cp == 45 || cp == 95 || cp == 46 || cp == 126 {
      match s[i].to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
    } else if cp == 32 {
      result = result + "+"
    } else {
      // String indexing yields a Unicode code point; encode it to UTF-8 bytes
      // then percent-encode each byte (%XX)
      let bytes = utf8_bytes(cp)
      for b in bytes {
        let v = b.to_int()
        result = result + "%" + hex_nibble(v / 16) + hex_nibble(v % 16)
      }
    }
    i = i + 1
  }
  result
}

/// Encode a Unicode code point into its UTF-8 byte sequence
fn utf8_bytes(cp : Int) -> Array[Byte] {
  if cp <= 0x7F {
    [cp.to_byte()]
  } else if cp <= 0x7FF {
    [(0xC0 | (cp >> 6)).to_byte(), (0x80 | (cp & 0x3F)).to_byte()]
  } else if cp <= 0xFFFF {
    [(0xE0 | (cp >> 12)).to_byte(), (0x80 | ((cp >> 6) & 0x3F)).to_byte(), (0x80 | (cp & 0x3F)).to_byte()]
  } else {
    [(0xF0 | (cp >> 18)).to_byte(), (0x80 | ((cp >> 12) & 0x3F)).to_byte(), (0x80 | ((cp >> 6) & 0x3F)).to_byte(), (0x80 | (cp & 0x3F)).to_byte()]
  }
}

/// Convert a nibble (0-15) to its uppercase hex character ('0'-'9', 'A'-'F')
fn hex_nibble(n : Int) -> String {
  if n < 10 { Int::unsafe_to_char(48 + n).to_string() } else { Int::unsafe_to_char(55 + n).to_string() }
}

/// Collapse whitespace control characters (\n \r \t and runs of spaces) into a single space.
/// Bing's RSS endpoint rejects queries containing line breaks with HTTP 400.
fn sanitize_query(s : String) -> String {
  let mut result = ""
  let mut prev_space = false
  let mut i = 0
  while i < s.length() {
    let v = s[i].to_int()
    if v == 10 || v == 13 || v == 9 || v == 32 {
      if !prev_space {
        result = result + " "
        prev_space = true
      }
    } else {
      match s[i].to_char() {
        Some(c) => result = result + c.to_string()
        None => ()
      }
      prev_space = false
    }
    i = i + 1
  }
  if result.length() > 0 && result[0] == ' ' {
    result = result[1:].to_owned()
  }
  if result.length() > 0 && result[result.length()-1] == ' ' {
    result = result[:result.length()-1].to_owned()
  }
  result
}

/// Parse Bing RSS search result XML into a readable text list
fn parse_bing_rss(xml : String, query : String) -> String {
  let results : Array[String] = []
  let mut search_from = 0
  while results.length() < 10 {
    let item_start = match string_find_from(xml, "<item>", search_from) {
      None => break
      Some(pos) => pos
    }
    let item_end = match string_find_from(xml, "</item>", item_start) {
      Some(pos) => pos
      None => xml.length()
    }
    let item = xml[item_start : item_end].to_owned()
    let title = extract_xml_tag(item, "title")
    let link = extract_xml_tag(item, "link")
    if title.length() > 0 && link.length() > 0 {
      let description = extract_xml_tag(item, "description")
      results.push("标题: " + title + "\n链接: " + link + "\n摘要: " + description)
    }
    search_from = item_end
  }
  if results.length() == 0 {
    return "搜索结果: 未找到与\"\{query}\"相关的网页"
  }
  let mut output = "搜索结果 (\"" + query + "\", " + results.length().to_string() + " 条):"
  if !results_relevant(results, query) {
    output = output +
      "\n\n提示: 以上搜索结果似乎与该主题不相关（结果中未出现查询关键词），请改用更短更通用的关键词重新搜索，例如直接使用指数名称或代码（如: 标普500 行情 / SPX / KS11）。"
  }
  let mut idx = 0
  while idx < results.length() {
    output = output + "\n\n" + (idx + 1).to_string() + ". " + results[idx]
    idx = idx + 1
  }
  output
}

/// Whether any search result title contains a meaningful key term from the query
/// (e.g. "标普" or "KOSPI"). Bing's RSS sometimes tokenizes a Chinese query so
/// badly that it returns pages about a single character; flagging that lets the
/// model pick a shorter, more precise keyword instead of retrying the same one.
fn results_relevant(results : Array[String], query : String) -> Bool {
  let cjk_terms = extract_cjk_terms(query)
  let en_term = extract_en_term(query)
  for r in results {
    if en_term.length() >= 3 {
      if string_find(r, en_term) is Some(_) { return true }
    }
    for t in cjk_terms {
      if string_find(r, t) is Some(_) { return true }
    }
  }
  false
}

/// Extract runs of 2+ consecutive CJK characters from a string (e.g. "标普")
fn extract_cjk_terms(s : String) -> Array[String] {
  let terms : Array[String] = []
  let mut i = 0
  while i < s.length() {
    let cp = s[i].to_int()
    if cp >= 0x4E00 && cp <= 0x9FFF {
      let mut j = i
      while j < s.length() {
        let c2 = s[j].to_int()
        if c2 >= 0x4E00 && c2 <= 0x9FFF {
          j = j + 1
        } else {
          break
        }
      }
      if j - i >= 2 {
        let seg = s[i : j].to_owned()
        let mut dup = false
        for t in terms {
          if t == seg { dup = true; break }
        }
        if !dup { terms.push(seg) }
      }
      i = j
    } else {
      i = i + 1
    }
  }
  terms
}

/// Extract the longest run of 3+ ASCII letters/digits from a string (e.g. "KOSPI")
fn extract_en_term(s : String) -> String {
  let mut best = ""
  let mut cur = ""
  let mut i = 0
  while i < s.length() {
    let cp = s[i].to_int()
    let is_alnum = (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122)
    if is_alnum {
      match s[i].to_char() {
        Some(c) => cur = cur + c.to_string()
        None => ()
      }
    } else {
      if cur.length() >= 3 && cur.length() > best.length() { best = cur }
      cur = ""
    }
    i = i + 1
  }
  if cur.length() >= 3 && cur.length() > best.length() { best = cur }
  best
}

/// Extract the text content of a single XML tag like <title>...</title>
fn extract_xml_tag(xml : String, tag : String) -> String {
  let open = "<" + tag + ">"
  let start = match string_find(xml, open) {
    None => return ""
    Some(pos) => pos + open.length()
  }
  let close = "</" + tag + ">"
  let end = match string_find_from(xml, close, start) {
    None => return ""
    Some(pos) => pos
  }
  if end <= start { return "" }
  strip_tags(decode_html_entities(xml[start : end].to_owned()))
}

/// Remove HTML tags from a string and trim surrounding whitespace
fn strip_tags(s : String) -> String {
  let mut result = ""
  let mut i = 0
  let mut in_tag = false
  while i < s.length() {
    let c = s[i].to_int()
    if c == 60 {
      in_tag = true
    } else if c == 62 {
      in_tag = false
    } else if !in_tag {
      match s[i].to_char() {
        Some(ch) => result = result + ch.to_string()
        None => ()
      }
    }
    i = i + 1
  }
  result.trim(chars=" \t\r\n").to_string()
}

/// Decode common HTML/XML entities (named and numeric)
fn decode_html_entities(s : String) -> String {
  let mut result = ""
  let mut i = 0
  while i < s.length() {
    let c = s[i].to_int()
    if c == 38 { // '&'
      let semi = string_find_from(s, ";", i)
      if semi is Some(end) && end - i <= 12 {
        let entity = s[i + 1 : end].to_owned()
        match entity {
          "amp" => { result = result + "&"; i = end + 1 }
          "lt" => { result = result + "<"; i = end + 1 }
          "gt" => { result = result + ">"; i = end + 1 }
          "quot" => { result = result + "\""; i = end + 1 }
          "apos" => { result = result + "'"; i = end + 1 }
          "nbsp" | "ensp" | "emsp" | "thinsp" => { result = result + " "; i = end + 1 }
          _ =>
            if entity.length() > 0 && entity[0].to_int() == 35 { // '#' numeric entity
              let code = parse_entity_number(entity[1:].to_owned())
              if code >= 32 && code <= 0x10FFFF {
                result = result + Int::unsafe_to_char(code).to_string()
                i = end + 1
              } else {
                match s[i].to_char() {
                  Some(ch) => result = result + ch.to_string()
                  None => ()
                }
                i = i + 1
              }
            } else {
              match s[i].to_char() {
                Some(ch) => result = result + ch.to_string()
                None => ()
              }
              i = i + 1
            }
        }
      } else {
        match s[i].to_char() {
          Some(ch) => result = result + ch.to_string()
          None => ()
        }
        i = i + 1
      }
    } else {
      match s[i].to_char() {
        Some(ch) => result = result + ch.to_string()
        None => ()
      }
      i = i + 1
    }
  }
  result
}

/// Parse a numeric HTML entity like "123" or "x1F600" (without the leading #)
fn parse_entity_number(num_str : String) -> Int {
  if num_str.length() == 0 { return -1 }
  let mut is_hex = false
  let mut i = 0
  let first = num_str[0].to_int()
  if first == 120 || first == 88 { // 'x' or 'X'
    is_hex = true
    i = 1
  }
  let mut code = 0
  let mut ok = true
  while i < num_str.length() {
    let c = num_str[i].to_int()
    if c >= 48 && c <= 57 {
      code = code * (if is_hex { 16 } else { 10 }) + (c - 48)
    } else if is_hex && c >= 97 && c <= 102 {
      code = code * 16 + (c - 87)
    } else if is_hex && c >= 65 && c <= 70 {
      code = code * 16 + (c - 55)
    } else {
      ok = false
      break
    }
    i = i + 1
  }
  if ok { code } else { -1 }
}

/// Find the first occurrence of a pattern starting from a given byte index
fn string_find_from(s : String, pat : String, from : Int) -> Option[Int] {
  if pat.length() == 0 { return Some(from) }
  let max_start = s.length() - pat.length()
  let mut i = if from < 0 { 0 } else { from }
  while i <= max_start {
    let mut matched = true
    let mut j = 0
    while j < pat.length() {
      if s[i + j] != pat[j] { matched = false; break }
      j = j + 1
    }
    if matched { return Some(i) }
    i = i + 1
  }
  None
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
