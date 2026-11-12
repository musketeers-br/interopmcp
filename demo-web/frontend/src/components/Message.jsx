import React from 'react';
import MarkdownRenderer from './MarkdownRenderer.jsx';
import { IRIS_PATHS, irisUrl } from './IrisLinks.jsx';

function formatTime(iso) {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch {
    return '';
  }
}

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

function buildPortalLinks({ irisWebBase, invocationId, approvalId }) {
  if (!irisWebBase) return [];

  const links = [];
  if (invocationId) {
    links.push({
      label: 'Message Viewer',
      url: irisUrl(irisWebBase, IRIS_PATHS.messageViewer),
      icon: '📨',
      title: `Invocation ID: ${invocationId}`
    });
  }
  if (approvalId) {
    links.push({
      label: 'Approval in User Portal',
      url: irisUrl(irisWebBase, IRIS_PATHS.userPortal),
      icon: '🔐',
      title: `Approval ID: ${approvalId}`
    });
  }
  return links;
}

export default function Message({ role, content, tool, args, error, timestamp, invocationId, approvalId, irisWebBase }) {
  const isUser = role === 'user';
  const time = formatTime(timestamp);
  const text = typeof content === 'string' ? content : String(content ?? '');

  const portalLinks = !isUser ? buildPortalLinks({ irisWebBase, invocationId, approvalId }) : [];

  return (
    <div
      data-testid={isUser ? 'msg-user' : 'msg-assistant'}
      style={{ display: 'flex', flexDirection: isUser ? 'row-reverse' : 'row', gap: '12px', alignItems: 'flex-end' }}
    >
      {!isUser && (
        <div style={{ width: '32px', height: '32px', borderRadius: '50%', background: '#e5e7eb', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '16px', flexShrink: 0 }}>
          🤖
        </div>
      )}

      <div style={{ maxWidth: '80%', display: 'flex', flexDirection: 'column' }}>
        <div style={{
          padding: '10px 14px',
          borderRadius: isUser ? '18px 18px 4px 18px' : '18px 18px 18px 4px',
          background: isUser ? '#2563eb' : (error ? '#fef2f2' : '#f3f4f6'),
          color: isUser ? '#fff' : (error ? '#b91c1c' : '#111827'),
          fontSize: '14px',
          lineHeight: 1.5,
          wordBreak: 'break-word',
          marginBottom: '4px'
        }}>
          {isUser ? text : <MarkdownRenderer content={text} />}
        </div>

        {!isUser && tool && (
          <div style={{
            fontSize: '11px',
            color: '#6b7280',
            marginBottom: '4px',
            background: '#eff6ff',
            padding: '6px 10px',
            borderRadius: '6px',
            border: '1px solid #dbeafe'
          }}>
            <strong style={{ color: '#1d4ed8' }}>Tool:</strong> {tool}
            {args && Object.keys(args).length > 0 && (
              <span style={{ marginLeft: '10px', fontFamily: 'monospace', fontSize: '10px', color: '#64748b' }}>
                {JSON.stringify(args)}
              </span>
            )}
          </div>
        )}

        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', justifyContent: isUser ? 'flex-end' : 'flex-start', flexWrap: 'wrap' }}>
          {!isUser && text && (
            <button
              onClick={() => copyToClipboard(text)}
              title="Copy response"
              style={{
                padding: '2px 8px',
                fontSize: '11px',
                background: '#fff',
                border: '1px solid #d1d5db',
                color: '#374151',
                borderRadius: '5px',
                cursor: 'pointer'
              }}
            >
              Copy
            </button>
          )}

          {portalLinks.map((link, i) => (
            <a
              key={i}
              data-testid="msg-iris-link"
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              title={link.title || link.label}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '5px',
                padding: '4px 10px',
                fontSize: '12px',
                fontWeight: 500,
                background: '#eff6ff',
                border: '1px solid #bfdbfe',
                color: '#1d4ed8',
                borderRadius: '6px',
                textDecoration: 'none',
                cursor: 'pointer'
              }}
            >
              {link.icon} {link.label}
            </a>
          ))}

          <span style={{ fontSize: '11px', color: '#9ca3af' }}>{time}</span>
        </div>
      </div>

      {isUser && (
        <div style={{ width: '32px', height: '32px', borderRadius: '50%', background: '#dbeafe', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '16px', flexShrink: 0 }}>
          👤
        </div>
      )}
    </div>
  );
}