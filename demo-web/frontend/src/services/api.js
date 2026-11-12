export async function sendPrompt(prompt) {
  const res = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt })
  });
  return res.json();
}

export async function getTutorial() {
  const res = await fetch('/api/tutorial');
  return res.json();
}
