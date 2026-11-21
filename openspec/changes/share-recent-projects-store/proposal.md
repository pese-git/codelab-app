## Why

Список недавних проектов у двух клиентов CodeLab сейчас разный и хранится в разных местах:

- CodeLab app пишет его в `shared_preferences` под ключом `codelab.recent_projects` (`SharedPreferencesRecentProjectsStore`, `apps/codelab_desktop/lib/core/platform/`). На macOS это `flutter.codelab.recent_projects` в `~/Library/Preferences/com.example.codelabApp.plist`. Имя файла берётся из идентификатора бандла, а задача 9.4 дорожной карты ([`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md), §4.5) заменит `com.example.codelabApp` постоянным идентификатором. После этого список пропадёт.
- `codelab` недавние проекты не пишет и не читает. `JsonFileRecentProjectsStore` из `codelab_client_io` есть, он описан в spec `acp-client-kit` («IO-адаптеры клиента»), но ни одно приложение его не создаёт.

Профили подключения уже решают ту же задачу: один файл `$CODELAB_HOME/profiles.json` на app и CLI (design.md change [`add-app-settings-shell`](../archive/2026-11-05-add-app-settings-shell/design.md), D5, D7). Недавние проекты должны лежать так же: папка, открытая в `codelab`, видна в app, и список не зависит от идентификатора бандла.

Ещё одно требование: прогоны не должны засорять список. На машине разработчика список app сейчас целиком состоит из временных папок `/private/tmp/...` от smoke-прогонов. Когда список станет общим, это правило нужно и для CLI: его запускают скрипты, CI и e2e-тесты.

## What Changes

- **Одно хранилище на оба клиента.** App и `codelab` пишут недавние проекты через `JsonFileRecentProjectsStore` в `$CODELAB_HOME/recent_projects.json`. Путь строится по общему правилу `resolveCodelabHome`, как у `profiles.json`. Формат — `{"version": 1, "projects": [{"path", "lastOpenedAt"}]}`. Правило списка не меняется: последний открытый первым, не больше `recentProjectsLimit` (10).
- **Строгое чтение.** Битый файл, незнакомая версия и запись неверного вида дают `FormatException` (сейчас неверная запись может дать `TypeError`). Такой файл хранилище не перезаписывает. App при этом запускается, список пуст, в диагностике предупреждение. CLI работает как обычно, предупреждение печатается только с `--verbose`.
- **Сериализация внутри процесса.** Операции одного экземпляра хранилища выполняются по очереди, поэтому два почти одновременных `record` в одном процессе не теряют запись. Между процессами (app и CLI) потеря одной записи при почти одновременной записи допустима и описана: файл при этом остаётся целым (D3).
- **Правило слияния в kit.** Новая чистая функция `mergeRecentProjects` в `codelab_client_core`: дубли по пути сливаются с более поздним временем, список упорядочен по времени и обрезан до лимита. На ней работают `record` и перенос.
- **Одноразовый перенос в app.** При первом обращении к списку app переносит ключ `codelab.recent_projects` из `shared_preferences` в файл: слияние с тем, что уже записал CLI, затем удаление ключа. Перенос идемпотентен. Если файл нечитаем или `CODELAB_HOME` недопустим, ключ не удаляется (D4).
- **CLI пишет проект только в интерактивных режимах.** Это построчный REPL и `--ui tui`: один раз за запуск, после мастера первого запуска, до подключения, папка — проверенная папка сессии (`-C`/`--cwd` или текущая). Headless (`-p`, `-f`, промпт из stdin), `test-scenario`, `config`, `provider`, `mcp`, `secret`, `profiles` и алиас `serve` список не трогают. Ошибка записи не меняет код выхода (D6).
- **Изоляция тестов.** PTY-помощник e2e CLI по умолчанию задаёт временный `CODELAB_HOME`. Тестовая сборка app подставляет хранилище в памяти: настоящий файл в `testWidgets` зависал бы, как с `profileStore`. Интеграционные тесты app уже работают с временным `CODELAB_HOME` (D7).
- **Удаление `SharedPreferencesRecentProjectsStore`.** От него остаётся только чтение и удаление прежнего ключа для переноса. Шов `createCodeLabRootScope(recentProjectsStore:)` (D8, D9).
- **Документация:** `docs/ops/codelab-home.md` (новый общий файл), эксплуатация app и CLI, README `codelab_client_io` и `codelab_client_core`, `AGENTS.md` `codelab_client_io`, `platform-integration.md` §28, `technology-stack.md`, `12-4-first-run-and-settings.md`, заметка к задаче 9.4 в `delivery-roadmap.md`.

## Не входит

- **Показ списка в CLI.** Это команда вроде `/projects` в REPL и TUI, выбор проекта при запуске, `codelab --recent`. CLI в этом change только пишет список. Показ — отдельный change: он меняет интерфейс CLI и требует решения о выборе папки посреди сессии.
- **Межпроцессная блокировка файла** и повтор записи с проверкой (D3, альтернативы).
- **Нормализация путей** (realpath, `/tmp` ↔ `/private/tmp`, регистр). Пути сравниваются как строки, как сейчас. App хранит путь из системного диалога, CLI — абсолютный нормализованный путь `_sessionFolder`.
- **Удаление записи из списка** и очистка несуществующих папок в UI.
- **Фильтр временных папок** при переносе и при записи. Перенос переносит список как есть (вопрос Q1 в design.md).
- **Остальные настройки app в `shared_preferences`.** Снимок рабочего места, профиль по умолчанию, раскладка, язык, оформление и флаг onboarding по-прежнему зависят от идентификатора бандла. Их перенос относится к задаче 9.4.
- **Изменения ACP:** новых методов, полей и `_meta` нет. Агентская сторона (`codelab_agent_*`, `codelab_embedded`, `codelab_setup`) не меняется.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `acp-client-kit` — «IO-адаптеры клиента»: `JsonFileRecentProjectsStore` получает путь `$CODELAB_HOME/recent_projects.json` и становится общим файлом CLI и app; `SharedPreferencesRecentProjectsStore` больше не упоминается. Новое требование «Хранилище недавних проектов в CODELAB_HOME»: формат, строгое чтение, отказ перезаписывать нечитаемый файл, сериализация в процессе, `mergeRecentProjects`.
- `agent-workbench-ui` — «Recent projects persist across app restarts»: список общий с CLI, перенос из прежнего хранилища, поведение при нечитаемом файле и недопустимом `CODELAB_HOME`.
- `codelab-cli` — новое требование «Недавние проекты CLI»: когда CLI пишет проект, когда не пишет, сбой записи.

## Impact

- **Пакеты:** `codelab_client_core` (функция `mergeRecentProjects`, doc-комментарий порта), `codelab_client_io` (`JsonFileRecentProjectsStore`: версия, строгое чтение, очередь операций, метод `merge`), `apps/codelab_cli` (`CodelabHome.recentProjectsFile`, запись в REPL и TUI, PTY-помощник e2e), `apps/codelab_desktop` (привязка, перенос, удаление `SharedPreferencesRecentProjectsStore`, тестовая сборка).
- **Зависимости:** новых нет. Allowlist `codelab_client_io` и `codelab_cli` не меняется, правило сторожа не добавляется, граф пакетов в `README.md` прежний (design.md, D10).
- **Данные пользователя:** при первом запуске новой версии app ключ `codelab.recent_projects` переносится в файл и удаляется. Откат на прежнюю сборку app покажет пустой список недавних. Файл и профили при этом не затрагиваются.
