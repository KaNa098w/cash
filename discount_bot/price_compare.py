"""Conservative cross-store matching of recently observed Shymkent offers."""
import html
import re
import time
import unicodedata
from datetime import datetime
from decimal import Decimal


def comparison_price(price, old):
    from price_history import amount
    if old and old > price:
        percent = f'{Decimal(old - price) * 100 / old:.1f}'.rstrip('0').rstrip('.')
        return f'💰 <s>{amount(old)}</s> → <b>{amount(price)}</b> <b>(-{percent}%)</b>'
    return f'💰 <b>{amount(price)}</b>'


def match_key(name, gtin=None):
    if gtin and re.fullmatch(r'\d{8}|\d{12,14}', gtin):
        return 'gtin:' + gtin
    text = unicodedata.normalize('NFKC', name).casefold().replace('ё', 'е')
    model = appliance_model(text)
    if model:
        return 'appliance:' + model[0] + ':' + re.sub(r'[^a-z0-9]', '', model[1])
    text = re.sub(r'(\d)\s*гб\b', r'\1gb', text)
    text = re.sub(r'(\d)\s*тб\b', r'\1tb', text)
    aliases = {'гб': 'gb', 'тб': 'tb', 'черный': 'black', 'черная': 'black',
               'белый': 'white', 'белая': 'white', 'серый': 'gray', 'серая': 'gray',
               'grey': 'gray', 'синий': 'blue', 'зеленый': 'green', 'фиолетовый': 'purple',
               'серебристый': 'silver', 'розовый': 'pink'}
    for original, replacement in aliases.items():
        text = re.sub(r'\b' + original + r'\b', replacement, text)
    text = re.sub(r'(\d)\s+(gb|tb)\b', r'\1\2', text)
    tokens = re.findall(r'[a-zа-я0-9]+', text)
    generic = {'смартфон', 'ноутбук', 'процессор', 'наушники', 'компьютер', 'моноблок',
               'smartphone', 'laptop', 'processor', 'headphones', 'цвет'}
    tokens = [token for token in tokens if token not in generic]
    if len(tokens) < 2 or not any(re.search(r'\d', token) for token in tokens):
        return None
    # Keep every model, capacity, colour, generation, suffix and bundle token.
    # No fuzzy similarity: an uncertain match is safer left unconfirmed.
    return 'title:' + '|'.join(sorted(tokens))


def appliance_model(name):
    if not re.search(r'холодильник|морозильник|стиральн|посудомо|духов|микроволн|пылесос|утюг|чайник|блендер|кондиционер', name, re.I):
        return None
    match = re.search(r'\b([a-z][a-z-]{1,20})\s+([a-z]{1,6}\d{2,}[a-z0-9.\-]*)\b', name, re.I)
    return (match[1].lower(), match[2].lower()) if match else None


def search_terms(name):
    model = appliance_model(name)
    return ' '.join(model) if model else name[:180]


def build_comparison(connection, product_id, now=None, fresh_since=None, search_results=None):
    from price_history import LOCAL_TZ, STORE_NAMES, amount
    now = int(time.time()) if now is None else now
    source = connection.execute('SELECT store,name,match_key,city FROM products WHERE id=?', (product_id,)).fetchone()
    if not source:
        return '🏪 <b>Цены в других магазинах</b>\n📭 Товар пока не найден в базе.'
    source_store, name, key, city = source
    header = f'🏪 <b>ЦЕНЫ В ДРУГИХ МАГАЗИНАХ</b>\n\n<b>{html.escape(name[:220])}</b>\n📍 Только Шымкент\n'
    if city != 'Шымкент' or not key:
        return header + '\n⏳ Для точного сравнения нужно дождаться повторной проверки товара для Шымкента.'
    rows = connection.execute('''
        SELECT p.store,p.url,o.price,o.observed,o.old FROM products p
        JOIN observations o ON o.rowid=(SELECT o2.rowid FROM observations o2
          WHERE o2.store=p.store AND o2.url=p.url ORDER BY o2.observed DESC,o2.rowid DESC LIMIT 1)
        WHERE p.match_key=? AND p.city='Шымкент' AND p.available=1
          AND p.checked>=? AND p.checked<=? AND o.observed>=? AND o.observed<=?
        ORDER BY o.price ASC
    ''', (key, fresh_since if fresh_since is not None else now - 86400, now,
          fresh_since if fresh_since is not None else now - 86400, now)).fetchall()
    stores = {}
    for store, url, price, checked, old in rows:
        stores.setdefault(store, (url, price, checked, old))
    lines = [header, '🕒 Последние сохранённые цены (не старше 24 часов):', '']
    if search_results is not None:
        lines = [header, '🔎 Результат поиска по магазинам сейчас:', '']
    for store, (url, price, checked, old) in stores.items():
        label = ' · исходный магазин' if store == source_store else ''
        lines.extend([f'🏬 <b>{html.escape(STORE_NAMES.get(store, store))}</b>{label}',
                      comparison_price(price, old),
                      f'🕒 {datetime.fromtimestamp(checked, LOCAL_TZ):%d.%m.%Y %H:%M} · Шымкент',
                      f'<a href="{html.escape(url, quote=True)}">🛒 Открыть товар</a>', ''])
    other_stores = set(stores) - {source_store}
    if not other_stores:
        lines.append('🔎 В других магазинах пока нет подтверждённых совпадений той же модели и комплектации.\n')
    for store, label in STORE_NAMES.items():
        if store in stores:
            continue
        health = connection.execute('SELECT error FROM health WHERE store=?', (store,)).fetchone()
        state = (search_results.get(store, 'поиск не выполнен') if search_results is not None else
                 ('магазин временно недоступен' if health and health[0] else 'нет свежей подтверждённой цены на эту модель'))
        lines.append(f'▫️ {label}: {state}')
    explanation = ('ℹ️ Цены проверены отдельным поиском после вашего запроса. '
                   if search_results is not None else
                   'ℹ️ Это данные последнего обхода, а не проверка сайтов в момент нажатия. ')
    lines.extend(['', explanation +
                  'Память, модель и комплектация должны совпадать; похожие товары не подставляются. '
                  'Цену и наличие уточняйте по ссылке.'])
    return '\n'.join(lines)
