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

        // Initialize all agents as 'idle'
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

    // Create a new streaming log entry
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
          // Remove the empty streaming entry
          const filtered = prev.filter(l => l.id !== logId)
          return [...filtered