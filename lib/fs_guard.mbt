///|
/// Path sandboxing for file tools (read_file / write_file / analyze_csv).
///
/// Resolves a user/model-supplied path so that it can never escape the
/// configured `data_dir` sandbox. The resolver rejects absolute paths,
/// drive-letter paths, home-relative paths and any `..` traversal segment.
/// The returned path is always a join of `data_dir` plus a normalized,
/// relative sub-path.

///|
/// Result of the safe path resolution.
/// `Ok(String)` carries the resolved absolute path inside `data_dir`;
/// `Err(Reason)` explains why the raw path is rejected.
pub enum PathError {
  Empty
  Absolute
  DriveLetter
  Traversal
}

///|
/// Resolve `raw` relative to `data_dir`, ensuring the result stays inside the
/// sandbox. Returns `Err(PathError)` when the path is unusable or escapes.
pub fn resolve_safe_path(
  data_dir : String,
  raw : String,
) -> Result[String, PathError] {
  let trimmed = raw.trim(chars=" \t\r\n").to_owned()
  if trimmed.length() == 0 {
    return Err(Empty)
  }
  // Absolute path (POSIX or Windows style) and `~` home shortcut are refused.
  let first = trimmed[0].to_int()
  if first == 47 || first == 92 { // '/' or '\'
    return Err(Absolute)
  }
  if first == 126 { // '~'
    return Err(Absolute)
  }
  // Windows drive letter, e.g. `C:\...` or `C:/...`
  if trimmed.length() >= 2 && trimmed[1].to_int() == 58 {
    return Err(DriveLetter)
  }
  // Tokenize on both '/' and '\', validating each segment.
  let segments : Array[String] = []
  let mut i = 0
  let mut start = 0
  while i <= trimmed.length() {
    if i == trimmed.length() ||
      trimmed[i].to_int() == 47 ||
      trimmed[i].to_int() == 92 {
      let seg = trimmed[start:i].to_owned()
      if seg == ".." {
        return Err(Traversal)
      } else if seg == "." || seg.length() == 0 {
        () // skip current-dir and empty segments
      } else {
        segments.push(seg)
      }
      start = i + 1
    }
    i = i + 1
  }
  if segments.length() == 0 {
    return Err(Empty)
  }
  let base = strip_trailing_separator(data_dir)
  let joined = if base.length() == 0 {
    segments.join("/")
  } else {
    base + "/" + segments.join("/")
  }
  Ok(joined)
}

///|
/// Strip a single trailing '/' or '\' from a directory path.
fn strip_trailing_separator(dir : String) -> String {
  if dir.length() == 0 {
    return dir
  }
  let last = dir[dir.length() - 1].to_int()
  if last == 47 || last == 92 {
    dir[:dir.length() - 1].to_owned()
  } else {
    dir
  }
}
