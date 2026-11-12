import React, { useEffect, useRef } from 'react';
import { marked } from 'marked';
import DOMPurify from 'dompurify';

export default function MarkdownRenderer({ content }) {
  const divRef = useRef(null);

  useEffect(() => {
    if (!divRef.current) return;

    // Configure marked
    marked.setOptions({
      breaks: true,
      gfm: true,
      headerIds: false,
      mangle: false
    });

    // Parse markdown to HTML
    const rawHtml = marked.parse(content || '');

    // Sanitize HTML
    const cleanHtml = DOMPurify.sanitize(rawHtml, {
      ADD_TAGS: ['details', 'summary'],
      ADD_ATTR: ['open']
    });

    divRef.current.innerHTML = cleanHtml;

    // Style code blocks and tables after render
    const codeBlocks = divRef.current.querySelectorAll('pre code');
    codeBlocks.forEach(block => {
      block.style.whiteSpace = 'pre-wrap';
      block.style.wordBreak = 'break-word';
    });

    const tables = divRef.current.querySelectorAll('table');
    tables.forEach(table => {
      table.style.borderCollapse = 'collapse';
      table.style.width = '100%';
      table.style.margin = '8px 0';
      table.style.fontSize = '13px';

      const cells = table.querySelectorAll('th, td');
      cells.forEach(cell => {
        cell.style.border = '1px solid #e5e7eb';
        cell.style.padding = '6px 10px';
        cell.style.textAlign = 'left';
      });

      const headers = table.querySelectorAll('th');
      headers.forEach(h => {
        h.style.backgroundColor = '#f9fafb';
        h.style.fontWeight = '600';
      });
    });

    // Style blockquotes
    const quotes = divRef.current.querySelectorAll('blockquote');
    quotes.forEach(q => {
      q.style.borderLeft = '3px solid #2563eb';
      q.style.paddingLeft = '12px';
      q.style.margin = '8px 0';
      q.style.color = '#4b5563';
      q.style.fontStyle = 'italic';
    });

    // Style inline code
    const inlineCodes = divRef.current.querySelectorAll(':not(pre) > code');
    inlineCodes.forEach(code => {
      code.style.backgroundColor = '#f3f4f6';
      code.style.padding = '2px 6px';
      code.style.borderRadius = '4px';
      code.style.fontSize = '0.9em';
      code.style.fontFamily = 'monospace';
    });
  }, [content]);

  return <div ref={divRef} style={{ lineHeight: 1.6 }} />;
}