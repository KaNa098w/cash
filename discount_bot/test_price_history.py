import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock

from bot import Database, Telegram, TelegramError, offer
from price_history import build_analysis, deal_buttons, handle_callback, handle_private_message, product_key


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.db = Database(':memory:')
        self.product = dict(name='Смартфон <Test>', url='https://shop.kz/offer/test/',
                            price=8500000, old=10000000, available=True)
        self.key = self.db.register_product('shop', self.product)
        self.now = int(datetime(2026, 10, 27, tzinfo=timezone.utc).timestamp())

    def tearDown(self):
        self.db.db.close()

    def add_price(self, price, days_ago):
        with self.db.db:
            self.db.db.execute('INSERT INTO observations VALUES (?,?,?,?,?)',
                               ('shop', self.product['url'], price, None, self.now - days_ago * 86400))

    def test_year_report_excludes_older_future_and_other_store_prices(self):
        self.add_price(100, 366)
        self.add_price(10000000, 200)
        self.add_price(7500000, 30)
        self.add_price(8500000, 0)
        self.add_price(200, -1)
        self.db.db.execute('INSERT INTO observations VALUES (?,?,?,?,?)',
                           ('dns', self.product['url'], 100, None, self.now))
        text = build_analysis(self.db.db, self.key, self.now)
        self.assertIn('Минимум: <b>75 000 ₸</b>', text)
        self.assertIn('Максимум: <b>100 000 ₸</b>', text)
        self.assertIn('Последняя цена: <b>85 000 ₸</b>', text)
        self.assertIn('-15.0%', text)
        self.assertIn('Проверок: 3', text)
        self.assertIn('&lt;Test&gt;', text)
        self.assertIn('Пропуски не заполняются', text)

    def test_one_observation_does_not_claim_a_yearly_record(self):
        self.add_price(8500000, 0)
        text = build_analysis(self.db.db, self.key, self.now)
        self.assertIn('Пока только одна проверка', text)
        self.assertNotIn('🏆', text)

    def test_missing_and_empty_history(self):
        self.assertIn('История пока недоступна', build_analysis(self.db.db, 'missing', self.now))
        self.assertIn('сохранённых цен нет', build_analysis(self.db.db, self.key, self.now))

    def test_buttons_have_stable_short_callback(self):
        buttons = deal_buttons(self.key, self.product['url'])
        data = buttons['inline_keyboard'][0][0]['callback_data']
        self.assertLessEqual(len(data.encode()), 64)
        self.assertEqual(self.key, product_key('shop', self.product['url']))
        self.assertEqual(buttons['inline_keyboard'][1][0]['url'], self.product['url'])

    def query(self, chat_id=123):
        return dict(id='callback-id', data=f'analysis:{self.key}', **{'from': {'id': 456}},
                    message=dict(message_id=42, message_thread_id=5, chat=dict(id=chat_id)))

    def test_callback_sends_analysis_only_to_clicking_user(self):
        sender = MagicMock()
        sender.chat = '123'
        handle_callback(sender, self.db.db, self.query())
        self.assertEqual([c.args[0] for c in sender.call.call_args_list], ['sendMessage', 'answerCallbackQuery'])
        payload = sender.call.call_args_list[0].args[1]
        self.assertEqual(payload['chat_id'], 456)
        self.assertNotIn('message_thread_id', payload)
        self.assertNotIn('reply_parameters', payload)
        self.assertIn('ПОЛНЫЙ АНАЛИЗ', payload['text'])

    def test_new_button_opens_private_bot_with_product_id(self):
        button = deal_buttons(self.key, self.product['url'], 'ramdiscountbot')['inline_keyboard'][0][0]
        self.assertEqual(button['url'], f'https://t.me/ramdiscountbot?start=analysis_{self.key}')
        self.assertNotIn('callback_data', button)

    def test_private_start_returns_requested_analysis(self):
        sender = MagicMock()
        message = dict(text=f'/start analysis_{self.key}', chat={'id': 456, 'type': 'private'},
                       **{'from': {'id': 456}})
        handle_private_message(sender, self.db.db, message)
        self.assertEqual(sender.call.call_args.args[1]['chat_id'], 456)
        self.assertIn('ПОЛНЫЙ АНАЛИЗ', sender.call.call_args.args[1]['text'])
        sender.call.reset_mock()
        message['chat']['type'] = 'supergroup'
        handle_private_message(sender, self.db.db, message)
        sender.call.assert_not_called()

    def test_unstarted_private_chat_gets_start_link(self):
        sender = MagicMock()
        sender.chat = '123'
        sender.username = 'ramdiscountbot'
        sender.call.side_effect = [TelegramError(403), True]
        handle_callback(sender, self.db.db, self.query())
        payload = sender.call.call_args.args[1]
        self.assertEqual(payload['url'], f'https://t.me/ramdiscountbot?start=analysis_{self.key}')

    def test_twenty_percent_threshold_is_exact(self):
        settings = dict(baseline='store_old_price', min_discount_percent=20)
        self.product['price'] = 8000000
        self.assertIsNotNone(offer('shop', self.product, None, settings))
        self.product['price'] += 1
        self.assertIsNone(offer('shop', self.product, None, settings))

    def test_callback_from_another_chat_is_rejected(self):
        sender = MagicMock()
        sender.chat = '123'
        handle_callback(sender, self.db.db, self.query(999))
        self.assertEqual(sender.call.call_count, 1)
        self.assertEqual(sender.call.call_args.args[0], 'answerCallbackQuery')

    def test_forged_callback_does_not_query_or_send_analysis(self):
        sender = MagicMock()
        sender.chat = '123'
        query = self.query()
        query['data'] = 'analysis:../../fake'
        handle_callback(sender, self.db.db, query)
        self.assertEqual(sender.call.call_count, 1)

    def test_keyboard_survives_photo_fallback(self):
        sender = Telegram.__new__(Telegram)
        sender.chat = '123'
        sender.call = MagicMock(side_effect=[TelegramError(400), {'message_id': 1}])
        buttons = deal_buttons(self.key, self.product['url'])
        sender.send('🔥 Скидка', photo='https://cdn.shop.kz/image.jpg', reply_markup=buttons)
        for call in sender.call.call_args_list:
            self.assertEqual(call.args[1]['reply_markup'], buttons)

    def test_deal_shows_discount_savings_and_escaped_name(self):
        _, text = offer('shop', self.product, None,
                        dict(baseline='store_old_price', min_discount_percent=15))
        self.assertIn('🔥 <b>СКИДКА 15.0%</b>', text)
        self.assertIn('💎 Экономия: <b>15 000 ₸</b>', text)
        self.assertIn('<s>100 000 ₸</s>', text)
        self.assertIn('&lt;Test&gt;', text)


if __name__ == '__main__':
    unittest.main()
