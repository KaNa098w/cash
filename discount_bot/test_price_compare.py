import time
import unittest
from unittest.mock import MagicMock

from bot import Database
from price_compare import build_comparison, comparison_price, match_key
from price_history import deal_buttons, handle_private_message


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.db = Database(':memory:')
        self.now = int(time.time())

    def tearDown(self):
        self.db.db.close()

    def add(self, store, price, name='Смартфон Apple iPhone 17 256GB Black', age=0, city='Шымкент', available=True):
        product = dict(url=f'https://{store}.kz/phone', name=name, price=price, old=None, available=available)
        key = self.db.register_product(store, product)
        self.db.observe(store, product)
        self.db.db.execute('UPDATE products SET city=?,checked=? WHERE id=?', (city, self.now-age, key))
        self.db.db.execute('UPDATE observations SET observed=? WHERE store=?', (self.now-age, store))
        self.db.db.commit()
        return key

    def test_same_model_units_and_colour_aliases(self):
        self.assertEqual(match_key('Смартфон Apple iPhone 17 256GB Black'),
                         match_key('Apple iPhone 17 256 ГБ Черный'))

    def test_memory_model_colour_and_bundle_must_match(self):
        base = 'Смартфон Apple iPhone 17 256GB Black'
        for name in [base.replace('256', '512'), base.replace('17', '16'),
                     base.replace('Black', 'White'), base + ' Pro', base + ' комплект наушники']:
            self.assertNotEqual(match_key(base), match_key(name))
        self.assertNotEqual(match_key('Процессор Intel Core i7 14700F'),
                            match_key('Процессор Intel Core i7 14700KF'))

    def test_comparison_only_fresh_same_variant_shymkent(self):
        source = self.add('sulpak', 10000000)
        self.add('shop', 9000000, name='Apple iPhone 17 256 ГБ Черный')
        self.add('technodom', 8000000, city='Алматы')
        self.add('evrika', 7000000, age=90000)
        self.add('dns', 6000000, name='Apple iPhone 17 512GB Black')
        self.add('mechta', 5000000, available=False)
        text = build_comparison(self.db.db, source, self.now)
        self.assertIn('90 000 ₸', text)
        self.assertIn('100 000 ₸', text)
        for price in ['80 000 ₸', '70 000 ₸', '60 000 ₸', '50 000 ₸']:
            self.assertNotIn(price, text)
        self.assertLess(text.index('90 000 ₸'), text.index('100 000 ₸'))
        self.assertIn('не проверка сайтов в момент нажатия', text)

    def test_unknown_source_region_does_not_claim_local_prices(self):
        key = self.add('sulpak', 10000000, city=None)
        self.assertIn('повторной проверки', build_comparison(self.db.db, key, self.now))

    def test_no_match_and_unavailable_store_are_explicit(self):
        key = self.add('sulpak', 10000000)
        self.db.health('dns', 0, '403')
        text = build_comparison(self.db.db, key, self.now)
        self.assertIn('нет подтверждённых совпадений', text)
        self.assertIn('DNS: магазин временно недоступен', text)

    def test_private_compare_button_and_request(self):
        key = self.add('sulpak', 10000000)
        button = deal_buttons(key, 'https://sulpak.kz/phone', 'ramdiscountbot')['inline_keyboard'][2][0]
        self.assertEqual(button['url'], f'https://t.me/ramdiscountbot?start=compare_{key}')
        sender = MagicMock()
        handle_private_message(sender, self.db.db,
                               dict(text=f'/start compare_{key}', chat={'id': 123, 'type': 'private'},
                                    **{'from': {'id': 123}}))
        payload = sender.call.call_args.args[1]
        self.assertEqual(payload['chat_id'], 123)
        self.assertIn('Ищу в других магазинах', payload['text'])
        self.assertEqual(self.db.db.execute('SELECT product_id,state FROM comparison_jobs').fetchone(), (key, 'pending'))

    def test_appliance_matches_model_despite_descriptor_and_keeps_suffix(self):
        self.assertEqual(match_key('Встраиваемый холодильник Hansa BK2705.2N'),
                         match_key('Холодильник Hansa BK2705.2N белый'))
        self.assertNotEqual(match_key('Встраиваемый холодильник Hansa BK2705.2N'),
                            match_key('Встраиваемый холодильник Hansa BK2705.2M'))

    def test_pending_search_is_not_queued_twice(self):
        from price_history import queue_comparison
        key = self.add('sulpak', 10000000)
        sender = MagicMock()
        queue_comparison(sender, self.db.db, 123, key)
        queue_comparison(sender, self.db.db, 123, key)
        self.assertEqual(self.db.db.execute('SELECT count(*) FROM comparison_jobs').fetchone()[0], 1)
        self.assertIn('уже выполняется', sender.call.call_args.args[1]['text'])

    def test_live_report_does_not_use_cached_price_from_before_search(self):
        key = self.add('sulpak', 10000000, age=60)
        self.add('shop', 9000000, age=60)
        text = build_comparison(self.db.db, key, self.now, fresh_since=self.now,
                                search_results={'sulpak': 'не найдено', 'shop': 'не найдено'})
        self.assertNotIn('90 000 ₸', text)
        self.assertIn('Результат поиска', text)

    def test_evrika_live_search_overlay_card(self):
        from bot import parse_products
        store = {'rules': [dict(card='a.rees46-search-product', link='__self__',
                               name='.rees46-search-product__name', price='.rees46-search-product__price-current')]}
        markup = '''<a class="rees46-search-product" href="/catalog/shymkent/fridge/p38407">
          <div class="rees46-search-product__name">Встраиваемый холодильник Hansa BK2705.2N</div>
          <div class="rees46-search-product__price-current">249 990 ₸</div></a>'''
        products = parse_products(markup, 'https://evrika.com/catalog/shymkent', store)
        self.assertEqual(products[0]['price'], 24999000)

    def test_price_has_old_price_and_inline_discount(self):
        self.assertEqual(comparison_price(6500000, 10000000),
                         '💰 <s>100 000 ₸</s> → <b>65 000 ₸</b> <b>(-35%)</b>')
        self.assertIn('(-22.4%)', comparison_price(24999000, 32199000))

    def test_missing_or_invalid_old_price_does_not_invent_discount(self):
        for old in (None, 0, 5000000, 6500000):
            self.assertEqual(comparison_price(6500000, old), '💰 <b>65 000 ₸</b>')

    def test_report_uses_old_price_from_same_latest_observation(self):
        key = self.add('sulpak', 6500000)
        self.db.db.execute('UPDATE observations SET old=10000000')
        text = build_comparison(self.db.db, key, self.now)
        self.assertIn('<s>100 000 ₸</s> → <b>65 000 ₸</b> <b>(-35%)</b>', text)


if __name__ == '__main__':
    unittest.main()
