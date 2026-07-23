import { useState, useRef, useEffect, useCallback } from 'react'
import {
  Zap, MemoryStick, Cpu, Settings, Square, Play,
  Terminal, Send, CircleDot, Loader2, WifiOff
} from 'lucide-react'
import { fetchAgents, fetchTools, createChatStream } from './api'

function App() {
  const [agents, setAgents] = useState([])
  const [selectedAgent, setSelectedAgent] = useState(null)
  const [tools, setTools] = useState([])
  const [logs, setLogs] = useState([])
  const [input, setInput] = useState('')
  const [isStreaming, setIsStreaming] = useState(false)
  const [connecting, setConnecting] = useState(true)
  const [agentStatuses, setAgentStatuses] = useState({})
  const logEndRef = useRef(null)
  const inputRef = useRef(null)
  const abortRef = useRef(null)

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
    <div className="h-screen flex bg-[#0a0a0a] text-gray-300 overflow-hidden">
      {/* ===== 左侧栏 ===== */}
      <aside className="w-64 border-r border-gray-900 flex flex-col bg-[#0d0d0d] shrink-0">
        {/* Logo */}
        <div className="h-14 border-b border-gray-900 flex items-center gap-2.5 px-5">
          <Zap className="w-5 h-5 text-emerald-400" />
          <span className="text-white font-semibold text-sm tracking-wide">MoonBit Runtime</span>
        </div>

        {/* Agent 列表 */}
        <div className="flex-1 overflow-y-auto p-3 space-y-1.5">
          <div className="text-[10px] text-gray-600 uppercase tracking-widest px-2 mb-2 font-semibold">
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
              className={`w-full text-left px-3 py-2.5 rounded-lg transition-all duration-200 group ${
                selectedAgent?.id === agent.id
                  ? 'bg-gray-800/60 border border-gray-700/80'
                  : 'hover:bg-gray-800/30 border border-transparent'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 min-w-0">
                  <CircleDot className={`w-3 h-3 shrink-0 ${statusColor(agentStatuses[agent.id] || 'idle')}`} />
                  <span className="text-sm text-gray-200 font-mono truncate">{agent.name}</span>
                </div>
                <span className="text-[10px] text-gray-600 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
                  {agent.model}
                </span>
              </div>
            </button>
          ))}
          {!connecting && agents.length === 0 && (
            <div className="text-xs text-gray-600 text-center py-4">
              <WifiOff className="w-4 h-4 mx-auto mb-1" />
              No agents found
            </div>
          )}
        </div>

        {/* 资源监控 */}
        <div className="border-t border-gray-900 p-4 space-y-3">
          <div className="text-[10px] text-gray-600 uppercase tracking-widest font-semibold">
            Runtime
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1 text-gray-500">
                <MemoryStick className="w-3 h-3" /> Memory
              </span>
              <span className="text-gray-400 font-mono">-- MB</span>
            </div>
            <div className="h-1 bg-gray-900 rounded-full overflow-hidden">
              <div className="h-0 w-0 bg-blue-500 rounded-full transition-all duration-700" />
            </div>
          </div>
          <div>
            <div className="flex justify-between text-xs mb-1">
              <span className="flex items-center gap-1 text-gray-500">
                <Cpu className="w-3 h-3" /> CPU
              </span>
              <span className="text-gray-400 font-mono">--%</span>
            </div>
            <div className="h-1 bg-gray-900 rounded-full overflow-hidden">
              <div className="h-0 w-0 bg-purple-500 rounded-full transition-all duration-700" />
            </div>
          </div>
          {tools.length > 0 && (
            <div className="pt-1">
              <div className="text-[10px] text-gray-600 font-mono">
                {tools.length} tools registered
              </div>
            </div>
          )}
        </div>
      </aside>

      {/* ===== 主交互区 ===== */}
      <main className="flex-1 flex flex-col min-w-0">
        {/* 顶部栏 */}
        <header className="h-14 border-b border-gray-900 flex items-center justify-between px-6 bg-[#0d0d0d] shrink-0">
          <div className="flex items-center gap-4 min-w-0">
            <div className="flex items-center gap-3">
              {connecting ? (
                <Loader2 className="w-4 h-4 text-gray-500 animate-spin" />
              ) : (
                <>
                  <h2 className="text-white font-medium font-mono truncate text-sm">
                    {selectedAgent?.name || 'No Agent'}
                  </h2>
                  {selectedAgent && (
                    <span className={`flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full bg-gray-900 ${statusColor(currentStatus)}`}>
                      <span className="w-1.5 h-1.5 rounded-full bg-current" />
                      {currentStatus.toUpperCase()}
                    </span>
                  )}
                </>
              )}
            </div>
            {selectedAgent && (
              <span className="text-[10px] text-gray-600 hidden sm:inline font-mono">
                {selectedAgent.model}
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button
              disabled={connecting || !selectedAgent}
              className="text-xs text-gray-500 hover:text-white disabled:text-gray-700 flex items-center gap-1.5 px-3 py-1.5 rounded-lg hover:bg-gray-800 disabled:hover:bg-transparent transition-all duration-200"
            >
              <Settings className="w-3.5 h-3.5" /> Config
            </button>
            <button
              onClick={handleStopAgent}
              disabled={connecting || !selectedAgent || currentStatus !== 'running'}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-900/30 hover:bg-red-900/50 text-red-400 disabled:text-gray-700 disabled:bg-transparent transition-all duration-200"
            >
              <Square className="w-3 h-3" fill="currentColor" /> Stop
            </button>
            <button
              onClick={handleRunAgent}
              disabled={connecting || !selectedAgent || currentStatus === 'running'}
              className="text-xs flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-emerald-900/30 hover:bg-emerald-900/50 text-emerald-400 disabled:text-gray-700 disabled:bg-transparent transition-all duration-200"
            >
              <Play className="w-3 h-3" fill="currentColor" /> Run
            </button>
          </div>
        </header>

        {/* 终端输出区 */}
        <div className="flex-1 overflow-y-auto p-6 font-mono text-sm bg-[#0a0a0a]">
          {logs.length === 0 && connecting && (
            <div className="flex items-center justify-center h-full text-gray-700">
              <Loader2 className="w-5 h-5 animate-spin mr-2" />
              Connecting to backend...
            </div>
          )}
          {logs.length === 0 && !connecting && (
            <div className="flex items-center justify-center h-full text-gray-700">
              Select an agent to get started
            </div>
          )}
          {logs.map((log, index) => (
            <div
              key={index}
              className={`mb-1 leading-relaxed whitespace-pre-wrap ${
                log.type === 'sys' ? 'text-purple-400/70' :
                log.type === 'user' ? 'text-blue-400' :
                'text-gray-300'
              }`}
            >
              {log.text}
              {log.id && isStreaming && index === logs.length - 1 && (
                <span className="inline-block w-2 h-4 bg-gray-400 ml-0.5 animate-pulse" />
              )}
            </div>
          ))}
          <div ref={logEndRef} />
        </div>

        {/* 底部输入区 */}
        <div className="border-t border-gray-900 p-4 bg-[#0d0d0d] shrink-0">
          <div className="flex items-center gap-3 bg-[#0a0a0a] border border-gray-900 rounded-xl px-4 py-3 focus-within:border-gray-700 transition-all duration-300">
            <Terminal className="w-4 h-4 text-gray-600 shrink-0" />
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
              className="flex-1 bg-transparent text-sm text-white placeholder-gray-700 outline-none font-mono min-w-0 disabled:cursor-not-allowed"
            />
            <div className="flex items-center gap-2 shrink-0">
              <kbd className="text-[10px] text-gray-700 bg-gray-900 px-1.5 py-0.5 rounded hidden sm:inline">
                ⌘ + ↵
              </kbd>
              <button
                onClick={handleSend}
                disabled={!input.trim() || isStreaming || connecting || !selectedAgent}
                className="text-gray-500 hover:text-white disabled:text-gray-800 transition-colors p-1 disabled:cursor-not-allowed"
              >
                {isStreaming ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Send className="w-4 h-4" />
                )}
              </button>
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}

export default App
