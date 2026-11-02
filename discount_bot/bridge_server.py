"""Loopback-only receiver for user-initiated DNS card exports. Never sends Telegram messages."""
import hmac
import json
import logging
import re
import secrets
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from bot import ROOT, Database, canonical, category, money, offer

LOG = logging.getLogger('bridge')
MAX_BYTES = 2 * 1024 * 1024


def validate_batch(batch, now=None):
    now = int(time.time()) if now is None else now
    if not isinstance(batch, dict) or batch.get('store') != 'dns' or batch.get('city') != 'Шымкент':
        raise ValueError('Принимаются только товары DNS для Шымкента.')
    source = urlsplit(batch.get('source_url', ''))
    if source.scheme != 'https' or source.hostname != 'www.dns-shop.kz' or not source.path.startswith(('/catalog/', '/product/')):
        raise ValueError('Нужна страница каталога DNS, а не другая вкладка.')
    captured = batch.get('captured_at')
    if type(captured) is not int or not now - 300 <= captured <= now + 30:
        raise ValueError('Данные устарели. Нажмите «Проверить страницу» ещё раз.')
    items = batch.get('products')
    if not isinstance(items, list) or not 1 <= len(items) <= 200:
        raise ValueError('Нужно от 1 до 200 карточек с ценами.')
    result = {}
    for item in items:
        if not isinstance(item, dict):
            raise ValueError('Неверный формат карточки.')
        url = urlsplit(item.get('url', ''))
        if url.scheme != 'https' or url.hostname != source.hostname or not url.path.startswith('/product/'):
            raise ValueError('Ссылка товара не принадлежит DNS.')
        name = item.get('name')
        if not isinstance(name, str) or not 1 <= len(name) <= 500:
            raise ValueError('Некорректное название товара.')
        price, old = money(item.get('price_text', '')), money(item.get('old_price_text', ''))
        if not price:
            raise ValueError('Не удалось прочитать полную цену товара.')
        kind = category(name + ' ' + url.path)
        if not kind:
            continue
        photo = item.get('photo', '')
        if not isinstance(photo, str) or urlsplit(photo).scheme not in ('http', 'https'):
            photo = None
        result[canonical(item['url'])] = dict(url=canonical(item['url']), name=name, category=kind,
            price=price, old=old if old and old > price else None, photo=photo,
            available=item.get('available') is True)
    if not result:
        raise ValueError('На странице нет товаров выбранных категорий с распознанными ценами.')
    return list(result.values())


def save_batch(batch, database_path, settings):
    products = validate_batch(batch)
    db = Database(database_path)
    deals = 0
    try:
        for product in products:
            db.register_product('dns', product)
            previous = db.observe('dns', product)
            deals += int(offer('dns', product, previous, settings) is not None)
        db.health('dns', len(products))
    finally:
        db.db.close()
    return dict(saved=len(products), deals=deals, threshold=settings['min_discount_percent'], published=False)


def make_handler(key, database_path, settings):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            LOG.info('%s %s', self.command, self.path)

        def allowed(self):
            origin = self.headers.get('Origin', '')
            return (self.headers.get('Host') == '127.0.0.1:8765'
                    and re.fullmatch(r'chrome-extension://[a-p]{32}', origin)
                    and hmac.compare_digest(self.headers.get('X-Bridge-Key', ''), key))

        def reply(self, code, data):
            body = json.dumps(data, ensure_ascii=False).encode('utf-8')
            self.send_response(code)
            origin = self.headers.get('Origin', '')
            if re.fullmatch(r'chrome-extension://[a-p]{32}', origin):
                self.send_header('Access-Control-Allow-Origin', origin)
                self.send_header('Vary', 'Origin')
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            if not re.fullmatch(r'chrome-extension://[a-p]{32}', self.headers.get('Origin', '')):
                self.reply(403, {'error': 'Недопустимый источник.'})
                return
            self.send_response(204)
            self.send_header('Access-Control-Allow-Origin', self.headers['Origin'])
            self.send_header('Access-Control-Allow-Methods', 'POST, GET')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Bridge-Key')
            self.end_headers()

        def do_GET(self):
            if self.path != '/health' or not self.allowed():
                self.reply(403, {'error': 'Нет доступа.'})
                return
            self.reply(200, {'ok': True, 'mode': 'save_only'})

        def do_POST(self):
            if self.path != '/ingest' or not self.allowed():
                self.reply(403, {'error': 'Проверьте ключ подключения и источник запроса.'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= MAX_BYTES or self.headers.get_content_type() != 'application/json':
                    raise ValueError('Некорректный формат или размер запроса.')
                self.connection.settimeout(15)
                batch = json.loads(self.rfile.read(length))
                result = save_batch(batch, database_path, settings)
                LOG.info('DNS: сохранено %s товаров, скидок %s; публикация отключена', result['saved'], result['deals'])
                self.reply(200, result)
            except (ValueError, TypeError, KeyError) as exc:
                self.reply(400, {'error': str(exc)})
            except Exception:
                LOG.exception('Ошибка сохранения карточек')
                self.reply(500, {'error': 'Ошибка сохранения. Проверьте локальный журнал.'})
    return Handler


def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
    (ROOT / 'data').mkdir(exist_ok=True)
    path = ROOT / 'data' / 'bridge_pairing.txt'
    if not path.exists():
        path.write_text(secrets.token_urlsafe(32), encoding='utf-8')
    key = path.read_text(encoding='utf-8').strip()
    settings = json.loads((ROOT / 'settings.json').read_text(encoding='utf-8'))
    server = ThreadingHTTPServer(('127.0.0.1', 8765), make_handler(key, ROOT / 'data' / 'prices.sqlite3', settings))
    print('Приёмник DNS: 127.0.0.1:8765. Только сохранение, публикации отключены.', flush=True)
    print('Ключ подключения: data/bridge_pairing.txt (не токен Telegram).', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
