import { useState, useRef, useEffect, useCallback } from 'react'
import {
  Zap, MemoryStick, Cpu, Settings, Square, Play,
  Terminal, Send, CircleDot, Loader2, WifiOff,
  Sun, Moon, X, Info, Bot, Plus, Trash2
} from 'lucide-react'
import {
  fetchAgents, fetchTools, fetchRuntime, fetchSuperTasks,
  createChatStream, createSuperTask, deleteSuperTask, runSuperTaskStream
} from './api'
import { useTheme } from './ThemeContext'
import MarkdownMessage from './components/MarkdownMessage'

/* ─────────────────────────────────────────────
   Status → Tailwind color class
   ───────────────────────────────────────────── */
const statusColor = (status) => {
  switch (status) {
    case 'running': return 'text-emerald-400'
    case 'idle': return 'text-amber-400'
    case 'stopped': return 'text-rose-400'
    default: return 'text-gray-400'
  }
}

/* ─────────────────────────────────────────────
   Agent status badge in sidebar
   ───────────────────────────────────────────── */
function StatusDot({ status }) {
  const isRunning = status === 'running'
  return (
    <CircleDot
      className={`w-3 h-3 shrink-0 ${statusColor(status)} ${isRunning ? 'animate-pulse-dot' : ''}`}
    />
  )
}

/* ─────────────────────────────────────────────
   Toolbar button (icon + text, theme-aware)
   ───────────────────────────────────────────── */
function ToolbarBtn({ children, active, color, activeBg, disabled, onClick }) {
  const activeStyle = active
    ? { color, backgroundColor: activeBg }
    : { color: 'var(--text-muted)', backgroundColor: 'transparent' }

  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200
        ${!active && !disabled ? 'hover-bg hover-text' : ''}
        ${disabled ? 'opacity-30 cursor-not-allowed' : ''}
      `}
      style={activeStyle}
    >
      {children}
    </button>
  )
}

/* ==============================================
   Main App
   ============================================== */
function App() {
  const { theme, toggleTheme } = useTheme()
  const [agents, setAgents] = useState([])
  const [selectedAgent, setSelectedAgent] = useState(null)
  const [tools, setTools] = useState([])
  const [logs, setLogs] = useState([])
  const [input, setInput] = useState('')
  const [superTasks, setSuperTasks] = useState([])
  const [showCreateTask, setShowCreateTask] = useState(false)
  const [taskName, setTaskName] = useState('')
  const [taskDesc, setTaskDesc] = useState('')
  const [isStreaming, setIsStreaming] = useState(false)
  const [connecting, setConnecting] = useState(true)
  const [agentStatuses, setAgentStatuses] = useState({})
  const [showConfig, setShowConfig] = useState(false)
  const [showExamples, setShowExamples] = useState(true)
  const logEndRef = useRef(null)
  const inputRef = useRef(null)
  const abortRef = useRef(null)
  const cpuSampleRef = useRef({ cpuMs: 0, time: 0 })
  const [runtime, setRuntime] = useState({ memoryMb: null, cpuPct: null, totalMemoryMb: null })

  const examplePrompts = [
    '你好，宁波距离山东多远',
    '帮我计算 256 * 48 等于多少',
    '读取当前目录下的 agents.csv 文件',
    '有哪些工具可以使用？',
  ]

  /* ── Load backend data ── */
  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        setConnecting(true)
        const [agentData, toolData, superTaskData] = await Promise.all([
          fetchAgents(),
          fetchTools(),
          fetchSuperTasks(),
        ])
        if (cancelled) return

        setAgents(agentData)
        setTools(toolData)
        setSuperTasks(superTaskData.sort((a, b) => a.id.localeCompare(b.id)))

        const statuses = {}
        agentData.forEach(a => { statuses[a.id] = 'idle' })
        setAgentStatuses(statuses)

        if (agentData.length > 0) {
          setSelectedAgent(agentData[0])
        }

        setLogs([
          { type: 'sys', text: `[System] MoonBit Runtime connected` },
          { type: 'sys', text: `[System] Loaded ${agentData.length} agents, ${toolData.length} tools, ${superTaskData.length} super tasks` },
        ])
      } catch (err) {
        if (!cancelled) {
          setLogs([
            { type: 'sys', text: `[System] Failed to connect to backend: ${err.message}` },
            { type: 'sys', text: `[System] Make sure the server is running on port 8080` },
          ])
        }
      } finally {
        if (!cancelled) setConnecting(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [])

  /* ── Poll runtime stats (memory / CPU) ── */
  useEffect(() => {
    let cancelled = false
    const poll = async () => {
      try {
        const data = await fetchRuntime()
        if (cancelled) return
        const now = Date.now()
        const prev = cpuSampleRef.current
        let cpuPct = null
        if (prev.time > 0 && data.cpu_ms >= prev.cpuMs && now > prev.time) {
          cpuPct = Math.min(100, Math.max(0, Math.round(((data.cpu_ms - prev.cpuMs) / (now - prev.time)) * 100)))
        }
        cpuSampleRef.current = { cpuMs: data.cpu_ms, time: now }
        setRuntime({ memoryMb: data.memory_mb, cpuPct, totalMemoryMb: data.total_memory_mb })
      } catch {
        if (!cancelled) setRuntime(prev => ({ ...prev, cpuPct: null }))
      }
    }
    poll()
    const timer = setInterval(poll, 3000)
    return () => { cancelled = true; clearInterval(timer) }
  }, [])

  /* ── Auto-scroll ── */
  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [logs])

  /* ── Focus input after streaming ── */
  useEffect(() => {
    if (!isStreaming) inputRef.current?.focus()
  }, [isStreaming])

  /* ── Stream helpers ── */
  const appendStreamed = useCallback((logId, text) => {
    setLogs(prev => {
      const updated = [...prev]
      for (let i = updated.length - 1; i >= 0; i--) {
        if (updated[i].id === logId) {
          updated[i] = { ...updated[i], text: updated[i].text + text }
          break
        }
      }
      return updated
    })
  }, [])

  const startStream = useCallback((userTag) => {
    setLogs(prev => [...prev, { type: 'user', text: `> ${userTag}` }])
    setIsStreaming(true)
    const logId = `resp-${Date.now()}`
    setLogs(prev => [...prev, { type: 'agent', text: '', id: logId }])
    return logId
  }, [])

  const finishStream = useCallback(() => {
    setLogs(prev => [...prev, { type: 'sys', text: `[Runtime] Response complete` }])
    setIsStreaming(false)
  }, [])

  const failStream = useCallback((logId, err) => {
    setLogs(prev => {
      const filtered = prev.filter(l => l.id !== logId)
      return [...filtered, { type: 'sys', text: `[Error] ${err.message}` }]
    })
    setIsStreaming(false)
  }, [])

  /* ── Send message ── */
  const handleSend = useCallback(() => {
    if (!input.trim() || !selectedAgent || isStreaming) return
    const userMsg = input.trim()
    setInput('')
    const logId = startStream(userMsg)
    const controller = createChatStream(selectedAgent.id, userMsg, {
      onData: (text) => appendStreamed(logId, text),
      onDone: finishStream,
      onError: (err) => failStream(logId, err),
    })
    abortRef.current = controller
  }, [input, selectedAgent, isStreaming, startStream, appendStreamed, finishStream, failStream])

  /* ── Run a super task (agent autonomously calls tools to complete it) ── */
  const handleRunSuperTask = useCallback((st) => {
    if (isStreaming) return
    const agent = agents.find(a => a.id === st.agent_id) || selectedAgent
    if (!agent) {
      setLogs(prev => [...prev, { type: 'sys', text: `[Error] No agent found for task "${st.name}"` }])
      return
    }
    const logId = startStream(`[超级任务] ${st.name}`)
    const controller = runSuperTaskStream(st.id, agent.id, {
      onData: (text) => appendStreamed(logId, text),
      onDone: finishStream,
      onError: (err) => failStream(logId, err),
    })
    abortRef.current = controller
  }, [agents, selectedAgent, isStreaming, startStream, appendStreamed, finishStream, failStream])

  /* ── Create a custom super task ── */
  const handleCreateSuperTask = async () => {
    const name = taskName.trim()
    const desc = taskDesc.trim()
    if (!name || !desc) return
    try {
      const created = await createSuperTask({ name, description: desc })
      setSuperTasks(prev => [...prev, created].sort((a, b) => a.id.localeCompare(b.id)))
      setShowCreateTask(false)
      setTaskName('')
      setTaskDesc('')
      setLogs(prev => [...prev, { type: 'sys', text: `[System] Super task "${created.name}" created (${created.id})` }])
    } catch (err) {
      setLogs(prev => [...prev, { type: 'sys', text: `[Error] ${err.message}` }])
    }
  }

  /* ── Delete a custom super task ── */
  const handleDeleteSuperTask = async (id) => {
    try {
      await deleteSuperTask(id)
      setSuperTasks(prev => prev.filter(t => t.id !== id))
      setLogs(prev => [...prev, { type: 'sys', text: `[System] Super task ${id} deleted` }])
    } catch (err) {
      setLogs(prev => [...prev, { type: 'sys', text: `[Error] ${err.message}` }])
    }
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const updateAgentStatus = (agentId, status) => {
    setAgentStatuses(prev => ({ ...prev, [agentId]: status }))
    const agent = agents.find(a => a.id === agentId)
    if (agent) {
      setLogs(prev => [...prev, {
        type: 'sys',
        text: `[System] Agent ${agent.name} ${status === 'running' ? 'started' : 'stopped'}`,
      }])
    }
  }

  const handleRunAgent = () => selectedAgent && updateAgentStatus(selectedAgent.id, 'running')
  const handleStopAgent = () => {
    if (!selectedAgent) return
    if (abortRef.current) { abortRef.current.abort(); abortRef.current = null }
    setIsStreaming(false)
    updateAgentStatus(selectedAgent.id, 'stopped')
  }

  const currentStatus = selectedAgent ? (agentStatuses[selectedAgent.id] || 'idle') : 'idle'

  /* ── Log entry component ── */
  const renderLog = (log, index) => {
    const isLast = index === logs.length - 1
    const showCursor = log.id && isStreaming && isLast

    const typeClass =
      log.type === 'sys' ? 'log-entry-sys' :
      log.type === 'user' ? 'log-entry-user' :
      'log-entry-agent'

    return (
      <div key={index} className={`log-entry ${typeClass}`} style={{
        color: log.type === 'sys' ? 'var(--log-sys)' :
               log.type === 'user' ? 'var(--log-user)' :
               'var(--log-agent)'
      }}>
        {log.type === 'agent' ? (
          <MarkdownMessage text={log.text} isStreaming={showCursor} />
        ) : (
          <>
            <span className="whitespace-pre-wrap leading-relaxed">{log.text}</span>
            {showCursor && (
              <span className="inline-block w-2 h-4 ml-0.5 animate-pulse" style={{ backgroundColor: 'var(--cursor-color)' }} />
            )}
          </>
        )}
      </div>
    )
  }

  return (
    <div className="h-screen flex overflow-hidden" style={{
      backgroundColor: 'var(--bg-deep)',
      color: 'var(--text-primary)'
    }}>
      {/* ========================================
          Sidebar
      ======================================== */}
      <aside className="w-64 border-r flex flex-col shrink-0 relative" style={{
        backgroundColor: 'var(--bg-panel)',
        borderColor: 'var(--border-subtle)'
      }}>
        <div className="sidebar-gradient absolute inset-0" />

        {/* Logo */}
        <div className="h-14 border-b flex items-center gap-2.5 px-5 relative z-10" style={{ borderColor: 'var(--border-subtle)' }}>
          <div className="w-7 h-7 rounded-lg bg-emerald-500/10 flex items-center justify-center">
            <Zap className="w-4 h-4 text-emerald-400" />
          </div>
          <span className="font-semibold text-sm tracking-wide" style={{ color: 'var(--text-heading)' }}>
            MoonBit Runtime
          </span>
        </div>

        {/* Agent List */}
        <div className="flex-1 overflow-y-auto p-3 space-y-1 relative z-10">
          <div className="text-[10px] uppercase tracking-widest px-2 mb-2 font-semibold" style={{ color: 'var(--text-dim)' }}>
            {connecting ? (
              <span className="flex items-center gap-1.5">
                <Loader2 className="w-2.5 h-2.5 animate-spin" /> Connecting...
              </span>
            ) : (
              `Agents (${agents.length})`
            )}
          </div>

          {agents.map(agent => {
            const isSelected = selectedAgent?.id === agent.id
            return (
              <button
                key={agent.id}
                onClick={() => setSelectedAgent(agent)}
                className={`w-full text-left px-3 py-2.5 rounded-lg group border agent-item ${isSelected ? 'selected' : 'border-transparent'}`}
                style={{ borderColor: isSelected ? 'var(--border-muted)' : 'transparent' }}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 min-w-0">
                    <StatusDot status={agentStatuses[agent.id] || 'idle'} />
                    <span className="text-sm font-mono truncate" style={{ color: 'var(--text-heading)' }}>
                      {agent.name}
                    </span>
                  </div>
                  <span className="text-[10px] shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" style={{ color: 'var(--text-dim)' }}>
                    {agent.model}
                  </span>
                </div>
              </button>
            )
          })}

          {!connecting && agents.length === 0 && (
            <div className="flex flex-col items-center py-8 gap-2">
              <Bot className="w-8 h-8" style={{ color: 'var(--text-dimmer)' }} />
              <span className="text-xs" style={{ color: 'var(--text-dim)' }}>No agents available</span>
            </div>
          )}

          {/* Super Tasks */}
          <div className="mt-6">
            <div className="flex items-center justify-between px-2 mb-2">
              <span className="text-[10px] uppercase tracking-widest font-semibold" style={{ color: 'var(--text-dim)' }}>
                Super Tasks ({superTasks.length})
              </span>
              <button
                onClick={() => setShowCreateTask(true)}
                className="p-1 rounded transition-colors hover-bg hover-text"
                style={{ color: 'var(--text-dim)' }}
                title="创建自定义超级任务"
              >
                <Plus className="w-3.5 h-3.5" />
              </button>
            </div>
            <div className="space-y-1">
              {superTasks.map(st => (
                <div
                  key={st.id}
                  className="px-3 py-2.5 rounded-lg border group"
                  style={{ borderColor: 'var(--border-subtle)', backgroundColor: 'var(--bg-elevated)' }}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-medium truncate" style={{ color: 'var(--text-heading)' }}>{st.name}</span>
                    <div className="flex items-center gap-0.5 shrink-0">
                      {st.id !== 'st_001' && (
                        <button
                          onClick={() => handleDeleteSuperTask(st.id)}
                          className="p-1 rounded opacity-0 group-hover:opacity-100 transition-opacity hover-bg hover-text"
                          style={{ color: 'var(--text-dim)' }}
                          title="删除"
                        >
                          <Trash2 className="w-3 h-3" />
                        </button>
                      )}
                      <button
                        onClick={() => handleRunSuperTask(st)}
                        disabled={isStreaming}
                        className="p-1 rounded transition-colors hover-bg disabled:opacity-30 disabled:cursor-not-allowed"
                        style={{ color: isStreaming ? 'var(--text-dimmer)' : '#34d399' }}
                        title="执行"
                      >
                        <Play className="w-3 h-3" fill="currentColor" />
                      </button>
                    </div>
                  </div>
                  <p className="text-[10px] leading-relaxed mt-1 line-clamp-2" style={{ color: 'var(--text-dim)' }}>
                    {st.description}
                  </p>
                </div>
              ))}
              {superTasks.length === 0 && (
                <p className="text-[10px] px-2" style={{ color: 'var(--text-dimmer)' }}>No super tasks yet</p>
              )}
            </div>
          </div>
        </div>

        {/* Runtime Monitor */}
        <div className="border-t p-4 space-y-3 relative z-10" style={{ borderColor: 'var(--border-subtle)' }}>
          <div className="text-[10px] uppercase tracking-widest font-semibold" style={{ color: 'var(--text-dim)' }}>
            Runtime
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1" style={{ color: 'var(--text-dim)' }}>
                <MemoryStick className="w-3 h-3" /> Memory
              </span>
              <span className="font-mono text-[11px]" style={{ color: 'var(--text-muted)' }}>
                {runtime.memoryMb != null ? `${runtime.memoryMb} MB` : '-- MB'}
              </span>
            </div>
            <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--bg-elevated)' }}>
              <div className="h-full bg-blue-500/70 rounded-full transition-all duration-700" style={{
                width: runtime.totalMemoryMb ? `${Math.min(100, (runtime.memoryMb / runtime.totalMemoryMb) * 100)}%` : '0%'
              }} />
            </div>
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1" style={{ color: 'var(--text-dim)' }}>
                <Cpu className="w-3 h-3" /> CPU
              </span>
              <span className="font-mono text-[11px]" style={{ color: 'var(--text-muted)' }}>
                {runtime.cpuPct != null ? `${runtime.cpuPct}%` : '--%'}
              </span>
            </div>
            <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--bg-elevated)' }}>
              <div className="h-full bg-purple-500/70 rounded-full transition-all duration-700" style={{
                width: runtime.cpuPct != null ? `${runtime.cpuPct}%` : '0%'
              }} />
            </div>
          </div>
          {tools.length > 0 && (
            <div className="pt-1 flex items-center gap-1.5">
              <div className="flex -space-x-1">
                {tools.slice(0, 3).map((t, i) => (
                  <div key={t.id} className="w-4 h-4 rounded-full flex items-center justify-center text-[8px] font-mono border"
                    style={{ backgroundColor: 'var(--bg-elevated)', borderColor: 'var(--border-subtle)', color: 'var(--text-dim)' }}>
                    {t.name[0].toUpperCase()}
                  </div>
                ))}
              </div>
              <span className="text-[10px] font-mono" style={{ color: 'var(--text-dim)' }}>
                {tools.length} tools
              </span>
            </div>
          )}
        </div>
      </aside>

      {/* ========================================
          Main Area
      ======================================== */}
      <main className="flex-1 flex flex-col min-w-0">
        {/* Header */}
        <header className="h-14 border-b flex items-center justify-between px-6 shrink-0" style={{
          backgroundColor: 'var(--bg-panel)',
          borderColor: 'var(--border-subtle)'
        }}>
          <div className="flex items-center gap-4 min-w-0">
            {connecting ? (
              <Loader2 className="w-4 h-4 animate-spin" style={{ color: 'var(--text-muted)' }} />
            ) : (
              <>
                <h2 className="font-medium font-mono truncate text-sm" style={{ color: 'var(--text-heading)' }}>
                  {selectedAgent?.name || 'No Agent'}
                </h2>
                {selectedAgent && (
                  <span className={`flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full ${statusColor(currentStatus)}`}
                    style={{ backgroundColor: 'var(--bg-elevated)' }}
                  >
                    <span className="w-1.5 h-1.5 rounded-full bg-current" />
                    {currentStatus.toUpperCase()}
                  </span>
                )}
              </>
            )}
            {selectedAgent && (
              <span className="text-[10px] hidden sm:inline font-mono px-2 py-0.5 rounded" style={{ color: 'var(--text-dim)', backgroundColor: 'var(--bg-elevated)' }}>
                {selectedAgent.model}
              </span>
            )}
          </div>

          <div className="flex items-center gap-1.5 shrink-0">
            <ToolbarBtn onClick={toggleTheme} active={false}>
              {theme === 'dark' ? <Sun className="w-3.5 h-3.5" /> : <Moon className="w-3.5 h-3.5" />}
            </ToolbarBtn>
            <div className="w-px h-5 mx-0.5" style={{ backgroundColor: 'var(--border-subtle)' }} />
            <ToolbarBtn onClick={() => setShowConfig(true)} disabled={connecting || !selectedAgent}>
              <Settings className="w-3.5 h-3.5" /> Config
            </ToolbarBtn>
            <ToolbarBtn
              onClick={handleStopAgent}
              disabled={connecting || !selectedAgent || currentStatus !== 'running'}
              active={currentStatus === 'running'}
              color="#f87171"
              activeBg="var(--stop-btn-bg)"
            >
              <Square className="w-3 h-3" fill="currentColor" /> Stop
            </ToolbarBtn>
            <ToolbarBtn
              onClick={handleRunAgent}
              disabled={connecting || !selectedAgent || currentStatus === 'running'}
              active={currentStatus !== 'running'}
              color="#34d399"
              activeBg="var(--run-btn-bg)"
            >
              <Play className="w-3 h-3" fill="currentColor" /> Run
            </ToolbarBtn>
          </div>
        </header>

        {/* Terminal Logs */}
        <div className="flex-1 overflow-y-auto p-6 font-mono text-sm" style={{ backgroundColor: 'var(--bg-deep)' }}>
          {logs.length === 0 && connecting && (
            <div className="flex flex-col items-center justify-center h-full gap-3">
              <Loader2 className="w-6 h-6 animate-spin" style={{ color: 'var(--text-dimmer)' }} />
              <span className="text-xs" style={{ color: 'var(--text-dim)' }}>Connecting to backend...</span>
            </div>
          )}
          {logs.length === 0 && !connecting && (
            <div className="flex flex-col items-center justify-center h-full gap-3">
              <Terminal className="w-8 h-8" style={{ color: 'var(--text-dimmer)' }} />
              <span className="text-xs" style={{ color: 'var(--text-dim)' }}>Select an agent to get started</span>
            </div>
          )}
          {logs.map(renderLog)}
          <div ref={logEndRef} />
        </div>

        {/* Input Area */}
        <div className="border-t p-4 shrink-0" style={{
          backgroundColor: 'var(--bg-panel)',
          borderColor: 'var(--border-subtle)'
        }}>
          <div className="flex items-center gap-3 border rounded-xl px-4 py-3 input-wrapper" style={{
            backgroundColor: 'var(--bg-deep)',
            borderColor: 'var(--border-subtle)',
          }}>
            <div className="w-6 h-6 rounded-md flex items-center justify-center shrink-0" style={{ backgroundColor: 'var(--bg-elevated)' }}>
              <Terminal className="w-3.5 h-3.5" style={{ color: 'var(--text-dim)' }} />
            </div>
            <input
              ref={inputRef}
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={isStreaming || connecting || !selectedAgent}
              placeholder={
                connecting ? 'Connecting...' :
                isStreaming ? 'Waiting for response...' :
                !selectedAgent ? 'No agent selected' :
                'Type a message and press Enter...'
              }
              className="flex-1 bg-transparent text-sm outline-none font-mono min-w-0 disabled:cursor-not-allowed theme-input"
              style={{ color: 'var(--text-heading)' }}
            />
            <div className="flex items-center gap-2 shrink-0">
              <kbd className="text-[10px] px-1.5 py-0.5 rounded hidden sm:inline" style={{
                color: 'var(--text-dim)',
                backgroundColor: 'var(--bg-kbd)',
              }}>
                Enter
              </kbd>
              <button
                onClick={handleSend}
                disabled={!input.trim() || isStreaming || connecting || !selectedAgent}
                className="w-7 h-7 rounded-md flex items-center justify-center transition-all duration-200 disabled:cursor-not-allowed"
                style={{
                  backgroundColor: (!input.trim() || isStreaming) ? 'transparent' : 'var(--bg-elevated)',
                  color: (!input.trim() || isStreaming) ? 'var(--text-dimmer)' : 'var(--text-muted)',
                }}
              >
                {isStreaming ? (
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <Send className="w-3.5 h-3.5" />
                )}
              </button>
            </div>
          </div>

          {/* Example prompts */}
          {!isStreaming && !connecting && selectedAgent && showExamples && logs.length <= 2 && (
            <div className="mt-3 px-1 animate-fade-in" style={{ animation: 'fade-slide-in 0.3s ease-out' }}>
              <div className="flex items-center gap-2 mb-2">
                <span className="text-[10px] font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
                  Try asking
                </span>
                <button
                  onClick={() => setShowExamples(false)}
                  className="text-[10px] px-1.5 py-0.5 rounded hover-text"
                  style={{ color: 'var(--text-dimmer)' }}
                >
                  Hide
                </button>
              </div>
              <div className="flex flex-wrap gap-2">
                {examplePrompts.map((prompt, i) => (
                  <button
                    key={i}
                    onClick={() => { setInput(prompt); inputRef.current?.focus() }}
                    className="text-xs px-3 py-1.5 rounded-lg transition-all duration-200 border hover-bg hover-text"
                    style={{
                      color: 'var(--text-muted)',
                      borderColor: 'var(--border-subtle)',
                      backgroundColor: 'var(--bg-elevated)',
                    }}
                  >
                    {prompt}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </main>

      {/* ========================================
          Config Modal
      ======================================== */}
      {showConfig && selectedAgent && (
        <div className="fixed inset-0 z-50 flex items-center justify-center animate-modal" style={{ backgroundColor: 'var(--overlay-bg)' }}>
          <div className="rounded-xl w-full max-w-lg mx-4 max-h-[80vh] overflow-y-auto animate-modal" style={{
            backgroundColor: 'var(--bg-panel)',
            border: '1px solid var(--border-subtle)',
            boxShadow: '0 25px 50px -12px rgba(0,0,0,0.5)',
          }}>
            <div className="flex items-center justify-between px-5 py-4 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
              <h3 className="font-semibold text-sm flex items-center gap-2" style={{ color: 'var(--text-heading)' }}>
                <Settings className="w-4 h-4" /> Agent Configuration
              </h3>
              <button
                onClick={() => setShowConfig(false)}
                className="p-1 rounded-lg hover-bg hover-text transition-colors"
                style={{ color: 'var(--text-dim)' }}
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="p-5 space-y-4 text-sm">
              <ConfigField label="Agent ID" mono>{selectedAgent.id}</ConfigField>
              <ConfigField label="Name">{selectedAgent.name}</ConfigField>
              <ConfigField label="Model" mono>{selectedAgent.model}</ConfigField>
              <ConfigField label="System Prompt">
                <p className="text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{selectedAgent.system_prompt}</p>
              </ConfigField>
              <ConfigField label="Max Tokens" mono>{selectedAgent.max_tokens}</ConfigField>
              <ConfigField label="Temperature" mono>{selectedAgent.temperature}</ConfigField>

              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
                  Bound Tools ({tools.filter(t => selectedAgent.tool_ids?.includes(t.id)).length})
                </label>
                <div className="mt-1.5 space-y-1">
                  {tools.filter(t => selectedAgent.tool_ids?.includes(t.id)).map(tool => (
                    <div key={tool.id} className="flex items-center gap-2.5 px-3 py-2 rounded-lg" style={{ backgroundColor: 'var(--bg-elevated)' }}>
                      <div className="w-5 h-5 rounded flex items-center justify-center text-[9px] font-bold" style={{ backgroundColor: 'var(--bg-panel)', color: 'var(--text-dim)' }}>
                        {tool.name[0].toUpperCase()}
                      </div>
                      <div className="min-w-0">
                        <span className="text-xs font-mono" style={{ color: 'var(--text-heading)' }}>{tool.name}</span>
                        <span className="text-[10px] ml-2" style={{ color: 'var(--text-dim)' }}>{tool.description}</span>
                      </div>
                    </div>
                  ))}
                  {(!selectedAgent.tool_ids || selectedAgent.tool_ids.length === 0) && (
                    <p className="text-xs" style={{ color: 'var(--text-dimmer)' }}>No tools bound to this agent</p>
                  )}
                </div>
              </div>
            </div>

            <div className="border-t px-5 py-3 flex justify-end" style={{ borderColor: 'var(--border-subtle)' }}>
              <button
                onClick={() => setShowConfig(false)}
                className="text-xs px-4 py-2 rounded-lg transition-colors hover-bg"
                style={{ backgroundColor: 'var(--bg-elevated)', color: 'var(--text-heading)' }}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ========================================
          Create Super Task Modal
      ======================================== */}
      {showCreateTask && (
        <div className="fixed inset-0 z-50 flex items-center justify-center animate-modal" style={{ backgroundColor: 'var(--overlay-bg)' }}>
          <div className="rounded-xl w-full max-w-lg mx-4 animate-modal" style={{
            backgroundColor: 'var(--bg-panel)',
            border: '1px solid var(--border-subtle)',
            boxShadow: '0 25px 50px -12px rgba(0,0,0,0.5)',
          }}>
            <div className="flex items-center justify-between px-5 py-4 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
              <h3 className="font-semibold text-sm flex items-center gap-2" style={{ color: 'var(--text-heading)' }}>
                <Zap className="w-4 h-4" style={{ color: '#34d399' }} /> 新建超级任务
              </h3>
              <button
                onClick={() => setShowCreateTask(false)}
                className="p-1 rounded-lg hover-bg hover-text transition-colors"
                style={{ color: 'var(--text-dim)' }}
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="p-5 space-y-4 text-sm">
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
                  任务名称
                </label>
                <input
                  type="text"
                  value={taskName}
                  onChange={(e) => setTaskName(e.target.value)}
                  placeholder="例如: 市场行情总览"
                  className="mt-1.5 w-full px-3 py-2 rounded-lg outline-none text-sm font-mono"
                  style={{
                    backgroundColor: 'var(--bg-deep)',
                    border: '1px solid var(--border-subtle)',
                    color: 'var(--text-heading)',
                  }}
                />
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
                  任务描述
                </label>
                <textarea
                  value={taskDesc}
                  onChange={(e) => setTaskDesc(e.target.value)}
                  rows={5}
                  placeholder={'描述要执行的复杂任务，agent 会自主调用工具完成。\n例如: 帮我查阅大A、KOSPI、日经、纳斯达克、标普等最近的走势、振幅、换手和盘内异动信息，并汇总成一份简明报告'}
                  className="mt-1.5 w-full px-3 py-2 rounded-lg outline-none text-sm font-mono resize-none"
                  style={{
                    backgroundColor: 'var(--bg-deep)',
                    border: '1px solid var(--border-subtle)',
                    color: 'var(--text-heading)',
                  }}
                />
              </div>
              <p className="text-[10px] leading-relaxed" style={{ color: 'var(--text-dimmer)' }}>
                执行时将以任务描述作为指令发送给 ToolCaller Agent，它会按需调用搜索等工具逐步完成并汇总报告。
              </p>
            </div>

            <div className="border-t px-5 py-3 flex justify-end gap-2" style={{ borderColor: 'var(--border-subtle)' }}>
              <button
                onClick={() => setShowCreateTask(false)}
                className="text-xs px-4 py-2 rounded-lg transition-colors hover-bg"
                style={{ backgroundColor: 'var(--bg-elevated)', color: 'var(--text-heading)' }}
              >
                取消
              </button>
              <button
                onClick={handleCreateSuperTask}
                disabled={!taskName.trim() || !taskDesc.trim()}
                className="text-xs px-4 py-2 rounded-lg transition-all disabled:opacity-30 disabled:cursor-not-allowed"
                style={{ backgroundColor: 'var(--bg-elevated)', color: '#34d399' }}
              >
                创建并保存
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

/* ── Config field helper ── */
function ConfigField({ label, mono, children }) {
  return (
    <div>
      <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
        {label}
      </label>
      <p className={`mt-1 ${mono ? 'font-mono' : ''}`} style={{ color: 'var(--text-heading)' }}>
        {children}
      </p>
    </div>
  )
}

export default App
