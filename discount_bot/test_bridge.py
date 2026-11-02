import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from bridge_server import make_handler, save_batch, validate_batch


class BridgeTests(unittest.TestCase):
    def batch(self):
        return dict(store='dns', city='Шымкент', source_url='https://www.dns-shop.kz/catalog/phones/',
                    captured_at=1000, products=[dict(name='Смартфон Test 256GB',
                    url='https://www.dns-shop.kz/product/test/?utm=1', price_text='65 000 ₸',
                    old_price_text='100 000 ₸', available=True, photo='https://a.dns-shop.kz/image.jpg')])

    def test_valid_card_is_parsed_without_installment_numbers(self):
        products = validate_batch(self.batch(), now=1000)
        self.assertEqual(products[0]['price'], 6500000)
        self.assertEqual(products[0]['old'], 10000000)
        self.assertEqual(products[0]['url'], 'https://www.dns-shop.kz/product/test/')

    def test_wrong_city_domain_or_old_capture_is_rejected(self):
        for field, value in [('city', 'Астана'), ('source_url', 'https://other.kz/catalog/phones/'),
                             ('captured_at', 1)]:
            batch = self.batch()
            batch[field] = value
            with self.assertRaises(ValueError):
                validate_batch(batch, now=1000)

    def test_instalment_and_foreign_product_are_rejected(self):
        for field, value in [('price_text', '5000 x 24 мес'), ('url', 'https://evil.example/product/test/')]:
            batch = self.batch()
            batch['products'][0][field] = value
            with self.assertRaises(ValueError):
                validate_batch(batch, now=1000)

    def test_local_receiver_requires_extension_origin_and_pairing_key(self):
        handler = make_handler('pairing-key', 'unused', {})
        headers = {'Host': '127.0.0.1:8765', 'Origin': 'chrome-extension://' + 'a' * 32,
                   'X-Bridge-Key': 'pairing-key'}
        self.assertTrue(handler.allowed(SimpleNamespace(headers=headers)))
        for field, value in [('Origin', 'https://www.dns-shop.kz'), ('X-Bridge-Key', 'wrong'),
                             ('Host', 'attacker.example:8765')]:
            self.assertFalse(handler.allowed(SimpleNamespace(headers={**headers, field: value})))

    @patch('bridge_server.Database')
    @patch('bridge_server.time.time', return_value=1000)
    def test_saving_does_not_publish_or_enqueue_telegram(self, clock, database):
        db = MagicMock()
        database.return_value = db
        db.observe.return_value = None
        result = save_batch(self.batch(), 'unused', dict(baseline='store_old_price', min_discount_percent=20))
        self.assertEqual(result, dict(saved=1, deals=1, threshold=20, published=False))
        db.db.execute.assert_not_called()
        db.register_product.assert_called_once()


if __name__ == '__main__':
    unittest.main()
