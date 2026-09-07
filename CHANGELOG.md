# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

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

## [0.1.0] - 2026-09-07

- 初版 Agent Runtime：Agent CRUD、Task 管理、SuperTask、5 个内置工具、SSE 对话（DeepSeek OpenAI 兼容）、运行时监控、React 前端。
- 配置 GitHub Actions CI（ubuntu / macos / windows 三平台）。
- 发布准备：README、MIT License、mooncakes.io 配置。