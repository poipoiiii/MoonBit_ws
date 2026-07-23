import { useState, useRef, useEffect, useCallback } from 'react'
import {
  Zap, MemoryStick, Cpu, Settings, Square, Play,
  Terminal, Send, CircleDot, Loader2, WifiOff,
  Sun, Moon, X, Info
} from 'lucide-react'
import { fetchAgents, fetchTools, createChatStream } from './api'
import { useTheme } from './ThemeContext'
import MarkdownMessage from './components/MarkdownMessage'

function App() {
  const { theme, toggleTheme } = useTheme()
  const [agents, setAgents] = useState([])
  const [selectedAgent, setSelectedAgent] = useState(null)
  const [tools, setTools] = useState([])
  const [logs, setLogs] = useState([])
  const [input, setInput] = useState('')
  const [isStreaming, setIsStreaming] = useState(false)
  const [connecting, setConnecting] = useState(true)
  const [agentStatuses, setAgentStatuses] = useState({})
  const [showConfig, setShowConfig] = useState(false)
  const [showExamples, setShowExamples] = useState(true)
  const logEndRef = useRef(null)
  const inputRef = useRef(null)
  const abortRef = useRef(null)

  const examplePrompts = [
    '你好，宁波距离山东多远',
    '帮我计算 256 * 48 等于多少',
    '读取当前目录下的 agents.csv 文件',
    '有哪些工具可以使用？',
  ]

  // Load data from backend on mount
  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        setConnecting(true)
        const [agentData, toolData] = await Promise.all([
          fetchAgents(),
          fetchTools(),
        ])
        if (cancelled) return

        setAgents(agentData)
        setTools(toolData)

        const statuses = {}
        agentData.forEach(a => { statuses[a.id] = 'idle' })
        setAgentStatuses(statuses)

        if (agentData.length > 0) {
          setSelectedAgent(agentData[0])
        }

        setLogs([
          { type: 'sys', text: `[System] MoonBit Runtime connected` },
          { type: 'sys', text: `[System] Loaded ${agentData.length} agents, ${toolData.length} tools` },
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

  // Auto-scroll log
  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [logs])

  // Focus input after streaming completes
  useEffect(() => {
    if (!isStreaming) inputRef.current?.focus()
  }, [isStreaming])

  const statusColor = (status) => {
    switch (status) {
      case 'running': return 'text-emerald-400'
      case 'idle': return 'text-amber-400'
      case 'stopped': return 'text-rose-400'
      default: return 'text-gray-400'
    }
  }

  const handleSend = useCallback(() => {
    if (!input.trim() || !selectedAgent || isStreaming) return
    const userMsg = input.trim()

    setLogs(prev => [...prev, { type: 'user', text: `> ${userMsg}` }])
    setInput('')
    setIsStreaming(true)

    const logId = `resp-${Date.now()}`
    setLogs(prev => [...prev, { type: 'agent', text: '', id: logId }])

    const controller = createChatStream(selectedAgent.id, userMsg, {
      onData: (text) => {
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
      },
      onDone: () => {
        setLogs(prev => [...prev, { type: 'sys', text: `[Runtime] Response complete` }])
        setIsStreaming(false)
      },
      onError: (err) => {
        setLogs(prev => {
          const filtered = prev.filter(l => l.id !== logId)
          return [...filtered, { type: 'sys', text: `[Error] ${err.message}` }]
        })
        setIsStreaming(false)
      },
    })
    abortRef.current = controller
  }, [input, selectedAgent, isStreaming])

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

  const handleRunAgent = () => {
    if (!selectedAgent) return
    updateAgentStatus(selectedAgent.id, 'running')
  }

  const handleStopAgent = () => {
    if (!selectedAgent) return
    if (abortRef.current) {
      abortRef.current.abort()
      abortRef.current = null
    }
    setIsStreaming(false)
    updateAgentStatus(selectedAgent.id, 'stopped')
  }

  const currentStatus = selectedAgent ? (agentStatuses[selectedAgent.id] || 'idle') : 'idle'

  return (
    <div className="h-screen flex overflow-hidden" style={{
      backgroundColor: 'var(--bg-deep)',
      color: 'var(--text-primary)'
    }}>
      {/* ===== 左侧栏 ===== */}
      <aside className="w-64 border-r flex flex-col shrink-0" style={{
        backgroundColor: 'var(--bg-panel)',
        borderColor: 'var(--border-subtle)'
      }}>
        {/* Logo */}
        <div className="h-14 border-b flex items-center gap-2.5 px-5" style={{
          borderColor: 'var(--border-subtle)'
        }}>
          <Zap className="w-5 h-5 text-emerald-400" />
          <span className="font-semibold text-sm tracking-wide" style={{ color: 'var(--text-heading)' }}>
            MoonBit Runtime
          </span>
        </div>

        {/* Agent 列表 */}
        <div className="flex-1 overflow-y-auto p-3 space-y-1.5">
          <div className="text-[10px] uppercase tracking-widest px-2 mb-2 font-semibold" style={{ color: 'var(--text-dim)' }}>
            {connecting ? (
              <span className="flex items-center gap-1.5">
                <Loader2 className="w-2.5 h-2.5 animate-spin" /> Connecting...
              </span>
            ) : (
              `Agents (${agents.length})`
            )}
          </div>
          {agents.map(agent => (
            <button
              key={agent.id}
              onClick={() => setSelectedAgent(agent)}
              className={`w-full text-left px-3 py-2.5 rounded-lg transition-all duration-200 group border ${
                selectedAgent?.id === agent.id
                  ? 'border'
                  : 'border-transparent hover:'
              }`}
              style={{
                backgroundColor: selectedAgent?.id === agent.id
                  ? 'var(--bg-selected)'
                  : 'transparent',
                borderColor: selectedAgent?.id === agent.id
                  ? 'var(--border-muted)'
                  : 'transparent',
              }}
              onMouseEnter={e => {
                if (selectedAgent?.id !== agent.id)
                  e.currentTarget.style.backgroundColor = 'var(--bg-hover)'
              }}
              onMouseLeave={e => {
                if (selectedAgent?.id !== agent.id)
                  e.currentTarget.style.backgroundColor = 'transparent'
              }}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 min-w-0">
                  <CircleDot className={`w-3 h-3 shrink-0 ${statusColor(agentStatuses[agent.id] || 'idle')}`} />
                  <span className="text-sm font-mono truncate" style={{ color: 'var(--text-heading)' }}>
                    {agent.name}
                  </span>
                </div>
                <span className="text-[10px] shrink-0 opacity-0 group-hover:opacity-100 transition-opacity" style={{ color: 'var(--text-dim)' }}>
                  {agent.model}
                </span>
              </div>
            </button>
          ))}
          {!connecting && agents.length === 0 && (
            <div className="text-xs text-center py-4" style={{ color: 'var(--text-dim)' }}>
              <WifiOff className="w-4 h-4 mx-auto mb-1" />
              No agents found
            </div>
          )}
        </div>

        {/* 资源监控 */}
        <div className="border-t p-4 space-y-3" style={{
          borderColor: 'var(--border-subtle)'
        }}>
          <div className="text-[10px] uppercase tracking-widest font-semibold" style={{ color: 'var(--text-dim)' }}>
            Runtime
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1" style={{ color: 'var(--text-dim)' }}>
                <MemoryStick className="w-3 h-3" /> Memory
              </span>
              <span className="font-mono" style={{ color: 'var(--text-muted)' }}>-- MB</span>
            </div>
            <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--bg-elevated)' }}>
              <div className="h-0 w-0 bg-blue-500 rounded-full transition-all duration-700" />
            </div>
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1" style={{ color: 'var(--text-dim)' }}>
                <Cpu className="w-3 h-3" /> CPU
              </span>
              <span className="font-mono" style={{ color: 'var(--text-muted)' }}>--%</span>
            </div>
            <div className="h-1 rounded-full overflow-hidden" style={{ backgroundColor: 'var(--bg-elevated)' }}>
              <div className="h-0 w-0 bg-purple-500 rounded-full transition-all duration-700" />
            </div>
          </div>
          {tools.length > 0 && (
            <div className="pt-1">
              <div className="text-[10px] font-mono" style={{ color: 'var(--text-dim)' }}>
                {tools.length} tools registered
              </div>
            </div>
          )}
        </div>
      </aside>

      {/* ===== 主交互区 ===== */}
      <main className="flex-1 flex flex-col min-w-0">
        {/* 顶部栏 */}
        <header className="h-14 border-b flex items-center justify-between px-6 shrink-0" style={{
          backgroundColor: 'var(--bg-panel)',
          borderColor: 'var(--border-subtle)'
        }}>
          <div className="flex items-center gap-4 min-w-0">
            <div className="flex items-center gap-3">
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
            </div>
            {selectedAgent && (
              <span className="text-[10px] hidden sm:inline font-mono" style={{ color: 'var(--text-dim)' }}>
                {selectedAgent.model}
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {/* 主题切换按钮 */}
            <button
              onClick={toggleTheme}
              className="text-xs flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg transition-all duration-200"
              style={{
                color: 'var(--text-muted)',
              }}
              onMouseEnter={e => { e.currentTarget.style.backgroundColor = 'var(--config-hover)'; e.currentTarget.style.color = 'var(--text-heading)' }}
              onMouseLeave={e => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'var(--text-muted)' }}
              title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
            >
              {theme === 'dark' ? <Sun className="w-3.5 h-3.5" /> : <Moon className="w-3.5 h-3.5" />}
            </button>
            <button
              onClick={() => setShowConfig(true)}
              disabled={connecting || !selectedAgent}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
              style={{
                color: 'var(--text-muted)',
              }}
              onMouseEnter={e => { if (!e.currentTarget.disabled) { e.currentTarget.style.backgroundColor = 'var(--config-hover)'; e.currentTarget.style.color = 'var(--text-heading)' } }}
              onMouseLeave={e => { e.currentTarget.style.backgroundColor = 'transparent'; e.currentTarget.style.color = 'var(--text-muted)' }}
            >
              <Settings className="w-3.5 h-3.5" /> Config
            </button>
            <button
              onClick={handleStopAgent}
              disabled={connecting || !selectedAgent || currentStatus !== 'running'}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
              style={{
                color: currentStatus === 'running' ? '#f87171' : 'var(--text-dimmer)',
                backgroundColor: currentStatus === 'running' ? 'var(--stop-btn-bg)' : 'transparent',
              }}
              onMouseEnter={e => { if (!e.currentTarget.disabled) e.currentTarget.style.backgroundColor = 'var(--stop-btn-hover)' }}
              onMouseLeave={e => { e.currentTarget.style.backgroundColor = currentStatus === 'running' ? 'var(--stop-btn-bg)' : 'transparent' }}
            >
              <Square className="w-3 h-3" fill="currentColor" /> Stop
            </button>
            <button
              onClick={handleRunAgent}
              disabled={connecting || !selectedAgent || currentStatus === 'running'}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg transition-all duration-200"
              style={{
                color: currentStatus !== 'running' ? '#34d399' : 'var(--text-dimmer)',
                backgroundColor: currentStatus !== 'running' ? 'var(--run-btn-bg)' : 'transparent',
              }}
              onMouseEnter={e => { if (!e.currentTarget.disabled) e.currentTarget.style.backgroundColor = 'var(--run-btn-hover)' }}
              onMouseLeave={e => { e.currentTarget.style.backgroundColor = currentStatus !== 'running' ? 'var(--run-btn-bg)' : 'transparent' }}
            >
              <Play className="w-3 h-3" fill="currentColor" /> Run
            </button>
          </div>
        </header>

        {/* 终端输出区 */}
        <div className="flex-1 overflow-y-auto p-6 font-mono text-sm" style={{
          backgroundColor: 'var(--bg-deep)'
        }}>
          {logs.length === 0 && connecting && (
            <div className="flex items-center justify-center h-full" style={{ color: 'var(--text-dimmer)' }}>
              <Loader2 className="w-5 h-5 animate-spin mr-2" />
              Connecting to backend...
            </div>
          )}
          {logs.length === 0 && !connecting && (
            <div className="flex items-center justify-center h-full" style={{ color: 'var(--text-dimmer)' }}>
              Select an agent to get started
            </div>
          )}
          {logs.map((log, index) => {
            const isAgent = log.type === 'agent'
            return (
              <div
                key={index}
                className={`mb-1${isAgent ? '' : ' leading-relaxed whitespace-pre-wrap'}`}
                style={{
                  color: log.type === 'sys' ? 'var(--log-sys)' :
                         log.type === 'user' ? 'var(--log-user)' :
                         'var(--log-agent)'
                }}
              >
                {isAgent ? (
                  <MarkdownMessage
                    text={log.text}
                    isStreaming={isStreaming && index === logs.length - 1}
                  />
                ) : (
                  <>
                    {log.text}
                    {log.id && isStreaming && index === logs.length - 1 && (
                      <span className="inline-block w-2 h-4 ml-0.5 animate-pulse" style={{ backgroundColor: 'var(--cursor-color)' }} />
                    )}
                  </>
                )}
              </div>
            )
          })}
          <div ref={logEndRef} />
        </div>

        {/* 底部输入区 */}
        <div className="border-t p-4 shrink-0" style={{
          backgroundColor: 'var(--bg-panel)',
          borderColor: 'var(--border-subtle)'
        }}>
          <div className="flex items-center gap-3 border rounded-xl px-4 py-3 transition-all duration-300" style={{
            backgroundColor: 'var(--bg-deep)',
            borderColor: 'var(--border-subtle)',
          }}>
            <Terminal className="w-4 h-4 shrink-0" style={{ color: 'var(--text-dim)' }} />
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
                'Send a prompt or command...'
              }
              className="flex-1 bg-transparent text-sm outline-none font-mono min-w-0 disabled:cursor-not-allowed theme-input"
              style={{
                color: 'var(--text-heading)',
              }}
              onFocus={e => {
                const input = e.currentTarget.closest('.rounded-xl')
                if (input) input.style.borderColor = 'var(--border-muted)'
              }}
              onBlur={e => {
                const input = e.currentTarget.closest('.rounded-xl')
                if (input) input.style.borderColor = 'var(--border-subtle)'
              }}
            />
            <div className="flex items-center gap-2 shrink-0">
              <kbd className="text-[10px] px-1.5 py-0.5 rounded hidden sm:inline" style={{
                color: 'var(--text-dim)',
                backgroundColor: 'var(--bg-kbd)',
              }}>
                ⌘ + ↵
              </kbd>
              <button
                onClick={handleSend}
                disabled={!input.trim() || isStreaming || connecting || !selectedAgent}
                className="transition-colors p-1 disabled:cursor-not-allowed"
                style={{
                  color: (!input.trim() || isStreaming) ? 'var(--text-dimmer)' : 'var(--text-muted)',
                }}
                onMouseEnter={e => { if (!e.currentTarget.disabled) e.currentTarget.style.color = 'var(--text-heading)' }}
                onMouseLeave={e => { e.currentTarget.style.color = (!input.trim() || isStreaming) ? 'var(--text-dimmer)' : 'var(--text-muted)' }}
              >
                {isStreaming ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Send className="w-4 h-4" />
                )}
              </button>
            </div>
          </div>
          {/* Example prompts */}
          {!isStreaming && !connecting && selectedAgent && showExamples && logs.length <= 2 && (
            <div className="mt-3 px-2">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-[10px] font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>
                  你可以这样问我:
                </span>
                <button
                  onClick={() => setShowExamples(false)}
                  className="text-[10px] px-1.5 py-0.5 rounded transition-colors"
                  style={{ color: 'var(--text-dimmer)' }}
                  onMouseEnter={e => e.currentTarget.style.color = 'var(--text-muted)'}
                  onMouseLeave={e => e.currentTarget.style.color = 'var(--text-dimmer)'}
                >
                  Hide
                </button>
              </div>
              <div className="flex flex-wrap gap-2">
                {examplePrompts.map((prompt, i) => (
                  <button
                    key={i}
                    onClick={() => {
                      setInput(prompt)
                      inputRef.current?.focus()
                    }}
                    className="text-xs px-3 py-1.5 rounded-lg transition-all duration-200 border"
                    style={{
                      color: 'var(--text-muted)',
                      borderColor: 'var(--border-subtle)',
                      backgroundColor: 'var(--bg-elevated)',
                    }}
                    onMouseEnter={e => {
                      e.currentTarget.style.borderColor = 'var(--border-muted)'
                      e.currentTarget.style.color = 'var(--text-heading)'
                    }}
                    onMouseLeave={e => {
                      e.currentTarget.style.borderColor = 'var(--border-subtle)'
                      e.currentTarget.style.color = 'var(--text-muted)'
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
      {/* </div> */}

      {/* ===== Config Modal ===== */}
      {showConfig && selectedAgent && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }}>
          <div className="rounded-xl w-full max-w-lg mx-4 max-h-[80vh] overflow-y-auto" style={{
            backgroundColor: 'var(--bg-panel)',
            border: '1px solid var(--border-subtle)',
          }}>
            <div className="flex items-center justify-between px-5 py-4 border-b" style={{ borderColor: 'var(--border-subtle)' }}>
              <h3 className="font-semibold text-sm flex items-center gap-2" style={{ color: 'var(--text-heading)' }}>
                <Settings className="w-4 h-4" /> Agent Configuration
              </h3>
              <button onClick={() => setShowConfig(false)} className="p-1 rounded-lg transition-colors" style={{ color: 'var(--text-dim)' }}
                onMouseEnter={e => e.currentTarget.style.color = 'var(--text-heading)'}
                onMouseLeave={e => e.currentTarget.style.color = 'var(--text-dim)'}
              >
                <X className="w-4 h-4" />
              </button>
            </div>
            <div className="p-5 space-y-4 text-sm">
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Agent ID</label>
                <p className="mt-1 font-mono" style={{ color: 'var(--text-heading)' }}>{selectedAgent.id}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Name</label>
                <p className="mt-1" style={{ color: 'var(--text-heading)' }}>{selectedAgent.name}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Model</label>
                <p className="mt-1 font-mono" style={{ color: 'var(--text-heading)' }}>{selectedAgent.model}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>System Prompt</label>
                <p className="mt-1 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{selectedAgent.system_prompt}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Max Tokens</label>
                <p className="mt-1 font-mono" style={{ color: 'var(--text-heading)' }}>{selectedAgent.max_tokens}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Temperature</label>
                <p className="mt-1 font-mono" style={{ color: 'var(--text-heading)' }}>{selectedAgent.temperature}</p>
              </div>
              <div>
                <label className="text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-dim)' }}>Bound Tools ({tools.filter(t => selectedAgent.tool_ids?.includes(t.id)).length})</label>
                <div className="mt-1 space-y-1">
                  {tools.filter(t => selectedAgent.tool_ids?.includes(t.id)).map(tool => (
                    <div key={tool.id} className="flex items-center gap-2 px-2 py-1.5 rounded-lg" style={{ backgroundColor: 'var(--bg-elevated)' }}>
                      <Info className="w-3 h-3 shrink-0" style={{ color: 'var(--text-dim)' }} />
                      <span className="text-xs font-mono" style={{ color: 'var(--text-heading)' }}>{tool.name}</span>
                      <span className="text-[10px]" style={{ color: 'var(--text-dim)' }}>- {tool.description}</span>
                    </div>
                  ))}
                  {!selectedAgent.tool_ids && (
                    <p className="text-xs" style={{ color: 'var(--text-dimmer)' }}>No tools bound</p>
                  )}
                </div>
              </div>
            </div>
            <div className="border-t px-5 py-3 flex justify-end" style={{ borderColor: 'var(--border-subtle)' }}>
              <button onClick={() => setShowConfig(false)} className="text-xs px-4 py-2 rounded-lg transition-colors" style={{
                backgroundColor: 'var(--bg-elevated)',
                color: 'var(--text-heading)',
              }}
                onMouseEnter={e => e.currentTarget.style.backgroundColor = 'var(--bg-hover)'}
                onMouseLeave={e => e.currentTarget.style.backgroundColor = 'var(--bg-elevated)'}
              >Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default App
