import React, { useState } from 'react';

export default function ChatInput({ onSubmit, sending }) {
  const [prompt, setPrompt] = useState('');

  function handleSend(e) {
    e.preventDefault();
    if (!prompt.trim() || sending) return;
    const current = prompt;
    setPrompt('');
    onSubmit(current);
  }

  return (
    <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: '16px', flexShrink: 0 }}>
      <form onSubmit={handleSend} style={{ display: 'flex', gap: '10px' }}>
        <input
          type="text"
          value={prompt}
          onChange={e => setPrompt(e.target.value)}
          placeholder="Type your command (e.g. Use the PayLookup tool with OrderId 88201 and CustomerId C-1)"
          style={{
            flex: 1,
            padding: '10px 16px',
            border: '1px solid #d1d5db',
            borderRadius: '8px',
            fontSize: '14px',
            fontFamily: 'inherit',
            outline: 'none'
          }}
          disabled={sending}
        />
        <button
          type="submit"
          disabled={sending || !prompt.trim()}
          style={{
            padding: '10px 24px',
            background: (sending || !prompt.trim()) ? '#9ca3af' : '#2563eb',
            color: '#fff',
            border: 'none',
            borderRadius: '8px',
            fontSize: '14px',
            fontWeight: 500,
            cursor: (sending || !prompt.trim()) ? 'not-allowed' : 'pointer',
            fontFamily: 'inherit'
          }}
        >
          {sending ? 'Sending...' : 'Send'}
        </button>
      </form>
      {sending && (
        <p style={{ margin: '8px 0 0', color: '#6b7280', fontSize: '13px' }}>
          OpenCode is processing your request… this may take up to a few minutes.
        </p>
      )}
    </div>
  );
}
