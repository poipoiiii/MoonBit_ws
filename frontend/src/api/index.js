// 开发环境通过 Vite proxy 代理 /api
// 生产环境需配置 VITE_API_BASE 指向后端地址（如 http://your-host:8080）
const API_BASE = import.meta.env.VITE_API_BASE || '/api'

/**
 * 获取所有 Agent 列表
 * @returns {Promise<Array<{id:string, name:string, model:string, max_tokens:number}>>}
 */
export async function fetchAgents() {
  const res = await fetch(`${API_BASE}/agents`)
  if (!res.ok) throw new Error(`Failed to fetch agents: ${res.status}`)
  return res.json()
}

/**
 * 获取所有已启用的 Tool 列表
 * @returns {Promise<Array<{id:string, name:string, description:string, enabled:boolean}>>}
 */
export async function fetchTools() {
  const res = await fetch(`${API_BASE}/tools`)
  if (!res.ok) throw new Error(`Failed to fetch tools: ${res.status}`)
  return res.json()
}

/**
 * 获取运行时资源使用情况（进程内存与 CPU）
 * @returns {Promise<{memory_mb:number, cpu_ms:number, total_memory_mb:number}>}
 */
export async function fetchRuntime() {
  const res = await fetch(`${API_BASE}/runtime`)
  if (!res.ok) throw new Error(`Failed to fetch runtime: ${res.status}`)
  return res.json()
}

/**
 * 获取所有超级任务
 * @returns {Promise<Array<{id:string, name:string, description:string, agent_id:string, created_at:string}>>}
 */
export async function fetchSuperTasks() {
  const res = await fetch(`${API_BASE}/super_tasks`)
  if (!res.ok) throw new Error(`Failed to fetch super tasks: ${res.status}`)
  return res.json()
}

/**
 * 创建自定义超级任务
 * @param {{name:string, description:string}} task
 * @returns {Promise<{status:string, id:string, name:string, description:string, agent_id:string}>}
 */
export async function createSuperTask({ name, description }) {
  const res = await fetch(`${API_BASE}/super_tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, description }),
  })
  if (!res.ok) throw new Error(`Failed to create super task: ${res.status}`)
  return res.json()
}

/**
 * 删除自定义超级任务（默认任务不可删除）
 * @param {string} id
 */
export async function deleteSuperTask(id) {
  const res = await fetch(`${API_BASE}/super_tasks?id=${encodeURIComponent(id)}`, { method: 'DELETE' })
  if (!res.ok) throw new Error(`Failed to delete super task: ${res.status}`)
  return res.json()
}

/**
 * 内部：通过 fetch 消费 SSE 流，逐行解析 "data: " 前缀的数据
 */
function streamEventSource(url, { onData, onDone, onError }) {
  const controller = new AbortController()

  ;(async () => {
    try {
      const res = await fetch(url, {
        signal: controller.signal,
        headers: { 'Accept': 'text/event-stream' },
      })

      if (!res.ok) {
        const text = await res.text().catch(() => '')
        throw new Error(`API error ${res.status}: ${text || res.statusText}`)
      }

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() || '' // keep incomplete line in buffer

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6)
            if (data === '[DONE]') {
              onDone?.()
            } else {
              onData?.(data)
            }
          }
        }
      }

      // Process remaining buffer
      if (buffer.startsWith('data: ')) {
        const data = buffer.slice(6)
        if (data !== '[DONE]') onData?.(data)
      }

      onDone?.()
    } catch (err) {
      if (err.name === 'AbortError') return
      onError?.(err)
    }
  })()

  return controller
}

/**
 * 创建 SSE 聊天流
 * @param {string} agentId - Agent ID
 * @param {string} message - 用户消息
 * @param {object} callbacks
 * @param {(text: string) => void} callbacks.onData - 收到数据回调
 * @param {() => void} callbacks.onDone - 流结束回调
 * @param {(err: Error) => void} callbacks.onError - 错误回调
 * @returns {AbortController} 用于取消请求的 controller
 */
export function createChatStream(agentId, message, callbacks) {
  const url = `${API_BASE}/chat?agent_id=${encodeURIComponent(agentId)}&message=${encodeURIComponent(message)}`
  return streamEventSource(url, callbacks)
}

/**
 * 执行超级任务（SSE 流，agent 自主调用工具完成）
 * @param {string} id - 超级任务 ID
 * @param {string} agentId - 执行该任务的 Agent ID
 * @param {object} callbacks - 同 createChatStream
 * @returns {AbortController}
 */
export function runSuperTaskStream(id, agentId, callbacks) {
  const url = `${API_BASE}/super_tasks/run?id=${encodeURIComponent(id)}&agent_id=${encodeURIComponent(agentId)}`
  return streamEventSource(url, callbacks)
}
