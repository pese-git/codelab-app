## Context

Сегодня `WorkbenchInspectorPane` (`apps/codelab_app/lib/features/workbench/presentation/widgets/inspector_pane.dart`) — один `codelab_app`-виджет, который в одном `DecoratedBox`/`Column` рисует и список approval/tool/protocol-записей, и НИЖЕ него, как последний элемент того же `ListView`, — `AcpDebugLogPanel` (organism из `acp_ui`, `packages/flutter/acp_ui/lib/src/organisms/acp_debug_log_panel.dart`) высотой 260px, получающий `state.diagnostics` (`List<AcpDebugLogEntry>`, наполняется `CodeLabShellCubit._recordDiagnostic`, включая как presentation-события, так и переретранслированные `AcpClientApplication.diagnosticChanges` — подробности редиректа см. `add-structured-logging`).

Дизайн-исследование (`Log Viewer Integration (Fluent)`, https://claude.ai/code/artifact/42aa4f6d-552f-40a4-9128-75e5f065840e) зафиксировало целевой layout: Debug log — отдельная, персистентно видимая карточка-sibling Inspector (не вложена), докнутая компактная версия с поиском/фильтром/кнопкой Expand, и полноэкранный master-detail viewer, открываемый через `/logs` или Expand.

## Goals / Non-Goals

**Goals:**
- Развести `WorkbenchInspectorPane` на два независимых sibling-виджета: Inspector (approval/tool/protocol, без изменений в содержимом) и новый Debug log pane (structured_log-driven).
- Подключить `structured_log_flutter` (`LogBuffer`/`LogViewerController`) как дополнительный, третий `LogSink` к уже существующему `configureCodeLabLogging()` (`add-structured-logging`), не меняя контракт двух существующих sink'ов (`application`/`protocol`).
- Докнутая панель и полноэкранный viewer показывают ОДИН и тот же источник данных (`LogBuffer`), не два независимых стрима.
- Удалить `AcpDebugLogPanel`/`AcpDebugLogEntry` из `acp_ui` — заменяются полностью, не остаются как мёртвый код.

**Non-Goals:**
- ~~Показ `category=protocol` в in-app viewer'е~~ — **отменено пользователем после первичной реализации, см. Decision 5**: in-app viewer теперь безусловно захватывает и protocol-trace тоже (не только `application`); видимость — через category-селектор (view-фильтр), не через capture-toggle. Файловый `protocol.log`-sink сохраняет свой отдельный, независимый off-by-default toggle.
- Перестройка Inspector'а (approval/tool/protocol карточки) — контент и поведение этой части не меняются, меняется только то, что раньше было её частью (Debug log), а теперь стало соседом.

Изначально в эту секцию также входил пункт "не трогать `CodeLabShellCubit._recordDiagnostic`/`state.diagnostics`" — по факту реализации выяснилось, что `AcpDebugLogEntry`/`AcpDebugLogSeverity` были не только UI-типом панели, но и внутренним diagnostics-стейтом кубита (~30 call sites, ~25 test-assertions в `codelab_app/test/widget_test.dart`), поэтому Non-Goal пришлось снять — см. Decision 2's дополнение "Удаление diagnostics-стейта из `CodeLabShellCubit`" ниже.

## Decisions

### 1. `structured_log_flutter`/`structured_log_fluent` — зависимость только в `codelab_app`, не в `acp_ui`

`acp_ui` сегодня не имеет ни одной зависимости на logging-технологию (`packages/flutter/acp_ui/pubspec.yaml`: только `fluent_ui`/`flutter_bloc`/`freezed_annotation`). У нового log viewer ровно один consumer — `codelab_app` (§44 `layers-and-dependencies.md`: выносить в переиспользуемый пакет стоит, если нужно нескольким приложениям — здесь не так). Решение: обе новых зависимости добавляются только в `apps/codelab_app/pubspec.yaml`; `acp_ui` остаётся без изменений в своём dependency-графе — тот же паттерн, что уже закреплён в `add-structured-logging` Decision 1 для самого `structured_log`.

Альтернатива (отклонена): добавить в `acp_ui` как "reusable ACP UI organism". Отклонено — log viewer не является ACP-специфичным виджетом (в отличие от tool-call card/approval prompt/conversation renderer, §46), это универсальный logging UI, и единственный текущий consumer не оправдывает расширение публичного API `acp_ui`.

### 2. `AcpDebugLogPanel`/`AcpDebugLogEntry` удаляются из `acp_ui`, `WorkbenchInspectorPane` разделяется на два виджета в `codelab_app`

`WorkbenchInspectorPane` (см. Context) перестаёт рендерить `AcpDebugLogPanel` как последний элемент своего `ListView` — вместо этого:
- `WorkbenchInspectorPane` сохраняет `DecoratedBox`/заголовок/`ListView` только для `state.inspectorEntries` (approval/tool/protocol) — без изменений в содержимом.
- Новый `WorkbenchDebugLogPane` (`apps/codelab_app/lib/features/workbench/presentation/widgets/debug_log_pane.dart`) — отдельный `DecoratedBox` с собственным заголовком/поиском/фильтром/списком, driven `LogViewerController`.
- Родительский layout (там, где сегодня `WorkbenchInspectorPane` помещается в правую колонку workbench) кладёт оба виджета как siblings в `Column`/`Flex` с `gap`, как в дизайн-канве.

`AcpDebugLogPanel`/`AcpDebugLogEntry` удаляются из `acp_ui` полностью (не остаются неиспользуемыми) — вместе с их usages в `acp_ui`'s собственных preview/test файлах (`acp_organism_previews.dart`, `acp_organisms_test.dart`) и в `codelab_app/test/widget_test.dart`.

Альтернатива (отклонена): оставить `AcpDebugLogPanel` в `acp_ui` "на будущее". Отклонено — мёртвый, неиспользуемый reusable-компонент нарушает §13 AGENTS.md (пропорциональность); если понадобится generic debug-panel снова, его проще написать заново под актуальные требования, чем поддерживать неиспользуемый код.

**Дополнение, обнаруженное при реализации: удаление diagnostics-стейта из `CodeLabShellCubit`.** `AcpDebugLogEntry`/`AcpDebugLogSeverity` оказались не только UI-типом `AcpDebugLogPanel`, но и внутренним состоянием кубита: `CodeLabShellState.diagnostics`, `_recordDiagnostic()`, `clearDiagnostics()` — ~30 call sites, единственный UI-потребитель которых был тот же `AcpDebugLogPanel` в `inspector_pane.dart`. Оставить их означало бы либо мёртвый, неиспользуемый стейт (нарушает ту же §13, что и альтернатива выше), либо тихую потерю части существующей диагностируемости — 25 из 37 вызовов `_recordDiagnostic` НЕ логировались через `Logger` вообще (только копились в `state.diagnostics` для старой панели), и просто выбросить их означало бы регресс по приоритету 5 AGENTS.md (наблюдаемость).

Решение (подтверждено пользователем при выборе между тремя вариантами — таблица плюсов/минусов обсуждена в чате): `state.diagnostics`/`AcpDebugLogEntry`/`clearDiagnostics()`/подписка на `AcpClientApplication.diagnosticChanges` (`_handleApplicationDiagnostic`) удаляются из `CodeLabShellCubit` полностью; ВСЕ 37 вызовов `_recordDiagnostic` (не только прежние 12) теперь безусловно логируются через `Logger` — `logSource`-параметр убран, `source` (уже присутствующий на каждом call site) используется как context для Logger напрямую. Так `LogBuffer` становится единственным, полным источником diagnostics-событий (ничего не теряется), без параллельного, ныне бесполезного списка в состоянии кубита.

### 3. Единый `LogBuffer` — третий sink `configureCodeLabLogging()`, обе категории

`configureCodeLabLogging()` (`packages/dart/acp_client_core/lib/src/infrastructure/structured_log_logger.dart`, уже реализован в `add-structured-logging`) получает новый опциональный параметр. **Итоговая форма** (после ревизии Decision 5 — изначально `inAppViewerOutput` принимал только `category=application`, затем добавлялся условный второй sink для protocol, затем оба слились в один безусловный):

```dart
void configureCodeLabLogging({
  required structured_log.OutputFunction applicationOutput,
  required structured_log.OutputFunction protocolTraceOutput,
  structured_log.OutputFunction? inAppViewerOutput,
  bool protocolTracingEnabledByDefault = false,
}) {
  ...
  sinks: [
    LogSink(name: 'application', output: applicationOutput, categories: const {applicationLogCategory}),
    if (inAppViewerOutput != null)
      LogSink(
        name: 'debug-panel',
        output: inAppViewerOutput,
        minLevel: LogLevel.trace,
        categories: const {applicationLogCategory, protocolTraceLogCategory},
      ),
    LogSink(name: 'protocol', output: protocolTraceOutput, minLevel: LogLevel.trace, categories: const {protocolTraceLogCategory}, enabled: protocolTracingEnabledByDefault),
  ],
}
```

`inAppViewerOutput`'s sink принимает ОБЕ категории безусловно (`enabled` не выставлен → всегда `true`) — см. Decision 5 для обоснования. `CodeLabLoggingModule` (`app_scope.dart`) создаёт один `LogBuffer` (bounded ring buffer — свой собственный лимит записей, независимый от `_diagnostics`' 500 из `add-structured-logging`), передаёт `buffer.capture` как `inAppViewerOutput`, и биндит `LogBuffer` в CherryPick-scope, откуда его резолвят `WorkbenchDebugLogPane` и полноэкранный viewer — один и тот же инстанс, не два независимых стрима (каждый строит свой `LogViewerController` поверх него — см. Decision 4).

### 4. Докнутая панель встраивает `FluentLogViewer` как есть, полноэкранная — оборачивает `FluentLogViewerPage` (тонкую обёртку над тем же `FluentLogViewer`)

**История ревизий этого решения** (снизу вверх — но актуально только последнее состояние):

1. Изначально (после сверки `structured_log_fluent` `0.1.0-dev.2`): докнутая панель переиспользовала только низкоуровневые примитивы (`LogEntryTile`, `LogViewerEmptyState`) внутри собственноручно написанного `ListView.builder` + заголовка/поиска/level-фильтра — потому что `FluentLogViewerPage` тогда была монолитной `ScaffoldPage`, не параметризуемой под меньшую ширину/embedding.
2. По ТЗ, отправленному пользователем (как автором `structured_log_fluent`) в апстрим: `structured_log_fluent` `0.1.0-dev.3` вынес мастер-detail UI `FluentLogViewerPage` в отдельный **переиспользуемый embeddable widget `FluentLogViewer`** (`fluent_log_viewer.dart`) — search + category-selector (`LogCategoryComboBox`, см. Decision 5) + level-фильтр + pause/clear + responsive master-detail (адаптируется к собственной ширине через `LayoutBuilder`, а не ширине окна — подходит и для узкой докнутой панели, и для full-screen). `FluentLogViewerPage` теперь — тонкий `ScaffoldPage`-wrapper вокруг него (заголовок "Logs" + back-button, без своей копии toolbar-логики).

**Итоговое решение (`0.1.0-dev.4`)**: `WorkbenchDebugLogPane` больше не переопределяет ни поиск, ни фильтры, ни список — это `DecoratedBox` с собственным заголовком CodeLab ("Debug log" + кнопка "Expand", своя докинг-хрома) и `Expanded(child: FluentLogViewer(controller: _controller))` как тело. Весь toolbar/список/detail/пустое состояние — из пакета, ничего не задублировано. `WorkbenchDebugLogPane` теряет собственные `TextEditingController`/`ComboBox`-поля поиска и уровня — они инкапсулированы внутри `FluentLogViewer`.

Полноэкранный viewer не меняется по сути (`DebugLogViewerDialog` → `FluentLogViewerPage`), просто теперь наследует все улучшения `FluentLogViewer` (category-селектор, pause/clear-кнопки) автоматически, без отдельной реализации.

**Два независимых `LogViewerController` поверх одного `LogBuffer`, не один общий** — докнутая панель и полноэкранный viewer держат каждый свой `LogViewerController` (своё состояние `searchQuery`/`levelFilter`/`categoryFilter`/`paused` — фильтры одной панели не должны навязываться другой), но оба instance строятся над одним и тем же `LogBuffer` singleton из CherryPick-scope — это и есть "один источник данных, не два независимых стрима" из Goals (единство данных, не единство UI-состояния фильтра).

Полноэкранный viewer открывается через `showDialog` (сам пушит route → `Navigator.canPop(context)` истинен → `FluentLogViewerPage` сам показывает back-button без дополнительной обёртки); `dismissWithEsc: true`/тёмный `barrierColor` — дефолты `showDialog`, закрывают требования Esc/затемнения без дополнительного кода.

И `/logs` (командная палитра), и кнопка "Expand" докнутой панели вызывают один и тот же метод — `DebugLogViewerDialog.show(context, logBuffer)` — не два независимых пути с разным поведением.

### 5. Protocol-trace в in-app viewer'е — всегда захватывается, видимость — через category-селектор, не toggle

Пользователь явно запросил видеть `protocol.log` "аналогичным образом" в Debug Log — то есть в том же `LogBuffer`/viewer'е, что и `application`-события, а не только в отдельном файле. Пересматривает Non-Goal design.md, отклонённый изначально из-за объёма/verbosity сырых ACP-payload'ов (не из-за секретов — маскирование и так общее для всей `StructlogConfiguration`, не per-sink, см. Risks).

**История ревизий**: первая реализация добавляла второй, условный in-app sink (`debug-panel-protocol`), включаемый/выключаемый ЧЕРЕЗ ТОТ ЖЕ toggle, что и файловый `protocol`-sink (`setProtocolTracingEnabled`), плюс `ToggleSwitch` "Protocol" в заголовке докнутой панели. Пользователь предложил заменить toggle на **селектор по типу** — итоговое решение:

- `configureCodeLabLogging()`'s in-app viewer sink — **один** sink (`debug-panel`), безусловно (`enabled: true`, не привязан к `protocolTracingEnabledByDefault`) принимающий ОБЕ категории: `categories: {applicationLogCategory, protocolTraceLogCategory}`, `minLevel: LogLevel.trace` (чтобы trace-уровневые protocol-события проходили). `LogBuffer` — bounded/in-memory и проходит через тот же `secretRedactionProcessor`, что и остальные sinks, поэтому нет capture-side причины держать его отдельно gated — единственная причина исходного off-by-default была verbosity/шум, а не секреты.
- Файловый `protocol.log`-sink остаётся отдельным, со своим независимым `enabled`/`setProtocolTracingEnabled`/`isProtocolTracingEnabled` (developer opt-in для файлового трейсинга, не связан с in-app viewer'ом).
- Видимость protocol-событий в UI — не capture-toggle, а **view-фильтр**: `LogCategoryComboBox` (новый виджет `structured_log_fluent` `0.1.0-dev.3`, добавлен по ТЗ CodeLab) — динамически перечисляет distinct `category`-значения из `controller.buffer`, рендерит себя ТОЛЬКО когда их 2+ (иначе `SizedBox.shrink()` — один вариант нечего фильтровать), пишет в `controller.categoryFilter`. Встроен в `FluentLogViewer`'s toolbar, поэтому CodeLab не пишет собственный ComboBox для этого — получает его "из коробки" вместе с переходом на Decision 4.

Альтернатива (отклонена, реализовывалась первой, затем отменена по прямому запросу пользователя): единый on/off toggle, гейтящий capture И file-sink одновременно. Отклонено — переключатель гейтил СБОР данных, а не то, что видно; после отказа от toggle в пользу селектора это стало избыточным усложнением — сбор всегда включён (дёшево, bounded, redacted), а что показывать — решает `categoryFilter`, для которого инфраструктура (`LogViewerController.categoryFilter`) уже существовала и раньше просто не имела готового UI.

## Risks / Trade-offs

- [`structured_log_flutter`/`structured_log_fluent` — тот же автор/контроль roadmap, что и `structured_log`, но ещё более ранний prerelease (`0.1.0-dev.2`, `dev.1` не публиковался) — риск: API компонентов может не совпасть с тем, что описано в дизайн-референсе.] → перед реализацией (tasks) свериться с реальным исходником пакетов тем же способом, что и для `structured_log` (GitHub-репозиторий автора), а не полагаться только на текстовое описание; при расхождении — адаптировать докнутую панель под реальный API, оставаясь на согласованном визуальном направлении.
- [Удаление `AcpDebugLogPanel` из `acp_ui` — breaking change для внутренних consumers пакета (его собственные preview/test файлы).] → затронутые файлы перечислены в Decision 2, входят в scope этого change, не забыты.
- [Несколько независимых sink'ов (`application` console/file, `debug-panel` LogBuffer, `protocol` file) должны оставаться синхронными по маскированию.] → все проходят через тот же `secretRedactionProcessor` (общий для всей `StructlogConfiguration`, не per-sink) — расхождения по маскированию невозможны, независимо от того, какие категории читает каждый конкретный sink.

## Open Questions

- ~~Точный API `LogEntryTile`/`LogViewerController`/`FluentLogViewerPage`~~ — снято: сверено с реальным исходником `pese-git/structured_log` (develop), см. Decision 4.
- Способ показа полноэкранного viewer'а как overlay (`showDialog` — простейший вариант, раз он сам пушит route и тем самым включает автоматический back-button `FluentLogViewerPage`, — либо кастомный full-screen route) и способ перехвата `Esc` поверх него — конкретный Flutter-механизм выбирается на этапе реализации (tasks §6.1), ограничение только одно: закрытие не должно терять state workbench под ним (см. спеку).
