# AGENTS.md — codelab_desktop

Правила этого приложения дополняют корневой `AGENTS.md` для каталога `apps/codelab_desktop`.

Источники: `design.md` OpenSpec change `add-agent-secret-store` (D15 — встроенные профили этапа 7, D16 — почему не готовая библиотека); `09-12-stage-7-embedded.md`; `design.md` change `add-embedded-agent-mode` (D3 — правила сторожа, D5 — конфиг и секреты, D6 — жизненный цикл и решение L4, D8 — сценарий модели, D9 — тип подключения и composition root, D10 — тесты по веткам). Если документов не хватает, сначала дополняется документация, потом пишется код.

## Встроенный агент

* Встроенный агент работает в процессе приложения через мост `codelab_embedded`: тип подключения `CodeLabTransportType.embedded` («Embedded agent»), профиль `ConnectionProfile.embedded(id: 'embedded', hostProfile: 'embedded-app-desktop')` (D9). Прямой импорт `package:codelab_agent_*` по-прежнему запрещён (корневой `AGENTS.md` §5; правило `apps/codelab_desktop` сторожа).
* Границы барелей моста (D3, правила `packages/dart/codelab_architecture_tests/test/support/rules.dart`):
  * `package:codelab_embedded/io.dart` (`localEmbeddedAgentOpener`) импортируется только из `lib/app/` — composition root;
  * `package:codelab_embedded/testing.dart` запрещён во всём `lib/`: сценарий модели в релизную сборку не попадает (D8). Сценарный открыватель передают только тесты и `integration_test/` через шов `createCodeLabRootScope(embeddedOpener:)` (D9);
  * основной барель `package:codelab_embedded/codelab_embedded.dart` web-безопасен и сторожем внутри app не ограничен.
* `EmbeddedTransportResolver` и адаптер `Logger` → логгер приложения лежат в `lib/app/`; `app_scope.dart` регистрирует резолвер вторым резолвером `ClientWorkspace` и закрывает его (`close()`) при закрытии root scope, до `AcpClientApplication` (D9). Ожидание `close()` ограничено 10 с, как в CLI: по истечении — событие `embedded.close_timeout` уровня `warning`, освобождение транспорта и `AcpClientApplication` продолжается (D9, «Таймаут закрытия»). Резолвер сериализует `open`: сначала `await` `dispose()` прежнего агента, затем открыватель. Агент, вернувшийся из открывателя после отмены подключения, сразу получает `dispose()` и текущим не становится (корневой `AGENTS.md` §12; D6, «Резолвер клиента»).
* Поводов отмены подключения два — новый Connect или Reconnect и `close()` резолвера при закрытии root scope. Кнопки Disconnect нет, публичный API `TransportResolver` и `ClientWorkspace` ради встроенного агента не меняется (решение L4, подтверждено пользователем 2026-11-02; D6, «Отмена подключения в app»). Disconnect — отдельный change клиентского слоя для всех типов подключения. Вытесненная попытка подключения не меняет состояние: `ClientWorkspace` ведёт номер попытки, а `ConnectionCubit` не пишет для неё ни `failed`, ни «started» (D6, «Устаревшая попытка в `ClientWorkspace`»).
* Невалидный или отсутствующий конфиг — `ConnectionFailed`, резолвер переводит `EmbeddedAgentConfigException` в `ClientWorkspaceException(message)`, и баннер показывает его текст без имени класса (проблемы загрузчика и подсказку `codelab config check`); нет ключа провайдера — соединение открывается, первый ход даёт заметку «Failed turn» (D5).

## Секреты

* Секреты (ключи провайдеров, токены) читаются и пишутся только через общие бэкенды `codelab_agent_io` — через `package:codelab_setup/io.dart` (`SecretAdmin`, `openSecretStore`; тот же файл реэкспортирует `DescribedSecretStore`, `SecretStoreUnavailableException` и `Logger`) и встроенный агент через `codelab_embedded`. Приложение не импортирует `package:codelab_agent_*` напрямую (корневой `AGENTS.md` §5).
* `flutter_secure_storage` и другие Flutter-плагины хранения секретов на desktop НЕ ИСПОЛЬЗУЮТСЯ: у приложения, CLI и автономного агента ОДНО хранилище (общий файловый бэкенд `$CODELAB_HOME/secrets.yaml` и переменные `CODELAB_SECRET_*`; после 1.0 — общие записи хранилища ОС, change `add-agent-os-secret-backends`), иначе записи разошлись бы (D15, D16).
* Перенос секретов из файла конфига встроенного агента (задача 8.11; design.md change `add-config-literal-secrets-and-migrate`, D8): признак `EmbeddedAgent.secretsInConfig` резолвер передаёт в `SecretMigrationOffer` (`lib/app/`); порт `SecretMigrationRunner` (`features/workbench/application/`) реализуется только в `lib/app/` через `SecretMigrator` из `package:codelab_embedded/io.dart` (app уже импортирует его из `lib/app/`; `codelab_setup` app не нужен) с тем же `CODELAB_HOME`, `CODELAB_CONFIG` и окружением, что у открывателя; тексты ошибок — без `error.toString()`; виджеты к файлам и хранилищу не обращаются; `--force` в app не предлагается.
* Приложение, запущенное из Finder (macOS), получает минимальное окружение и не видит переменных `CODELAB_SECRET_*` оболочки. Рабочий путь в 1.0 — `secrets.backend: file` в конфиге и ключ, записанный `codelab secret set` (design.md change `add-embedded-agent-mode`, D5).
* Значения секретов живут только в памяти и проходят через `SecretAdmin`; в виджетах, состоянии (Cubit/`SessionView`), логах и диагностике их быть НЕ ДОЛЖНО — только имя секрета и признак «задан».
* Условие macOS App Sandbox: сейчас `com.apple.security.app-sandbox = false` в `macos/Runner/*.entitlements`. Если песочницу включат, бэкенды файла и ОС потребуют пересмотра — это отдельный change, а не правка на месте.

## Тесты

* Интеграционный прогон со встроенным агентом — `CODELAB_E2E_AGENT=embedded` (скрипт `test:e2e:app:embedded`, вне `check`): сценарный открыватель и сценарии `integration_test/llm_scripts/`. Как все `test:e2e:app:*`, он запускается на устройстве или симуляторе только в `release/<version>`; в `feature/*` и `hotfix/*` — только `fvm flutter analyze` (корневой `AGENTS.md` §21; D10).
