import React from 'react';
import Message from './Message.jsx';

export default function MessageList({ messages, sending, irisWebBase }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
      {messages.map(msg => (
        <Message key={msg.id} {...msg} irisWebBase={irisWebBase} />
      ))}

      {sending && (
        <div data-testid="msg-typing" style={{ display: 'flex', gap: '12px', alignItems: 'flex-end' }}>
          <div style={{ width: '32px', height: '32px', borderRadius: '50%', background: '#e5e7eb', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '16px', flexShrink: 0 }}>
            🤖
          </div>
          <div style={{ padding: '14px 16px', borderRadius: '18px 18px 18px 4px', background: '#f3f4f6', display: 'flex', gap: '4px', alignItems: 'center' }}>
            <span className="typing-dot" />
            <span className="typing-dot" />
            <span className="typing-dot" />
          </div>
        </div>
      )}
    </div>
  );
}
