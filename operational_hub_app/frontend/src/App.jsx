import { useState, useRef, useCallback, useEffect } from 'react'
import './App.css'
import snowflakeLogo from './assets/snowflake-bug-color-rgb.svg'

const QUESTIONS = [
  { icon: '📊', text: 'What are the top-performing regions by transaction volume this month?' },
  { icon: '💳', text: 'Break down transaction volumes across all regions for this week' },
  { icon: '📉', text: 'Which customers are most likely to churn based on current risk scores?' },
  { icon: '🔍', text: 'Are there any unusual patterns in recent transaction data?' },
  { icon: '🏦', text: 'How does our customer base break down by segment and risk level?' },
  { icon: '📋', text: 'Summarize the latest compliance findings and recommended actions' },
  { icon: '👤', text: 'Show me the high-value customers with declining activity' },
  { icon: '🛡️', text: 'How many fraud alerts were auto-resolved vs escalated to humans?' },
  { icon: '⚠️', text: 'What does the AML risk landscape look like across our reports?' },
  { icon: '📈', text: 'Give me a trend analysis of transaction values over the past week' },
]

const SnowflakeLogo = () => (
  <img src={snowflakeLogo} alt="Snowflake" width="24" height="24" />
)

function formatMetric(value, format) {
  if (value == null) return '\u2014'
  switch (format) {
    case 'currency':
      if (value >= 1e9) return `$${(value / 1e9).toFixed(1)}B`
      if (value >= 1e6) return `$${(value / 1e6).toFixed(0)}M`
      return `$${value.toLocaleString()}`
    case 'percent':
      return `${value.toFixed(1)}%`
    case 'number':
    default:
      if (value >= 1e6) return `${(value / 1e6).toFixed(1)}M`
      if (value >= 1e3) return `${(value / 1e3).toFixed(1)}K`
      return value.toLocaleString()
  }
}

function TrendArrow({ direction }) {
  if (direction === 'up') return <span className="trend trend-up" title="Up vs previous day">&#9650;</span>
  if (direction === 'down') return <span className="trend trend-down" title="Down vs previous day">&#9660;</span>
  return <span className="trend trend-flat" title="No change">&#9644;</span>
}

function Dashboard({ metrics, loading }) {
  const sections = [
    {
      label: "Pipeline Health",
      cards: [
        { key: "pipelines_run_24h", label: "Pipelines Run (24h)", value: metrics?.pipelines_run_24h, format: "number" },
        { key: "pipeline_success_rate", label: "Success Rate", value: metrics?.pipeline_success_rate, format: "percent" },
        { key: "records_processed_24h", label: "Records Processed", value: metrics?.records_processed_24h, format: "number" },
        { key: "avg_pipeline_duration", label: "Avg Duration (s)", value: metrics?.avg_pipeline_duration, format: "number" },
        { key: "ai_generated_pipelines", label: "AI-Generated Runs", value: metrics?.ai_generated_pipelines, format: "number" },
      ],
    },
    {
      label: "Transaction Activity",
      cards: [
        { key: "total_transactions", label: "Total Transactions", value: metrics?.total_transactions, format: "number" },
        { key: "total_value", label: "Transaction Volume", value: metrics?.total_value, format: "currency" },
        { key: "avg_transaction_value", label: "Avg Txn Value", value: metrics?.avg_transaction_value, format: "currency" },
        { key: "daily_pct_change", label: "Daily vs 7d Avg", value: metrics?.daily_pct_change, format: "percent" },
      ],
    },
    {
      label: "Customer Metrics",
      cards: [
        { key: "total_customers", label: "Total Customers", value: metrics?.total_customers, format: "number" },
        { key: "active_accounts", label: "Active Accounts", value: metrics?.active_accounts, format: "number" },
        { key: "customers_at_risk", label: "Customers at Risk", value: metrics?.customers_at_risk, format: "number" },
        { key: "avg_churn_risk", label: "Avg Churn Score", value: metrics?.avg_churn_risk, format: "number" },
      ],
    },
    {
      label: "Detection & Monitoring",
      cards: [
        { key: "anomaly_count", label: "Anomalies Detected", value: metrics?.anomaly_count, format: "number" },
        { key: "fraud_alerts", label: "Fraud Alerts", value: metrics?.fraud_alerts, format: "number" },
        { key: "fraud_auto_resolved", label: "Auto-Resolved", value: metrics?.fraud_auto_resolved, format: "number" },
        { key: "fraud_escalated", label: "Escalated to Human", value: metrics?.fraud_escalated, format: "number" },
      ],
    },
  ]

  const asOf = metrics?.as_of
    ? new Date(metrics.as_of + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
    : null

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h2 className="dashboard-title">Overnight Batch Results</h2>
        {asOf && <span className="dashboard-date">As of {asOf}</span>}
      </div>
      {sections.map((section, si) => (
        <div key={si} className="metric-section">
          <div className="metric-section-label">{section.label}</div>
          <div className="dashboard-grid">
            {section.cards.map((card, ci) => (
              <div key={ci} className="metric-card">
                <div className="metric-value">
                  {loading ? '\u2014' : formatMetric(card.value, card.format)}
                  {!loading && metrics?.trends && <TrendArrow direction={metrics.trends[card.key]} />}
                </div>
                <div className="metric-label">{card.label}</div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function renderMarkdown(text) {
  if (!text) return null
  const lines = text.split('\n')
  const elements = []
  let inList = false
  let listItems = []
  let inTable = false
  let tableRows = []
  let tableHeaders = []

  const flushList = () => {
    if (listItems.length > 0) {
      elements.push(<ul key={`ul-${elements.length}`}>{listItems}</ul>)
      listItems = []
      inList = false
    }
  }

  const flushTable = () => {
    if (tableRows.length > 0) {
      elements.push(
        <table key={`tbl-${elements.length}`}>
          {tableHeaders.length > 0 && (
            <thead><tr>{tableHeaders.map((h, i) => <th key={i}>{h}</th>)}</tr></thead>
          )}
          <tbody>
            {tableRows.map((row, ri) => (
              <tr key={ri}>{row.map((cell, ci) => <td key={ci}>{cell}</td>)}</tr>
            ))}
          </tbody>
        </table>
      )
      tableRows = []
      tableHeaders = []
      inTable = false
    }
  }

  const formatInline = (str) => {
    const parts = []
    let remaining = str
    let key = 0
    while (remaining.length > 0) {
      const boldMatch = remaining.match(/\*\*(.+?)\*\*/)
      const codeMatch = remaining.match(/`(.+?)`/)
      let firstMatch = null
      let matchType = null
      if (boldMatch && (!codeMatch || boldMatch.index <= codeMatch.index)) {
        firstMatch = boldMatch
        matchType = 'bold'
      } else if (codeMatch) {
        firstMatch = codeMatch
        matchType = 'code'
      }
      if (!firstMatch) {
        parts.push(remaining)
        break
      }
      if (firstMatch.index > 0) {
        parts.push(remaining.slice(0, firstMatch.index))
      }
      if (matchType === 'bold') {
        parts.push(<strong key={key++}>{firstMatch[1]}</strong>)
      } else {
        parts.push(<code key={key++}>{firstMatch[1]}</code>)
      }
      remaining = remaining.slice(firstMatch.index + firstMatch[0].length)
    }
    return parts
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const trimmed = line.trim()

    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      const cells = trimmed.slice(1, -1).split('|').map(c => c.trim())
      if (cells.every(c => /^[-:]+$/.test(c))) continue
      if (!inTable) {
        flushList()
        inTable = true
        tableHeaders = cells
      } else {
        tableRows.push(cells)
      }
      continue
    } else if (inTable) {
      flushTable()
    }

    if (!trimmed) {
      flushList()
      continue
    }

    if (trimmed.startsWith('### ')) {
      flushList()
      elements.push(<h3 key={`h3-${i}`}>{formatInline(trimmed.slice(4))}</h3>)
    } else if (trimmed.startsWith('## ')) {
      flushList()
      elements.push(<h2 key={`h2-${i}`}>{formatInline(trimmed.slice(3))}</h2>)
    } else if (trimmed.startsWith('# ')) {
      flushList()
      elements.push(<h1 key={`h1-${i}`}>{formatInline(trimmed.slice(2))}</h1>)
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      inList = true
      listItems.push(<li key={`li-${i}`}>{formatInline(trimmed.slice(2))}</li>)
    } else if (/^\d+\.\s/.test(trimmed)) {
      inList = true
      listItems.push(<li key={`li-${i}`}>{formatInline(trimmed.replace(/^\d+\.\s/, ''))}</li>)
    } else {
      flushList()
      elements.push(<p key={`p-${i}`}>{formatInline(trimmed)}</p>)
    }
  }
  flushList()
  flushTable()
  return elements
}

function App() {
  const [view, setView] = useState('grid')
  const [selectedQuestion, setSelectedQuestion] = useState(null)
  const [reasoning, setReasoning] = useState('')
  const [statusSteps, setStatusSteps] = useState([])
  const [answerText, setAnswerText] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [reasoningOpen, setReasoningOpen] = useState(true)
  const [metrics, setMetrics] = useState(null)
  const [metricsLoading, setMetricsLoading] = useState(true)
  const abortRef = useRef(null)

  useEffect(() => {
    fetch('/api/metrics')
      .then(r => r.json())
      .then(data => { setMetrics(data); setMetricsLoading(false) })
      .catch(() => setMetricsLoading(false))
  }, [])

  const askQuestion = useCallback(async (question) => {
    setSelectedQuestion(question)
    setView('answer')
    setReasoning('')
    setStatusSteps([])
    setAnswerText('')
    setError(null)
    setLoading(true)
    setReasoningOpen(true)

    try {
      abortRef.current = new AbortController()
      const resp = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
        signal: abortRef.current.signal,
      })

      if (!resp.ok) {
        const data = await resp.json().catch(() => ({}))
        throw new Error(data.error || `Request failed (${resp.status})`)
      }

      const reader = resp.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })

        const lines = buffer.split('\n')
        buffer = lines.pop() || ''

        let currentEvent = null
        for (const line of lines) {
          if (line.startsWith('event: ')) {
            currentEvent = line.slice(7).trim()
          } else if (line.startsWith('data: ') && currentEvent) {
            try {
              const data = JSON.parse(line.slice(6))
              if (currentEvent === 'thinking' && data.text) {
                setReasoning(prev => prev + data.text)
              } else if (currentEvent === 'status' && data.message) {
                setStatusSteps(prev => {
                  const last = prev[prev.length - 1]
                  if (last && last.message === data.message) return prev
                  return [...prev, { message: data.message, status: data.status }]
                })
              } else if (currentEvent === 'text' && data.text) {
                setAnswerText(prev => prev + data.text)
                setReasoningOpen(false)
              } else if (currentEvent === 'error' && data.error) {
                setError(data.error)
              } else if (currentEvent === 'done') {
                // stream complete
              }
            } catch {
              // ignore parse errors
            }
            currentEvent = null
          } else if (line.trim() === '') {
            currentEvent = null
          }
        }
      }
    } catch (err) {
      if (err.name !== 'AbortError') {
        setError(err.message)
      }
    } finally {
      setLoading(false)
    }
  }, [])

  const goBack = () => {
    if (abortRef.current) abortRef.current.abort()
    setView('grid')
    setSelectedQuestion(null)
    setReasoning('')
    setStatusSteps([])
    setAnswerText('')
    setError(null)
    setLoading(false)
  }

  return (
    <div className="app">
      <header className="header">
        <div className="header-brand">
          <div className="header-logo"><SnowflakeLogo /></div>
          <div>
            <div className="header-title">FrostBank</div>
          </div>
        </div>
      </header>

      {view === 'grid' ? (
        <main className="main">
          <div className="hero-text">
            <h1>Operational Intelligence <span>Hub</span></h1>
          </div>
          <Dashboard metrics={metrics} loading={metricsLoading} />
          {QUESTIONS.length > 0 && (
            <div className="questions-grid">
              {QUESTIONS.map((q, i) => (
                <div
                  key={i}
                  className="question-card"
                  onClick={() => askQuestion(q.text)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => e.key === 'Enter' && askQuestion(q.text)}
                >
                  <div className="card-icon">{q.icon}</div>
                  <div className="card-text">{q.text}</div>
                </div>
              ))}
            </div>
          )}
        </main>
      ) : (
        <main className="answer-view">
          <button className="back-button" onClick={goBack}>
            &larr; Back to questions
          </button>
          <div className="selected-question">{selectedQuestion}</div>

          {(reasoning || statusSteps.length > 0 || loading) && (
            <div className="reasoning-section">
              <div className="reasoning-header" onClick={() => setReasoningOpen(!reasoningOpen)}>
                <div className="reasoning-label">
                  {loading && !answerText ? <div className="spinner" style={{width:14,height:14,borderWidth:2}} /> : null}
                  Agent Reasoning
                </div>
                <div className="reasoning-toggle">{reasoningOpen ? 'Hide' : 'Show'}</div>
              </div>
              {reasoningOpen && (
                <div className="reasoning-content">
                  {statusSteps.map((s, i) => (
                    <div key={i} className="status-step">
                      <div className={`status-dot${i === statusSteps.length - 1 && loading ? ' active' : ''}`} />
                      {s.message}
                    </div>
                  ))}
                  {reasoning && <div style={{marginTop: statusSteps.length > 0 ? 12 : 0, opacity: 0.8}}>{reasoning}</div>}
                </div>
              )}
            </div>
          )}

          {answerText && (
            <div className="answer-section">
              <div className="answer-label">Answer</div>
              <div className="answer-text">
                {renderMarkdown(answerText)}
              </div>
            </div>
          )}

          {loading && !answerText && (
            <div className="loading-indicator">
              <div className="spinner" />
              Processing your question...
            </div>
          )}

          {error && <div className="error-message">{error}</div>}
        </main>
      )}

      <footer className="footer">
        Powered by <span>Snowflake</span> Cortex Agent &middot; Women in Data 2026
      </footer>
    </div>
  )
}

export default App
