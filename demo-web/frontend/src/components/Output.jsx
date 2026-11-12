import React from 'react';

export default function Output({ data }) {
  if (!data) return null;
  if (data.error) {
    return (
      <section style={{ marginBottom: '30px', padding: '16px', background: '#fee2e2', border: '1px solid #fecaca', borderRadius: '8px' }}>
        <h2>Error</h2>
        <pre>{data.error}</pre>
      </section>
    );
  }
  return (
    <section style={{ marginBottom: '30px', padding: '16px', background: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: '8px' }}>
      <h2>OpenCode Output</h2>
      {data.tool && <p><strong>Tool detected:</strong> {data.tool}</p>}
      {data.args && <p><strong>Arguments:</strong> {JSON.stringify(data.args)}</p>}
      <pre style={{ whiteSpace: 'pre-wrap', background: '#fff', padding: '12px', borderRadius: '4px' }}>{data.output || ''}</pre>
    </section>
  );
}
