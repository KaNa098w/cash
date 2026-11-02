"""Offline browser test: all DNS URLs below are intercepted with a local fixture."""
from playwright.sync_api import sync_playwright
from bot import ROOT


fixture = '''<!doctype html><html><head><meta charset="utf-8"></head><body>
<div data-city-select-label><span data-analytics-city-id="city">Шымкент</span></div>
<div class="catalog-product">
<a class="catalog-product__name" href="/product/test/">Смартфон Test 256GB</a>
<div class="product-buy__price">65 000 ₸ <span class="product-buy__prev">100 000 ₸</span></div>
<img src="data:image/gif;base64,x"><button>Купить</button></div>
</body></html>'''
with sync_playwright() as pw:
    browser = pw.chromium.launch()
    page = browser.new_page()
    page.route('**/*', lambda route: route.fulfill(status=200, content_type='text/html', body=fixture))
    page.goto('https://www.dns-shop.kz/catalog/test/')
    page.add_script_tag(path=str(ROOT / 'chrome_bridge' / 'extract.js'))
    result = page.evaluate('collectDns()')
    assert result['city'] == 'Шымкент'
    assert len(result['products']) == 1
    assert result['products'][0]['price_text'] == '65 000 ₸'
    assert result['products'][0]['old_price_text'] == '100 000 ₸'
    page.locator('[data-analytics-city-id]').evaluate("el => el.textContent = 'Астана'")
    try:
        page.evaluate('collectDns()')
    except Exception as exc:
        assert 'Выберите Шымкент' in str(exc)
    else:
        raise AssertionError('Другой город должен быть отклонён')
    browser.close()
print('Проверка DOM: цена, старая цена и блокировка другого города — OK. Сайты не запрашивались.')
