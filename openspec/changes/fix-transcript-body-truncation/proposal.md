## Why

`openspec/specs/agent-workbench-ui/spec.md`, requirement "Паттерны взаимодействия agent workbench", уже содержит сценарий "Меняется режим отображения": при переключении `summary`/`normal`/`verbose` transcript и детали tool call **меняют детализацию, не теряя данных**. Текущая реализация это нарушает: `_AcpTranscriptEntryRow` в `AcpTranscriptPanel` обрезает `entry.body` через `maxLines` (1/4/8 в зависимости от режима) и `TextOverflow.ellipsis` — при любом режиме, включая `verbose`, текст длиннее лимита строк **необратимо** теряется из UI (данных для просмотра просто нет, в отличие от, например, свёрнутого, но раскрываемого блока). До `add-streaming-message-coalescing` это было почти незаметно: каждая transcript-запись агента содержала один короткий streaming-чанк, редко достигающий даже 4 строк. После того как подряд идущие чанки стали схлопываться в одну запись (по дизайну самого ACP-стриминга — полный ответ агента), обычный многострочный ответ теперь реально обрезается многоточием — подтверждено вживую на реальном ACP-агенте. Это не новое требование, а исправление кода под уже одобренную спецификацию (см. AGENTS.md §3.1: при противоречии кода и спеки код не считается автоматически правильным).

## What Changes

- `_AcpTranscriptEntryRow` (`packages/flutter/acp_ui/lib/src/organisms/acp_transcript_panel.dart`) перестаёт применять `maxLines`/`TextOverflow.ellipsis` к `entry.body` для записей, представляющих содержательный текст диалога (`AcpTranscriptEntryKind.user`, `.agent`, `.diagnostic`) — текст рендерится полностью, перенос строк без обрезки; общая прокрутка списка (`AcpTranscriptPanel`'s `ListView.separated`) уже существует и справляется с возросшей высотой записи.
- Ограничение по `_bodyMaxLines` (1/4/8 по `AcpViewMode`) сохраняется без изменений там, где оно не приводит к потере данных о самом диалоге — в частности, `AcpToolCallSummary` (виджет `_toolCallForMode`, используемый для `.toolCall`/`.approval` записей) не тронут: его собственная логика детализации по `viewMode` не входит в это исправление.
- Режимы `summary`/`normal`/`verbose` продолжают существовать и осмысленно применяться к тем частям transcript, где сокращение действительно не теряет данные (например, к заголовкам/меткам через уже существующий `maxLines: 1` у `title`/`timestampLabel` — не трогаем).

## Capabilities

### New Capabilities
(нет)

### Modified Capabilities
(нет — существующий сценарий "Меняется режим отображения" в `agent-workbench-ui` уже корректно требует "не теряя данных"; это исправление реализации под уже одобренную спецификацию, а не изменение требований)

## Impact

- `packages/flutter/acp_ui/lib/src/organisms/acp_transcript_panel.dart`: `_AcpTranscriptEntryRow._bodyMaxLines`/body `AcpText` widget.
- Публичный API `AcpTranscriptPanel`/`AcpTranscriptEntry` не меняется (те же поля, тот же конструктор).
- Существующие widget-тесты в `packages/flutter/acp_ui/test/` и `apps/codelab_app/test/widget_test.dart`, если они полагаются на текущее обрезание длинного текста, потребуют обновления.
