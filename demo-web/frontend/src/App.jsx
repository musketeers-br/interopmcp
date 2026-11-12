import React, { useState, useEffect, useRef } from 'react';
import ChatInput from './components/ChatInput.jsx';
import MessageList from './components/MessageList.jsx';
import Tutorial from './components/Tutorial.jsx';
import IrisLinks from './components/IrisLinks.jsx';

export default function App() {
  const [history, setHistory] = useState([]);
  const [sending, setSending] = useState(false);
  const [irisWebBase, setIrisWebBase] = useState('');
  const bottomRef = useRef(null);

  useEffect(() => {
    fetch('/api/config')
      .then(r => r.json())
      .then(data => setIrisWebBase(data.irisWebBase || ''))
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (bottomRef.current && typeof bottomRef.current.scrollIntoView === 'function') {
      bottomRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }, [history, sending]);

  async function sendMessage(rawPrompt) {
    const prompt = typeof rawPrompt === 'string' ? rawPrompt : String(rawPrompt ?? '');
    if (!prompt.trim() || sending) return;

    setSending(true);
    const userMsg = {
      id: `u-${Date.now()}`,
      role: 'user',
      content: prompt,
      timestamp: new Date().toISOString()
    };
    setHistory(prev => [...prev, userMsg]);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt })
      });

      let data = null;
      try { data = await res.json(); } catch { data = null; }

      if (!res.ok || !data) {
        throw new Error(data && data.error ? data.error : `Request failed (HTTP ${res.status})`);
      }

      const assistantMsg = {
        id: `a-${Date.now()}`,
        role: 'assistant',
        content: data.error
          ? `Error: ${String(data.error)}`
          : (typeof data.output === 'string' ? data.output : JSON.stringify(data.output, null, 2)),
        tool: data.tool,
        args: data.args,
        error: data.error,
        invocationId: data.invocationId,
        approvalId: data.approvalId,
        timestamp: new Date().toISOString()
      };
      setHistory(prev => [...prev, assistantMsg]);
    } catch (err) {
      setHistory(prev => [...prev, {
        id: `e-${Date.now()}`,
        role: 'assistant',
        content: `Error: ${err && err.message ? err.message : String(err)}`,
        error: true,
        timestamp: new Date().toISOString()
      }]);
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="app">
      <header style={{ marginBottom: '20px', borderBottom: '1px solid #e5e7eb', paddingBottom: '16px', flexShrink: 0 }}>
        <h1 style={{ margin: 0, fontSize: '24px', fontWeight: 600, color: '#111827' }}>InteropMCP Demo</h1>
        <p style={{ margin: '6px 0 0', color: '#6b7280', fontSize: '14px' }}>
          Send commands to OpenCode. Use the tutorial shortcuts to walk through section 4 of the article.
        </p>
        <IrisLinks irisWebBase={irisWebBase} />
      </header>

      <div className="app-body">
        <aside className="tutorial-pane">
          <Tutorial onUsePrompt={sendMessage} sending={sending} />
        </aside>

        <section className="chat-pane">
          <main className="chat-scroll">
            <MessageList messages={history} sending={sending} irisWebBase={irisWebBase} />
            {history.length === 0 && !sending && (
              <div style={{ padding: '40px 20px', textAlign: 'center', color: '#9ca3af', fontSize: '14px' }}>
                No messages yet. Type a command below or click a tutorial step to get started.
              </div>
            )}
            <div ref={bottomRef} />
          </main>

          <ChatInput onSubmit={sendMessage} sending={sending} />
        </section>
      </div>
    </div>
  );
}