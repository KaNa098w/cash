"""Isolated on-demand searches using region-verified browser session snapshots."""
import json
import logging
import time

from price_compare import build_comparison, match_key, search_terms

LOG = logging.getLogger('discounts')
SEARCH_INPUTS = {
    'sulpak': 'input[name="q"]',
    'shop': 'input[name="query"]',
    'technodom': '[data-testid="search-input"]',
    'evrika': 'input[name="search"]',
    'dns': 'input[name="q"]',
    'mechta': 'input[type="search"]',
}


def search_store(browser, store, source, db, root):
    from bot import check_city, parse_products, same_site
    snapshot = root / 'data' / 'sessions' / (store['id'] + '.json')
    # Without a verified region session do not silently use a default city.
    if not snapshot.exists():
        return 'нет доступной сессии Шымкента; магазин пока не проверен'
    context = browser.new_context(storage_state=str(snapshot), locale='ru-RU', timezone_id='Asia/Qyzylorda')
    try:
        page = context.new_page()
        response = page.goto(store['home'], wait_until='domcontentloaded', timeout=25000)
        if response and response.status >= 400:
            return f'сайт отклонил запрос (HTTP {response.status})'
        page.wait_for_timeout(2500)
        check_city(page, store)
        field = page.locator(SEARCH_INPUTS[store['id']]).filter(visible=True).first
        field.fill(search_terms(source['name']), timeout=10000)
        field.press('Enter')
        page.wait_for_timeout(5000)
        if not same_site(page.url, store):
            return 'поиск перенаправил за пределы магазина'
        # Different shops use different search routes; the selected city is
        # checked independently and explicit region paths must remain local.
        if store['id'] == 'technodom' and '/shymkent/' not in page.url:
            return 'не подтверждён регион страницы поиска'
        check_city(page, store)
        products = parse_products(page.content(), page.url, store)
        matched = 0
        expected = match_key(source['name'])
        for product in products:
            if store['id'] in ('evrika', 'technodom', 'sulpak') and '/shymkent' not in product['url']:
                continue
            if product['available'] and match_key(product['name']) == expected:
                db.register_product(store['id'], product)
                db.observe(store['id'], product)
                matched += 1
        LOG.info('Поиск сравнения %s: карточек %s, совпадений %s', store['id'], len(products), matched)
        return 'модель найдена' if matched else 'точная модель с ценой не найдена в результатах поиска'
    finally:
        context.close()


def perform_search(pw, settings, db, product_id, root):
    source_row = db.db.execute('SELECT store,url,name FROM products WHERE id=?', (product_id,)).fetchone()
    if not source_row:
        return '📭 Товар не найден в базе.'
    source = dict(zip(('store', 'url', 'name'), source_row))
    # Refresh the matching identity for entries collected before model-code matching.
    with db.db:
        db.db.execute('UPDATE products SET match_key=? WHERE id=?', (match_key(source['name']), product_id))
    started = int(time.time())
    statuses = {}
    browser = pw.chromium.launch(headless=True)
    try:
        for store in settings['stores']:
            if not store.get('enabled', True):
                statuses[store['id']] = 'магазин отключён'
                continue
            try:
                statuses[store['id']] = search_store(browser, store, source, db, root)
            except Exception as exc:
                LOG.warning('Поиск сравнения %s: %s', store['id'], str(exc)[:250])
                statuses[store['id']] = 'не удалось завершить поиск или подтвердить Шымкент'
    finally:
        browser.close()
    return build_comparison(db.db, product_id, fresh_since=started, search_results=statuses)


def comparison_worker(telegram, settings, stop):
    from bot import Database, ROOT
    from playwright.sync_api import sync_playwright
    db = Database(ROOT / 'data' / 'prices.sqlite3')
    try:
        with db.db:
            db.db.execute("UPDATE comparison_jobs SET state='pending' WHERE state='running'")
        with sync_playwright() as pw:
            while not stop.is_set():
                job = db.db.execute("SELECT id,chat_id,product_id FROM comparison_jobs WHERE state='pending' ORDER BY id LIMIT 1").fetchone()
                if not job:
                    stop.wait(1)
                    continue
                job_id, chat_id, product_id = job
                with db.db:
                    db.db.execute("UPDATE comparison_jobs SET state='running' WHERE id=?", (job_id,))
                try:
                    LOG.info('Поиск сравнения: задание %s', job_id)
                    report = perform_search(pw, settings, db, product_id, ROOT)
                    telegram.call('sendMessage', dict(chat_id=chat_id, text=report, parse_mode='HTML',
                                                     link_preview_options={'is_disabled': True}))
                    with db.db:
                        db.db.execute("UPDATE comparison_jobs SET state='done',error=NULL WHERE id=?", (job_id,))
                except Exception as exc:
                    LOG.error('Поиск сравнения: задание %s: %s', job_id, exc)
                    with db.db:
                        db.db.execute("UPDATE comparison_jobs SET state='failed',error=? WHERE id=?", (str(exc)[:300], job_id))
                    try:
                        telegram.call('sendMessage', {'chat_id': chat_id, 'text': '⚠️ Поиск не завершился. Попробуйте кнопку ещё раз.'})
                    except Exception:
                        LOG.error('Не удалось сообщить об ошибке поиска в личку')
    finally:
        db.db.close()
