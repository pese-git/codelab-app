# Начало работы

Глава для разработчика, который впервые открыл код приложения. Она отвечает на практические вопросы: как подготовить репозиторий, как запустить приложение (в том числе изолированно), как читать журнал и отлаживать Cubit-ы, как гонять тесты и в какой файл идти с задачей. Устройство кода объясняют остальные главы; сюда они ссылаются по месту.

## Подготовка репозитория

Шаги подготовки — в [запуске из исходников](../../../docs/user/run-from-source.md#1-подготовка). Здесь конспект; команды выполняются из корня репозитория.

1. Установите [FVM](https://fvm.app) и Xcode с командной строкой (сборка приложения только под macOS). Версия Flutter SDK лежит в `.fvmrc`; все команды Dart и Flutter идут через `fvm`.
2. Поставьте SDK и свяжите пакеты:

   ```bash
   fvm install
   fvm flutter pub get
   fvm dart run melos bootstrap
   ```

3. Создайте сгенерированный код. Часть файлов (`*.freezed.dart`) в git не хранится, и без них пакеты, от которых зависит приложение, не соберутся:

   ```bash
   fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
   ```

Исключение в самом приложении: `lib/app/app_scope.module.cherrypick.g.dart` хранится в git. Он нужен только после правки аннотированных модулей, как — в [главе 02](02-composition-root.md#аннотации-и-сгенерированный-код). Каталоги локализации `lib/l10n/app_localizations*.dart` тоже коммитятся ([глава 05](05-localization.md)).

## Запуск

Из каталога приложения:

```bash
cd apps/codelab_desktop
fvm flutter run -d macos
```

Пока приложение запущено, в консоли работают обычные клавиши Flutter: `r` — горячая перезагрузка, `R` — перезапуск с потерей состояния, `q` — выход. При правке `lib/app/app_scope.dart` и модулей Cherrypick нужен именно перезапуск (`R` или повторный запуск): scope собирается один раз при старте, и горячая перезагрузка его не пересоберёт.

Что увидите при первом запуске, — в [руководстве пользователя](user-guide.md#первый-запуск); сначала откроются пять приветственных шагов, пятый из них — «Open a project»; экран с тем же названием показывается, если пропустить шаги («Skip for now») или если проекта нет. Без выбранной папки проекта агент не стартует.

## Изолированный запуск с `CODELAB_HOME`

Почему `flutter run` не годится для временных данных и как запустить собранный бинарь с `CODELAB_HOME` — в [разработке](development.md#изолированный-ручной-прогон). Команда оттуда с предварительной сборкой:

```bash
cd apps/codelab_desktop
fvm flutter build macos --debug
CODELAB_HOME=<временная папка> \
  build/macos/Build/Products/Debug/codelab_app.app/Contents/MacOS/codelab_app
```

Что при этом изолировано, а что нет:

| Что | Где лежит | Изолируется `CODELAB_HOME` |
|---|---|---|
| конфигурация агента, профили, недавние проекты, секреты, журналы сессий, пользовательские темы | `$CODELAB_HOME` | да |
| снимок рабочего пространства, раскладка дока, язык, оформление, флаги onboarding и «Reopen the last project», последняя страница настроек, профиль по умолчанию | домен настроек `com.example.codelabApp` (`~/Library/Preferences/…`) | **нет**: общий для всех сборок с этим идентификатором |
| журналы приложения | `~/Library/Application Support/com.example.codelabApp/logs/` | нет |

Сбросить настройки окна можно командой `defaults delete com.example.codelabApp` при закрытом приложении ([эксплуатация](operations.md#данные-приложения-вне-codelab_home)). Ключи провайдеров при ручных запусках передавайте через `CODELAB_SECRET_*` или файловое хранилище внутри временного дома, а не из своей оболочки: настоящие переменные с ключами в такое окружение лучше не тащить.

Запросы к настоящим провайдерам моделей при разработке без нужды не делайте: для проверки ленты, одобрений и страниц настроек есть сценарий модели ([глава 08](08-testing.md)).

## Управление запущенным приложением: `flutter_driver` и Dart MCP

Точка входа `test_driver/app.dart`, команда запуска с `--print-dtd`, ключи вроде `settings-nav-providers` и размер окна по умолчанию — в [разработке](development.md#управление-запущенным-приложением). Что делать с адресом DTD:

1. Подключите инструмент Dart MCP к DTD: сначала найдите адреса (`listDtdUris` инструмента `dtd`), потом подключитесь по выбранному (`connect`).
2. `listConnectedApps` покажет запущенное приложение; через него вызываются действия `flutter_driver` — нажать элемент по ключу, ввести текст, прочитать текст, сделать снимок.
3. Находите элементы по `ValueKey`, а не по координатам: ключи стабильны и заведены в виджетах специально для тестов. Нужен новый ключ — добавьте его в виджет, а не ищите по тексту (язык интерфейса может смениться).

Интеграционные сценарии `integration_test/` работают иначе (на устройстве, через `flutter test`) и запускаются только в ветке `release/<version>` ([глава 08](08-testing.md)).

## Журнал приложения

События приложения — структурные записи `structured_log`, а не вывод `print`: `print` в рабочем коде запрещён (`AGENTS.md`, §15). Каждое событие имеет имя вида `компонент.событие` и поля.

| Сборка | Куда пишется |
|---|---|
| debug (`flutter run`, `flutter test`) | цветной вывод в консоль процесса |
| release | `~/Library/Application Support/com.example.codelabApp/logs/application.log`, строки JSON |
| любая | панель «Protocol» (вид «Log», команда `/logs`): буфер журнала в памяти |
| любая, по умолчанию выключено | `protocol.log`: полная трассировка кадров ACP, ротация по 10 МБ |

Полная таблица событий и полей — [эксплуатация](operations.md#логи-и-диагностика). Секреты в записях маскируются. Какие поля есть у каждого события, смотрите в этой таблице: событий с путями и командами немного (например, диагностика подключения компонента `presentation` пишет путь проекта и команду stdio-профиля), поэтому не считайте журнал безопасным для публикации целиком.

Так выглядит консольный вывод. Фрагмент получен запуском `fvm flutter test test/app/root_scope_close_test.dart` в `apps/codelab_desktop` (в тестах журнал настроен так же, как в debug-сборке):

```text
[2026-11-24T18:15:25.331227Z] INFO: app.locale_resolved {"logger":"codelab_desktop.app","category":"application","component":"app","preference":"system","locale":"en"}
[2026-11-24T18:15:25.346229Z] INFO: app.appearance_resolved {"logger":"codelab_desktop.settings","category":"application","component":"settings","mode":"system","light_theme":"light","dark_theme":"dark","system_accent":false,"fallback":"none"}
[2026-11-24T18:15:25.434100Z] INFO: terminal.close_all {"logger":"codelab_desktop.terminal","category":"application","component":"terminal","count":0,"forced":false}
```

Как читать:

- `component` — `app`, `settings`, `onboarding`, `terminal`, `workbench`, `usage`, `protocol`, `project_files`, `secret_migration`, `recent_projects`, `embedded` (лог встроенного агента) и `presentation` (диагностика подключения клиентского слоя): по нему фильтруют;
- имя события — всё после `INFO:` (первое слово); его же ищите по коду: `grep -rn "app.exit_timeout" lib`;
- сбои и таймауты (`app.exit_timeout`, `embedded.close_timeout` — `warning`, `app.shutdown_step_failed` — `error`) ищите по уровню.

Нужно новое событие — заведите его рядом с кодом через логгер компонента (`_settingsLogger()`, `codeLabAppLogger()` и другие — функции в `lib/app/app_scope.dart` перед контрактами Cherrypick) и сразу добавьте строку в таблицу событий [эксплуатации](operations.md#логи-и-диагностика): документ перечисляет события, и устаревшая таблица — дефект.

## Отладка Cubit-ов

Общего `BlocObserver` в приложении нет (поиск `BlocObserver` и `Bloc.observer` по `lib/` и `test/` пуст), и переходы Cubit-ов в журнал сами не попадают. Что есть:

1. **События журнала.** Cubit-ы настроек и рабочего места пишут события о значимых переходах (`provider_settings.loaded`, `settings.appearance_changed`, `connection_profile.saved` и другие). Их имена и поля — в `AGENTS.md` приложения и в [эксплуатации](operations.md#логи-и-диагностика).
2. **Тест с потоком состояний.** Самый воспроизводимый способ — написать тест на Cubit: состояния читаются как `cubit.stream`, а логгер подменяется `RecordingLogger` (`test/support/recording_logger.dart`) и пишет события в список. Образцы подмены логгера: `test/app/app_exit_handler_test.dart`, `test/features/settings/application/startup_settings_cubit_test.dart`.
3. **Временный `BlocObserver`.** Чтобы посмотреть все переходы живого приложения, поставьте наблюдателя локально и **не коммитьте**: в `main()` до `runApp` или в `test_driver/app.dart`:

   ```dart
   final class TraceObserver extends BlocObserver {
     @override
     void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
       super.onChange(bloc, change);
       debugPrint(
         '${bloc.runtimeType}: ${change.currentState.runtimeType} '
         '-> ${change.nextState.runtimeType}',
       );
     }
   }

   // Bloc.observer = TraceObserver();
   ```

   Печатайте имена типов, а не `toString()` целиком: в состоянии настроек бывают пути, а журнал и консоль не должны их показывать.
4. **DevTools.** `fvm flutter run` выводит адрес Flutter DevTools. Виджет-инспектор помогает найти, какой виджет рисует элемент и какой `ValueKey` у него; вкладка Performance — найти лишние перестроения. Адрес DTD (`--print-dtd`) позволяет подключить DevTools и инструменты MCP к одному процессу.

Правила по состоянию — [state-management.md](../../../docs/architecture/state-management.md), по потокам и отмене — [concurrency.md](../../../docs/architecture/concurrency.md). Как состояние клиентского слоя доходит до Cubit-ов — [глава 03](03-state-flow.md).

## Прогон тестов

Все команды — из каталога приложения. Полные тесты:

```bash
cd apps/codelab_desktop
fvm flutter test
```

Один файл:

```bash
fvm flutter test test/app/root_scope_close_test.dart
```

Один тест по имени (подстрока названия; кавычки обязательны, если в названии есть пробелы):

```bash
fvm flutter test test/app/root_scope_close_test.dart --plain-name "параллельные closeCodeLabRootScope"
```

Результат этого запуска (получен на этом дереве, ключи провайдеров из окружения убраны через `env -u`):

```text
00:00 +0: (setUpAll)
00:00 +0: параллельные closeCodeLabRootScope закрывают root scope один раз
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

Полезно знать:

- `test/` повторяет структуру `lib/`: `test/app`, `test/core`, `test/features/<фича>/{application,presentation}`, `test/l10n`; общие двойники и построители — `test/support/`.
- Виджет-тесты строят дерево через `CodeLabTestBinding` ([глава 02](02-composition-root.md#швы-тестов)). Файловый ввод-вывод внутри `testWidgets` зависает в fake-async зоне: файлы проверяют обычными `test` на временном каталоге.
- `test/flutter_test_config.dart` следит за настоящим `$CODELAB_HOME/recent_projects.json` и роняет файл тестов, если тест его изменил; лечение — шов `recentProjectsStore:` или временный `CODELAB_HOME`.
- Теги: `scripted-only` помечает тесты, которым нужен scripted-агент; прогон против Dart-агента идёт с `--exclude-tags scripted-only` (`dart_test.yaml`).
- Интеграционные тесты `integration_test/` и скрипты `test:e2e:app:*` на устройстве запускаются только в ветке `release/<version>`; в `feature/*` для них достаточно `fvm flutter analyze` ([глава 08](08-testing.md), корневой [`AGENTS.md`](../../../AGENTS.md), §21).

Остальные проверки (формат, `analyze`, `guard`, `l10n:check`) — в списке под таблицей тестов [разработки](development.md#тесты). После правки `.arb` выполните `fvm flutter gen-l10n` и закоммитьте результат. При изменении виджетов `codelab_ui` запускайте тесты и в `packages/flutter/codelab_ui`. Полный `melos run check` перед pull request запускают только по просьбе ([`AGENTS.md`](../../../AGENTS.md), §21). Уровни тестов — [testing.md](../../../docs/architecture/testing.md).

## Что изменить и куда смотреть

| Задача | Куда смотреть | Глава |
|---|---|---|
| новая зависимость, порт или фабрика Cubit-а в графе | `lib/app/app_scope.dart`: модули, `CodeLabDependencies`, `CodeLabBootstrap` | [02](02-composition-root.md) |
| что и в каком порядке закрывается при выходе | `CodeLabRootLifecycle` в `app_scope.dart`, `lib/app/app_exit_handler.dart` | [02](02-composition-root.md) |
| лента: как строка транскрипта превращается в виджет | `lib/features/workbench/application/ui_mappers.dart`, виджеты в `codelab_ui` | [03](03-state-flow.md) |
| одобрения, «Go to approval», ответ сочетанием | `lib/features/workbench/application/approval_*.dart` | [03](03-state-flow.md) |
| подключение, старт агента, восстановление проекта | `connection_cubit.dart`, `settings_cubit.dart`, `sessions_cubit.dart` в `lib/features/workbench/application/` | [03](03-state-flow.md), [07](07-embedded-agent-and-connections.md) |
| переходы между рабочим местом, настройками и приветственными шагами | `lib/app/navigation/`, `lib/features/onboarding/`, `lib/app/onboarding/` | [04](04-navigation-and-settings.md) |
| новая страница настроек, поведение страницы | `lib/app/navigation/settings_page.dart`, `lib/features/settings/{application,presentation}/`, `lib/app/default_settings_pages.dart` | [04](04-navigation-and-settings.md), [09](09-extending.md) |
| строка интерфейса, перевод | `lib/l10n/app_en.arb`, `app_ru.arb`, `context.l10n` | [05](05-localization.md) |
| язык интерфейса | `lib/app/language/` | [05](05-localization.md) |
| порт к ОС, диалог, ключ `shared_preferences` | `lib/core/platform/` | [06](06-platform-and-appearance.md) |
| тема, режим оформления, системный акцент | `lib/app/appearance/`, `lib/features/settings/presentation/appearance_page.dart` | [06](06-platform-and-appearance.md) |
| встроенный агент, профили и токены, провайдеры, MCP | `lib/app/embedded_transport_resolver.dart`, `provider_settings_session.dart`, `client_profile_secrets.dart`, `lib/features/settings/` | [07](07-embedded-agent-and-connections.md) |
| панель «Usage», «Files», «Terminal», «Protocol» | `lib/features/usage/`, `project_files/`, `terminal/`, `protocol/` | [01](01-overview.md) |
| сочетание клавиш | каталог `CodeLabShortcut` в `packages/flutter/codelab_ui`, `lib/features/settings/presentation/keyboard_page.dart` | [09](09-extending.md) |
| правило сторожа, запрет импорта | `packages/dart/codelab_architecture_tests/test/support/rules.dart` | [01](01-overview.md), [06](06-platform-and-appearance.md) |
| событие журнала | функции логгеров в `lib/app/app_scope.dart` (перед контрактами Cherrypick) и логгеры Cubit-ов; таблица — [эксплуатация](operations.md#логи-и-диагностика) | эта глава |
| тест на Cubit или виджет, двойник порта | `test/support/`, `test/features/…` | [08](08-testing.md) |
| что-то сломалось при запуске | — | [10](10-troubleshooting.md) |

Если задача меняет поведение продукта, ACP-контракты, хранение или безопасность, начните с OpenSpec change ([`AGENTS.md`](../../../AGENTS.md), §17), а не с кода. Правила изменений приложения — [`AGENTS.md`](../AGENTS.md) приложения.

## Что дальше

- Карта кода и слои — [глава 01](01-overview.md).
- Как всё собирается — [глава 02](02-composition-root.md).
- Сводка «симптом — причина — что сделать» — [глава 10](10-troubleshooting.md).
