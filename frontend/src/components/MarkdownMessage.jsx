import React from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

/**
 * MarkdownMessage - renders agent response text with full Markdown support.
 *
 * Handles streaming text gracefully: react-markdown will re-render
 * whenever the `text` prop changes, so partial tokens accumulate
 * naturally and the user sees progressive rendering.
 */
export default function MarkdownMessage({ text, isStreaming }) {
  if (!text) return null

  return (
    <div className="markdown-body">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          // --- Code blocks (fenced ```) ---
          code({ node, className, children, ...props }) {
            const match = /language-(\w+)/.exec(className || '')
            const isInline = !match && !className
            const codeStr = String(children).replace(/\n$/, '')

            if (isInline) {
              return (
                <code
                  className="inline-code"
                  style={{
                    backgroundColor: 'var(--bg-elevated)',
                    color: 'var(--text-heading)',
                    padding: '2px 6px',
                    borderRadius: '4px',
                    fontSize: '0.875em',
                    fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                  }}
                  {...props}
                >
                  {children}
                </code>
              )
            }

            return (
              <div className="code-block-wrapper" style={{ margin: '12px 0' }}>
                {match && (
                  <div
                    className="code-lang-label"
                    style={{
                      padding: '2px 12px',
                      fontSize: '11px',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      color: 'var(--text-dim)',
                      backgroundColor: 'var(--bg-elevated)',
                      borderBottom: '1px solid var(--border-subtle)',
                      fontFamily: 'monospace',
                    }}
                  >
                    {match[1]}
                  </div>
                )}
                <pre
                  style={{
                    backgroundColor: 'var(--bg-elevated)',
                    border: '1px solid var(--border-subtle)',
                    borderRadius: match ? '0 0 8px 8px' : '8px',
                    padding: '14px 16px',
                    overflow: 'auto',
                    fontSize: '13px',
                    lineHeight: '1.6',
                    fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                    margin: 0,
                  }}
                >
                  <code className={className} {...props}>
                    {children}
                  </code>
                </pre>
              </div>
            )
          },

          // --- Tables ---
          table({ children }) {
            return (
              <div style={{ overflow: 'auto', margin: '12px 0' }}>
                <table
                  style={{
                    borderCollapse: 'collapse',
                    width: '100%',
                    fontSize: '13px',
                  }}
                >
                  {children}
                </table>
              </div>
            )
          },
          th({ children }) {
            return (
              <th
                style={{
                  border: '1px solid var(--border-subtle)',
                  padding: '8px 12px',
                  backgroundColor: 'var(--bg-elevated)',
                  fontWeight: 600,
                  textAlign: 'left',
                }}
              >
                {children}
              </th>
            )
          },
          td({ children }) {
            return (
              <td
                style={{
                  border: '1px solid var(--border-subtle)',
                  padding: '6px 12px',
                }}
              >
                {children}
              </td>
            )
          },

          // --- Links ---
          a({ href, children }) {
            return (
              <a
                href={href}
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: 'var(--log-user)', textDecoration: 'underline' }}
              >
                {children}
              </a>
            )
          },

          // --- Headings ---
          h1({ children }) {
            return <h1 style={{ fontSize: '1.3em', margin: '16px 0 8px', fontWeight: 600 }}>{children}</h1>
          },
          h2({ children }) {
            return <h2 style={{ fontSize: '1.15em', margin: '14px 0 6px', fontWeight: 600 }}>{children}</h2>
          },
          h3({ children }) {
            return <h3 style={{ fontSize: '1.05em', margin: '12px 0 4px', fontWeight: 600 }}>{children}</h3>
          },

          // --- Lists ---
          ul({ children }) {
            return <ul style={{ paddingLeft: '20px', margin: '8px 0' }}>{children}</ul>
          },
          ol({ children }) {
            return <ol style={{ paddingLeft: '20px', margin: '8px 0' }}>{children}</ol>
          },
          li({ children }) {
            return <li style={{ margin: '2px 0' }}>{children}</li>
          },

          // --- Blockquote ---
          blockquote({ children }) {
            return (
              <blockquote
                style={{
                  borderLeft: '3px solid var(--log-user)',
                  margin: '12px 0',
                  padding: '4px 16px',
                  backgroundColor: 'var(--bg-elevated)',
                  borderRadius: '0 4px 4px 0',
                }}
              >
                {children}
              </blockquote>
            )
          },

          // --- Paragraph ---
          p({ children }) {
            return <p style={{ margin: '6px 0', lineHeight: '1.7' }}>{children}</p>
          },

          // --- Horizontal rule ---
          hr() {
            return <hr style={{ border: 'none', borderTop: '1px solid var(--border-subtle)', margin: '16px 0' }} />
          },
        }}
      >
        {text}
      </ReactMarkdown>
      {isStreaming && (
        <span
          className="inline-block w-2 h-4 ml-0.5 animate-pulse"
          style={{ backgroundColor: 'var(--cursor-color)', verticalAlign: 'middle' }}
        />
      )}
    </div>
  )
}
