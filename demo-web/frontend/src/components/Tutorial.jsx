import React, { useState, useEffect } from 'react';

function copyToClipboard(text) {
  navigator.clipboard.writeText(text).catch(() => {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  });
}

export default function Tutorial({ onUsePrompt, sending }) {
  const [tutorials, setTutorials] = useState([]);
  const [copied, setCopied] = useState(null);
  const [loadError, setLoadError] = useState(null);

  useEffect(() => {
    fetch('/api/tutorial')
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then(data => setTutorials(Array.isArray(data) ? data : []))
      .catch(err => setLoadError(err.message));
  }, []);

  function handleCopy(step, prompt) {
    copyToClipboard(prompt);
    setCopied(step);
    setTimeout(() => setCopied(prev => (prev === step ? null : prev)), 1500);
  }

  return (
    <div>
      <h2 style={{ fontSize: '17px', fontWeight: 600, color: '#111827', margin: '0 0 6px' }}>
        Tutorial — Article Section 4
      </h2>
      <p style={{ fontSize: '13px', color: '#6b7280', margin: '0 0 16px' }}>
        Click <strong>Use this prompt</strong> to send a step automatically, or <strong>Copy</strong> to copy its text.
      </p>

      {loadError && (
        <p style={{ color: '#b91c1c', fontSize: '13px' }}>Could not load tutorial: {loadError}</p>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
        {tutorials.map(t => (
          <div key={t.step} style={{ padding: '12px', background: '#fff', border: '1px solid #e5e7eb', borderRadius: '10px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
              <div style={{
                width: '26px', height: '26px', borderRadius: '50%', background: '#eff6ff',
                color: '#2563eb', display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontWeight: 600, fontSize: '13px', flexShrink: 0
              }}>
                {t.step}
              </div>
              <div style={{ fontSize: '13px', fontWeight: 600, color: '#111827' }}>{t.tool}</div>
            </div>

            <div style={{ fontSize: '12px', color: '#6b7280', fontFamily: 'monospace', whiteSpace: 'pre-wrap', marginBottom: '10px' }}>
              {t.prompt}
            </div>

            <div style={{ display: 'flex', gap: '6px' }}>
              <button
                onClick={() => onUsePrompt(t.prompt)}
                disabled={sending}
                style={{
                  padding: '6px 12px',
                  fontSize: '12px',
                  fontWeight: 500,
                  background: sending ? '#9ca3af' : '#2563eb',
                  color: '#fff',
                  border: 'none',
                  borderRadius: '6px',
                  cursor: sending ? 'not-allowed' : 'pointer',
                  whiteSpace: 'nowrap'
                }}
              >
                {sending ? 'Working…' : 'Use this prompt'}
              </button>
              <button
                onClick={() => handleCopy(t.step, t.prompt)}
                style={{
                  padding: '6px 12px',
                  fontSize: '12px',
                  fontWeight: 500,
                  background: '#fff',
                  color: '#374151',
                  border: '1px solid #d1d5db',
                  borderRadius: '6px',
                  cursor: 'pointer',
                  whiteSpace: 'nowrap'
                }}
              >
                {copied === t.step ? 'Copied ✓' : 'Copy'}
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
