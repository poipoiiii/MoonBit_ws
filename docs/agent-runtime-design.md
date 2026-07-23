# 基于 MoonBit 的轻量级 AI Agent 运行时设计与实现

## 1. 项目概述

### 1.1 背景

AI Agent 是当前大语言模型（LLM）应用的核心范式。MoonBit 作为新兴的系统编程语言，具有高性能、强类型、Wasm 原生支持等优势，适合构建轻量级 Agent 运行时。

### 1.2 目标

- 设计一个**最小可用的 AI Agent 运行时**，支持 Agent 定义、任务调度、工具调用、记忆管理等核心能力
- 使用 MoonBit 实现核心引擎，验证 MoonBit 在 AI 基础设施场景下的可行性
- 以学习探讨为主，保持架构简洁，不追求生产级复杂度

### 1.3 关键设计原则

| 原则 | 说明 |
|------|------|
| 极简主义 | 只实现最核心的运行时能力，避免过度设计 |
| 数据驱动 | Agent 配置、任务定义、工具注册均基于结构化数据（CSV/JSON） |
| 可观测 | 运行时状态可通过简单接口查询，便于调试和学习 |
| 渐进演进 | 先实现单 Agent 串行执行，再逐步引入并发和协作 |

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    用户接口层                        │
│          CLI / HTTP API / 配置文件                   │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│                   Agent 运行时                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Agent    │  │ Task     │  │ Memory           │  │
│  │ 管理器   │◄─│ 调度器   │◄─│ 管理器           │  │
│  └────┬─────┘  └────┬─────┘  └──────────────────┘  │
│       │              │                              │
│  ┌────▼──────────────▼─────┐                        │
│  │     Tool 调用引擎       │                        │
│  │  (Function Calling)     │                        │
│  └────┬────────────────────┘                        │
└───────┼─────────────────────────────────────────────┘
        │
┌───────▼─────────────────────────────────────────────┐
│                   LLM 网关                          │
│          LLM API (OpenAI / 本地模型)                │
└─────────────────────────────────────────────────────┘
```

### 2.1 分层说明

| 层 | 职责 |
|----|------|
| **用户接口层** | CLI 命令解析、配置文件读取、结果输出 |
| **Agent 运行时** | 核心引擎，包含 Agent 管理、任务调度、记忆管理、Tool 调用 |
| **LLM 网关** | 统一封装 LLM API 调用，支持多模型后端切换 |

---

## 3. 核心模块设计

### 3.1 Agent 定义

Agent 是运行时的基本执行单元，通过结构化数据定义：

```moonbit
// Agent 核心结构（伪代码）
struct Agent {
    id          : String
    name        : String
    model       : String          // 使用的 LLM 模型
    instruction : String          // 指令模板
    system_prompt : String        // 系统提示词
    max_tokens  : Int             // 最大输出 Token
    temperature : Float           // 生成温度
    tools       : Array[String]   // 绑定的工具 ID 列表
}
```

Agent 配置来源于 `agents.csv`，运行时启动时一次性加载到内存。

### 3.2 任务调度

任务生命周期：`pending -> running -> completed / failed`

```moonbit
// 任务结构（伪代码）
enum TaskStatus {
    Pending
    Running
    Completed
    Failed(String)
}

struct Task {
    id          : String
    agent_id    : String
    description : String
    status      : TaskStatus
    priority    : Int
    created_at  : String
    updated_at  : String
    result      : Option[String]
}
```

调度策略（初版）：
- 简单优先级队列调度
- 单线程串行执行
- 支持阻塞等待和异步轮询两种模式

### 3.3 工具调用机制

工具是 Agent 与外部世界交互的桥梁。每个工具定义如下结构：

```moonbit
struct Tool {
    id           : String
    name         : String
    description  : String
    input_schema : Map[String, String]  // 输入参数 JSON Schema
    enabled      : Bool
    version      : String
    // 运行时绑定的执行函数
    execute     : (Map[String, Any]) -> Result[String, String]
}
```

工具调用流程：

1. LLM 返回结构化 Tool Call 请求（函数名 + 参数）
2. 运行时解析请求，校验参数
3. 查找已注册的工具执行函数
4. 执行并将结果返回给 LLM
5. LLM 基于工具结果生成最终回复

### 3.4 记忆管理

记忆分为两个层次：

| 层级 | 存储位置 | 生命周期 | 说明 |
|------|---------|---------|------|
| 短期记忆 | 运行时内存 | 单次对话 | LLM 上下文窗口内的消息历史 |
| 长期记忆 | CSV/本地文件 | 持久化 | 关键信息摘要、历史任务记录 |

初版实现：短期记忆直接使用 LLM 上下文窗口，长期记忆通过 `tasks.csv` 记录历史。

---

## 4. 数据流设计

### 4.1 核心执行流程

```
用户输入
  │
  ▼
① 任务解析 → 创建 Task（状态: pending）
  │
  ▼
② 任务调度 → 分配给对应 Agent（状态: running）
  │
  ▼
③ Agent 构建 Prompt（System + Instruction + 上下文）
  │
  ▼
④ 调用 LLM 网关 → 获取回复
  │
  ├── 如果回复包含 Tool Call ──► ⑤ 执行工具 → 结果带回 ③
  │
  ▼
⑥ 生成最终输出，更新 Task（状态: completed / failed）
  │
  ▼
⑦ 写入记忆（短期 + 长期）
```

### 4.2 数据持久化

初版使用 CSV 作为存储格式，原因：
- MoonBit 标准库对 CSV 解析有良好支持
- 人类可直接阅读和编辑
- 无需引入外部数据库依赖

后续可演进为 SQLite 或更专业的存储。

---

## 5. MoonBit 实现方案

### 5.1 项目结构

```
ai-agent-runtime/
├── main.mbt              # 入口：CLI 解析
├── agent.mbt             # Agent 定义与管理
├── task.mbt              # 任务模型与调度
├── tool.mbt              # 工具注册与执行
├── memory.mbt            # 记忆管理
├── llm.mbt               # LLM 网关（HTTP 调用）
├── csv_util.mbt          # CSV 读写工具函数
├── static/
│   └── data/
│       ├── agents.csv    # Agent 配置数据
│       ├── tools.csv     # 工具注册数据
│       └── tasks.csv     # 任务记录数据
└── README.md
```

### 5.2 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| CSV 解析 | 使用 MoonBit `标准库` | 减少外部依赖 |
| HTTP 请求 | MoonBit 的 `http` 包 | 调用 LLM API |
| 并发模型 | 初版单线程 | 降低复杂度，先跑通流程 |
| 错误处理 | MoonBit 的 `Result` 类型 | 强制处理错误，符合 MoonBit 哲学 |
| 测试策略 | MoonBit 内建测试框架 | `moon test` 原生支持 |

### 5.3 核心类型概览（MoonBit 伪代码）

```moonbit
/// 运行时配置
struct RuntimeConfig {
    agent_file  : String   // agents.csv 路径
    tool_file   : String   // tools.csv 路径
    task_file   : String   // tasks.csv 路径
    llm_api_key : String   // LLM API Key
    llm_base_url : String  // LLM API 地址
}

/// 运行时状态
struct Runtime {
    agents      : Map[String, Agent]
    tools       : Map[String, Tool]
    tasks       : Map[String, Task]
    config      : RuntimeConfig
    memory      : MemoryManager
}

/// 执行结果
enum ExecutionResult {
    Text(String)
    ToolCall(String, Map[String, Any])
    Error(String)
}
```

---

## 6. 落地计划与演进路线

### Phase 1：基础运行时（MVP）
- [x] 数据结构定义（CSV 配置）
- [ ] Agent 管理器：加载 agents.csv，按 ID 查询
- [ ] 任务调度器：基础队列 + 状态流转
- [ ] Tool 引擎：注册 + 调用 + 结果返回
- [ ] LLM 网关：HTTP 调用 OpenAI 兼容 API
- [ ] CLI 入口：简单交互循环（REPL）

### Phase 2：增强能力
- [ ] 多 Agent 协作（Agent 间消息传递）
- [ ] 长期记忆持久化与检索
- [ ] 工具执行沙箱（Wasm 隔离）
- [ ] 任务重试与超时机制

### Phase 3：生产化方向
- [ ] MoonBit → Wasm 编译，浏览器端运行
- [ ] 可观测性（日志、指标、链路追踪）
- [ ] 插件化工具系统
- [ ] 分布式任务队列

---

## 7. 学习要点总结

通过本项目可以探索以下 MoonBit 特性在实际场景中的应用：

| MoonBit 特性 | 在本项目中的应用 |
|-------------|----------------|
| 强类型系统 | Agent/Task/Tool 结构体定义，编译期类型安全 |
| Result 类型 | LLM 调用、文件读写、工具执行的错误处理 |
| Map/Trait | Agent 注册表、工具查找表 |
| Wasm 编译 | 将运行时编译为 Wasm，在浏览器中运行 Agent |
| JSON 序列化 | LLM API 请求/响应编解码 |
| 模块系统 | 按职责拆分 agent/task/tool/memory 模块 |

---

## 8. 参考资料

- [MoonBit 官方文档](https://moonbitlang.com/)
- [OpenAI Function Calling](https://platform.openai.com/docs/guides/function-calling)
- [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)
- [LangChain Agent 概念](https://python.langchain.com/docs/concepts/agents/)
