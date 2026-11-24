## Context

Состояние `develop` на 2026-11-24, ветка `feature/align-cross-cutting-specs`.

Аудит сверял четыре спеки с кодом и документами:
- `structured-logging` ↔ `docs/architecture/observability.md`;
- `workspace-architecture` ↔ `layers-and-dependencies.md`, `technology-stack.md`;
- `testing-quality` ↔ `testing.md`, `AGENTS.md` §21;
- `approval-safety` ↔ `permissions.md`, `AGENTS.md` §10.

Документы после переводов и сверки (коммиты `docs:` ноября 2026) содержат абзацы «В коде» и точнее спек. Спеки отстали: часть их SHALL описывает удалённый или никогда не существовавший код (`outcome`, `knownGaps`, `PermissionMode` в продукте, inspector), часть — принципы и процесс без автоматической проверки.

Активные changes на тех же спеках:

| Change | Состояние | Пересечение |
|---|---|---|
| `redesign-protocol-pane` | 45/46, открыта U.2 (вычитка `ru`) | MODIFIED `structured-logging` «Protocol tracing выключен по умолчанию в release» и «Существующий контракт diagnostics-потока не меняется»; ADDED `approval-safety` «Секрет в паре name/value», `acp-protocol-client` «Кадры ACP клиента», `acp-client-kit` «Буфер кадров протокола»; MODIFIED `testing-quality` «Тесты Flutter UI» |
| `extend-secret-name-redaction` | ✓ Complete, не заархивирован | MODIFIED `approval-safety` «Редактирование секретов» |
| `switch-default-agent-to-dart` | 51/57 | ADDED `testing-quality` «Проверка доказательств матрицы целей», «Машинные отчёты прогонов», «Ночная проверка доказательств в CI». Дельты уже слиты в главные спеки (задача S.1); архивация — `--skip-specs` (задача 4.8) |
| PR #467 (не change) | открыт | `web-compile` в суженном CI для `codelab_embedded` и `codelab_setup` (`ci_scope.dart`) |

Этот change не модифицирует ни одного требования, которое модифицируют другие активные changes. Исключение — «Редактирование секретов»: его меняет и `extend-secret-name-redaction` (D11, D15).

## Goals / Non-Goals

**Goals:**
- каждое оставшееся SHALL четырёх спек верно для `develop` и названо вместе с проверкой (тест, правило сторожа, CI);
- принципы, выбор технологий и процесс уходят из спек в документы и `AGENTS.md`; документы ссылаются на требования, а не пересказывают их;
- там, где норма спеки сильнее кода и норма правильная, код догоняет норму минимальной правкой (D3, D6, D9).

**Non-Goals:**
- новое поведение продукта, ACP, UI;
- правки чужих активных changes (решения Q4, Q5);
- массовая чистка повторов в соседних спеках (D13 — следующий change).

## Decisions

### D1. Разведение ролей: спека, документ, `AGENTS.md`

| Что | Где живёт | Кто ссылается |
|---|---|---|
| Проверяемая норма: есть тест, правило сторожа или проверка CI | `openspec/specs/<capability>/spec.md`, требование со сценарием, в котором названа проверка | документы: «требование — spec `<capability>` «<имя>»» (образец — `layers-and-dependencies.md` §54) |
| Обоснование, альтернативы, «Где в коде», что сторож не проверяет | `docs/architecture/*.md` | спека — «подробности — `<документ>` §N» |
| Принцип и выбор технологии без автоматической проверки (SOLID, Clean Architecture, Cherrypick, `fpdart`) | `AGENTS.md` §4–§6, §13; `layers-and-dependencies.md`; `technology-stack.md` | — |
| Процесс: что запускать перед pull request, правила по типам веток, полный `check` по просьбе, DoD, чек-лист pull request | только `AGENTS.md` §17–§22; шаблон `.github/pull_request_template.md` следует §21 | спека и `testing.md` — ссылкой на §21 |
| Одна норма в нескольких спеках | одна спека-владелец | остальные — ссылкой (D13) |

Правило проверяемости: SHALL остаётся в спеке, если его нарушение роняет тест, сторож или CI. Если проверки нет, но норма правильная и проверка дешёвая — добавляется проверка (D6, D7). Иначе норма уходит в документ.

Изменения сценариев с названными тестами — только там, где тест есть. Где нужен новый тест, сценарий ссылается на задачу `tasks.md` этого change, а не на будущее имя теста.

Исполнитель правок `docs/architecture/**` — `codelab-architect`, метка `[docs]` в `tasks.md`: правило «сначала документ, потом код» (`codelab_agent_core/AGENTS.md`). README и `doc/` пакетов правит `docs-writer` (шаг 2а `/implement`). Правки `AGENTS.md` и шаблона pull request — отдельные задачи, одобрены пользователем 2026-11-24 (Q7).

*Альтернатива:* оставить спеки «как есть» и чинить только устаревшие SHALL. Отклонено: повтор нормы в спеке и документе и есть причина расхождений; без правила D1 они вернутся.

### D2. `structured-logging`: только то, что пишет код и проверяют тесты

- **«Logger-абстракция».** Поле `outcome` из сценария убирается: его нет ни в одной записи `codelab_client_acp` (`connection_state_changed` пишет `from`/`to`). Сценарий опирается на тест «reconnect logs the current connection_generation». Запрет `print` проверяет `avoid_print` (корневой `analysis_options.yaml`; `flutter_lints` в desktop). `debugPrint` линтер не ловит, поэтому в норме его нет: правило остаётся в `observability.md` §32.
- **«Логирование по слоям».** Формулировка «`codelab_acp_protocol` → protocol-ошибки» читалась как «пакет протокола пишет журнал». На деле протокол и транспорты не журналируют и не зависят от `structured_log`; метку ставит `AcpClientApplication` (`observability.md` §3). Фраза «presentation не дублирует trace» автоматически не проверяется и остаётся в документе (§3, §55).
- **«Маскирование секретов».** Сценарий ссылался на удалённый «UI debug-лог (inspector)». Теперь он опирается на тест «masks secrets in structured log output». Владелец правил распознавания — approval-safety «Редактирование секретов» (D13).
- **ADDED «Маршрутизация категорий журнала по sink».** Есть два теста («protocol tracing sink is off by default», «in-app viewer sink always captures…»), а в спеках норма была только косвенно. Пересылка на dev-сервер (`httpOutput`) в требование **не включена**: её тест эмитит только диагностику и не проверяет, что записи `protocol` не уходят (D14).
- **ADDED «Причина сбоя в диагностике по политике payload».** Нормы про класс ошибки во вложенной причине транспорта (`_causeDetail`, PR #456) нет ни в одной спеке. Дельта `redesign-protocol-pane` упоминает класс ошибки только в ветках декодирования. Требование отдельное, чтобы не модифицировать то же требование, что и `redesign-protocol-pane`.
- **Порог 256 KiB** payload кадра в спеку этого change не входит: он уже есть в дельте `redesign-protocol-pane` (acp-protocol-client «Кадры ACP клиента»).

### D3. Предел `AcpSession.diagnostics`

Сейчас `_recordDiagnostic` дописывает каждую запись в общий буфер на 500 (`_maxDiagnostics`) и в `AcpSession.diagnostics` **каждой** известной сессии — без предела (`acp_client_application.dart`, ~2853–2857). В `lib/` список сессии никто не читает: проверено поиском по `packages/` и `apps/`.

| Вариант | Что | За | Против |
|---|---|---|---|
| A | список сессии ограничивается тем же `_maxDiagnostics`, старейшие вытесняются | минимальная правка, публичный API `AcpSession` не меняется; норма «буфер ограничен» (`observability.md` §29, OBS-004) выполняется | копия диагностики во всех сессиях и лишний `sessionChanges` на каждую запись остаются |
| B | переформулировать требование на общий буфер, код не трогать | ноль кода | неограниченный рост памяти в долгой сессии остаётся; нарушение §29 узаконивается в спеке — против приоритета 4 (`AGENTS.md` §2) |
| C | перестать копировать диагностику в сессии, удалить поле `AcpSession.diagnostics` | убирает и память, и лишние события сессий | изменение публичного API `codelab_client_acp` и Freezed-модели; §19 — без необходимости не менять public API |

**Решение пользователя 2026-11-24 (Q2): вариант C.** Поле `AcpSession.diagnostics` и копирование в `_recordDiagnostic` удаляются. Обоснование:
- поле в продукте никто не читает: app и CLI берут диагностику из `ClientWorkspace.diagnostics` и потока `AcpClientApplication.diagnosticChanges`;
- запись копируется во все открытые сессии без связи с сессией — в снимке сессии она ничего не значит;
- список растёт без предела;
- на каждую запись `_storeSession` публикует `sessionChanges` для всех сессий — лишние события и пересборка проекций.

Требование «Ограниченная (bounded) история» переписано: единственный буфер — `AcpClientApplication.diagnostics` на 500 записей, снимок сессии диагностику не несёт. Изменение публичного типа `AcpSession` (Freezed): `domain_models.freezed.dart` перегенерируется; файл отслеживается git в обход `.gitignore`, новую версию коммитят вместе с кодом.

### D4. Сценарий «Payload пропущенного обновления» (`acp-protocol-client`)

Сценарий требует полный payload в `category=protocol` всегда, а код при `metadataOnly` его не пишет (`payload_policy_diagnostics_test.dart`, группа «неподдерживаемый sessionUpdate»). Расхождение внёс `redesign-protocol-pane` (D3 того change), но его дельта этот сценарий не модифицирует: противоречие переживёт его архивацию.

| Вариант | За | Против |
|---|---|---|
| **A (выбран)** — MODIFIED «Жизненный цикл prompt turn» в этом change | чужой активный change не трогается; дельта готова и проходит `validate` | между архивацией `redesign-protocol-pane` и этого change в спеке остаётся противоречие |
| B — дописать MODIFIED в `redesign-protocol-pane` до его архивации | норма меняется в том же change, что её поменял; противоречия нет ни дня | правка чужого активного change, требует решения пользователя |

**Решение пользователя 2026-11-24 (Q4): вариант A** — MODIFIED `acp-protocol-client` остаётся в этом change.

### D5. `workspace-architecture`: принципы — в документы

REMOVED «Границы Clean Architecture», «Ограничения SOLID, KISS и DRY», «CherryPick как dependency injection», «Стандартные библиотеки моделирования». Сверка, что смысл не теряется:

| Удаляемое | Где уже есть (и точнее) | Чего не хватает — задача |
|---|---|---|
| Domain/Application не зависят от Presentation и Infrastructure; порты | `AGENTS.md` §6; `layers-and-dependencies.md` §3, §15–§18, §34 | — |
| Composition root | `layers-and-dependencies.md` §24 (три корня), термины в шапке | — |
| Узкая ответственность, без god-сервисов, без преждевременных абстракций | `AGENTS.md` §13, §14 | — |
| Централизация кодеков, переходов состояний, UI-примитивов | `layers-and-dependencies.md` §5, §7, §8, §45–§47, §52 | `codelab_ui/atomics` как место примитивов — проверить §8, при отсутствии добавить строку (задача 6.3) |
| CherryPick, жизненный цикл root scope, без сервис-локатора в domain | `technology-stack.md` §9–§9.2; `layers-and-dependencies.md` §23, §38 | закрытие root scope при выходе — `concurrency.md`/`platform-integration.md` (уже описано, change `add-client-process-shutdown-on-exit`); сослаться из §9.1 (задача 6.3) |
| `fpdart` для восстановимых результатов, Freezed для union-состояний | `layers-and-dependencies.md` §39, §40; `technology-stack.md` §10, §11; `AGENTS.md` §8, §15 | — |

«Границы пакетов monorepo» сужается до проверяемого: имена пакетов (`package_naming_test.dart`) и web-smoke трёх точек входа. Добавляется сценарий `codelab_setup`: точка есть в скрипте `web-compile`, а в спеке не было. Из требования уходят:
- перечень пакетов (дублирует `AGENTS.md` §5 и уже устарел: не было `codelab_setup`, `codelab_desktop` назван пакетом);
- «`bin/` содержит только точку входа» — не проверяется;
- «ни один `packages/dart/*` не импортирует Flutter» — не проверяется для `codelab_acp_protocol` и `codelab_acp_testing` (`layers-and-dependencies.md` §42).

Чистота пакетов без общего правила остаётся нормой `AGENTS.md` §5. Новое общее правило сторожа «`packages/dart/*` без `package:flutter/`» возможно, но это расширение охвата, а не исправление расхождения. Оно вынесено в D14.

### D6. Сторож: требование = `rules.dart`; две нормы сильнее сторожа — сторож догоняет

«Автоматический сторож границ пакетов» переписан по таблице `rules` и константам `*Allowlist`. Добавлены правила, которых в спеке не было:
- основной барель транспортов web-безопасен;
- `codelab_client_acp` — `webUnsafe` без allowlist;
- запечатанные тестовые и сценарные слои `codelab_agent_io` и `codelab_embedded`;
- `bin/` CLI;
- адаптеры платформы desktop: `file_selector`, `url_launcher`, `system_theme`, `pty2`, `dart:ffi`, терминальные пакеты, транзитивные пакеты markdown;
- чистота application фич `terminal`, `usage`, `protocol` и фичи `project_files`;
- markdown в ките;
- `package_naming_test`, HOST-6.

`ui_literals_test.dart` сюда не входит: это норма локализации, её владелец — `app-settings` «Локализация интерфейса app» (D13).

Две нормы спеки были сильнее сторожа:

| Норма | Сторож сейчас | Решение |
|---|---|---|
| `codelab_setup/io.dart` в CLI — только `lib/src/run.dart` | правило на `apps/codelab_cli/lib/src`; барели `lib/*.dart` и `bin/` не охвачены (`layers-and-dependencies.md` §42) | **сторож расширяется**: правило на `apps/codelab_cli/lib` с `exclude: ['src/run.dart']`, `package:codelab_setup/io.dart` — в правило `apps/codelab_cli/bin`. Код CLI уже соответствует (импорт только в `run.dart`), тест красный только на временном дереве |
| `codelab_ui` не зависит от `desktop_drop` | не проверяется | **сторож расширяется**: правило `packages/flutter/codelab_ui/lib` с `package:desktop_drop/`; в `pubspec.yaml` кита плагина нет |

*Альтернатива:* ослабить спеку до охвата сторожа. Отклонена: обе нормы правильные (`AGENTS.md` §5, §11), а проверка — по строке в `rules.dart`.

Исполнители по зонам: правило CLI — `[client]` (`client-engineer`, зона `apps/codelab_cli`), правило кита — `[desktop]` (`desktop-engineer`, зона `codelab_ui`). Правило сторожа правит тот, чью границу оно описывает (`CLAUDE.md`).

Что требование не охватывает, — по-прежнему таблица `layers-and-dependencies.md` §42. Документ ссылается на требование, а не перечисляет правила второй раз (задача 6.3).

### D7. `testing-quality`: CI и `check` по фактам `ci.yml` и `ci_scope.dart`

- **«Проверки workspace».** 13 шагов `check` по `pubspec.yaml` (было 7). `web-compile` — три точки web-smoke. Сценарий «Протокол изменился — запускается `protocol-conformance`» — процессный; его проверяемую часть (корпус затронутого ACP-слоя в CI) покрывает `ci_scope_test` «conformance runs only the corpora of the affected ACP layers».
- **Новый тест «полный прогон CI = шаги `check`»** (`ci_scope_test.dart`): множество скриптов `fullJobs` равно шагам `check` из `pubspec.yaml`. Сейчас совпадение проверено частично (тесты «the full run has the embedded jobs…», «…the l10n job…»). Сегодня тест зелёный сразу; он стережёт расхождение скрипта `check` и CI, после которого сужение по затронутому молча теряло бы проверку.
- **Новый тест «в `ci.yml` все джобы на `ubuntu-latest`»** (`ci_scope_test.dart`): строковая проверка строк `runs-on:`. Скрипты джобов приходят из `fullJobs` и проверяются тестом выше. Норма «джобов на macOS нет» была в спеке, но не проверялась.
- **«Непрерывная интеграция»** описывает охват по `ciScope` и тестам `ci_scope_test.dart`. Неверное «`e2e-cli-dart` на любом pull request» убрано. Причины полного прогона задаёт `ci.yml` (`FULL_REASON`): любое событие, кроме `pull_request`, pull request в `master` и из `release/*`. Поэтому сужение действует для любого другого pull request, а не только `feature/*`/`hotfix/*` → `develop`. Спека описывает то, что делает код. Различие с формулировкой `testing.md` §74 и `AGENTS.md` §21 («из `feature/*` и `hotfix/*` в `develop`») безопасно: других веток процесс не предполагает. В документах уточняется (задача 6.4).
- **PR #467.** Сценарий про `web-compile` в суженном прогоне сформулирован так, что верен до и после #467: «изменение ядра агента или пакета, от которого оно зависит, добавляет `web-compile`». Утверждения «изменение `codelab_embedded` не добавляет `web-compile`» в спеке нет. Если #467 влит до реализации, строку списка «`web-compile` — …» в требовании «Непрерывная интеграция» стоит дополнить мостами (задача 7.2).
- **Группы concurrency** ночного прогона и `workflow_dispatch` в спеку не входят: их проверяет только наблюдение за запусками, тест по YAML был бы хрупким (D14). Норма остаётся в `testing.md` §74.

Исполнитель тестов `codelab_architecture_tests` и `tool/ci` — `[protocol]`. Так сделано в `switch-default-agent-to-dart`; отдельной зоны у CI в `CLAUDE.md` нет.

### D8. Процесс — только в `AGENTS.md` §21

- REMOVED «Соблюдение Definition of Done»: процесс, проверяет ревью.
- REMOVED «Характеризационные тесты фасада приложения»: перенос `extract-acp-client-kit` завершён (архив `2026-10-26`), правило «тексты не меняются на время переноса» больше не к чему применять. Сами тесты остаются регрессионными.
- «Интеграционные тесты stdio» и «Встроенный режим»: «прогон на устройстве только в `release/<version>`» заменено проверяемым «`test:e2e:app:*` нет в `check` и в CI» и ссылкой на §21. `fvm flutter analyze` → `fvm dart analyze` (`melos run analyze`, `AGENTS.md` §20, §21).
- **Шаблон pull request** (`.github/pull_request_template.md`) требует «`fvm dart run melos run check` зелёный локально», а §21 — проверку затронутого и полный `check` только в `release/*` или по просьбе. Шаблон приводится к §21; в спеке о шаблоне больше нет нормы (задача 6.7, одобрено пользователем 2026-11-24, Q7).
- **`AGENTS.md` §21** — уточнение, что состав `check` и охват CI заданы требованиями `testing-quality` («Проверки workspace», «Непрерывная интеграция»), а §21 задаёт только, что запускать человеку или агенту (задача 6.6, Q7).

### D9. Режимы разрешений клиента

`PermissionMode { readOnly, ask, plan, autoEdits }` и `ApprovalPolicy.decidePermission` (`codelab_client_acp/lib/src/domain/approval_policy.dart`):
- вызываются только тестами (`codelab_client_acp_test.dart`, `state_machines_test.dart`);
- `readOnly` и `ask` дают одинаковые решения;
- запрос `session/request_permission` клиент всегда отдаёт пользователю. Исключение — headless CLI со своей политикой `--approve`: она опирается на `ApprovalRiskLevel`, а не на `PermissionMode`.

Режимы разрешений принадлежат агенту (`agent-permissions`: `alwaysAsk`, `write`, `acceptEdits`, `yolo`, `autopilot`), клиент выбирает их опцией конфигурации сессии. Требование «SHALL NOT `bypass`» прямо противоречит `yolo`/`autopilot` агента.

| Вариант | За | Против |
|---|---|---|
| **A (выбран)** — REMOVED требования; удалить `PermissionMode`, `PermissionModeDecision`, `decidePermission`, `requiresExplicitApproval` и их тесты; в «Риск вызова неизвестного вида» и kit «Неизвестный уровень риска вызова» заменить «решение режима разрешений клиента» на реальную автоматическую политику (`--approve read-only`) | спека и код описывают одно поведение; мёртвый публичный API уходит (`AGENTS.md` §13) | изменение публичного API `codelab_client_acp`; потребителей вне тестов нет |
| B — REMOVED требования, код оставить | ноль кода | мёртвый API выглядит как действующая политика; README пакета вводит в заблуждение |
| C — реализовать клиентские режимы | — | дублирует режимы агента; клиентское «автоодобрение» поверх агента противоречит модели ACP, где разрешение запрашивает агент (`08-Tool Calls.md#requesting-permission`), и §10 |

Удаление — TDD без красного шага: сначала удаляются тесты мёртвого кода и проверяется, что тесты `classifyToolCall*` и `unknown_tool_kind_test.dart` покрывают сценарии требования; затем удаляется код (задачи 4.1–4.2).

**Решение пользователя 2026-11-24 (Q1): вариант A.**

### D10. «Уровни риска» и «Поток разрешений ACP»

- Уровней шесть (`unknown` — change `add-provider-setup-ui`, D27). Сценарий «деструктивное → клиент требует одобрения» неисполним для внешнего агента: одобрение запрашивает агент (`permissions.md` §58). Он заменён проверяемым сценарием классификации (`codelab_client_acp_test.dart`).
- В «Поток разрешений ACP» добавлена дедупликация запроса с тем же id: тест «ignores duplicate permission request ids» есть, нормы в спеках не было (`permissions.md` §34). Ответ `cancelled` без хода и при отмене — норма acp-protocol-client «Отмена prompt turn», здесь — ссылкой.
- **Fail closed** при внутренней ошибке обработки запроса (`_handlePermissionRequest` → `cancelled`, `permissions.md` §46) в требование **не включён**: тест `payload_policy_diagnostics_test.dart` проходит эту ветку, но ответ `cancelled` не проверяет (D14).

### D11. «Редактирование секретов»: промпты в debug-логе и «персистентное состояние»

Расхождения:
- сценарий «debug-лог скрывает промпты, если явная настройка не разрешает» не реализован как отдельная настройка. Видимость промптов в журнале задаёт политика payload `redesign-protocol-pane`: release — `metadataOnly`, нет payload; debug-сборка и `--verbose` — `full`;
- «персистентное состояние» противоречит `codelab-cli`: до 1.0 журналы сессий, промпты и вывод инструментов не маскируются, и CLI об этом предупреждает.

| Вариант | За | Против |
|---|---|---|
| **A (выбран)** — перечислить места маскирования (журнал во всех sinks, диагностика, строки инструментов); видимость промптов — ссылкой на политику payload; явно указать, что не маскируется до 1.0 | спека совпадает с кодом и с `codelab-cli`; норма о промптах живёт в одном месте (D1) | нормы «промпты скрыты всегда» нет — она и не выполнялась |
| B — реализовать настройку скрытия промптов и маскирование журналов сессий | — | новая функция продукта, вне цели change; маскирование журнала сессии меняет persistence-семантику агента (отдельный change агента) |

**Решение пользователя 2026-11-24 (Q3): вариант A** — спека приводится к факту.

Текст правил имён, счётчиков, присваиваний, адресов и PEM переносится **дословно** из дельты `extend-secret-name-redaction`: меняются только первый абзац и сценарий «Открыт debug-лог». Его заменяет «Полный payload в журнале маскируется» с тестом. Поэтому этот change архивируется **после** `extend-secret-name-redaction` (D15). Если тот change до архивации поменяет текст, задача 7.1 переносит правку сюда.

### D12. «Review-first изменения»: исключение `fs/*` и `terminal/*`

SHALL «до применения правок файлов показать diff» конфликтует с исключением `AGENTS.md` §10: `fs/write_text_file` и `terminal/*` клиент выполняет без своего гейта, компенсирующий контроль — containment. Требование переформулировано: детали показываются **до ответа на запрос одобрения агента**. Исключение и containment-сценарий записаны явно со ссылкой на acp-fs-client.

Сценарий diff в карточке одобрения app явным тестом не подтверждён (быстрый поиск по тестам app и кита не нашёл проверки diff в одобрении). Задача 5.3 — найти тест или добавить характеризационный тест `[desktop]`; сценарий команды подтверждён `approval_prompt_test.dart` CLI.

### D13. Владельцы повторяющихся норм

| Норма | Владелец | Повторы (заменить ссылкой в следующем change) |
|---|---|---|
| Разбор незнакомого `kind` вызова (wire, журнал WARN) | acp-protocol-client «Неизвестный вид вызова инструмента» | — |
| Риск незнакомого вида и `switch_mode` | approval-safety «Риск вызова неизвестного вида и смены режима» | acp-client-kit «Неизвестный уровень риска вызова» (здесь уже сокращён до ранга `unknown` и ссылки), agent-workbench-ui «Вызов смены режима и неизвестного вида в ленте» (часть про риск), acp-golden-fixtures «Фикстура неизвестного вида вызова» (только фикстура — оставить) |
| Правила распознавания секретов | approval-safety «Редактирование секретов» (+ «Секрет в паре name/value») | structured-logging «Маскирование секретов в structured-выводе» (здесь сокращено до места применения), acp-client-kit «Диагностика без секретов», app-settings «События журнала … без секретов» (перечни полей событий — свои, правила — ссылкой) |
| Ответ `cancelled` на ожидающие одобрения при отмене | approval-safety «Поток разрешений ACP» | acp-protocol-client «Отмена prompt turn» (новые запросы во время отмены — своя норма), testing-quality «Тесты core state» (сценарий «Отмена при ожидающих approval»), acp-client-kit «Отмена по признаку агента» |
| Литералы интерфейса (`ui_literals_test`) | app-settings «Локализация интерфейса app» | — |

Замена повторов ссылками в `acp-protocol-client`, `acp-client-kit`, `agent-workbench-ui`, `app-settings` в этот change не входит. Эти спеки меняют `redesign-protocol-pane`, `add-file-tree-ignore-watch-follow`, `remove-recent-projects-migration`, и правка их сценариев здесь увеличила бы риск конфликтов. **Решение пользователя 2026-11-24 (Q8):** таблица принята; замена повторов ссылками — следующим change после архивации этих трёх.

### D14. Кандидаты, не включённые в спеку

| Кандидат | Почему не сейчас | Что нужно |
|---|---|---|
| Fail closed: внутренняя ошибка обработки `session/request_permission` → ответ `cancelled` | ответ не проверен тестом | тест в `payload_policy_diagnostics_test.dart` или `application_use_cases_test.dart`, затем ADDED в approval-safety |
| Пересылка на dev-сервер (`httpOutput`) не получает `protocol` | тест не эмитит записей `protocol` | усилить тест «httpOutput sink…» созданием сессии, затем сценарий в «Маршрутизация категорий журнала по sink» |
| Группы concurrency ночного прогона и `workflow_dispatch` | проверяется только наблюдением запусков | остаётся в `testing.md` §74 |
| `CODELAB_TEST_REPORT_DIR` — абсолютный путь | нет проверки | остаётся в комментарии скрипта и `testing.md` |
| Общее правило «`packages/dart/*` без `package:flutter/`» | расширение охвата сторожа, не исправление | отдельная задача сторожа по решению пользователя |
| Единые имена полей диагностики (`observability.md` §60) и текст ошибки в `attempt_superseded` (§48а) | это изменение формата записей и политики, а не сверка | отдельный change позже (решение Q6) |

### D15. Зависимости и порядок архивации

1. `extend-secret-name-redaction` (✓ Complete) архивируется **до** этого change: дельта «Редактирование секретов» здесь включает его текст. Если архивировать в обратном порядке, его MODIFIED затрёт первый абзац этого change.
2. `redesign-protocol-pane` архивируется **до** этого change. Требования structured-logging «Причина сбоя…», MODIFIED acp-protocol-client и сценарий «Полный payload в журнале маскируется» опираются на политику payload и правило пары `name`/`value`, которые вводит он. Его MODIFIED structured-logging и этот change меняют разные требования.
3. `switch-default-agent-to-dart` архивируется с `--skip-specs` (его задача 4.8), поэтому технического конфликта нет. Но его дельта `testing-quality` до сих пор содержит `knownGaps`. Сверка 4.8 («если дельта менялась после S.1 — перенести правку в главную спецификацию») не должна возвращать `knownGaps` в главную спеку. **Решение пользователя 2026-11-24 (Q5):** чужой активный change не правится; задача 7.3 этого change — сверка перед архивацией `switch-default-agent-to-dart`: главная спека остаётся без `knownGaps`.
4. PR #467: независим. Задача 7.2 сверяет требование «Непрерывная интеграция» после его merge.
5. Строки `## Purpose` спек дельтой не меняются. При архивации (задача 8.2) `codelab-architect` правит Purpose `workspace-architecture` (убрать CherryPick, `fpdart`, SOLID), `testing-quality` (убрать Definition of Done) и `approval-safety` (убрать «режимы разрешений MVP») — так же, как `switch-default-agent-to-dart` правил Purpose `agent-transports`.

### D16. Пакеты, слои, граф

| Пакет (ADR-0002) | Слой | Что меняется |
|---|---|---|
| `codelab_client_acp` (`client`, протокольный клиент) | `domain/approval_policy.dart`, `domain/domain_models.dart` (+ `.freezed.dart`), `application/acp_client_application.dart` | удаление мёртвого API режимов (D9); удаление поля `AcpSession.diagnostics` и копирования диагностики в сессии (D3) |
| `codelab_architecture_tests` (без стороны) | тесты сторожа | два правила `rules.dart` (D6), два теста `ci_scope_test.dart` (D7) |
| `apps/codelab_cli`, `apps/codelab_desktop`, `codelab_ui` | — | код не меняется; на них действуют новые правила сторожа |

- Направление зависимостей не меняется; новых пакетов, зависимостей и allowlist нет; граф в `README.md` не меняется.
- Новые правила сторожа — да (D6). Web-безопасность `codelab_client_acp` не затрагивается: правки — чистый Dart без новых импортов. Allowlist ядра агента (PKG-2) не затрагивается.
- ACP: новых методов, полей и состояний нет; удаляемое — клиентская локальная модель, не wire.

## Risks / Trade-offs

- **Конфликт архивации** с `extend-secret-name-redaction` и `redesign-protocol-pane` → порядок D15, задача 8.1 сверяет тексты перед архивацией.
- **Удаление публичного API `codelab_client_acp`** (D9) → потребителей вне тестов нет (поиск по `packages/`, `apps/`); README пакета обновляется в той же задаче; `fvm dart analyze` зависимых пакетов (§21).
- **Удаление поля `AcpSession.diagnostics`** (D3) — изменение публичного типа `AcpSession`: потребителей вне тестов нет (`client_fixture_conformance_test.dart:480`; контрактный тест `codelab_agent_acp` использует `AcpSession` — его `analyze` обязателен). Диагностика остаётся в `AcpClientApplication.diagnostics`, `diagnosticChanges` и журнале. Побочный выигрыш — запись диагностики больше не публикует `sessionChanges` всех сессий.
- **Расширение правил сторожа** (D6) может покраснеть на ветках других changes, если они импортируют `codelab_setup/io.dart` в барель CLI или `desktop_drop` в кит → код `develop` правилам уже соответствует; конфликт возможен только у нового кода, и это и есть цель правила.
- **Строковый тест `ci.yml`** (D7) хрупок к переформатированию workflow → проверяются только строки `runs-on:` вне комментариев, без разбора YAML-структуры; комментарии с `macOS` не мешают.
- **Race/cancellation/late events**: поведение не меняется. Предел списка не влияет на порядок применения событий и на поколение соединения.

## Решения пользователя (2026-11-24)

- **Q1** (D9) — A: удалить требование «Режимы разрешений» и мёртвый код с тестами.
- **Q2** (D3) — C: удалить поле `AcpSession.diagnostics` и копирование в `_recordDiagnostic`.
- **Q3** (D11) — A: спека приводится к факту.
- **Q4** (D4) — A: MODIFIED `acp-protocol-client` в этом change.
- **Q5** (D15 п. 3) — дельту `switch-default-agent-to-dart` не править; сверка — задача 7.3.
- **Q6** — camelCase-ключи диагностики и `attempt_superseded` — отдельный change позже.
- **Q7** — правки `AGENTS.md` §21 и `.github/pull_request_template.md` одобрены.
- **Q8** (D13) — таблица владельцев принята; замена повторов — следующим change.

Открытых вопросов нет.
