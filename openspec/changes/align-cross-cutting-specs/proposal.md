## Why

Аудит четырёх «сквозных» спецификаций — `structured-logging`, `workspace-architecture`, `testing-quality`, `approval-safety` — показал две проблемы.

1. **Они устарели относительно кода.** Документы `docs/architecture/*.md` с абзацами «В коде» актуальны, а спеки — нет. Примеры:
   - `structured-logging` требует поле `outcome`, которого в записях нет, и предел истории диагностики «в рамках сессии», которого нет (`AcpSession.diagnostics` растёт без предела);
   - `workspace-architecture` описывает один composition root вместо трёх, CherryPick v4 для всех и обязательный `fpdart`, хотя сторож запрещает `fpdart` ядру агента и `codelab_client_core`; перечень правил сторожа не совпадает с `rules.dart`;
   - `testing-quality` требует храповик `knownGaps`, который уже удалён из сторожа, и не знает о сужении CI по затронутому;
   - `approval-safety` требует режимы `readOnly/ask/plan/autoEdits` и запрет `bypass`. Режимы в продукте не используются (`ApprovalPolicy.decidePermission` вызывают только тесты), а запрет `bypass` противоречит спеке `agent-permissions`.
2. **Они пересказывают документы и процесс.** Принципы (SOLID, Clean Architecture), выбор технологий и процессные правила («полный `check` по просьбе», «устройство только в `release/*`») автоматически не проверяются. Повтор в двух местах расходится: так и появились устаревшие SHALL.

По `AGENTS.md` §3.1 источник истины о поведении — спека, а молча подгонять её под код запрещено (§17). Поэтому расхождения исправляются этим change.

## What Changes

**Правило разведения ролей** (design.md, D1):
- спека — только то, что проверяет тест, сторож или CI: требования со сценариями и названной проверкой;
- `docs/architecture/` — обоснование и «Где в коде»; проверяемую норму документ не пересказывает, а ссылается на требование (как `layers-and-dependencies.md` §54);
- процессные правила — только `AGENTS.md` §21; спека и `testing.md` ссылаются на него;
- одна норма — одна спека, остальные ссылаются.

**`structured-logging`** (D2):
- «Logger-абстракция» — поля, которые реально пишутся (`event`, `component`, корреляция; без `outcome`), и `avoid_print`;
- «Логирование по слоям» — протокол и транспорты сами не журналируют, метку `component` ставит `AcpClientApplication`;
- «Ограниченная история» — единственный буфер диагностики `AcpClientApplication.diagnostics` на 500 записей; поле `AcpSession.diagnostics` и копирование в него удаляются (правка кода `[client]`, D3);
- сценарий маскирования ссылается на владельца правил — `approval-safety` «Редактирование секретов», без удалённого инспектора;
- новые требования, уже покрытые тестами: маршрутизация категорий журнала по sink и текст причины сбоя по политике payload.

**`acp-protocol-client`** (D4): сценарий «Payload пропущенного обновления» учитывает политику payload — при `metadataOnly` payload не пишется, как и проверяет `payload_policy_diagnostics_test.dart`.

**`workspace-architecture`** (D5, D6):
- REMOVED «Границы Clean Architecture», «Ограничения SOLID, KISS и DRY», «CherryPick как dependency injection», «Стандартные библиотеки моделирования»: их смысл уже точнее изложен в `layers-and-dependencies.md` и `technology-stack.md`;
- «Границы пакетов monorepo» — только проверяемое: имена пакетов и web-smoke трёх точек входа (добавлен `codelab_setup`); перечень пакетов остаётся в `AGENTS.md` §5;
- «Автоматический сторож границ пакетов» приведён к `rules.dart` и allowlist-ам. Две нормы спеки были сильнее сторожа — сторож расширяется двумя правилами (D6): IO-барель `codelab_setup` в CLI запрещён во всём `lib/` и в `bin/`, кроме `run.dart`; `codelab_ui` не импортирует `desktop_drop`.

**`testing-quality`** (D7, D8):
- «Проверки workspace» — 13 шагов `check`, `web-compile` трёх точек входа, новая проверка «полный прогон CI = шаги `check`»;
- «Непрерывная интеграция» — сужение по затронутому (`ci_scope.dart`), итоговый статус `ci`, джобы без macOS; процессные правила и шаблон pull request — в `AGENTS.md` §21;
- «Встроенный режим» и «Интеграционные тесты stdio» — без правил «только в `release/*`» (ссылка на §21); `fvm dart analyze` вместо `fvm flutter analyze`;
- «Проверка доказательств матрицы целей» — без `knownGaps` (удалён из сторожа), с проверкой роли `agent` у фикстуры;
- REMOVED «Соблюдение Definition of Done» (процесс) и «Характеризационные тесты фасада приложения» (перенос `extract-acp-client-kit` завершён и заархивирован).

**`approval-safety`** и **`acp-client-kit`** (D9–D12):
- REMOVED «Режимы разрешений»: режимы разрешений — у агента (`agent-permissions`); мёртвые `PermissionMode` и `decidePermission` удаляются из `codelab_client_acp` (`[client]`);
- «Риск вызова неизвестного вида» и kit «Неизвестный уровень риска вызова»: вместо «решения режима разрешений клиента» — реальная автоматическая политика клиента, `--approve read-only` CLI;
- «Уровни риска» — шесть уровней с `unknown`, сценарий классификации вместо неисполнимого «клиент требует одобрения»;
- «Поток разрешений ACP» — дедупликация повторного запроса и fail closed при внутренней ошибке обработки запроса (ответ `cancelled`); на оба есть тесты;
- «Редактирование секретов» — перечень мест маскирования без «персистентного состояния», с кадрами протокола клиента (панель Protocol, Copy, экспорт); журналы сессий до 1.0 не маскируются (`codelab-cli`); видимость промптов в журнале задаёт политика payload (`structured-logging`);
- «Review-first изменения» — явное исключение для `fs/*` и `terminal/*` (`AGENTS.md` §10);
- agent-workbench-ui «Выбор значения селектора отправляется агенту» — ссылка на удалённые клиентские режимы заменена ссылкой на режимы агента (`agent-permissions`), иначе после REMOVED она повисла бы.

**Документы и процесс** (задачи `[docs]`):
- `observability.md`, `permissions.md`, `layers-and-dependencies.md`, `technology-stack.md`, `testing.md` вместо пересказа ссылаются на требования; в них переносится смысл удалённых требований, где его ещё нет;
- `AGENTS.md` §21 и `.github/pull_request_template.md` приводятся к правилу проверки затронутого. Шаблон сейчас требует «`melos run check` зелёный локально». Отдельные задачи, одобрены пользователем 2026-11-24.

## Не входит

- Новые функции продукта, новые методы, поля и semantics ACP.
- Изменение политики payload, кадров и панели Protocol: это change `redesign-protocol-pane`. Два его MODIFIED-требования `structured-logging` («Protocol tracing выключен по умолчанию в release», «Существующий контракт diagnostics-потока не меняется») здесь не трогаются.
- Правила имён секретов: change `extend-secret-name-redaction`. Здесь меняются только первый абзац, сценарий debug-лога и сценарий «Отображаются переменные окружения» (сужен под тест задачи 5.2) требования «Редактирование секретов». Текст правил переносится из его дельты без изменений; при сверке 7.1 эти три места — правки этого change (design.md, D11).
- Единые имена полей диагностики (camelCase-ключи в контексте, `observability.md` §60) и текст ошибки в `attempt_superseded` — отдельный change позже (решение пользователя 2026-11-24).
- Замена повторов норм ссылками в соседних спеках (`acp-protocol-client`, `acp-client-kit`, `agent-workbench-ui`, `app-settings`, `acp-golden-fixtures`): таблица владельцев (design.md, D13) принята; замена — следующим change после архивации `redesign-protocol-pane`, `add-file-tree-ignore-watch-follow` и `remove-recent-projects-migration`.
- Правка дельты активного change `switch-default-agent-to-dart` (`knownGaps`): не правится, только сверка перед его архивацией (задача 7.3).
- Сужение `web-compile` по мостам в CI — открытый pull request #467; спека описывает `develop` без опоры на него.
- Показ diff в карточке одобрения — отдельный change (расширение `ToolCallView`/`PendingApprovalView`, виджет diff в `codelab_ui`). Здесь сценарий «Запрошена правка файла» (approval-safety «Review-first изменения») описывает только проверенное тестами: заголовок вызова, путь файла и команду до ответа (design.md, D12).
- Новые кандидаты без теста (ответ `cancelled` на запрос разрешения без активного хода, sink пересылки на dev-сервер без категории `protocol`, правила CLI для `codelab_acp_testing` и `dart_tui` на барель и `bin/`, группы concurrency CI, абсолютный `CODELAB_TEST_REPORT_DIR`) в спеку не входят. Они перечислены в design.md (D14) как будущие требования.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `structured-logging` — MODIFIED «Logger-абстракция вместо print/debugPrint», «Маскирование секретов в structured-выводе», «Логирование по слоям согласно ownership», «Ограниченная (bounded) история diagnostic-событий»; ADDED «Маршрутизация категорий журнала по sink», «Причина сбоя в диагностике по политике payload».
- `acp-protocol-client` — MODIFIED «Жизненный цикл prompt turn».
- `workspace-architecture` — MODIFIED «Границы пакетов monorepo», «Автоматический сторож границ пакетов», «Плагин перетаскивания из ОС только в адаптере платформы»; REMOVED «Границы Clean Architecture», «Ограничения SOLID, KISS и DRY», «CherryPick как dependency injection», «Стандартные библиотеки моделирования».
- `testing-quality` — MODIFIED «Проверки workspace», «Интеграционные тесты stdio», «Непрерывная интеграция», «Встроенный режим в e2e и conformance», «Проверка доказательств матрицы целей»; REMOVED «Соблюдение Definition of Done», «Характеризационные тесты фасада приложения».
- `approval-safety` — MODIFIED «Уровни риска», «Поток разрешений ACP», «Редактирование секретов», «Review-first изменения», «Риск вызова неизвестного вида и смены режима»; REMOVED «Режимы разрешений».
- `acp-client-kit` — MODIFIED «Неизвестный уровень риска вызова».
- `agent-workbench-ui` — MODIFIED «Выбор значения селектора отправляется агенту» (только ссылка на режимы разрешений).

## Impact

- **Код:**
  - `packages/dart/codelab_client_acp`: удаление поля `AcpSession.diagnostics` и копирования диагностики в сессии, перегенерация `domain_models.freezed.dart` (D3); удаление `PermissionMode`, `PermissionModeDecision`, `decidePermission`, `requiresExplicitApproval` и их тестов (D9). Это изменение публичного API пакета, в том числе типа `AcpSession`; потребителей вне тестов нет;
  - `packages/dart/codelab_architecture_tests`: два правила `rules.dart` (D6), тест «полный прогон CI = шаги `check`» и тест «в `ci.yml` нет macOS-джобов» (D7).
- **Граф пакетов** (`README.md`) не меняется. Новых пакетов и зависимостей нет.
- **Документы:** `docs/architecture/observability.md`, `permissions.md`, `acp-boundary.md`, `layers-and-dependencies.md`, `technology-stack.md`, `testing.md`; `README.md` пакетов `codelab_client_acp` и `codelab_architecture_tests`; `AGENTS.md` §21 и `.github/pull_request_template.md` (одобрено пользователем 2026-11-24).
- **Порядок архивации** (D15): после `extend-secret-name-redaction` и `redesign-protocol-pane`; с `switch-default-agent-to-dart` (архивируется с `--skip-specs`) порядок свободный, но его задача 4.8 не должна возвращать `knownGaps` в главную спеку.
