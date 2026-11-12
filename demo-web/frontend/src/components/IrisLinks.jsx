import React from 'react';

// Paths inside the IRIS web server (csp app "irisapp").
export const IRIS_PATHS = {
  messageViewer: '/csp/irisapp/EnsPortal.MessageViewer.zen',
  userPortal: '/csp/irisapp/_DeepSee.UserPortal.Workflow.zen'
};

// Resolve the IRIS base coming from the backend (/api/config -> IRIS_WEB_BASE).
// Accepts either an absolute URL (http://host:port) or an app-relative prefix (/iris).
export function irisUrl(base, path) {
  if (!base) return '';
  const clean = String(base).replace(/\/+$/, '');
  if (/^https?:\/\//i.test(clean)) return `${clean}${path}`;
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  return `${origin}${clean.startsWith('/') ? clean : `/${clean}`}${path}`;
}

const linkStyle = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: '6px',
  padding: '7px 14px',
  fontSize: '13px',
  fontWeight: 500,
  background: '#eff6ff',
  border: '1px solid #bfdbfe',
  color: '#1d4ed8',
  borderRadius: '8px',
  textDecoration: 'none',
  cursor: 'pointer'
};

// Always-visible links to the IRIS web portal pages.
export default function IrisLinks({ irisWebBase }) {
  if (!irisWebBase) return null;

  const links = [
    {
      key: 'message-viewer',
      label: 'Message Viewer',
      icon: '📨',
      url: irisUrl(irisWebBase, IRIS_PATHS.messageViewer)
    },
    {
      key: 'user-portal',
      label: 'User Portal',
      icon: '🔐',
      url: irisUrl(irisWebBase, IRIS_PATHS.userPortal)
    }
  ];

  return (
    <div
      data-testid="iris-links"
      style={{ display: 'flex', gap: '10px', marginTop: '12px', flexWrap: 'wrap' }}
    >
      {links.map(link => (
        <a
          key={link.key}
          data-testid={`iris-link-${link.key}`}
          href={link.url}
          target="_blank"
          rel="noopener noreferrer"
          style={linkStyle}
        >
          <span aria-hidden="true">{link.icon}</span>
          {link.label}
        </a>
      ))}
    </div>
  );
}
