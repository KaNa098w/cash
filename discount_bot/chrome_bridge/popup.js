let payload = null;
const status = document.getElementById('status');
const save = document.getElementById('save');
const scan = document.getElementById('scan');
const key = document.getElementById('key');
chrome.storage.local.get('bridgeKey').then(data => { key.value = data.bridgeKey || ''; });
key.addEventListener('change', () => chrome.storage.local.set({bridgeKey: key.value.trim()}));
scan.addEventListener('click', async () => {
  save.disabled = true; scan.disabled = true; payload = null;
  document.getElementById('preview').replaceChildren();
  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    const [result] = await chrome.scripting.executeScript({target: {tabId: tab.id}, func: collectDns});
    payload = result.result;
    if (!payload?.products?.length) throw new Error(`Найдено карточек: ${payload?.cards_seen || 0}, но цены не прочитаны. Откройте категорию, дождитесь цен и прокрутите страницу.`);
    status.textContent = `📍 ${payload.city}\nКарточек: ${payload.cards_seen}\nС ценами: ${payload.products.length}`;
    for (const product of payload.products.slice(0, 5)) {
      const item = document.createElement('li');
      item.textContent = `${product.name.slice(0, 100)} — ${product.price_text}`;
      document.getElementById('preview').append(item);
    }
    save.disabled = false;
  } catch (error) { status.textContent = '⚠️ ' + error.message; }
  finally { scan.disabled = false; }
});
save.addEventListener('click', async () => {
  if (!payload) return;
  save.disabled = true;
  try {
    await chrome.storage.local.set({bridgeKey: key.value.trim()});
    const answer = await chrome.runtime.sendMessage({type: 'saveDns', payload});
    if (!answer?.ok) throw new Error(answer?.error || 'Нет ответа приёмника.');
    status.textContent = `✅ Сохранено: ${answer.result.saved}\nСкидок от ${answer.result.threshold}%: ${answer.result.deals}\nВ Telegram ничего не отправлено.`;
  } catch (error) { status.textContent = '⚠️ ' + error.message; save.disabled = false; }
});
