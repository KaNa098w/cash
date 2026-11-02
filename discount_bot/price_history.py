"""Telegram presentation and analysis of observed prices, without invented history."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import hashlib
import html
import logging
import re
import sqlite3
import time
from price_compare import build_comparison

LOCAL_TZ = timezone(timedelta(hours=5))
STORE_NAMES = {'sulpak': 'Sulpak', 'shop': 'Белый Ветер', 'mechta': 'Мечта',
               'technodom': 'Technodom', 'evrika': 'Evrika', 'dns': 'DNS'}
LOG = logging.getLogger('discounts')


def amount(value):
    return f'{Decimal(str(value)) / 100:,.2f}'.replace(',', ' ').removesuffix('.00') + ' ₸'


def product_key(store, url):
    return hashlib.sha256(f'{store}|{url}'.encode()).hexdigest()[:24]


def deal_buttons(product_id, url, bot_username=None):
    analysis = {'text': '📊 Полный анализ', 'callback_data': f'analysis:{product_id}'}
    if isinstance(bot_username, str) and bot_username:
        analysis = {'text': '📊 Полный анализ',
                    'url': f'https://t.me/{bot_username}?start=analysis_{product_id}'}
    compare = {'text': '🏪 Цены в других магазинах', 'callback_data': f'compare:{product_id}'}
    if isinstance(bot_username, str) and bot_username:
        compare = {'text': '🏪 Цены в других магазинах',
                   'url': f'https://t.me/{bot_username}?start=compare_{product_id}'}
    return {'inline_keyboard': [
        [analysis],
        [{'text': '🛒 Открыть в магазине', 'url': url}],
        [compare],
    ]}


def build_analysis(connection, product_id, now=None):
    now = int(time.time()) if now is None else now
    product = connection.execute('SELECT store,url,name FROM products WHERE id=?', (product_id,)).fetchone()
    if not product:
        return '📭 <b>История пока недоступна</b>\nТовар ещё не найден в базе наблюдений.'
    store, url, name = product
    cutoff = now - 365 * 86400
    rows = connection.execute(
        'SELECT observed,price FROM observations WHERE store=? AND url=? AND observed>=? AND observed<=? '
        'ORDER BY observed,rowid', (store, url, cutoff, now)).fetchall()
    header = (f'📊 <b>ПОЛНЫЙ АНАЛИЗ ЦЕНЫ</b>\n\n<b>{html.escape(name[:300])}</b>\n'
              f'🏬 {html.escape(STORE_NAMES.get(store, store))} · 📍 Шымкент\n'
              '🗓 Период анализа: последние 365 дней\n')
    if not rows:
        return header + '\n📭 За этот период сохранённых цен нет. История появится после проверки товара.'
    first_time, first_price = rows[0]
    last_time, last_price = rows[-1]
    minimum = min(price for _, price in rows)
    maximum = max(price for _, price in rows)
    date = lambda ts: datetime.fromtimestamp(ts, LOCAL_TZ).strftime('%d.%m.%Y')
    days = len({date(ts) for ts, _ in rows})
    change = Decimal(last_price - first_price) * 100 / first_price
    verdict = ('🏆 <b>Последняя цена — минимум за доступный период!</b>' if last_price == minimum
               else f'🔎 Последняя цена выше наблюдаемого минимума на {amount(last_price - minimum)}.')
    if len(rows) == 1:
        verdict = '🌱 Пока только одна проверка. Для сравнения цен нужно накопить историю.'
    monthly = {}
    for ts, price in rows:
        month = datetime.fromtimestamp(ts, LOCAL_TZ).strftime('%m.%Y')
        monthly.setdefault(month, []).append(price)
    lines = [header, f'💰 Последняя цена: <b>{amount(last_price)}</b>',
             f'🕒 Проверена: {datetime.fromtimestamp(last_time, LOCAL_TZ):%d.%m.%Y %H:%M} (Шымкент)',
             f'📉 Минимум: <b>{amount(minimum)}</b>',
             f'📈 Максимум: <b>{amount(maximum)}</b>',
             f'🏁 Первая цена: {amount(first_price)}',
             f'↔️ Изменение от первой: <b>{change:+.1f}%</b>', '', verdict, '',
             '📆 <b>По месяцам · минимум — максимум</b>']
    for month, prices in monthly.items():
        span = amount(min(prices)) if min(prices) == max(prices) else f'{amount(min(prices))} — {amount(max(prices))}'
        lines.append(f'▫️ {month}: {span}')
    lines.extend(['', f'🗃 Наблюдения: {date(first_time)} — {date(last_time)}',
                  f'📌 Проверок: {len(rows)} · дней с данными: {days}',
                  'ℹ️ Только сохранённые проверки этого магазина. Пропуски не заполняются; '
                  'цен до начала наблюдений нет. Это не полная история рынка за год.',
                  f'<a href="{html.escape(url, quote=True)}">🛒 Открыть товар</a>'])
    return '\n'.join(lines)


def handle_callback(telegram, connection, query):
    message = query.get('message') or {}
    chat = message.get('chat') or {}
    configured = str(telegram.chat)
    allowed = str(chat.get('id')) == configured or (
        configured.startswith('@') and chat.get('username')
        and configured[1:].casefold() == chat['username'].casefold())
    data = query.get('data', '')
    match = re.fullmatch(r'(analysis|compare):([a-f0-9]{24})', data)
    if not allowed or not match:
        telegram.call('answerCallbackQuery', {'callback_query_id': query['id'],
                                             'text': 'Эта кнопка недоступна в данном чате.'})
        return
    user_id = (query.get('from') or {}).get('id')
    if not isinstance(user_id, int) or user_id <= 0:
        telegram.call('answerCallbackQuery', {'callback_query_id': query['id'], 'text': 'Не удалось определить получателя.'})
        return
    report = build_comparison if match[1] == 'compare' else build_analysis
    payload = dict(chat_id=user_id, text=report(connection, match[2]),
                   parse_mode='HTML', link_preview_options={'is_disabled': True})
    try:
        if match[1] == 'compare':
            queue_comparison(telegram, connection, user_id, match[2])
        else:
            telegram.call('sendMessage', payload)
    except Exception as exc:
        if getattr(exc, 'code', None) != 403:
            raise
        username = getattr(telegram, 'username', None)
        if not isinstance(username, str) or not username:
            username = telegram.call('getMe', {})['username']
        telegram.call('answerCallbackQuery', {'callback_query_id': query['id'],
                      'text': 'Откройте бота и нажмите «Запустить», чтобы получить анализ.',
                      'url': f'https://t.me/{username}?start={match[1]}_{match[2]}'})
        return
    telegram.call('answerCallbackQuery', {'callback_query_id': query['id'], 'text': '📩 Анализ отправлен вам в личный чат.'})


def handle_private_message(telegram, connection, message):
    chat = message.get('chat') or {}
    if chat.get('type') != 'private' or (message.get('from') or {}).get('id') != chat.get('id'):
        return
    match = re.fullmatch(r'/start(?:@[\w]+)?\s+(analysis|compare)_([a-f0-9]{24})', message.get('text', '').strip())
    if match:
        if match[1] == 'compare':
            queue_comparison(telegram, connection, chat['id'], match[2])
            return
        report = build_comparison if match[1] == 'compare' else build_analysis
        telegram.call('sendMessage', dict(chat_id=chat['id'], text=report(connection, match[2]),
                                         parse_mode='HTML', link_preview_options={'is_disabled': True}))


def queue_comparison(telegram, connection, chat_id, product_id):
    product = connection.execute('SELECT name FROM products WHERE id=?', (product_id,)).fetchone()
    if not product:
        telegram.call('sendMessage', {'chat_id': chat_id, 'text': '📭 Товар не найден в базе.'})
        return
    pending = connection.execute("SELECT id FROM comparison_jobs WHERE chat_id=? AND product_id=? AND state IN ('pending','running')",
                                 (chat_id, product_id)).fetchone()
    text = ('⏳ Поиск этого товара уже выполняется. Результат придёт сюда.' if pending else
            f'🔎 Ищу в других магазинах для Шымкента:\n{product[0][:220]}\n\nПроверка может занять несколько минут. Результат пришлю сюда.')
    # Send first: an unstarted private chat must not create an undeliverable job.
    telegram.call('sendMessage', {'chat_id': chat_id, 'text': text})
    if not pending:
        with connection:
            connection.execute("INSERT INTO comparison_jobs(chat_id,product_id,state,created) VALUES (?,?,'pending',?)",
                               (chat_id, product_id, int(time.time())))


def callback_worker(telegram, database_path, stop):
    # Each thread owns its SQLite connection. Price collection can take minutes;
    # button clicks are processed independently of the hourly scan.
    connection = sqlite3.connect(database_path, timeout=30)
    try:
        row = connection.execute("SELECT value FROM bot_state WHERE key='update_offset'").fetchone()
        offset = int(row[0]) if row else 0
        while not stop.is_set():
            try:
                updates = telegram.call('getUpdates', {'offset': offset, 'timeout': 20,
                                                       'allowed_updates': ['callback_query', 'message']})
                for update in updates:
                    if stop.is_set():
                        return
                    if update.get('callback_query'):
                        try:
                            handle_callback(telegram, connection, update['callback_query'])
                        except Exception as exc:
                            # An expired or malformed callback must not block all
                            # later clicks. The user can press the button again.
                            LOG.error('Не удалось ответить на нажатие кнопки: %s', exc)
                    if update.get('message'):
                        try:
                            handle_private_message(telegram, connection, update['message'])
                        except Exception as exc:
                            LOG.error('Не удалось отправить личный анализ: %s', exc)
                    offset = update['update_id'] + 1
                    with connection:
                        connection.execute("INSERT OR REPLACE INTO bot_state VALUES ('update_offset',?)", (str(offset),))
            except Exception as exc:
                LOG.error('Кнопки Telegram: %s. Проверьте сеть, webhook и отсутствие второго экземпляра бота.', exc)
                stop.wait(5)
    finally:
        connection.close()
