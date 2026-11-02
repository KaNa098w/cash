// Executed only after the user clicks the extension on an allowed DNS tab.
function collectDns() {
  if (location.protocol !== 'https:' || location.hostname !== 'www.dns-shop.kz') {
    throw new Error('Откройте каталог товаров на https://www.dns-shop.kz/');
  }
  const visible = el => !!el && el.getClientRects().length > 0;
  const text = el => el?.textContent?.replace(/\s+/g, ' ').trim() || '';
  const cityNodes = [...document.querySelectorAll('[data-city-select-label] [data-analytics-city-id], .city-select__text')].filter(visible);
  const cities = [...new Set(cityNodes.map(text).filter(Boolean))];
  const city = cities.length === 1 ? cities[0] : '';
  if (!/^Шымкент$/i.test(city)) {
    throw new Error(`Выберите Шымкент в шапке DNS. Сейчас: ${city || 'город не подтверждён'}`);
  }
  const price = (card, selectors, removeOld = false) => {
    for (const selector of selectors) {
      const el = card.querySelector(selector);
      if (!el || !visible(el)) continue;
      const clone = el.cloneNode(true);
      if (removeOld) clone.querySelectorAll('.product-buy__prev, [class*="old"], [class*="credit"], [class*="installment"]').forEach(e => e.remove());
      const value = text(clone);
      if (/^[\d\s\u00a0\u202f.,]+(?:₸|тг)?$/.test(value)) return value;
    }
    return '';
  };
  const cards = [...document.querySelectorAll('.catalog-product')];
  const products = [];
  for (const card of cards.slice(0, 200)) {
    const link = card.querySelector('a.catalog-product__name, a[href*="/product/"]');
    if (!link) continue;
    const target = new URL(link.href, location.href);
    if (target.hostname !== location.hostname || !target.pathname.startsWith('/product/')) continue;
    const priceText = price(card, ['.product-buy__price-current', '.product-buy__price'], true);
    if (!priceText) continue;
    const image = card.querySelector('img');
    let photo = image?.getAttribute('data-src') || image?.currentSrc || image?.src || '';
    if (photo.startsWith('data:')) photo = '';
    const unavailable = /нет в наличии|нет в продаже|снят с производства/i.test(text(card));
    products.push({
      name: text(link).slice(0, 500), url: target.href,
      price_text: priceText,
      old_price_text: price(card, ['.product-buy__prev', '.product-buy__price-old']),
      available: !unavailable, photo
    });
  }
  return {store: 'dns', city, source_url: location.href, captured_at: Math.floor(Date.now() / 1000),
    cards_seen: cards.length, products};
}
