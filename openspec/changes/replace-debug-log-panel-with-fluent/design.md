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
- Показ `category=protocol` (raw ACP payload tracing) в докнутой панели/полноэкранном viewer'е по умолчанию — protocol-trace остаётся developer-only, off-by-default, file-only каналом (`add-structured-logging`, Decision 4/6). In-app viewer показывает только `category=application` (это покрывает все layer-owned события: `component=client/transport/protocol/presentation` — включая protocol-ошибки, но не сырой payload). Раскрытие protocol-trace в UI — отдельный будущий follow-up, если понадобится.
- Изменение самого `CodeLabShellCubit._recordDiagnostic`/Logger-эмиссии из `add-structured-logging` — тот механизм не трогается, `LogBuffer` — независимый, дополнительный consumer тех же structured-событий.
- Перестройка Inspector'а (approval/tool/protocol карточки) — контент и поведение этой части не меняются, меняется только то, что раньше было её частью (Debug log), а теперь стало соседом.

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

### 3. Единый `LogBuffer` — третий sink `configureCodeLabLogging()`, `category=application`

`configureCodeLabLogging()` (`packages/dart/acp_client_core/lib/src/infrastructure/structured_log_logger.dart`, уже реализован в `add-structured-logging`) получает новый опциональный параметр, например:

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
      LogSink(name: 'debug-panel', output: inAppViewerOutput, categories: const {applicationLogCategory}),
    LogSink(name: 'protocol', output: protocolTraceOutput, minLevel: LogLevel.trace, categories: const {protocolTraceLogCategory}, enabled: protocolTracingEnabledByDefault),
  ],
}
```

`inAppViewerOutput` — тот же `categories: {applicationLogCategory}`, что и консольный/файловый application-sink (не `protocolTraceLogCategory`) — см. Non-Goals. `CodeLabLoggingModule` (`app_scope.dart`) создаёт один `LogBuffer` (bounded ring buffer — свой собственный лимит записей, независимый от `_diagnostics`' 500 из `add-structured-logging`), передаёt `buffer.capture` как `inAppViewerOutput`, и биндит `LogBuffer`/`LogViewerController` в CherryPick-scope, откуда их резолвят `WorkbenchDebugLogPane` и полноэкранный viewer — один и тот же инстанс, не два независимых стрима.

### 4. Докнутая панель напрямую переиспользует `LogEntryTile`/`LogEntryDetailPane`/`LogViewerEmptyState`, полноэкранная — оборачивает `FluentLogViewerPage`

**Подтверждено чтением реального исходника** (`pese-git/structured_log`, ветка `develop`, монорепозиторий — `structured_log_flutter`/`structured_log_fluent` публикуются из него, а не из отдельных репозиториев с такими же именами):

- `LogBuffer.capture(Map<String, dynamic>, LogLevel)` — сигнатура совпадает с `structured_log`'s `OutputFunction` один в один; `buffer.capture` можно передавать в `LogSink.output` напрямую, без обёрток.
- `LogViewerController` — `ChangeNotifier` поверх `LogBuffer` с `levelFilter`/`categoryFilter`/`searchQuery`/`paused`/`clear()`/`visibleEntries` (oldest-first) — подтверждает Decision 3 as-is.
- `LogEntryTile(entry, selected, onTap)`, `LogEntryDetailPane(entry)`, `LogViewerEmptyState(hasLogs, onClearFilters)`, а также свободные функции `logLevelOf(entry)`, `formatEntryTime(raw)`, `logLevelColor(level, brightness)`, `logLevelAbbreviation(level)` — все экспортированы из `structured_log_fluent` и не зависят от `FluentLogViewerPage`. Докнутая панель (`WorkbenchDebugLogPane`) переиспользует их буквально: `ListView.builder` из `LogEntryTile` + `LogViewerEmptyState`, со своим заголовком/поиском/level-фильтром поверх собственного `LogViewerController`.
- `FluentLogViewerPage(controller)` — `ScaffoldPage` с фиксированным 340px мастер-списком и `Expanded` detail-панелью; это full-page widget, не параметризуется под меньшую ширину/embedding-режим — значит, он используется только для полноэкранного viewer'а, не для докнутой панели (что и предполагалось). Back-button в его заголовке показывается автоматически по `Navigator.canPop(context)` и скрыт, если этот widget — корень своего Navigator'а.

Отсюда — полноэкранный viewer открывается через route/dialog, при котором `Navigator.canPop(context)` истинен (например, `showDialog` — сам по себе пушит route), тогда `FluentLogViewerPage` сам покажет back-button без дополнительной обёртки поверх заголовка; обработка `Esc` как альтернативного способа закрытия — на уровне обёртки (route/dialog), не самого `FluentLogViewerPage`.

**Два независимых `LogViewerController` поверх одного `LogBuffer`, не один общий** — уточнение к Decision 3: докнутая панель и полноэкранный viewer держат каждый свой `LogViewerController` (своё состояние `searchQuery`/`levelFilter`/`paused` — фильтры одной панели не должны навязываться другой), но оба instance строятся над одним и тем же `LogBuffer` singleton из CherryPick-scope — это и есть "один источник данных, не два независимых стрима" из Goals (единство данных, не единство UI-состояния фильтра).

И `/logs` (командная палитра), и кнопка "Expand" докнутой панели вызывают один и тот же application-level метод открытия viewer'а (например, `CodeLabShellCubit`-сосед или прямой widget-level `showDialog` — конкретика на этапе tasks) — не два независимых пути с разным поведением.

## Risks / Trade-offs

- [`structured_log_flutter`/`structured_log_fluent` — тот же автор/контроль roadmap, что и `structured_log`, но ещё более ранний prerelease (`0.1.0-dev.2`, `dev.1` не публиковался) — риск: API компонентов может не совпасть с тем, что описано в дизайн-референсе.] → перед реализацией (tasks) свериться с реальным исходником пакетов тем же способом, что и для `structured_log` (GitHub-репозиторий автора), а не полагаться только на текстовое описание; при расхождении — адаптировать докнутую панель под реальный API, оставаясь на согласованном визуальном направлении.
- [Удаление `AcpDebugLogPanel` из `acp_ui` — breaking change для внутренних consumers пакета (его собственные preview/test файлы).] → затронутые файлы перечислены в Decision 2, входят в scope этого change, не забыты.
- [Два независимых sink'а (`application` console/file и `debug-panel` LogBuffer) должны оставаться синхронными по содержимому — иначе докнутая панель покажет не то же самое, что консоль/лог-файл.] → оба читают один и тот же `category=application` фильтр и оба проходят через тот же `secretRedactionProcessor` (общий для всей `StructlogConfiguration`, не per-sink) — расхождения по маскированию невозможны.

## Open Questions

- ~~Точный API `LogEntryTile`/`LogViewerController`/`FluentLogViewerPage`~~ — снято: сверено с реальным исходником `pese-git/structured_log` (develop), см. Decision 4.
- Способ показа полноэкранного viewer'а как overlay (`showDialog` — простейший вариант, раз он сам пушит route и тем самым включает автоматический back-button `FluentLogViewerPage`, — либо кастомный full-screen route) и способ перехвата `Esc` поверх него — конкретный Flutter-механизм выбирается на этапе реализации (tasks §6.1), ограничение только одно: закрытие не должно терять state workbench под ним (см. спеку).
