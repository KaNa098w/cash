import unittest
from unittest.mock import MagicMock, patch
from bs4 import BeautifulSoup

from bot import Database, Telegram, TelegramError, category, check_city, collect, discover, money, offer, parse_products, product_photo, run_cycle


class PriceTests(unittest.TestCase):
    def setUp(self):
        self.settings = {'baseline': 'store_old_price', 'min_discount_percent': 15}
        self.product = dict(url='https://shop.kz/offer/cpu/', name='Процессор <AMD>',
                            price=850000, old=1000000, available=True)

    def test_money_rejects_instalments_and_ranges(self):
        self.assertEqual(money('123\u202f990 ₸'), 12399000)
        self.assertEqual(money('99,50'), 9950)
        for invalid in ['0', '-100', '10 000 × 24 мес', '100–200', 'от 100', 'NaN']:
            self.assertIsNone(money(invalid))

    def test_exact_threshold_and_below(self):
        self.assertIsNotNone(offer('shop', self.product, None, self.settings))
        self.product['price'] += 1
        self.assertIsNone(offer('shop', self.product, None, self.settings))

    def test_no_old_price_and_out_of_stock(self):
        self.product['available'] = False
        self.assertIsNone(offer('shop', self.product, None, self.settings))
        self.product.update(available=True, old=None)
        self.assertIsNone(offer('shop', self.product, None, self.settings))

    def test_previous_price_first_run_and_drop(self):
        self.settings['baseline'] = 'previous_price'
        self.assertIsNone(offer('shop', self.product, None, self.settings))
        self.assertIsNotNone(offer('shop', self.product, 1000000, self.settings))

    def test_identity_ignores_inflated_old_price_and_escapes_html(self):
        key, text = offer('shop', self.product, None, self.settings)
        self.assertIn('&lt;AMD&gt;', text)
        self.product['old'] *= 2
        self.assertEqual(key, offer('shop', self.product, None, self.settings)[0])

    def test_history_dedup_and_preview(self):
        db = Database(':memory:')
        self.assertIsNone(db.observe('shop', self.product, persist=False))
        self.assertIsNone(db.observe('shop', self.product))
        self.assertEqual(db.observe('shop', self.product), self.product['price'])
        db.mark_sent('a')
        self.assertTrue(db.already_sent('a'))
        db.db.close()

    def test_parse_cards_and_reject_ambiguous_prices(self):
        store = {'rules': [dict(card='.card', link='a', price='.price', old='.old')]}
        markup = '''<div class="card"><a href="/offer/cpu/?utm=1">Процессор AMD</a>
          <b class="price">85 000 ₸</b><s class="old">100 000 ₸</s></div>
          <div class="card"><a href="/offer/no/">Ноутбук</a>
          <b class="price">100</b><b class="price">200</b></div>
          <div class="card"><a href="https://other.kz/cpu">Процессор</a><b class="price">100</b></div>'''
        parsed = parse_products(markup, 'https://shop.kz/', store)
        self.assertEqual(len(parsed), 1)
        self.assertEqual(parsed[0]['price'], 8500000)
        self.assertEqual(parsed[0]['url'], 'https://shop.kz/offer/cpu/')

    def test_city_rejects_other_city_and_city_picker(self):
        page = MagicMock()
        for values in [['Алматы'], [], ['Шымкент', 'Алматы'], ['Выберите город ' * 20 + 'Шымкент']]:
            page.locator.return_value.all_text_contents.return_value = values
            with self.assertRaises(RuntimeError):
                check_city(page, {'city_selector': '.selected-city'})
        page.locator.return_value.all_text_contents.return_value = ['Шымкент']
        check_city(page, {'city_selector': '.selected-city'})

    def test_discovery_same_domain_and_requested_categories(self):
        store = dict(home='https://shop.kz/', category_path=r'^/offers/')
        markup = '''<a href="/offers/smartfony/">Смартфоны</a>
          <a href="/offers/toys/">Игрушки</a>
          <a href="https://foreign.kz/offers/noutbuki/">Ноутбуки</a>'''
        self.assertEqual(discover(markup, store['home'], store), ['https://shop.kz/offers/smartfony/'])

    def test_accessory_is_not_a_laptop(self):
        self.assertIsNone(category('Подставка для ноутбука'))
        self.assertEqual(category('Apple iPhone 17'), 'smartphones')

    def test_pagination_handles_numeric_links(self):
        store = dict(home='https://shop.kz/', category_path=r'^/offers/')
        markup = '<a href="?PAGEN_1=2">2</a><a href="?PAGEN_1=3">3</a>'
        self.assertEqual(discover(markup, 'https://shop.kz/offers/cpu/', store, True),
                         ['https://shop.kz/offers/cpu/?PAGEN_1=2'])

    def test_sulpak_excludes_other_city_links_and_reads_data_url_pagination(self):
        store = dict(home='https://www.sulpak.kz/', category_path=r'^/f/[^/]+(?:/shymkent)?/?$',
                     allowed_path=r'^/(?:$|(?:f|p)/[^/]+(?:/shymkent)?/?$)')
        markup = '''<a href="/f/smartfoniy/almaty/1056_267">Смартфоны Алматы</a>
          <a href="/f/noutbuki">Ноутбуки</a>
          <a data-url="/f/smartfoniy?page=2">Следующая</a>'''
        url = 'https://www.sulpak.kz/f/smartfoniy'
        self.assertEqual(discover(markup, url, store), ['https://www.sulpak.kz/f/noutbuki'])
        self.assertEqual(discover(markup, url, store, True), [url + '?page=2'])
        regional = 'https://www.sulpak.kz/f/smartfoniy/shymkent'
        self.assertEqual(discover('<a data-url="/f/smartfoniy/shymkent?page=2">Следующая</a>',
                                  regional, store, True), [regional + '?page=2'])

    def test_card_from_other_city_is_excluded(self):
        store = {'rules': [dict(card='.card', link='a', price='.price')]}
        markup = '''<div class="card"><a href="/g/cpu">Процессор AMD</a><b class="price">100</b>
          <button data-city-title="Алматы">Купить</button></div>'''
        self.assertEqual(parse_products(markup, 'https://www.sulpak.kz/', store), [])
        self.assertEqual(len(parse_products(markup.replace('Алматы', 'Шымкент'),
                                            'https://www.sulpak.kz/', store)), 1)

    @patch('bot.check_city')
    @patch('bot.parse_products')
    @patch('bot.discover')
    def test_unlimited_crawl_exhausts_discovered_pages(self, discover_pages, parse, city):
        page = MagicMock()
        context = MagicMock()
        context.new_page.return_value = page
        first, second = 'https://shop.kz/offers/cpu/', 'https://shop.kz/offers/cpu/?page=2'
        def navigate(url, **kwargs):
            page.url = url
            return MagicMock(status=200)
        page.goto.side_effect = navigate
        discover_pages.side_effect = lambda markup, url, store, pagination=False: [second] if url == first else []
        parse.return_value = [self.product]
        store = dict(id='shop', home='https://shop.kz/', urls=[first])
        settings = dict(max_pages_per_store=None, render_wait_ms=0, scroll_steps=0, request_delay_ms=0)
        receive = MagicMock()
        self.assertEqual(len(collect(context, store, settings, receive)), 1)
        self.assertEqual(page.goto.call_count, 2)
        self.assertEqual(receive.call_count, 2)

    def test_photo_uses_lazy_image_and_preserves_query(self):
        card = BeautifulSoup('<div><img src="data:image/gif;base64,x" '
                             'data-src="//cdn.shop.kz/cpu.jpg?size=800"></div>', 'html.parser')
        self.assertEqual(product_photo(card, 'https://shop.kz/'), 'https://cdn.shop.kz/cpu.jpg?size=800')
        card = BeautifulSoup('<img src="/placeholder.svg"><img src="/real.jpg">', 'html.parser')
        self.assertEqual(product_photo(card, 'https://shop.kz/offer/'), 'https://shop.kz/real.jpg')

    def test_parser_carries_product_photo(self):
        store = {'rules': [dict(card='.card', link='a', price='.price')]}
        markup = '<div class="card"><a href="/offer/cpu/">Процессор AMD</a><img src="/cpu.jpg"><b class="price">100</b></div>'
        self.assertEqual(parse_products(markup, 'https://shop.kz/', store)[0]['photo'],
                         'https://shop.kz/cpu.jpg')

    def test_telegram_photo_and_text_fallback(self):
        sender = Telegram.__new__(Telegram)
        sender.chat = '123'
        sender.call = MagicMock(return_value={'message_id': 1})
        sender.send('Скидка 15%', photo='https://cdn.shop.kz/cpu.jpg')
        method, payload = sender.call.call_args.args
        self.assertEqual(method, 'sendPhoto')
        self.assertEqual(payload['caption'], 'Скидка 15%')
        sender.call.reset_mock()
        sender.call.side_effect = [TelegramError(400), {'message_id': 2}]
        sender.send('Скидка 15%', photo='https://cdn.shop.kz/broken.jpg')
        self.assertEqual([c.args[0] for c in sender.call.call_args_list], ['sendPhoto', 'sendMessage'])

    def test_photo_rate_limit_does_not_send_duplicate_text(self):
        sender = Telegram.__new__(Telegram)
        sender.chat = '123'
        sender.call = MagicMock(side_effect=TelegramError(429))
        with self.assertRaises(TelegramError):
            sender.send('Скидка', photo='https://cdn.shop.kz/cpu.jpg')
        self.assertEqual(sender.call.call_count, 1)

    def test_old_outbox_migrates_preserving_pending_messages(self):
        import sqlite3
        connection = sqlite3.connect(':memory:')
        connection.execute('CREATE TABLE outbox (fingerprint TEXT PRIMARY KEY, store TEXT, message TEXT)')
        connection.execute("INSERT INTO outbox VALUES ('key', 'shop', 'pending')")
        connection.commit()
        with patch('bot.sqlite3.connect', return_value=connection):
            db = Database('unused')
        self.assertEqual(db.db.execute('SELECT message,photo FROM outbox').fetchone(), ('pending', None))
        db.db.close()

    @patch('bot.time.sleep')
    @patch('bot.store_batches')
    @patch('bot.browser_context')
    def test_deal_sends_before_later_page_failure(self, context, collect, sleep):
        db = Database(':memory:')
        sender = MagicMock()
        sender.send.return_value = {'message_id': 77}
        settings = dict(self.settings, stores=[{'id': 'shop'}])
        def pages(pw, store, settings):
            yield [self.product, self.product]
            sender.send.assert_called_once()
            raise RuntimeError('later page failed')
        collect.side_effect = pages
        self.assertEqual(run_cycle(None, settings, db, sender), 1)
        self.assertEqual(db.db.execute('SELECT count(*) FROM observations').fetchone()[0], 1)
        self.assertEqual(db.db.execute('SELECT count(*) FROM sent').fetchone()[0], 1)
        db.db.close()

    @patch('bot.time.sleep')
    @patch('bot.store_batches')
    @patch('bot.browser_context')
    def test_failed_telegram_is_retried_after_price_baseline_changes(self, context, collect, sleep):
        db = Database(':memory:')
        original = dict(self.product, price=1000000)
        db.observe('shop', original)
        settings = dict(self.settings, baseline='previous_price', stores=[{'id': 'shop'}])
        collect.side_effect = lambda *args: iter([[self.product]])
        self.product['photo'] = 'https://cdn.shop.kz/cpu.jpg'
        sender = MagicMock()
        sender.send.side_effect = RuntimeError('network')
        self.assertEqual(run_cycle(None, settings, db, sender), 1)
        self.assertEqual(db.db.execute('SELECT count(*) FROM outbox').fetchone()[0], 1)
        sender.send.side_effect = None
        self.assertEqual(run_cycle(None, settings, db, sender), 0)
        self.assertEqual(db.db.execute('SELECT count(*) FROM outbox').fetchone()[0], 0)
        self.assertEqual(db.db.execute('SELECT count(*) FROM sent').fetchone()[0], 1)
        self.assertEqual(sender.send.call_args.kwargs['photo'], self.product['photo'])
        self.assertIn('Полный анализ', str(sender.send.call_args.kwargs['reply_markup']))
        db.db.close()


    @patch('bot.store_batches')
    def test_stores_alternate_and_failed_store_does_not_block_others(self, batches):
        db = Database(':memory:')
        order = []
        def pages(pw, store, settings):
            for page in range(2):
                order.append((store['id'], page))
                if store['id'] == 'blocked':
                    raise RuntimeError('403')
                yield []
        batches.side_effect = pages
        settings = dict(self.settings, stores=[{'id': 'a'}, {'id': 'blocked'}, {'id': 'b'}])
        self.assertEqual(run_cycle(None, settings, db, None, dry_run=True), 1)
        self.assertEqual(order, [('a', 0), ('blocked', 0), ('b', 0), ('a', 1), ('b', 1)])
        db.db.close()


if __name__ == '__main__':
    unittest.main()
