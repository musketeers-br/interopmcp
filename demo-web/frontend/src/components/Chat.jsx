import React, { useState } from 'react';

export default function Chat({ onSubmit }) {
  const [prompt, setPrompt] = useState('');
  const [sending, setSending] = useState(false);

  async function handleSend(e) {
    e.preventDefault();
    if (!prompt.trim()) return;
    setSending(true);
    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt })
      });
      const data = await res.json();
      onSubmit(data);
    } catch (err) {
      onSubmit({ error: err.message });
    } finally {
      setSending(false);
    }
  }

  return (
    <section style={{ marginBottom: '30px', padding: '16px', border: '1px solid #ddd', borderRadius: '8px' }}>
      <h2>Send command to OpenCode</h2>
      <form onSubmit={handleSend} style={{ display: 'flex', gap: '8px' }}>
        <input
          type="text"
          value={prompt}
          onChange={e => setPrompt(e.target.value)}
          placeholder="Type your command (ex: Use the PayLookup tool with OrderId 88201 and CustomerId C-1)"
          style={{ flex: 1, padding: '8px' }}
          disabled={sending}
        />
        <button type="submit" disabled={sending}>{sending ? 'Sending...' : 'Send'}</button>
      </form>
    </section>
  );
}
