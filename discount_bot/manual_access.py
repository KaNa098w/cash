"""Interactive store access setup. Security checks are completed by the user."""
import argparse
import json
import time

from bot import ROOT, browser_context, same_site
from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--store', choices=['dns', 'mechta'], required=True)
    parser.add_argument('--auto-city', action='store_true')
    args = parser.parse_args()
    settings = json.loads((ROOT / 'settings.json').read_text(encoding='utf-8'))
    store = next(s for s in settings['stores'] if s['id'] == args.store)
    research = ROOT / 'research'
    research.mkdir(exist_ok=True)
    status_path = research / f'{args.store}-manual-status.json'
    with sync_playwright() as pw:
        try:
            interactive_context = browser_context(pw, store, headed=True)
        except Exception:
            # Use the installed Chrome if the bundled visible browser cannot start.
            interactive_context = pw.chromium.launch_persistent_context(
                str(ROOT / 'data' / 'profiles' / store['id']), channel='chrome',
                headless=False, locale='ru-RU', timezone_id='Asia/Qyzylorda')
        with interactive_context as context:
            page = context.new_page()
            page.goto(store['home'], wait_until='domcontentloaded', timeout=60000)
            previous = None
            deadline = time.monotonic() + 1800
            while time.monotonic() < deadline:
                if page.is_closed():
                    break
                try:
                    if not same_site(page.url, store):
                        page.wait_for_timeout(2000)
                        continue
                    title = page.title()
                    body = page.locator('body').inner_text(timeout=5000)
                    blocked = any(s in title.casefold() for s in ['один момент', 'just a moment']) or 'Выполнение проверки безопасности' in body
                    city = page.locator(store['city_selector']).all_text_contents() if store.get('city_selector') else []
                    verified = bool(city) and all('шымкент' in value.casefold() and len(value.strip()) < 100 for value in city if value.strip()) and any(value.strip() for value in city)
                    status = dict(store=args.store, url=page.url, title=title, blocked=blocked,
                                  city=city, shymkent_verified=verified, checked=int(time.time()))
                    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding='utf-8')
                    signature = (page.url, title, blocked, tuple(city))
                    if signature != previous:
                        print(json.dumps(status, ensure_ascii=False), flush=True)
                        previous = signature
                    if not blocked:
                        (research / f'{args.store}-manual.html').write_text(page.content(), encoding='utf-8')
                    if args.auto_city and not blocked and not verified:
                        city_choice = page.get_by_text('Шымкент', exact=True).filter(visible=True)
                        if city_choice.count():
                            city_choice.first.click()
                            page.wait_for_timeout(1500)
                            continue
                        change = page.get_by_text('Сменить город', exact=True).filter(visible=True)
                        if change.count():
                            change.first.click()
                            page.wait_for_timeout(1500)
                            continue
                    if not blocked and verified:
                        sessions = ROOT / 'data' / 'sessions'
                        sessions.mkdir(exist_ok=True)
                        context.storage_state(path=str(sessions / f'{args.store}.json'))
                        print('Доступ и Шымкент подтверждены. Сессия сохранена. Публикации не запущены.', flush=True)
                        break
                except Exception as exc:
                    print(type(exc).__name__, flush=True)
                page.wait_for_timeout(2000)


if __name__ == '__main__':
    main()
