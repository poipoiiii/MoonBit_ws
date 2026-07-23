# MoonBit AI Agent Runtime

基于 [MoonBit](https://moonbitlang.com/) 构建的轻量级 AI Agent 运行时框架，提供 Agent 管理、任务调度、工具调用及 LLM 集成能力。

## 架构概览

```
┌─────────────────────────────────────┐
│          Frontend (React)           │
│     Vite + Tailwind CSS + Oxlint    │
└────────────────┬────────────────────┘
                 │ HTTP / SSE
┌────────────────▼────────────────────┐
│      Backend (MoonBit + HTTP)       │
│  Agent 管理  │  任务调度  │  Tool 引擎│
│  LLM 网关 (DeepSeek/OpenAI 兼容)    │
└────────────────┬────────────────────┘
                 │
┌────────────────▼────────────────────┐
│          Data Layer (CSV)           │
│    agents.csv  tools.csv  tasks.csv │
└─────────────────────────────────────┘
```

## 项目结构

```
MoonBit_ws/
├── cmd/main/              # 后端入口 (MoonBit)
│   ├── main.mbt           # HTTP 服务器 + SSE 流式 API
│   └── moon.pkg
├── lib/                   # 后端核心库
│   ├── agent.mbt          # Agent 定义与管理
│   ├── task.mbt           # 任务模型与调度
│   ├── tool.mbt           # 工具注册与执行
│   ├── csv_util.mbt       # CSV 读写工具
│   ├── llm.mbt            # LLM 网关
│   └── types.mbt          # 核心数据结构
├── frontend/              # 前端 (React + Vite)
│   ├── src/
│   │   ├── App.jsx        # 主页面组件
│   │   ├── ThemeContext.jsx # 主题上下文
│   │   ├── api/index.js   # API 请求封装
│   │   └── main.jsx       # 入口
│   ├── index.html
│   ├── vite.config.js
│   └── tailwind.config.js
├── static/data/           # 静态数据 (CSV)
│   ├── agents.csv         # Agent 配置
│   ├── tools.csv          # 工具定义
│   └── tasks.csv          # 任务记录
├── docs/
│   └── agent-runtime-design.md  # 设计文档
├── .env                   # 环境变量 (不提交)
├── .gitignore
├── moon.mod               # MoonBit 模块配置
├── run.ps1                # Windows 启动脚本
└── run.cmd                # Windows 启动脚本 (CMD)
```

## 前置条件

- [MoonBit](https://moonbitlang.com/) (最新版本)
- [Node.js](https://nodejs.org/) v18+
- [DeepSeek API Key](https://platform.deepseek.com/) (或其他 OpenAI 兼容 API)

## 快速开始

### 1. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env
# 编辑 .env 填入你的 API Key
DEEPSEEK_API_KEY=sk-your-key-here
DEEPSEEK_MODEL=deepseek-chat
PORT=8080
DATA_DIR=static/data
CORS_ORIGIN=*
```

### 2. 启动后端

```bash
# 构建 MoonBit 后端
moon build --target native

# 启动服务
./run.ps1       # Windows PowerShell
# 或
./run.cmd       # Windows CMD
```

后端将在 `http://localhost:8080` 启动。

### 3. 启动前端

```bash
cd frontend
npm install
npm run dev
```

前端将在 `http://localhost:5173` 启动（开发模式）。

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | GET | 主页 (HTML) |
| `/api/agents` | GET | 获取所有 Agent 列表 (JSON) |
| `/api/tools` | GET | 获取所有启用的工具列表 (JSON) |
| `/api/chat?message=...&agent_id=...` | GET | SSE 流式聊天 |

## 环境变量

| 变量 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `DEEPSEEK_API_KEY` | 是 | - | DeepSeek API 密钥 |
| `DEEPSEEK_MODEL` | 否 | `deepseek-chat` | 使用的模型名称 |
| `PORT` | 否 | `8080` | 后端 HTTP 端口 |
| `DATA_DIR` | 否 | `static/data` | CSV 数据文件目录 |
| `CORS_ORIGIN` | 否 | `*` | CORS 允许的源 |

## Agent 配置

Agent 通过 `static/data/agents.csv` 定义，支持多个 Agent：

| 字段 | 说明 |
|------|------|
| `id` | Agent 唯一标识 |
| `name` | Agent 名称 |
| `model` | 使用的 LLM 模型 |
| `instruction` | 指令模板 |
| `system_prompt` | 系统提示词 |
| `max_tokens` | 最大输出 Token |
| `temperature` | 生成温度 (0.0-1.0) |

## 技术栈

- **后端语言:** [MoonBit](https://moonbitlang.com/)
- **后端运行:** MoonBit HTTP Server + SSE
- **前端框架:** React 19 + Vite
- **前端样式:** Tailwind CSS
- **前端工具:** Oxlint (代码检查)
- **数据存储:** CSV
- **LLM 集成:** DeepSeek API (兼容 OpenAI 格式)
