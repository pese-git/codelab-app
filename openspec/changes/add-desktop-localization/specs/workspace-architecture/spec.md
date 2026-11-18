## ADDED Requirements

### Requirement: Ядро клиента не зависит от языка интерфейса
`codelab_client_core` и `codelab_client_acp` НЕ SHALL импортировать `package:intl/` и `package:flutter_localizations/`. Локализованный текст строит хост (desktop) по типизированным данным ядра. CLI показывает английские тексты ядра. Нарушение SHALL ловить сторож `codelab_architecture_tests` (`melos run guard`).

Каталоги сообщений и сгенерированный код локализации SHALL жить только в `apps/codelab_desktop/lib/l10n/` и `packages/flutter/codelab_ui/lib/l10n/`. Сгенерированный код SHALL совпадать с каталогами ARB; это проверяет скрипт Melos `l10n:check` в составе `check`.

#### Scenario: intl в ядре клиента
- **WHEN** файл в `packages/dart/codelab_client_core/lib/` импортирует `package:intl/intl.dart`
- **THEN** `melos run guard` падает и называет файл и импорт

#### Scenario: Устаревший сгенерированный код
- **WHEN** в `app_en.arb` изменён текст сообщения, а `lib/l10n/app_localizations_en.dart` не перегенерирован
- **THEN** `melos run l10n:check` завершается с ошибкой и называет файл
