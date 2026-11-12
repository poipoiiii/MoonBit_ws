# Changelog

All notable changes to this project are documented in this file.

## [0.2.1] - 2026-11-12

### Compatibility
- 升级 `moonbitlang/async` 依赖 `0.20.2` → `0.22.4`，适配新版 HTTP 客户端 API：请求头类型由 `Map[String, String]` 改为 `Map[CaseInsensitiveString, String]`（`tool_executor.mbt` 与 `server/stream.mbt`）。
- 清理所有编译告警，CI 启用 `--deny-warn`：
  - 移除 `lib/moon.pkg` 中未使用的 `moonbitlang/async/io` 与 `moonbitlang/core/env`。
  - 移除 `tool_executor.mbt` 与 `lib_test.mbt` 中非异步工具闭包上多余的 `async` 注解。
  - `chat_store.mbt` 中 `Json::to_string()` 改用 `stringify()`，消除已弃用的 `Show` trait 告警。
- 修复 `moon.mod` 中已弃用的 `exclude` 选项，改用 `.moonignore` 排除 `scratch_test/`。

### CI
- 将工作流从 `workflows/check.yml` 迁移至 `.github/workflows/check.yml`，使 GitHub Actions 能正确识别并执行三平台（ubuntu / macos / windows）检查。

## [0.2.0] - 2026-10-22

### Security
- 文件工具沙箱：新增 `fs_guard`（`resolve_safe_path`），`read_file` / `write_file` / `analyze_csv` 拒绝绝对路径、盘符路径、`~` 与 `../` 穿越，统一限定在 `data_dir` 内。
- 工具参数校验：`read_file` / `write_file` / `analyze_csv` 缺失必需参数时返回明确错误，而非静默使用默认路径。

### Architecture
- 拆分单文件 `main.mbt`：HTTP/SSE 请求处理迁移至 `lib/server` 分层包；`cmd/main` 仅负责加载配置与启动服务。
- 用 MoonBit 原生 `@json` 替换手写 JSON 解析。

### Store
- 对话持久化：聊天历史写入 `static/data/chat_history.json`，重启后记忆保留。
- 记忆窗口：以字符预算（`MAX_HISTORY_CHARS`）替代固定 10 条截断，始终保留最近对话。

### Tools
- 可插拔工具引擎：新增 `ToolSpec` + `ToolEngine` 注册架构，替代硬编码 `match` 调度，支持注册新工具。
- 新增内置工具 `json_format`（校验并美化打印 JSON）与 `text_stats`（统计字符数/词数/行数）。

### Fixed
- 修复 Agent 保存时 `temperature` 被清零：`parse_float` 原基于 `parse_int` 实现，导致 `0.3` 等小数被解析为 `0` 并回写 CSV。改用 `@string.parse_double`，并在写回时消除 32 位浮点噪声。

### Docs
- README 顶部改为单句定位 + 控制台截图 + Mermaid 数据流图，30 秒内可判断项目用途。
- 新增「使用情况」章节：明确当前无外部采用者，只列可复用组件与可验证信号。
- 补充缺失的 `.env.example`（README 的快速开始一直引用它）。

## [0.1.0] - 2026-09-07

- 初版 Agent Runtime：Agent CRUD、Task 管理、SuperTask、5 个内置工具、SSE 对话（DeepSeek OpenAI 兼容）、运行时监控、React 前端。
- 配置 GitHub Actions CI（ubuntu / macos / windows 三平台）。
- 发布准备：README、MIT License、mooncakes.io 配置。