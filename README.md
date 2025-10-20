# POS Desktop (Clean Architecture)

Готовый шаблон кассы под Flutter Desktop. Структура слоёв:
- `features/pos/domain` — сущности и абстракции
- `features/pos/data` — источники и реализации репозиториев
- `features/pos/presentation` — Cubit/Widgets/Pages
- `core` — тема, DI, утилиты

Запуск:
```bash
flutter pub get
flutter run -d macos # или windows/linux
```
