chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || sender.tab || message.type !== 'saveDns') return false;
  (async () => {
    const {bridgeKey} = await chrome.storage.local.get('bridgeKey');
    if (!bridgeKey) throw new Error('Вставьте ключ подключения из локального файла.');
    const response = await fetch('http://127.0.0.1:8765/ingest', {
      method: 'POST', headers: {'Content-Type': 'application/json', 'X-Bridge-Key': bridgeKey},
      body: JSON.stringify(message.payload), signal: AbortSignal.timeout(15000)
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Приёмник отклонил данные.');
    return result;
  })().then(result => respond({ok: true, result})).catch(error => respond({ok: false, error: error.message}));
  return true;
});
