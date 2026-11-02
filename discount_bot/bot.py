"""Price monitor. All local paths are relative to this file, not the caller's cwd."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import logging
import os
from pathlib import Path
import re
import sqlite3
import time
import threading
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs, urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

from bs4 import BeautifulSoup
from price_history import STORE_NAMES, amount, callback_worker, deal_buttons, product_key
from price_compare import match_key

ROOT = Path(__file__).resolve().parent
LOG = logging.getLogger("discounts")
CATEGORIES = {
    "smartphones": r"смартфон|smartfon|\biphone\b",
    "laptops": r"ноутбук|noutbuk|ноутбуг|\bmacbook\b",
    "headphones": r"наушник|naushnik|құлаққап|гарнитур|\bairpods\b",
    "processors": r"процессор|processor|processory|protsessor|\bintel core\b|\bamd ryzen\b",
    "computers": r"компьютер|моноблок|системный блок|komp.juter|kompyuter|monoblok|sistemny",
    "household": r"бытов|bytov|кухонн|встраива|климатич|kuhonn|vstraiva|klimatich|для приготовления кофе|холодильник|стиральн|пылесос|микроволн|чайник|утюг|кофевар|кофемашин|посудомо|морозиль|варочн|духов|блендер|миксер|мясоруб|тостер|фен\b|кондиционер|обогревател|отпаривател|тепловентилятор|сковород|кастрюл|holodil|stiral|pylesos|posuda",
}


def money(value):
    """Parse one KZT amount; reject ranges, instalments and mixed labels."""
    value = re.sub(r"[\s\u00a0\u202f₸]", "", str(value)).replace("тг", "")
    if not re.fullmatch(r"\d+(?:[.,]\d{1,2})?", value):
        return None
    try:
        result = Decimal(value.replace(",", "."))
        return int(result * 100) if result > 0 else None
    except InvalidOperation:
        return None


def canonical(url):
    p = urlsplit(url)
    return urlunsplit((p.scheme, p.netloc.lower(), p.path, "", ""))


def category(text):
    if re.match(r'\s*(подставка|чехол|сумка|пленка|плёнка|защитное стекло|адаптер|кабель|зарядное устройство)\b', text, re.I):
        return None
    for key, pattern in CATEGORIES.items():
        if re.search(pattern, text, re.I):
            return key
    return None


def unique_price(card, selector):
    values = {money(el.get("content") or el.get_text(" ", strip=True))
              for el in card.select(selector)} if selector else set()
    values.discard(None)
    return next(iter(values)) if len(values) == 1 else None


def product_photo(card, base_url):
    for image in card.select('img'):
        candidates = [image.get(key) for key in ('data-original-src', 'data-src', 'data-original', 'src')]
        srcset = image.get('data-srcset') or image.get('srcset')
        if srcset:
            candidates.append(srcset.split(',')[0].strip().split(' ')[0])
        for candidate in candidates:
            if not candidate or candidate.startswith(('data:', 'blob:')):
                continue
            target = urljoin(base_url, candidate.strip())
            parsed = urlsplit(target)
            if parsed.scheme not in ('http', 'https') or not parsed.hostname:
                continue
            if re.search(r'placeholder|no[-_]?image|loading|\.svg(?:\?|$)', target, re.I):
                continue
            return target
    return None


def parse_products(markup, url, store):
    """Only explicit card price fields; never infer a price from arbitrary numbers."""
    soup = BeautifulSoup(markup, "html.parser")
    result = {}
    for rule in store["rules"]:
        for card in soup.select(rule["card"]):
            cities = {el.get('data-city-title', '').strip().casefold()
                      for el in card.select('[data-city-title]') if el.get('data-city-title', '').strip()}
            if cities and not cities.issubset({'шымкент', 'shymkent'}):
                continue
            link = card if rule['link'] == '__self__' else card.select_one(rule["link"])
            if not link:
                link = card.find_parent('a', href=True)
            if not link or not link.get("href"):
                continue
            target = canonical(urljoin(url, link["href"]))
            if urlsplit(target).hostname != urlsplit(url).hostname:
                continue
            title = (card.get("data-name") or link.get_text(" ", strip=True)
                     or link.get("title") or link.get("aria-label") or "").strip()
            if rule.get('name') and (name_node := card.select_one(rule['name'])):
                title = name_node.get_text(' ', strip=True)
            if not title:
                image = link.select_one("img[alt]")
                title = image.get("alt", "") if image else ""
            kind = category(title + ' ' + urlsplit(target).path)
            price = unique_price(card, rule["price"])
            old = unique_price(card, rule.get("old", ""))
            if not kind or not price:
                continue
            # Do not send offers explicitly marked out of stock.
            unavailable = bool(card.select('[itemprop="availability"][href$="OutOfStock"]'))
            if re.search(r"нет в наличии|нет в продаже|снят с производства", card.get_text(" "), re.I):
                unavailable = True
            result[target] = dict(url=target, name=title, category=kind, price=price,
                                  old=old if old and old > price else None,
                                  available=not unavailable, photo=product_photo(card, url))
            gtin = card.select_one('[itemprop="gtin13"], [itemprop="gtin14"], [itemprop="gtin12"], [itemprop="gtin8"]')
            if gtin:
                result[target]['gtin'] = gtin.get('content') or gtin.get_text(strip=True)
    return list(result.values())


class Database:
    def __init__(self, path):
        self.db = sqlite3.connect(path, timeout=30)
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS observations (
            store TEXT, url TEXT, price INTEGER, old INTEGER, observed INTEGER);
          CREATE INDEX IF NOT EXISTS observations_url ON observations(store,url,observed);
          CREATE TABLE IF NOT EXISTS sent (fingerprint TEXT PRIMARY KEY, sent_at INTEGER);
          CREATE TABLE IF NOT EXISTS outbox (fingerprint TEXT PRIMARY KEY, store TEXT, message TEXT);
          CREATE TABLE IF NOT EXISTS health (store TEXT PRIMARY KEY, checked INTEGER,
            products INTEGER, error TEXT);
          CREATE TABLE IF NOT EXISTS products (id TEXT PRIMARY KEY, store TEXT, url TEXT, name TEXT);
          CREATE TABLE IF NOT EXISTS bot_state (key TEXT PRIMARY KEY, value TEXT);
          CREATE TABLE IF NOT EXISTS comparison_jobs (id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id INTEGER,product_id TEXT,state TEXT,created INTEGER,error TEXT);
        """)
        # Preserve pending notifications created by earlier versions.
        for column in ('photo', 'product_id'):
            if column not in {row[1] for row in self.db.execute('PRAGMA table_info(outbox)')}:
                with self.db:
                    self.db.execute(f'ALTER TABLE outbox ADD COLUMN {column} TEXT')
        columns = {row[1] for row in self.db.execute('PRAGMA table_info(products)')}
        for column, sql_type in [('match_key', 'TEXT'), ('city', 'TEXT'), ('checked', 'INTEGER'), ('available', 'INTEGER')]:
            if column not in columns:
                with self.db:
                    self.db.execute(f'ALTER TABLE products ADD COLUMN {column} {sql_type}')
        self.db.execute('CREATE INDEX IF NOT EXISTS products_matching ON products(match_key,city)')

    def register_product(self, store, product):
        key = product_key(store, product['url'])
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO products (id,store,url,name,match_key,city,checked,available) VALUES (?,?,?,?,?,?,?,?)',
                            (key, store, product['url'], product['name'], match_key(product['name'], product.get('gtin')),
                             'Шымкент', int(time.time()), int(product.get('available', False))))
        return key

    def observe(self, store, product, persist=True):
        previous = self.db.execute(
            'SELECT price FROM observations WHERE store=? AND url=? ORDER BY rowid DESC LIMIT 1',
            (store, product['url'])).fetchone()
        if persist:
            with self.db:
                self.db.execute('INSERT INTO observations VALUES (?,?,?,?,?)',
                                (store, product['url'], product['price'], product['old'], int(time.time())))
        return previous[0] if previous else None

    def health(self, store, count, error=None):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO health VALUES (?,?,?,?)',
                            (store, int(time.time()), count, error))

    def already_sent(self, key):
        return self.db.execute('SELECT 1 FROM sent WHERE fingerprint=?', (key,)).fetchone() is not None

    def mark_sent(self, key):
        with self.db:
            self.db.execute('INSERT OR IGNORE INTO sent VALUES (?,?)', (key, int(time.time())))
            self.db.execute('DELETE FROM outbox WHERE fingerprint=?', (key,))


def offer(store, product, previous, settings):
    baseline = product['old'] if settings['baseline'] == 'store_old_price' else previous
    if not product['available'] or not baseline or baseline <= product['price']:
        return None
    discount = Decimal(baseline - product['price']) * 100 / baseline
    if discount < Decimal(str(settings['min_discount_percent'])):
        return None
    # Same price never re-alerts merely because the retailer increased its crossed-out price.
    identity = f"{store}|{product['url']}|{product['price']}|{settings['baseline']}"
    key = hashlib.sha256(identity.encode()).hexdigest()
    label = 'Старая цена магазина' if settings['baseline'] == 'store_old_price' else 'Предыдущая проверка'
    text = (f"🔥 <b>СКИДКА {discount:.1f}%</b>\n\n"
            f"<b>{html.escape(product['name'][:220])}</b>\n\n"
            f"🏷 {label}: <s>{amount(baseline)}</s>\n"
            f"💰 Сейчас: <b>{amount(product['price'])}</b> <b>(-{discount:.1f}%)</b>\n"
            f"💎 Экономия: <b>{amount(baseline - product['price'])}</b>\n\n"
            f"🏬 {html.escape(STORE_NAMES.get(store, store))} · 📍 Шымкент\n"
            f"ℹ️ Наличие уточняйте в магазине\n"
            f'<a href="{html.escape(product["url"], quote=True)}">🛒 Открыть товар</a>')
    return key, text


def load_env():
    path = ROOT / '.env'
    if path.exists():
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


class TelegramError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(f'Telegram: ошибка {code}')


class Telegram:
    def __init__(self, require_chat=True):
        self.token = os.getenv('TELEGRAM_BOT_TOKEN', '')
        self.chat = os.getenv('TELEGRAM_CHAT_ID', '')
        if not self.token or (require_chat and not self.chat):
            raise ValueError('Заполните TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID в .env')

    def call(self, method, payload):
        request = Request(f'https://api.telegram.org/bot{self.token}/{method}',
                          data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        try:
            with urlopen(request, timeout=35) as response:
                data = json.load(response)
        except HTTPError as exc:
            # Never log the request URL: it contains the bot token.
            raise TelegramError(exc.code) from None
        except (URLError, TimeoutError, OSError):
            raise RuntimeError('Telegram: ошибка сети') from None
        if not data.get('ok'):
            raise TelegramError(data.get('error_code'))
        return data['result']

    def send(self, text, photo=None, reply_markup=None):
        extra = {'reply_markup': reply_markup} if reply_markup else {}
        if photo and len(text) <= 1024:
            try:
                return self.call('sendPhoto', dict(chat_id=self.chat, photo=photo,
                                                 caption=text, parse_mode='HTML', **extra))
            except TelegramError as exc:
                if exc.code != 400:
                    raise
                # Rejected photo URLs fall back to text. Network errors and rate
                # limits stay queued, as delivery may be uncertain.
                LOG.warning('Telegram отклонил фото; отправляется текстовое уведомление')
        return self.call('sendMessage', dict(chat_id=self.chat, text=text, parse_mode='HTML',
                                          link_preview_options={'is_disabled': True}, **extra))


def same_site(url, store):
    parsed = urlsplit(url)
    return parsed.scheme == 'https' and parsed.hostname == urlsplit(store['home']).hostname


def check_city(page, store):
    selector = store.get('city_selector')
    if not selector:
        raise RuntimeError('Не настроен city_selector для подтверждения выбранного города')
    page.locator(selector).first.wait_for(state='attached', timeout=15000)
    values = page.locator(selector).all_text_contents()
    values = [re.sub(r'\s+', ' ', v).strip() for v in values if v.strip()]
    # A city list or all-page text must never serve as proof of selected city.
    if not values or not all(len(v) < 100 and re.search(r'Шымкент|Shymkent', v, re.I) for v in values):
        raise RuntimeError('Не подтверждён Шымкент в элементе выбранного города; выполните setup')


def discover(markup, url, store, pagination=False):
    soup = BeautifulSoup(markup, 'html.parser')
    found = []
    for a in soup.select('a[href], a[data-url]'):
        destination = a.get('data-url') if pagination else a.get('href')
        destination = destination or a.get('href')
        if not destination:
            continue
        target = urljoin(url, destination).split('#')[0]
        if not same_site(target, store):
            continue
        if store.get('allowed_path') and not re.search(store['allowed_path'], urlsplit(target).path):
            continue
        if pagination:
            current_query, next_query = parse_qs(urlsplit(url).query), parse_qs(urlsplit(target).query)
            numeric_next = any(key in next_query and next_query[key][0].isdigit()
                               and int(next_query[key][0]) == int(current_query.get(key, ['1'])[0]) + 1
                               for key in ('page', 'PAGEN_1')
                               if current_query.get(key, ['1'])[0].isdigit())
            is_next = (a.get('rel') and 'next' in a['rel']) or re.search(
                    r'следующ|далее|next', a.get('aria-label', '') + ' ' + a.get_text(' ', strip=True), re.I) or numeric_next
            if is_next and urlsplit(target).path == urlsplit(url).path:
                found.append(target)
        elif re.search(store['category_path'], urlsplit(target).path) and category(
                a.get_text(' ', strip=True) + ' ' + urlsplit(target).path):
            found.append(canonical(target))
    return list(dict.fromkeys(found))


def collect_pages(context, store, settings):
    page = context.new_page()
    seen, products = set(), {}
    queue = list(store.get('urls') or [store['home']])
    scheduled = set(queue)
    page_limit = settings.get('max_pages_per_store')
    try:
        while queue and (not page_limit or len(seen) < page_limit):
            url = queue.pop(0)
            if url in seen:
                continue
            if not same_site(url, store):
                raise RuntimeError('URL вне домена магазина')
            if store.get('allowed_path') and not re.search(store['allowed_path'], urlsplit(url).path):
                raise RuntimeError('Страница другого региона или неподдерживаемый путь каталога')
            seen.add(url)
            LOG.info('%s: страница %s — %s', store['id'], len(seen), url)
            response = page.goto(url, wait_until='domcontentloaded', timeout=60000)
            if response and response.status >= 400:
                raise RuntimeError(f'Магазин вернул HTTP {response.status}; проверка остановлена')
            page.wait_for_timeout(settings['render_wait_ms'])
            if not same_site(page.url, store) or (store.get('allowed_path') and not re.search(
                    store['allowed_path'], urlsplit(page.url).path)):
                raise RuntimeError(f'Магазин перенаправил на неподдерживаемую страницу или другой регион: {page.url}')
            check_city(page, store)
            session_dir = ROOT / 'data' / 'sessions'
            session_dir.mkdir(exist_ok=True)
            snapshot_path = session_dir / (store['id'] + '.tmp.json')
            context.storage_state(path=str(snapshot_path))
            if snapshot_path.exists():
                snapshot_path.replace(session_dir / (store['id'] + '.json'))
            if url.rstrip('/') == store['home'].rstrip('/') and store.get('catalog_open_selector'):
                page.locator(store['catalog_open_selector']).first.click()
                page.wait_for_timeout(settings['render_wait_ms'])
                check_city(page, store)
            # Load cards rendered only after scrolling.
            for _ in range(settings['scroll_steps']):
                page.evaluate('window.scrollBy(0, window.innerHeight)')
                page.wait_for_timeout(350)
            markup = page.content()
            page_products = parse_products(markup, page.url, store)
            for product in page_products:
                products[product['url']] = product
            LOG.info('%s: на странице найдено товаров %s', store['id'], len(page_products))
            yield page_products
            links = discover(markup, page.url, store) + discover(markup, page.url, store, pagination=True)
            for target in links:
                if target not in scheduled:
                    scheduled.add(target)
                    queue.append(target)
            page.wait_for_timeout(settings['request_delay_ms'])
        if queue:
            LOG.warning('%s: достигнут лимит страниц (%s); каталог проверен частично', store['id'], len(seen))
        else:
            LOG.info('%s: обход найденных страниц завершён, страниц %s', store['id'], len(seen))
        if not products:
            raise RuntimeError('Найдено 0 товаров: проверьте URLs, город и CSS-правила магазина')
    finally:
        page.close()


def collect(context, store, settings, on_products=None):
    products = {}
    for batch in collect_pages(context, store, settings):
        for product in batch:
            products[product['url']] = product
        if on_products:
            on_products(batch)
    return list(products.values())


def browser_context(pw, store, headed=False):
    profile = ROOT / 'data' / 'profiles' / store['id']
    return pw.chromium.launch_persistent_context(str(profile), headless=not headed,
                                                locale='ru-RU', timezone_id='Asia/Qyzylorda')


def store_batches(pw, store, settings):
    LOG.info('%s: начало проверки', store['id'])
    with browser_context(pw, store, settings.get('headed', False)) as context:
        yield from collect_pages(context, store, settings)


def flush_outbox(settings, db, telegram, selected=None):
    pending = db.db.execute('SELECT fingerprint,store,message,photo,product_id FROM outbox').fetchall()
    for key, store_id, message, photo, product_id in pending:
        if selected and selected != store_id:
            continue
        if not any(s['id'] == store_id and s.get('enabled', True) for s in settings['stores']):
            continue
        displayed_discount = re.search(r'(?:СКИДКА|Скидка)\s+(\d+(?:[.,]\d+)?)%', message)
        if displayed_discount and Decimal(displayed_discount[1].replace(',', '.')) < Decimal(str(settings['min_discount_percent'])):
            LOG.info('%s: предложение в очереди ниже нового порога, пропущено', store_id)
            continue
        try:
            product = db.db.execute('SELECT url FROM products WHERE id=?', (product_id,)).fetchone()
            buttons = deal_buttons(product_id, product[0], getattr(telegram, 'username', None)) if product else None
            result = telegram.send(message, photo=photo, reply_markup=buttons)
            db.mark_sent(key)
            LOG.info('%s: уведомление отправлено, message_id=%s', store_id, result.get('message_id'))
            time.sleep(1.1)
        except Exception as exc:
            LOG.error('Telegram: %s; уведомление сохранено для повторной отправки', exc)
            return 1
    return 0


def run_cycle(pw, settings, db, telegram, dry_run=False, selected=None):
    failures = 0
    delivery_failed = False
    if not dry_run:
        delivery_failed = bool(flush_outbox(settings, db, telegram, selected))
        failures += int(delivery_failed)
    active = [dict(store=store, stream=store_batches(pw, store, settings), processed=set(), urls=set(), count=0)
              for store in settings['stores']
              if store.get('enabled', True) and (not selected or selected == store['id'])]
    try:
        while active:
            for state in active[:]:
                store = state['store']
                try:
                    # Exactly one page per store per round. A large catalogue
                    # cannot prevent other stores from producing notifications.
                    products = next(state['stream'])
                    for product in products:
                        identity = (product['url'], product['price'])
                        if identity in state['processed']:
                            continue
                        state['processed'].add(identity)
                        state['urls'].add(product['url'])
                        product_id = db.register_product(store['id'], product) if not dry_run else None
                        previous = db.observe(store['id'], product, persist=not dry_run)
                        notification = offer(store['id'], product, previous, settings)
                        if not notification or db.already_sent(notification[0]):
                            continue
                        if dry_run:
                            LOG.info('ПРЕДПРОСМОТР %s', notification[1])
                        else:
                            with db.db:
                                db.db.execute('INSERT OR IGNORE INTO outbox (fingerprint,store,message,photo,product_id) VALUES (?,?,?,?,?)',
                                              (notification[0], store['id'], notification[1], product.get('photo'), product_id))
                        state['count'] += 1
                    if not dry_run and not delivery_failed:
                        delivery_failed = bool(flush_outbox(settings, db, telegram, selected))
                        failures += int(delivery_failed)
                    db.health(store['id'], len(state['urls']))
                except StopIteration:
                    active.remove(state)
                    db.health(store['id'], len(state['urls']))
                    LOG.info('%s: товаров %s, уведомлений %s', store['id'], len(state['urls']), state['count'])
                except Exception as exc:
                    failures += 1
                    active.remove(state)
                    state['stream'].close()
                    error = str(exc)[:700]
                    db.health(store['id'], len(state['urls']), error)
                    LOG.error('%s: %s', store['id'], error)
    finally:
        for state in active:
            state['stream'].close()
    return failures


def main():
    parser = argparse.ArgumentParser(description='Мониторинг скидок, Шымкент')
    parser.add_argument('command', choices=['run', 'check', 'setup', 'status', 'chat-id', 'test-message'])
    parser.add_argument('--store')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    load_env()
    settings = json.loads((ROOT / 'settings.json').read_text(encoding='utf-8-sig'))
    if settings['baseline'] not in ('store_old_price', 'previous_price'):
        parser.error('baseline: store_old_price или previous_price')
    if not 0 < settings['min_discount_percent'] < 100 or settings['interval_minutes'] < 1:
        parser.error('Неверный порог скидки или интервал')
    if args.store and args.store not in {s['id'] for s in settings['stores']}:
        parser.error('Неизвестный магазин')
    (ROOT / 'data').mkdir(exist_ok=True)
    db = Database(ROOT / 'data' / 'prices.sqlite3')
    if args.command == 'status':
        for row in db.db.execute('SELECT store,datetime(checked,\'unixepoch\'),products,error FROM health'):
            print(row)
        return 0
    if args.command == 'chat-id':
        for update in Telegram(False).call('getUpdates', {'timeout': 0}):
            message = update.get('message') or update.get('channel_post') or {}
            chat = message.get('chat')
            if chat:
                print('CHAT_ID:', chat['id'], 'Название:', chat.get('title') or chat.get('first_name', ''))
        return 0
    if args.command == 'test-message':
        Telegram().send(f"Проверка бота скидок. Город: Шымкент. Порог: {settings['min_discount_percent']}%.")
        return 0
    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        if args.command == 'setup':
            if not args.store:
                parser.error('Укажите --store sulpak|shop|mechta|technodom|evrika|dns')
            store = next(s for s in settings['stores'] if s['id'] == args.store)
            with browser_context(pw, store, True) as context:
                page = context.new_page()
                page.goto(store['home'], wait_until='domcontentloaded', timeout=60000)
                input('Выберите Шымкент на сайте, закройте список городов, затем нажмите Enter здесь: ')
                check_city(page, store)
                print('Шымкент подтверждён. Профиль браузера сохранён.')
            return 0
        dry_run = args.dry_run or args.command == 'check'
        telegram = None if dry_run else Telegram()
        LOG.info('Настройки: только Шымкент, скидки от %s%%, пауза %s мин, анализ в личном чате',
                 settings['min_discount_percent'], settings['interval_minutes'])
        stop = threading.Event()
        if telegram:
            telegram.username = telegram.call('getMe', {})['username']
            if telegram.call('getWebhookInfo', {}).get('url'):
                raise ValueError('У бота установлен webhook. Для кнопок нужен getUpdates; отключите webhook перед запуском.')
            threading.Thread(target=callback_worker, args=(telegram, ROOT / 'data' / 'prices.sqlite3', stop),
                             daemon=True, name='telegram-buttons').start()
            from live_compare import comparison_worker
            threading.Thread(target=comparison_worker, args=(telegram, settings, stop),
                             daemon=True, name='live-comparison').start()
        try:
            while True:
                failures = run_cycle(pw, settings, db, telegram, dry_run, args.store)
                if args.command == 'check':
                    return 1 if failures else 0
                LOG.info('Обход завершён. Пауза %s мин. Ошибок: %s', settings['interval_minutes'], failures)
                stop.wait(settings['interval_minutes'] * 60)
        finally:
            stop.set()


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print('\nБот остановлен.')
    except Exception as exc:
        LOG.error('%s', exc)
        raise SystemExit(1)
