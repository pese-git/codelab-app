## Why

Панель Protocol дока (change `redesign-workbench-shell`, D5) сейчас — две половины одной колонки: карточки «Inspector» и встроенный `FluentLogViewer`. Карточки строит `InspectorProjection` из снимка последнего хода сессии в фокусе: одобрения, вызовы, обновления. Это записи приложения, а не кадры JSON-RPC: по ним нельзя увидеть, что клиент отправил агенту и что получил, в каком порядке и в каком соединении. Инструмента «что было на проводе» в app нет (R-23, `agent-parity-goals.md`; экраны 18 и 18a, `docs/design/claude-design/Inspector.dc.html`, `InspectorLog.dc.html`).

Макет 18/18a задаёт панель-инспектор протокола: виды Frames и Log с переключателем, таблицы с фильтрами, панель выбранного кадра или записи под перетаскиваемым разделителем, общие Pause, Clear и Export в шапке дока, сочетания Cmd/Ctrl+Shift+I, Alt+←/→ и Alt+↑/↓.

По пути вскрылись два дефекта безопасности, которые макет прямо оговаривает («Release builds keep metadata only. Secrets are masked before a frame is stored»):

1. **Полный payload в release.** Трасса `protocol_message` (`AcpClientApplication._traceProtocolMessage`) всегда несёт `payload`, а sink встроенного журнала (`debug-panel`, `configureCodeLabLogging`) принимает категорию `protocol` безусловно (`replace-debug-log-panel-with-fluent`, решение 5). Значит, release-сборка держит в памяти и показывает полные кадры: промпты, содержимое файлов, вывод инструментов. Это нарушает OBS-005 (`observability.md` §62) и требование structured-logging «Protocol tracing выключен по умолчанию в release».
2. **Секрет в паре `name`/`value`.** `SecretRedactor` скрывает значение по имени поля. В ACP заголовки HTTP и переменные окружения MCP-серверов — объекты `{name, value}` (`17-Schema.md`, `HttpHeader`, `EnvVariable`). Ключ значения — `value`, поэтому `{"name": "Authorization", "value": "ghp_…"}` или `{"name": "GITHUB_TOKEN", "value": "…"}` проходят открытыми, если значение не похоже на `Bearer …` или `key=value`.

## What Changes

- **Кадры ACP на стороне клиента** (`codelab_client_acp`, design.md D2, D3). `AcpClientApplication` в единственной точке трассировки входящих и исходящих сообщений строит неизменяемый `ProtocolFrame`: порядковый номер, время, направление, поколение соединения, вид (`request`, `notification`, `result`, `error`), метод (у ответа — метод запроса), id, `sessionId`, краткая подробность (`sessionUpdate` у `session/update`, исход у ответа на `session/request_permission`, код ошибки), размер. Поток `protocolFrames`. Payload кадра маскируется до выхода из пакета и хранится только при политике `ProtocolPayloadPolicy.full`. Политика по умолчанию — `metadataOnly`. Desktop включает `full` только в debug-сборке, CLI — только с `--verbose`. Поверх базовой политики — runtime-режим Trace для кадров (D17).
- **Трасса `protocol_message` по той же политике** (D3). При `metadataOnly` запись журнала несёт направление, метод, id, вид и размер, но не `payload`. Release-сборка app больше не держит полные кадры в журнале никогда, а в буфере кадров — только в явно включённом режиме Trace.
- **Правило пары `name`/`value`** (D4). `SecretRedactor` скрывает `value` объекта, у которого `name` подпадает под правило секретных имён. Это расширение существующего правила, а не второй набор правил.
- **Буфер кадров** (`codelab_client_core`, D5). `ProtocolFrameLog` — ограниченный буфер на соединение: 2000 кадров и 8 MiB payload. Владелец — `ClientWorkspace`. Буфер переживает переподключение (кадры помечены поколением), очищается `clear()`, относит запрос `session/new` к сессии из его результата (D6) и управляет режимом Trace: выключение снимает payload со всех кадров (D17).
- **Режим Trace** (D17; решение пользователя 2026-11-22 «при trace показывать все данные»). Переключатель `Trace` панели Protocol в release-сборке: пока он включён, кадры хранят и показывают полные payload (в том числе сырые аргументы и результаты вызовов), секреты по-прежнему замаскированы. Выключен при каждом запуске, не сохраняется; выключение снимает payload из памяти; журнал и `protocol.log` не меняет. Видимая индикация — InfoBar `Trace on: full payloads.`, событие `protocol_pane.trace`.
- **Область — сессия в фокусе** (D6; решение пользователя 2026-11-22). Оба вида показывают сессию в фокусе и элементы соединения без сессии (`initialize`, события подключения) с тегом `connection`; при смене фокуса панель следует за ней; без фокуса — только элементы соединения. Выбора сессии и колонки `Session` нет.
- **Панель Protocol по макету** (`apps/codelab_desktop`, `codelab_ui`, D1, D6–D13, отступления — D13):
  - шапка дока с вкладкой Protocol и CommandBar `Pause` / `Clear` / `Export…` (в release — ещё `Trace`);
  - переключатель видов `Frames` и `Log` со счётчиками и подсказкой сочетаний;
  - Frames: поиск `Filter by method, id or text`, переключатели `Requests`, `Notifications`, `Errors only`, таблица «направление | Method | Id | Time»;
  - под таблицей перетаскиваемый горизонтальный разделитель и панель выбранного кадра: заголовок, теги направления и размера, `Copy`, InfoBar о политике сборки, JSON кадра с подсвеченными замаскированными значениями;
  - Log: тот же `LogBuffer`, что у полноэкранного просмотра, поиск, категория, уровень; таблица «Time | Level | Category | Event»; панель записи с полями корреляции и ссылкой `Show frame in Frames`; кнопка `Expand` открывает прежний полноэкранный просмотр;
  - подвал `Panes follow the focused session · <сочетание>`.
- **Export** (D10). Видимые в активном виде кадры или записи сохраняются в JSON Lines через системный диалог сохранения (новый порт `ProtocolExportSaver` по образцу `UsageCsvSaver`). Если в наборе есть кадры с payload (debug-сборка или Trace), перед диалогом — подтверждение. Сбой записи — заметка `Couldn't save the file.`.
- **Клавиатура** (D11). Cmd/Ctrl+Shift+I открывает и закрывает панель Protocol (`dart-agent-and-clients` §12.3, шаг 3). Alt+←/→ выбирают предыдущий и следующий кадр, Alt+↑/↓ — запись лога. Новые строки на странице «Keyboard».
- **Карточки Inspector уходят из app** (D9). Одобрения, вызовы, их риск и статус уже есть в строке вызова ленты, обновления хода — теперь кадры. Сырые аргументы и результат вызова без одобрения в release-сборке видны только в режиме Trace (решение пользователя 2026-11-22, Q8). `CodeLabShellState.inspectorEntries`, `inspector_pane.dart` и `debug_log_pane.dart` удаляются. `InspectorProjection` в `codelab_client_core` остаётся (решение пользователя 2026-11-22, Q4).
- **`/logs`** открывает панель Protocol на виде Log. Полноэкранный просмотр — кнопкой `Expand` вида Log.

### Для раздела выпуска `CHANGELOG.md`

- Панель Protocol показывает кадры ACP соединения: что клиент отправил агенту и что получил, для сессии в фокусе и самого соединения, с фильтрами, деталями кадра, копированием и экспортом в JSON Lines. Вид Log — тот же журнал, что раньше, в виде таблицы для сессии в фокусе и с переходом от записи к кадру.
- Release-сборка больше не хранит полные кадры ACP в журнале и по умолчанию в панели: только метод, id, сессию и размер. Полные кадры в панели — по переключателю `Trace`, который выключается при каждом запуске.
- Значения заголовков и переменных окружения с секретными именами (`Authorization`, `GITHUB_TOKEN`) маскируются в журнале и кадрах.

## Не входит

- **ACP.** Новых методов, полей, состояний и `_meta` нет. Кадр — проекция уже декодированного `JsonRpcMessage`. Подробности читаются только из полей схемы (`sessionId`, `update.sessionUpdate`, `outcome`, `error.code`, `error.message`).
- **Кадры, которые не декодировались.** Сообщение, которое транспорт не разобрал в `JsonRpcMessage`, в Frames не попадает. Ошибку разбора видно в Log, как сейчас.
- **Поздние кадры старого соединения.** При замене транспорта ядро перестаёт слушать прежний транспорт до привязки нового, а проверка поколения до трассировки остаётся защитой. В Frames их нет.
- **CLI.** `--include-acp` и `--trace-file` (`CliTrace.dc.html`) — отдельный change. CLI получает только явную политику payload в composition root, его вывод не меняется.
- **Файл `protocol.log`.** Sink, его ротация и выключенность по умолчанию не меняются.
- **Планшетная и телефонная раскладки** (`TabletProtocolFrames.dc.html`, `TabletProtocolLog.dc.html`). Панель работает в выдвижном доке, как остальные панели; отдельной вёрстки нет.
- **Сохранение состояния панели между запусками.** Вид, фильтры и положение разделителя живут до закрытия окна. Открытость панели и ширина дока сохраняются, как раньше.
- **Расширение правила секретных имён** (ревью безопасности, п. 5; решение пользователя 2026-11-23): частые имена вроде `OPENAI_KEY`, `AWS_ACCESS_KEY_ID` и userinfo в URL (`https://user:token@…`) — отдельный change; здесь правило имён не меняется, только применяется к паре `name`/`value` (D4).
- **Изменение `structured_log_fluent`.** Полноэкранный просмотр (`FluentLogViewerPage`) не меняется.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`:
  - REMOVED «Debug log — отдельная докнутая панель, не вложенная в Inspector»;
  - MODIFIED «Полноэкранный log viewer — master-detail»: открывается кнопкой `Expand` вида Log;
  - MODIFIED «Паттерны взаимодействия agent workbench»: панель Protocol показывает сессию в фокусе, записей инспектора больше нет;
  - ADDED «Панель Protocol: виды Frames и Log», «Таблица кадров», «Выбранный кадр», «Вид Log панели Protocol», «Pause, Clear и Export панели Protocol», «Режим Trace панели Protocol», «Клавиатура панели Protocol».
- `acp-protocol-client`: ADDED «Кадры ACP клиента».
- `acp-client-kit`: ADDED «Буфер кадров протокола»; MODIFIED «Диагностика без секретов»: текст сбоя в диагностике по базовой политике payload, без текста ошибки агента при `metadataOnly`.
- `structured-logging`:
  - MODIFIED «Protocol tracing выключен по умолчанию в release»: встроенный журнал release-сборки тоже без payload; Trace кадров журнал не меняет; текст ответа-ошибки агента (`error.message`, `error.data`) — payload и для диагностики; ключ `inner_cause`;
  - MODIFIED «Существующий контракт diagnostics-потока не меняется»: без ссылки на удаляемый `inspector_pane.dart`.
- `approval-safety`: ADDED «Секрет в паре name/value».
- `app-settings`: MODIFIED «Страница «Keyboard»: строки таблицы»: строки `toggle-protocol`, `protocol-frame-move`, `protocol-record-move`.
- `testing-quality`: MODIFIED «Тесты Flutter UI»: деталей инспектора больше нет.

## Impact

- **`codelab_client_acp`** (`[client]`): `ProtocolFrame`, `ProtocolPayloadPolicy`, внутренний `ProtocolFrameRecorder`, поток `AcpClientApplication.protocolFrames`, параметры конструктора `protocolPayloads` и `clock`, `traceAvailable`, `setFrameTrace`, перечисления кадра, расширение `ProtocolFrameRedaction.withoutPayload()`, правило пары в `SecretRedactor` и линейное время маскирования текста, метаданные вместо сырых данных и текста ошибки агента в диагностике ошибок при `metadataOnly`, геттер `protocolPayloads`, `describeFailureMetadata`. Публичный API пакета расширяется.
- **`codelab_client_core`** (`[client]`): `AgentBackend.protocolFrames`, `AgentBackend.protocolPayloads`, `ProtocolFrameLog`, `ClientWorkspace.protocolFrames`; текст сбоя `WorkspaceDiagnostic` по политике.
- **`apps/codelab_cli`** (`[client]`): composition root передаёт `protocolPayloads` по `--verbose`.
- **`apps/codelab_desktop`** (`[desktop]`): feature `lib/features/protocol/` (`ProtocolPaneCubit`, мапперы, порт `LogRecordSource`), порт `ProtocolExportSaver` в `lib/core/platform/`, удаление `inspector_pane.dart`, `debug_log_pane.dart`, `inspectorEntries`; `ShellDiagnostics.recordFailure` (журнал сбоев без текста агента при `metadataOnly`); привязки сочетаний; ARB `en`/`ru`.
- **`codelab_ui`** (`[desktop]`): `CodeLabDockTab.actions`, ось у `CodeLabResizeHandle`, организм `CodeLabProtocolPane`, записи каталога `CodeLabShortcut`.
- **Сторож** (`[desktop]`): правило для `apps/codelab_desktop/lib/features/protocol/application`.
- **`[protocol]`, `[agent]`** — задач нет: модели ACP, транспорты, фикстуры и ядро агента не меняются.
- **Документы**: `docs/architecture/observability.md` §14, §27, §48, §49; `acp-boundary.md` §35; `l10n-glossary.md`; `proposals/dart-agent-and-clients/12-3-desktop-display.md` (DSK-18, экран 18); `apps/codelab_desktop/AGENTS.md`, `packages/dart/codelab_client_core/AGENTS.md`, `packages/flutter/codelab_ui/AGENTS.md`; руководство app (`docs/user/`) и `doc/` app — `docs-writer`.
- **Зависимости**: новых нет. Граф пакетов в `README.md` не меняется.
