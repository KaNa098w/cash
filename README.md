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

Windows release через GitHub Actions:
```text
Actions -> Windows Release -> Run workflow
```

Что делает workflow:
- собирает `flutter build windows --release`
- публикует `updater`
- собирает `dist_installer/Leemon_<version>_win_x64.zip`
- опционально собирает `Leemon_Setup_<version>.exe`

Параметры:
- `version`: если оставить пустым, берется версия из `pubspec.yaml` без `+build`
- `channel`: уходит в `APP_UPDATE_CHANNEL`
- `build_installer`: включает сборку Inno Setup installer
