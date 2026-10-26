# 12.3. Десктоп-приложение: отображение

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [12.2. CLI: отображение и ввод](12-2-cli-display-and-input.md) · [Оглавление](../dart-agent-and-clients.md) · [12.4. Первый запуск и настройки](12-4-first-run-and-settings.md) →

## 12.3.1. Назначение

Раздел задаёт, как codelab-app показывает модель отображения из §12.1: markdown-ответы с
подсветкой кода (D-06), diff правок (D-07), мысли модели в сворачиваемом блоке (D-08), usage и
стоимость в статусе чата (D-09) и вложения в композере (D-12). Работа идёт после разделения
Cubit-ов (задача 5.9): app получает `SessionView` из `codelab_client_core` и только отображает его.
Логика проекции, разбора markdown (`IncrementalMarkdown`, §12.1.4), построения hunks
(`LineDiff`, §12.1.3), строки инструмента (`ToolRowFormatter`, §12.1.6), статус-строки
(`SessionStatusBar`, §12.1.5) и выбора `ContentBlock` (`PromptContentBuilder.build`, §12.1.7)
остаётся в kit.

Исходная точка в коде сегодня:

* `AcpTranscriptPanel` (`packages/flutter/codelab_ui/lib/src/organisms/acp_transcript_panel.dart`)
  рисует `List<AcpTranscriptEntry>` через `ListView.separated`. Тело агента выводится одним
  `AcpText` без разметки. Мысли и ответ склеиваются в одинаковые записи «Agent»
  (`_StreamingChunkKind` в `shell_cubit.dart`).
* Вызов инструмента показывает `AcpToolCallSummary` (имя, статус, цель, деталь) и встроенную
  карточку одобрения `AcpTranscriptApproval`. У карточки есть только текстовый `diffSummary`.
* `AcpPromptComposer` принимает только текст, команды `/` и чипы опций конфигурации.
* В `pubspec.yaml` пакетов нет markdown, подсветки, drag&drop, чтения изображений из буфера и
  открытия ссылок. Из плагинов есть только `file_selector`, он остаётся в app.

Улучшения НЕ ДОЛЖНЫ ломать существующие возможности: очередь промптов (R-18), чек-лист плана
(R-19), палитру Cmd+K (R-20), вкладки сессий со статусом (R-21), выбор проекта (R-22), инспектор
и лог-вьюер (R-23), а также встроенные одобрения с автопрокруткой (D-01, D-02).

Раздел также задаёт карту экранов app и правила навигации между ними (A13), хронологию хода
(A14, D-22) и доску субагентов и фоновых задач (A15, D-25). Макет всех экранов и граф навигации —
холст Claude Design «CodeLab Desktop — Feature UI/UX» (страница «Навигация и покрытие»); номера
экранов 01–27 ниже совпадают с номерами артбордов. Холст иллюстрирует этот раздел и §12.4; при
расхождении действует текст.

## 12.3.2. Контракт

**Размещение компонентов.** `codelab_ui` (ui_kit) содержит виджеты и собственные
презентационные модели без бизнес-логики и без зависимости от `codelab_client_core`. Feature
`workbench` содержит Cubit-ы, маппер kit → `codelab_ui` и обвязку с плагинами.

| Компонент | Пакет / путь | Слой | Ответственность |
|---|---|---|---|
| `AcpTranscriptRow` и наследники, `AcpMdBlock`, `AcpMdInline` | `codelab_ui/lib/src/models/` | ui_kit | неизменяемые модели строк ленты и markdown-блоков |
| `AcpTranscriptPanel` (расширен) | `codelab_ui/lib/src/organisms/` | ui_kit | виртуализированная лента строк, следование за хвостом, автопрокрутка к одобрению |
| `AcpMarkdownBlockView`, `AcpCodeBlock` | `codelab_ui/lib/src/molecules/` | ui_kit | один markdown-блок; код с подсветкой, языком и кнопкой копирования |
| `AcpThoughtBlock` | `codelab_ui/lib/src/molecules/` | ui_kit | сворачиваемый блок мыслей |
| `AcpDiffView`, `AcpDiffViewerDialog` | `codelab_ui/lib/src/molecules/`, `organisms/` | ui_kit | unified и side-by-side, свёрнутый предпросмотр, полный просмотр в диалоге |
| `AcpSessionStatusBar` | `codelab_ui/lib/src/molecules/` | ui_kit | модель, режим, токены, стоимость, заполнение контекста |
| `AcpAttachmentChip`, композер с вложениями | `codelab_ui/lib/src/molecules/` | ui_kit | чипы, удаление, подсветка зоны сброса |
| `AcpCodeHighlighter`, `AcpCodeTheme` | `codelab_ui/lib/src/rendering/` | ui_kit | токенизация кода (синхронно или в isolate), кеш, палитры светлой и тёмной темы |
| `TranscriptRowMapper` | `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart` | application | `SessionView` → `List<AcpTranscriptRow>` с переиспользованием неизменившихся строк |
| `ActiveSessionCubit` (из 5.9) | `.../workbench/application/` | application | строки ленты и статус активной сессии |
| `TranscriptViewCubit` | `.../workbench/application/` | application | только UI-состояние: ручное раскрытие блоков, режим diff |
| `ComposerCubit` | `.../workbench/application/` | application | черновик и вложения по сессиям, лимиты, отправка через `SessionHandle.send` |
| `AttachmentIntake`, `ClipboardAttachmentReader`, `ExternalLinkOpener` | `apps/codelab_desktop/lib/core/platform/` | infrastructure | чтение файлов и буфера, MIME, открытие URL |
| `ComposerDropZone` | `.../workbench/presentation/widgets/` | presentation | обёртка над плагином drag&drop, передаёт только пути |
| `ProjectFilesCubit` (после MVP, D-13, §12.6.8) | `apps/codelab_desktop/lib/features/project_files/application/` | application | раскрытые папки, плоский список видимых строк, предпросмотр |
| `AcpFileTree`, `AcpFilePreview` (после MVP, §12.6.8) | `codelab_ui/lib/src/organisms/`, `models/` | ui_kit | виртуализированное дерево, просмотр с подсветкой (`AcpCodeHighlighter`) |
| `ProjectFilesTab` (после MVP, §12.6.8) | `.../project_files/presentation/` | presentation | вкладка сайдбара рядом с `AcpSessionSidebar`, связь с `ComposerCubit` |
| `SessionSearchCubit` (после MVP, D-17, A12) | `.../workbench/application/` | application | владеет `SessionSearch` kit (§12.6.12): склейка ввода, фильтр даты, область, строки результатов |
| `AcpSessionSearchField`, `AcpSessionSearchResults`, `AcpSessionSearchRowData` (после MVP, A12) | `codelab_ui/lib/src/molecules/`, `organisms/`, `models/` | ui_kit | поле поиска с фильтрами даты и области; список результатов с подсветкой и сниппетами |
| `AppDestination`, `NavigationCubit` (A13) | `apps/codelab_desktop/lib/app/navigation/` | application | закрытый список экранов, текущий экран и вкладка инспектора, последняя страница настроек; переходы — только через Cubit |
| `CommandPaletteCubit` (A13, R-20) | `.../workbench/application/` | application | группы палитры: команды агента из `available_commands_update`, действия сессии, переходы, действия app; нечёткий поиск |
| `AcpTurnTimeline`, `AcpTurnStepData` (после MVP, D-22, A14) | `codelab_ui/lib/src/organisms/`, `models/` | ui_kit | вкладка инспектора «Timeline»: шаги хода, раскрытие шага до его вызовов |
| `SubagentBoardCubit`, `JobBoardCubit` (после MVP, D-25, A15) | `.../workbench/application/` | application | снимки `_codelab/subagents/*` и `_codelab/jobs/*` через kit, действия «Stop», «Kill», «Output» |
| `AcpTaskBoard`, `AcpTaskRowData` (после MVP, D-25, A15) | `codelab_ui/lib/src/organisms/`, `models/` | ui_kit | таблицы субагентов и фоновых задач, панель транскрипта ребёнка только для чтения |

**Поток состояния.**

```mermaid
flowchart LR
    subgraph Kit["codelab_client_core (чистый Dart)"]
        SV["SessionView<br/>transcript, statusBar, queue"]
        PAD["PromptContentBuilder.build"]
    end
    subgraph App["codelab_desktop / application"]
        MAP["TranscriptRowMapper<br/>кеш по identical"]
        ASC["ActiveSessionCubit<br/>rows, status"]
        TVC["TranscriptViewCubit<br/>expansion, diffLayout"]
        CC["ComposerCubit<br/>draft, attachments"]
    end
    subgraph Infra["core/platform"]
        AI["AttachmentIntake"]
        CR["ClipboardAttachmentReader"]
        LO["ExternalLinkOpener"]
    end
    subgraph UI["codelab_ui + presentation"]
        TP["AcpTranscriptPanel"]
        SB["AcpSessionStatusBar"]
        PC["AcpPromptComposer + ComposerDropZone"]
    end
    SV --> MAP --> ASC --> TP
    ASC --> SB
    TVC --> TP
    PC -- "пути, вставка, выбор файлов" --> CC
    CC --> AI
    CC --> CR
    CC --> PAD
    CC -- "SessionHandle.send" --> Kit
    TP -- "onOpenLink" --> LO
```

**Состояния Cubit-ов.** Неизменяемые; `copyWith` и `==` опущены.

```dart
// apps/codelab_desktop/lib/features/workbench/application/active_session_cubit.dart
final class ActiveSessionState {
  final SessionId? sessionId;
  final int sourceRevision;                  // SessionView.revision, из которого построены rows
  final List<AcpTranscriptRow> rows;         // результат TranscriptRowMapper
  final AcpSessionStatusData status;         // из SessionView.statusBar; UsageView.unknown → null-поля
  // план, очередь, команды, опции конфигурации — как в 5.9, без изменений
}

// .../application/transcript_view_cubit.dart — только UI-состояние, по сессиям
final class TranscriptViewState {
  final Map<String, bool> expansionOverrides; // id строки мыслей/diff → выбор пользователя
  final AcpDiffLayoutPreference diffLayout;   // auto | unified | sideBySide
  final AcpViewMode viewMode;                 // существующий summary | normal | verbose
}

// .../application/composer_cubit.dart
final class ComposerState {
  final String draft;
  final List<DraftAttachment> attachments;   // порядок = порядок добавления
  final AttachmentIntakeStatus intake;       // idle | reading(count) — явный автомат, не bool
  final AttachmentNotice? notice;            // последнее отклонение с причиной, сбрасывается
  final PromptContentPlan? plan;             // последний PromptContentBuilder.build по вложениям
}

final class DraftAttachment {
  final String id;                           // локальный, для ключей чипов
  final PromptAttachment source;             // FileAttachment | ImageAttachment, §12.1
  final PromptAttachmentView? view;          // plan.attachments[i]: вид и предупреждения; null — идёт расчёт
}
```

Предупреждения и вид вложения — типы kit (`AttachmentKindView`, `AttachmentWarningKind`,
§12.1.1); app своих не вводит.

Состояние раскрытия хранится в `TranscriptViewCubit`, а не в `State` виджета. Строки
виртуализированного списка уничтожаются при уходе с экрана, поэтому `State` виджета теряет выбор
пользователя. Это UI-состояние, а не состояние сессии. Оно не попадает в kit и не
сохраняется между запусками.

**Публичные API виджетов `codelab_ui`.**

```dart
// Строки ленты. Каждая строка неизменяема; равенство — по id и ревизии содержимого.
sealed class AcpTranscriptRow { String get id; }
final class AcpUserRow extends AcpTranscriptRow {
  final String text; final List<AcpAttachmentChipData> attachments; // только чтение
}
final class AcpAgentBlockRow extends AcpTranscriptRow {
  final String groupId;          // id исходного AgentTextItem
  final AcpMdBlock block;        // один блок верхнего уровня
  final bool isTail;             // нестабильный хвост, перерисовывается при стриме
  final bool isLastInGroup;      // показывает кнопку «Копировать ответ»
  final String Function()? copyText; // ленивый исходный markdown всего ответа
}
final class AcpThoughtRow extends AcpTranscriptRow {
  final String text;             // ThoughtItem.text как есть: мысли не размечаются (§12.1.2, шаг 7)
  final bool streaming; final Duration? duration;   // ThoughtItem.duration
}
final class AcpToolCallRow extends AcpTranscriptRow {
  final AcpToolRowData header;              // из ToolRowView (§12.1.6): glyph, label, detail, elapsed, secondary
  final AcpToolStatus status;               // зеркало ToolCallStatusView, для подписи доступности
  final List<AcpDiffData> diffs;            // из ToolDiffContent.diff (DiffView)
  final List<String>? terminalTail;         // ToolTerminalContent.output.tail
  final String? spillPath;                  // ToolTextContent.spill.path: только текст с копированием
  final AcpTranscriptApproval? approval;    // существующий тип, без изменений
}
final class AcpNoticeRow extends AcpTranscriptRow { final AcpTone tone; final String text; }

class AcpTranscriptPanel extends StatefulWidget {
  const AcpTranscriptPanel({
    required List<AcpTranscriptRow> rows,
    Map<String, bool> expansionOverrides = const {},
    ValueChanged<({String rowId, bool expanded})>? onExpansionChanged,
    AcpDiffLayoutPreference diffLayout = AcpDiffLayoutPreference.auto,
    AcpLinkTapCallback? onOpenLink,        // null — ссылки не кликабельны
    AcpViewMode viewMode = AcpViewMode.normal,
    String emptyLabel = 'No transcript yet',
    Key? key,
  });
  /// Переходный конструктор: старые AcpTranscriptEntry → строки (для превью и тестов).
  factory AcpTranscriptPanel.entries({required List<AcpTranscriptEntry> entries, ...});
}

class AcpMarkdownBlockView extends StatelessWidget {
  const AcpMarkdownBlockView({required AcpMdBlock block, bool isTail = false,
      AcpLinkTapCallback? onOpenLink, Key? key});
}
class AcpCodeBlock extends StatefulWidget {
  const AcpCodeBlock({required String code, String? language, bool closed = true,
      int collapsedMaxLines = 40, Key? key});
}
class AcpThoughtBlock extends StatelessWidget {
  const AcpThoughtBlock({required AcpThoughtRow row, required bool expanded,
      required ValueChanged<bool> onToggle, Key? key});
}
class AcpDiffView extends StatelessWidget {
  const AcpDiffView({required AcpDiffData diff, required AcpDiffPresentation presentation,
      AcpDiffLayoutPreference layout = AcpDiffLayoutPreference.auto,
      VoidCallback? onOpenFull, ValueChanged<bool>? onToggle, Key? key});
}
enum AcpDiffPresentation { summaryLine, preview, full }
enum AcpDiffLayoutPreference { auto, unified, sideBySide }

class AcpSessionStatusBar extends StatelessWidget {
  const AcpSessionStatusBar({required AcpSessionStatusData data, Key? key});
}
final class AcpSessionStatusData {
  final String? model; final String? mode;                // modelLabel, modeLabel
  final AcpUsageData? turn; final AcpUsageData? session;  // null — агент не сообщает usage
  final double? contextFraction;                          // UsageView.contextFraction, null — неизвестно
  final bool turnRunning;
}
final class AcpUsageData {                                // из TokenCounts и Money (§12.1.1)
  final int input, output, cacheRead, cacheWrite, reasoning;
  final String? costLabel;                                // готовая строка из Money; null — цена неизвестна
  final bool partial;                                     // UsageView.sessionPartial → префикс «~»
}

// Композер: новые параметры, существующие не меняются.
//   attachments: List<AcpAttachmentChipData>, onRemoveAttachment: ValueChanged<String>,
//   onPickFiles: VoidCallback?, onPasteAttachment: Future<bool> Function()?,
//   isDropHovering: bool, isReadingAttachments: bool
final class AcpAttachmentChipData {
  final String id; final String label; final String sizeLabel;
  final AcpAttachmentKind kind;            // image | file
  final AcpAttachmentDeliveryLabel delivery; // image | embedded | link | pathText | notSent (= AttachmentKindView)
  final List<String> warnings;             // готовые подписи AttachmentWarningKind
  final Uint8List? thumbnail;              // только для изображений, уменьшенная копия
}

typedef AcpLinkTapCallback = void Function(Uri uri);
```

Ключи для тестов: `transcript-row-<id>`, `thought-toggle-<id>`, `diff-open-full-<id>`,
`code-copy-<blockId>`, `status-bar-usage`, `status-bar-cost`, `status-bar-context`,
`composer-attachment-chip-<id>`, `composer-attachment-remove-<id>`, `composer-attach-button`,
`composer-drop-zone`; после MVP (§12.6.8) — `file-tree-row-<relativePath>`, `file-tree-show-ignored`,
`file-preview`.

**Порты платформы.**

```dart
// apps/codelab_desktop/lib/core/platform/attachment_intake.dart
abstract interface class AttachmentIntake {
  /// Нормализует пути (realpath), отклоняет папки и нечитаемые файлы. Содержимое не читает:
  /// тип по сигнатуре, лимиты и блоки определяет PromptContentBuilder.build через AttachmentFiles.
  Future<List<IntakeResult>> readPaths(List<String> paths);
  Future<List<String>> pickFiles();               // file_selector.openFiles
}
abstract interface class ClipboardAttachmentReader {
  /// Изображение (→ ImageAttachment) или список файлов (→ FileAttachment(origin: clipboard));
  /// null — в буфере только текст.
  Future<List<PromptAttachment>?> read();
}
abstract interface class ExternalLinkOpener {
  Future<bool> open(Uri uri);                      // только http, https, mailto
}
sealed class IntakeResult {}
final class IntakeAccepted extends IntakeResult { final FileAttachment attachment; }
final class IntakeRejected extends IntakeResult { final String path;
  final IntakeRejectReason reason; }               // directory | unreadable
```

Реализация `AttachmentFiles` (порт kit, §12.1.1) в app — та же, что в CLI, из `codelab_client_io`:
app на десктопе может зависеть от `dart:io`-пакетов.

## 12.3.3. Алгоритмы

**A1. Маппинг ленты с переиспользованием строк.** `TranscriptRowMapper.map(SessionView view,
List<AcpTranscriptRow> previous)` вызывается на каждую новую `revision`.

1. Для каждого `TranscriptItem` маппер ищет в кеше `Expando<List<AcpTranscriptRow>>` строки,
   построенные из того же экземпляра (`identical`). Kit не пересоздаёт неизменившиеся элементы и
   закреплённые блоки markdown (VIEW-11, §12.1.2, шаг 8). Поэтому при стриме попадание в кеш
   идёт по всей ленте, кроме последнего элемента.
2. `AgentTextItem` разворачивается в одну `AcpAgentBlockRow` на каждый блок
   `markdown.blocks` (`MarkdownDocument`). Id строки — `<itemId>#<blockIndex>`. Блоки
   `index < stableCount` получают `isTail = false` и кешируются по экземпляру `MdBlock`. Блоки
   хвоста получают `isTail = true` и строятся заново.
3. `ThoughtItem` → одна `AcpThoughtRow`. `ToolCallItem` → `AcpToolCallRow`: заголовок — из
   `ToolRowFormatter.format(item, now: clock.now(), cwd: …)` (`ToolRowView`), статус — из
   `ToolCallStatusView`, diff — из каждого `ToolDiffContent.diff`, хвост терминала — из
   `ToolTerminalContent.output`, путь выноса — из `ToolTextContent.spill` (файл лежит на машине
   агента, app его не открывает и не читает; строка показывает «полный вывод: <путь>» с кнопкой
   копирования), одобрение — из существующего маппинга `AcpTranscriptApproval`. `NoticeItem` →
   `AcpNoticeRow`. `UserItem` → `AcpUserRow` с чипами только для чтения из
   `UserItem.attachments` (`PromptAttachmentView`).
4. Если ни одна строка не изменилась (тот же список по `identical`), Cubit не эмитит состояние.
   Работа маппера на один chunk — O(число блоков хвоста), а не O(длины ленты).

**A2. Отрисовка при стриме: стабильный префикс и хвост.**

```mermaid
sequenceDiagram
    participant K as "codelab_client_core"
    participant M as "TranscriptRowMapper"
    participant C as "ActiveSessionCubit"
    participant L as "AcpTranscriptPanel"
    participant H as "AcpCodeHighlighter"
    K->>M: "SessionView rev N, хвост изменился"
    M->>M: "стабильные строки из кеша, хвост заново"
    M->>C: "rows, старые экземпляры кроме хвоста"
    C->>L: "emit не чаще одного раза за кадр"
    L->>L: "перестраивается только строка хвоста"
    Note over L: "незакрытый блок кода рисуется моноширинно без подсветки"
    K->>M: "rev N+1, блок кода закрыт и стал стабильным"
    M->>C: "новая стабильная строка с кодом"
    C->>L: "emit"
    L->>H: "tryHighlightSync для малого кода"
    H-->>L: "токены или null"
    L->>H: "highlight в isolate для большого кода"
    H-->>L: "токены, строка перерисована один раз"
```

1. `AcpTranscriptPanel` строит `ListView.builder` с `ValueKey(row.id)` и
   `findChildIndexCallback`. Вставка строк выше не пересоздаёт `State` нижних строк.
2. `AcpMarkdownBlockView` для стабильной строки обёрнут в `RepaintBoundary`. Родитель
   переиспользует тот же экземпляр модели, поэтому `Element` не перестраивается
   (`row == oldRow`, проверка по `identical`).
3. Хвост рисуется тем же виджетом, но без асинхронной подсветки. Незакрытый блок кода
   (`closed == false`) выводится моноширинным текстом. Таблица без завершённой строки-разделителя
   выводится как абзац. Так хвост не прыгает между вариантами разметки.
4. Частоту обновлений ограничивает kit: не больше одной публикации за кадр (§9.10, шаг 8).
   Дополнительно Cubit склеивает эмиты в `SchedulerBinding.scheduleFrameCallback`. Это
   ограничение только на границе отображения (`streaming.md`, §15), события не теряются.
5. Следование за хвостом. Если перед обновлением список был в пределах 80 px от низа
   (существующий `_autoScrollBottomThreshold`), после кадра он прокручивается к низу без анимации.
   Если пользователь прокрутил вверх, позиция не меняется и появляется кнопка
   «К последнему сообщению». Существующая анимированная автопрокрутка к новому ожидающему
   одобрению сохраняется без изменений.

**A3. Markdown.** Разбор выполняет kit (§12.1). Десктоп только рисует блоки:

| Блок / inline | Отображение |
|---|---|
| заголовки 1–6 | `typography.title` / `subtitle` / `bodyStrong` из `FluentTheme` |
| абзац, курсив, жирный, зачёркнутый, inline-код | `Text.rich` с `TextSpan`; inline-код — моноширинный шрифт на фоне `resources.subtleFillColorSecondary` |
| `MdList`, вложенные списки, задачи (`MdListItem.checked != null`) | отступ 20 px на уровень; задачи — неинтерактивный флажок |
| цитата | левая полоса `accentColor` с прозрачностью |
| таблица | `Table` с горизонтальной прокруткой при нехватке ширины; выравнивание столбцов из модели |
| блок кода | `AcpCodeBlock`: язык, кнопка «Копировать», подсветка, сворачивание длиннее 40 строк |
| ссылка | подчёркнутый `accentColor`, подсказка с полным URL |
| `MdImage(alt, src)` | не загружается (VIEW-12); выводится как ссылка с текстом `alt` и `src` в подсказке, по правилам ссылок ниже |
| сырой HTML | выводится как текст |

Выделение текста работает через `SelectionArea` вокруг ленты; оно пересекает границы строк, в
том числе блоков одного ответа. Кнопка «Копировать» блока кода кладёт в буфер исходный код без
нумерации. Кнопка «Копировать ответ» последней строки группы кладёт исходный markdown, полученный
через `copyText`. Запись в буфер — обычное действие пользователя на границе presentation
(`platform-integration.md`, §29).

Политика ссылок: клик вызывает `onOpenLink`. Cubit открывает небольшое окно подтверждения с
полным URL и кнопками «Открыть» и «Копировать», затем `ExternalLinkOpener.open`. Схемы, кроме
`http`, `https` и `mailto`, не кликабельны и показываются текстом. Относительные пути и
`file:` тоже не открываются: подсказка показывает путь, кнопка копирует его. Агент не может
открыть URL сам: открытие всегда начинается с клика пользователя (`platform-integration.md`,
§35).

**A4. Подсветка кода.** `AcpCodeHighlighter` возвращает токены как `(start, end, AcpTokenClass)`
по строкам. Эти данные состоят из простых чисел и enum и передаются между isolate без
копирования объектов Flutter.

| Размер кода | Режим |
|---|---|
| ≤ 300 строк и ≤ 16 КиБ | синхронно в кадре построения (типичная стоимость заметно ниже бюджета кадра) |
| ≤ 5000 строк и ≤ 256 КиБ | `compute`; до результата — моноширинный текст без цвета, затем одна перерисовка |
| больше | без подсветки, свёрнуто, полный просмотр в диалоге с виртуализированным списком строк |

Результат кешируется в LRU на 256 записей по ключу `(language, hash(code))`. Повторное
построение строки, например после прокрутки, не запускает токенизацию снова. Язык берётся из
info-строки блока. Неизвестный язык или его отсутствие → без подсветки, автоопределение не
выполняется (оно дорогое и часто ошибается). Цвета токенов задаёт `AcpCodeTheme` — расширение
`FluentThemeData.extensions` с палитрами для светлой и тёмной темы. По умолчанию палитра
выбирается по `FluentTheme.brightness`. Шрифт: системный моноширинный список (`SF Mono`,
`Menlo`, `Consolas`, `monospace`) без встраивания шрифтов в сборку.

**A5. Diff.** Источник — `ToolDiffContent.diff` (`DiffView`, §12.1.3): `displayPath`, `change`
(`created | modified | deleted`), `hunks` (`DiffHunk` из `DiffLine` с `DiffOp`, номерами строк и
`noNewlineAtEnd`), счётчики `added`/`removed` и `limited` (`DiffLimitReason`). Hunks строит
`LineDiff` в kit; десктоп выбирает форму и объём.

1. Форма. При `diffLayout == auto` выбирается side-by-side, если ширина строки ленты
   (`LayoutBuilder`) ≥ 960 px, иначе unified. Ручной выбор в заголовке diff сохраняется в
   `TranscriptViewCubit` для текущего запуска. В side-by-side удалённые и добавленные строки
   одного блока изменений ставятся рядом по порядку; лишние строки одной стороны получают пустую
   пару.
2. Объём зависит от `AcpViewMode`: `summary` — одна строка `displayPath  +added −removed`; `normal` — предпросмотр
   (первые 2 hunk, не больше 20 строк); `verbose` — полностью, но не больше 300 строк inline.
3. Большой diff (> 300 строк во всех hunks или > 512 КиБ текста) всегда свёрнут: показываются
   сводка, путь и первые 20 строк с кнопкой «Показать полностью» (`diff-open-full-<id>`).
   Кнопка открывает `AcpDiffViewerDialog` с виртуализированным `ListView.builder` по строкам.
4. Подсветка внутри diff — по расширению пути (тот же `AcpCodeHighlighter`), и только когда весь
   diff попадает в лимит `compute` из A4. Цвет фона строки — `AcpTone.success` и `AcpTone.danger`
   с прозрачностью из темы. Знаки `+` и `−` в поле номеров строк показываются всегда, поэтому
   цвет не единственный носитель смысла.
5. `change == created` показывается как «новый файл, N строк» (`N = added`) и далее теми же
   правилами; `deleted` — «файл удалён, N строк» (`N = removed`). Ограниченный diff (VIEW-5):
   `limited == binary` — «бинарный файл изменён» без строк; `tooLarge` — сводка «файл переписан:
   +N −M строк (diff не показан)» без предпросмотра и без диалога (hunks пусты); `budgetExceeded`
   — единственный блок «середина заменена целиком» с отметкой «diff упрощён: показана замена
   целиком». Частичный diff никогда не подаётся как полный.
6. Карточка одобрения (D-02) для правки использует `AcpDiffView` в режиме `preview` вместо
   текстового `diffSummary`. Кнопки и горячие клавиши карточки не меняются.

**A6. Мысли.** `AcpThoughtRow` рисуется блоком, отличным от ответа: приглушённый текст
(`AcpTextRole.caption`), левая пунктирная полоса, иконка и заголовок «Размышления».

1. Пока `streaming == true`, блок раскрыт и показывает последние 6 строк, с заголовком
   «Размышляет… N с». Таймер в заголовке тикает раз в секунду и перестраивает только заголовок.
2. Когда поток закончился, блок сворачивается до заголовка «Размышления · N с» без анимации,
   чтобы лента не прыгала у читающего пользователя. Исключения: пользователь уже вручную
   раскрыл или свернул этот блок (`expansionOverrides[id]` побеждает), или включён
   `AcpViewMode.verbose` (раскрыт по умолчанию).
3. В раскрытом законченном блоке текст выводится как есть, без разбора markdown (kit мысли не
   размечает, §12.1.2, шаг 7), с переносом строк. Если текст длиннее 4000 символов, видны первые
   4000 и кнопка «Показать всё».
4. Мысли не попадают в «Копировать ответ» и не подсвечиваются как ответ. При `summary` блок
   остаётся одной строкой заголовка.

**A7. Статус чата и usage.** `AcpSessionStatusBar` стоит строкой под композером, слева
направо: модель · режим · контекст · токены · стоимость.

Источник — `SessionView.statusBar` (`SessionStatusBar`, §12.1.5); десктоп ничего не собирает
сам.

| Поле | Источник | Неизвестно |
|---|---|---|
| модель | `SessionStatusBar.modelLabel` (kit уже выбрал опцию категории `model`) | поле скрыто |
| режим | `SessionStatusBar.modeLabel` (опция категории `mode` или `current_mode_update`) | поле скрыто |
| контекст | `usage.contextFraction` (из `contextUsed`/`contextWindow`) | индикатор скрыт; 0 % не показывается |
| токены хода и сессии | `usage.lastTurn`, `usage.session` (`TokenCounts`); при `sessionPartial` — префикс `~` | `UsageView.unknown`: «usage: —» с подсказкой «агент не сообщает расход» |
| стоимость хода и сессии | `usage.lastTurnCost`, `usage.sessionCost` (`Money`) | «—»; при известных токенах без цены — «цена неизвестна» |

`gitBranch` и `queued` статус-бар десктопа не показывает: очередь видна в своей панели (R-18),
ветка — вне объёма D-09.

Данные usage приходят от агента через расширение ACP для usage (L-11, OpenSpec change
`add-usage-extension`, §12.1.5). Без расширения kit отдаёт `UsageView.unknown`, поля остаются в
состоянии «неизвестно» и никогда не превращаются в нули (VIEW-6). Подпись:
`12,3k → 1,2k · $0,042 · сессия $1,20`; вход — `input + cacheRead + cacheWrite`, выход —
`output`, как в CLI (§12.2.6). Подсказка показывает `input`, `output`, `cacheRead`,
`cacheWrite`, `reasoning`. Если агент шлёт usage во время хода, значение хода обновляется на
месте. Если только в ответе `session/prompt`, оно появляется в конце хода; до этого рядом с полем
хода крутится `AcpProgressIndicator`. Пороги контекста: ≥ 80 % — `AcpTone.warning`, ≥ 95 % —
`AcpTone.danger`. Стоимость форматируется из целых микроединиц `Money.micros` без `double` по
локали: 2 значащих знака после первой ненулевой цифры для сумм меньше 0,01 и 2 знака после
запятой для остальных. Валюта — `Money.currency`; десктоп ничего не пересчитывает.

**A8. Вложения.**

```mermaid
sequenceDiagram
    participant U as "Пользователь"
    participant Z as "ComposerDropZone и AcpPromptComposer"
    participant C as "ComposerCubit"
    participant I as "AttachmentIntake"
    participant K as "codelab_client_core"
    U->>Z: "перетаскивает файлы или Cmd+V или кнопка"
    Z->>C: "addPaths или pasteFromClipboard или pickFiles"
    C->>I: "readPaths"
    I-->>C: "IntakeAccepted или IntakeRejected"
    C->>K: "PromptContentBuilder.build по promptCapabilities"
    K-->>C: "PromptContentPlan: виды вложений и предупреждения"
    C-->>Z: "чипы с видом доставки и предупреждениями"
    U->>Z: "Отправить"
    Z->>C: "submit"
    C->>K: "SessionHandle.send с attachments"
    K->>K: "тот же PromptContentBuilder.build, блоки в session/prompt"
```

1. Источники. (a) Drag&drop — `ComposerDropZone` над всей колонкой ленты и композера. Во время
   перетаскивания выставляется `isDropHovering`, композер подсвечивается рамкой `accentColor`. Плагин
   отдаёт только пути, которые сразу уходят в `ComposerCubit.addPaths`. (b) Вставка: Cmd/Ctrl+V
   в поле композера вызывает `onPasteAttachment`. Если `ClipboardAttachmentReader` вернул
   изображение (`ImageAttachment`) или файлы (`FileAttachment(origin: clipboard)`), они
   становятся вложениями. Иначе выполняется штатная вставка текста. (c) Кнопка «Прикрепить»
   (`composer-attach-button`) → `AttachmentIntake.pickFiles` (`file_selector.openFiles`, уже есть
   в app).
2. Нормализация в `AttachmentIntake`. Путь приводится к realpath с разрешением символических
   ссылок; папки и нечитаемые файлы отклоняются сразу, с причиной. Остальное — `FileAttachment`
   (`origin: drop` или `flag` для кнопки). Тип по сигнатуре (`png/jpeg/gif/webp`), размер и
   решение «встроить или сослаться» принимает kit (§12.1.7, шаги 3–4) через порт
   `AttachmentFiles`; чтение асинхронное, вне кадра, и большие файлы не читаются целиком, если
   они уйдут ссылкой.
3. Лимиты — `AttachmentLimits` kit (§12.1.1): до 10 вложений на промпт; изображение до 5 МиБ;
   встраиваемый текстовый ресурс до 256 КиБ и только в UTF-8; суммарное встраиваемое содержимое
   промпта до 20 МиБ. Файл сверх лимита встраивания уходит `resource_link`, на чипе —
   `downgradedBySize` («отправится ссылкой»). Вставленное изображение без файла сверх 5 МиБ —
   `notSent` + `tooLarge`: чип не создаётся, показывается уведомление, потому что понижать его не
   до чего. Одиннадцатое вложение `ComposerCubit` не добавляет (`tooMany`, уведомление).
4. Вид доставки чипа — `plan.attachments[i]` из `PromptContentBuilder.build`; ту же функцию
   с теми же аргументами вызывает `SessionHandle.send` при отправке, поэтому чип показывает то,
   что реально уйдёт (VIEW-13). `ComposerCubit` пересчитывает план при изменении списка
   вложений и при смене `promptCapabilities` (смена агента, переподключение); текст черновика на
   план вложений не влияет и пересчёта не вызывает. Без `promptCapabilities.image` изображение
   с файлом уходит `resource_link` с пометкой `imageNotSupported`, а без файла не отправляется.
   Без `embeddedContext` текстовый файл уходит `resource_link` (базовая возможность ACP). Если
   агент отклонил и `resource_link`, kit один раз повторяет промпт с путями текстом (`pathText`,
   §12.1.7, шаг 5) и добавляет `NoticeItem`.
5. Предупреждения на чипе (тон `warning`): `maybeSecret` («может содержать секреты» — имя
   совпадает с `.env*`, `*.pem`, `*.key`, `id_*`) отправку не блокирует. `outsideCwd` («вне папки
   проекта» — realpath не внутри `cwd` сессии) требует подтверждения (VIEW-8): при отправке
   `ComposerCubit` показывает окно «Отправить файлы вне папки проекта?» со списком путей;
   «Отправить» → `send(..., allowOutsideCwd: true)`, «Отмена» → промпт остаётся в композере.
   Для чипа план считается с `allowOutsideCwd: true`, чтобы показать вид доставки после
   подтверждения.
6. Чип показывает иконку или миниатюру (уменьшенную до 64 px копию, декодированную через
   `ui.instantiateImageCodec` с `targetWidth`), имя, размер (`PromptAttachmentView.bytes`), вид
   доставки и предупреждения. Удаление — кнопка на чипе или Delete/Backspace при фокусе на чипе.
7. Отправка: `SessionHandle.send(text, attachments: …, allowOutsideCwd: …)`. Если идёт ход,
   промпт с вложениями ставится в очередь (R-18) как `QueuedPrompt` с `attachments` и
   `allowOutsideCwd` (§12.1.1). Строка очереди показывает число вложений, а правка текста промпта
   в очереди вложения сохраняет. После успешной передачи в kit вложения композера очищаются
   вместе с черновиком. При ошибке до отправки они остаются.

**A9. Доступность и клавиатура.**

* Каждая строка ленты — `Semantics(container: true)` с ролью в подписи: «Вы», «Ответ агента»,
  «Размышления», «Инструмент: <метка> <деталь>, <статус>» (из `ToolRowView` и
  `ToolCallStatusView`). Блок мыслей и свёрнутый diff — кнопки
  `Semantics(button: true, expanded: …)`. Enter или Space переключает их.
* Строки diff получают подписи «добавлено: …» и «удалено: …»; поле номеров с `+`/`−` видно
  всегда.
* Поток не озвучивается по chunk. `liveRegion` есть только у статуса хода («ответ завершён»,
  «ожидает одобрения»).
* Статус-бар: подписи «Стоимость хода …», «Использование неизвестно», «Контекст заполнен на
  N процентов».
* Фокус: `FocusTraversalGroup` для ленты, композера и чипов. В ряду чипов работают стрелки
  влево и вправо. Backspace в пустом поле переводит фокус на последний чип. Существующие
  сочетания не переназначаются: Cmd/Ctrl+K — палитра, Esc — отмена, Cmd/Ctrl+Enter и
  Cmd/Ctrl+Backspace — одобрить и отклонить, Alt+←/→ — инспектор. Поэтому удаление чипа
  делается простым Delete/Backspace, а не Cmd+Backspace.
* Контраст палитр подсветки и фонов diff — не ниже 4,5:1 к фону темы. Масштаб текста ОС
  учитывается, размеры в логических пикселях не фиксируются.

**A10. Управление сессиями (после MVP, S-06…S-09, D-10; agent-core-architecture §17.6.11).**
Логика — в `SessionHandle` kit (§12.1.1); app только рисует и вызывает методы.

* Контекстное меню сессии в сайдбаре: «Rename» (поле ввода, `SessionHandle.rename`; ошибка
  `invalidTitle` — под полем) и «Fork» (`fork()` от листа; новая сессия открывается вкладкой).
  Новый заголовок приходит `session_info_update` и во все открытые окна этой сессии.
* «Rewind to here» — на наведении сообщения пользователя с `recordId`: сначала
  `rewind(recordId, dryRun: true)`, затем диалог-предупреждение со списком файлов, которые **не**
  будут восстановлены, и пометкой о прочих эффектах; «Rewind» → `rewind(...)`, перезагрузка
  транскрипта, исходный текст сообщения — в композер. Без `recordId` (агент без `sessionTree`)
  пункта нет.
* Панель веток: список `branches()` (превью, число сообщений, время, метки; активная выделена);
  клик — `switchBranch(tipId)`; ответ с `filesNotRestored` показывается уведомлением ленты.
  `branchChanged` в `session_info_update` → kit перезагружает сессию (`session/load`).
* Режим только чтения: при `access == ReadOnlyAccess` над композером баннер
  `Read-only: this session is open in <profile>. Fork to continue here.` с кнопками «Fork» и
  «Try again» (повторный `session/load` с `openMode: "write"`); композер выключен. Сессия CLI
  открывается через профиль `ws://` того же агента: сайдбар показывает отметку `lease`, а
  `session/load` подключает app вторым клиентом (D-10).

**A11. Steering (после MVP, C-03; agent-core-architecture §17.7.6).**

* Во время хода кнопка отправки — разделённая: основное действие «В очередь» (Enter),
  дополнительное «Направить» (Cmd+Shift+Enter на macOS, Ctrl+Shift+Enter на остальных:
  Cmd/Ctrl+Enter уже одобряет запрос, A9) — `SessionHandle.steer`. Без
  `agentCapabilities._meta.codelab.steering` вторая часть кнопки скрыта. Настройка
  app `codelab.input.enter_while_running` (`queue` | `steer`, `shared_preferences`, §12.6.1;
  не ключ `cli.yaml`) меняет действия местами.
* Панель очереди (R-18): у каждой строки рядом с «Отправить сейчас» (отмена хода) — «Направить»
  (без отмены), `PromptQueue.steer(id)`.
* Ожидающее steering (`SessionView.pendingSteers`) — полупрозрачный пузырь над композером с фазой
  («ждёт конца инструментов», «ждёт ответа на разрешение», «ждёт ответа модели»); доставленное —
  пузырь пользователя с меткой «во время хода» на своём месте ленты; возвращённое — снова строка
  очереди с заметкой.

**A12. Поиск и фильтр сессий (после MVP, D-17; логика — kit, §12.6.12; агент —
agent-core-architecture §17.6.17).** App ничего не фильтрует и не ищет сам: `SessionSearchCubit`
передаёт запрос в `SessionSearch` kit и превращает `SessionSearchView` в строки `codelab_ui`.

```dart
// apps/codelab_desktop/lib/features/workbench/application/session_search_cubit.dart
final class SessionSearchState {
  final String text;                            // поле ввода
  final AcpSessionDateFilter date;              // all | today | week | range(from, to)
  final AcpSessionSearchScope scope;            // thisProject | allProjects
  final SessionSearchUiStatus status;           // inactive | filtering | searchingText | done | textFailed(message)
  final List<AcpSessionSearchRowData> rows;     // пусто при inactive
  final bool titlesOnly;                        // !SessionSearchView.textSearchAvailable
  final bool moreAvailable;
}
```

1. **Поле.** Над `AcpSessionSidebar` — `AcpSessionSearchField`: `TextBox` с иконкой поиска и
   кнопкой очистки; ряд фильтров `All · Today · 7 days · Range…` (Range — два `DatePicker`,
   `from > to` подсвечивает поле и не отправляет запрос); переключатель
   `This project | All projects`. Фокус — Cmd+Shift+F на macOS, Ctrl+Shift+F на остальных
   (новое сочетание, существующие по DSK-18 не меняются). Esc в фокусированном поле очищает его,
   в пустом — возвращает фокус композеру; вне поля Esc сохраняет прежний смысл.
2. **Склейка.** `SessionSearch` создаётся `workspace.openSessionSearch()` при первом вводе и
   закрывается в `close()` Cubit-а (AGENTS.md §9). Ввод склеивается 250 мс: заголовочный фильтр
   kit отрабатывает по загруженным сводкам, текстовый поиск — после склейки (§12.6.12, шаг 5).
   Пустой текст и `All` → `inactive`: сайдбар показывает обычный список сессий (R-21 без
   изменений).
3. **Результаты** — `AcpSessionSearchResults` вместо списка: строка — заголовок с подсветкой
   терминов (фон `selection` и жирный — не только цвет), время, при `All projects` — имя папки;
   под ней до двух сниппетов (роль, текст с подсветкой; сниппет вне активной ветки — пометка
   «earlier branch»). Подпись под полем при `titlesOnly` —
   «Titles only — the agent does not support text search»; `textFailed` — «Text search failed:
   <message>» (результаты по заголовку остаются); `moreAvailable` — кнопка «Load more»
   (`loadMore`); пусто — «No sessions match». Число найденных объявляется `Semantics(liveRegion)`.
4. **Открытие.** Клик по строке — `activate` уже открытой сессии или `loadSession(id, cwd:
   row.cwd)` (папка сессии, не текущий проект). Клик по сниппету — то же и, если транскрипт
   содержит элемент с этим `recordId` (агент объявил `sessionTree`, §17.6.10), прокрутка к нему
   с кратковременной подсветкой; иначе только открытие.
5. **Ключи тестов:** `session-search-field`, `session-search-clear`,
   `session-search-date-<all|today|week|range>`, `session-search-scope`,
   `session-search-row-<sessionId>`, `session-search-snippet-<sessionId>-<recordId>`,
   `session-search-load-more`, `session-search-titles-only`.
6. Запрос, фильтр и область — UI-состояние окна: в `shared_preferences` и в kit они не
   сохраняются.

**A13. Карта экранов и навигация.** Экраны переключает состояние приложения, а не пакет
маршрутизации: навигация — часть application state (AGENTS.md §8), а новая библиотека для
задачи, которую решает существующий state management, не добавляется (AGENTS.md §4). Текущий
экран выбирает `NavigationCubit`, `CodeLabAppWidget` рисует экран по его состоянию.

```dart
// apps/codelab_desktop/lib/app/navigation/app_destination.dart
sealed class AppDestination {}
final class BootDestination extends AppDestination {}              // 08, §12.4.7
final class OnboardingDestination extends AppDestination {}        // 07, D-11
final class ProjectPickerDestination extends AppDestination {}     // 11, R-22
final class WorkbenchDestination extends AppDestination {          // 01 — единственный хаб
  final WorkbenchPanel panel;            // sessions | files (03) — вкладка сайдбара
  final InspectorTab inspector;          // plan | timeline | usage | agents | branches
  final WorkbenchOverlay? overlay;       // palette (12) | sessionHistory (14) | protocolInspector (18) | shortcuts (27)
}
final class SettingsDestination extends AppDestination { final SettingsPage page; }  // §12.4.9
```

1. **Хаб.** Рабочее место (01) — единственный хаб. Любой экран открывается из него одним
   действием: пунктом сайдбара, вкладкой инспектора, палитрой Cmd/Ctrl+K или сочетанием клавиш.
   Любая страница настроек — двумя: «Settings» в подвале сайдбара (или Cmd/Ctrl+,) → пункт
   навигации настроек. Esc и «Back» возвращают на рабочее место, на ту вкладку сессии, с которой
   ушли. На самом рабочем месте без открытого оверлея Esc сохраняет смысл A9 — отмена хода.
2. **Экраны.**

   | № | Экран | Цели | Вход |
   |---|---|---|---|
   | 01 | рабочее место: сайдбар сессий, вкладки, лента, инспектор, композер | D-01…D-09, R-18…R-21 | хаб |
   | 02 | идущий ход: мысли, очередь, steering | D-08, R-18, C-03 | состояние 01 |
   | 03 | файлы проекта | D-13 | вкладка сайдбара «Files», Cmd/Ctrl+Shift+E |
   | 04 | поиск и фильтр сессий | D-17, D-10 | поле над сайдбаром, Cmd/Ctrl+Shift+F (A12) |
   | 05, 05b, 10, 20–27 | страницы настроек | §12.4.9 | Cmd/Ctrl+, , подвал сайдбара |
   | 06 | мастер провайдера (`ContentDialog`) | L-24, U-17 | «Add provider», onboarding |
   | 07 | onboarding | D-11 | первый запуск |
   | 08 | сторож запуска | D-15 | старт app |
   | 09 | узкий макет (< 900 px) | D-21 | ширина окна |
   | 11 | выбор проекта и профиля подключения | R-22, U-06 | старт без проекта, переключатель проекта в app bar, Cmd/Ctrl+O |
   | 12 | палитра команд | R-20, U-26, S-21 | Cmd/Ctrl+K, поле в app bar |
   | 13 | меню композера: режим, модель, effort, профиль агента, `/`, `@`, вложения, Queue / Steer | U-05, L-16, P-05, C-04, D-12, C-03 | кнопки строки композера |
   | 14 | история сессии: rename, fork, ветки, rewind, экспорт | S-06…S-08, S-21 | заголовок сессии, контекстное меню сайдбара (A10) |
   | 15 | вопрос агента и одобрения `web_fetch` и критических шаблонов | T-22, T-13, P-07 | запрос агента |
   | 16 | доска субагентов и фоновых задач | D-25, T-10, E-22 | вкладка инспектора «Agents», чип в статус-баре (A15) |
   | 17 | usage и стоимость | D-09, L-29, C-13, C-15 | клик по статус-бару, вкладка инспектора «Usage» |
   | 18 | инспектор протокола и лог | R-23, E-16 | Cmd/Ctrl+Shift+I, палитра |
   | 19 | состояния соединения и ошибок хода | L-04, L-32, L-08, K-04, S-09 | значок соединения в app bar, уведомления ленты |

3. **Сочетания.** Новые: Cmd/Ctrl+N — новая сессия; Cmd/Ctrl+O — выбор проекта;
   Cmd/Ctrl+Shift+E — файлы проекта; Cmd/Ctrl+Shift+I — инспектор протокола; Cmd/Ctrl+/ —
   список сочетаний (страница 27). Существующие по DSK-18 не меняются.
4. **Палитра (R-20).** `CommandPaletteCubit` строит четыре группы: «Agent commands» — команды из
   `available_commands_update` с меткой источника (агент, MCP-prompt, skill, шаблон); выбор
   отправляет `session/prompt`, а `/compact` и `/plan` выполняют действие; «Session» — Rename,
   Fork, Rewind…, Export to Markdown, Copy as Markdown (S-21); «Go to» — каждый экран таблицы
   шага 2 с его сочетанием; «App» — Restart agent (U-26), Keyboard shortcuts, смена темы (D-20).
   Палитра не дублирует логику экранов: пункт «Go to» вызывает тот же переход `NavigationCubit`,
   что и сайдбар.
5. **Диалоги не накладываются.** Одновременно открыт не больше одного модального окна. Второй
   вопрос агента (T-22) или запрос разрешения ждут в ленте строкой «Question pending» или
   карточкой одобрения; модальное окно поверх модального не открывается.
6. **Инспектор.** Вкладки Plan (R-19), Timeline (A14), Usage (D-09), Agents (A15), Branches (A10).
   Вкладка без данных скрыта: Timeline и Agents — без соответствующего расширения агента,
   Branches — без `sessionTree`. Выбранная вкладка — UI-состояние окна (`shared_preferences`
   ключ `codelab.inspector.tab`).
7. **Узкий макет (D-21).** Граф тот же; сайдбар и инспектор становятся выдвижными панелями, лента
   и композер занимают всю ширину.
8. **Ключи тестов:** `nav-<destination>`, `palette-item-<id>`, `inspector-tab-<tab>`,
   `settings-nav-<page>`.

**A14. Хронология хода (после MVP, D-22, Could).** Вкладка инспектора «Timeline» показывает шаги
цикла последнего или выбранного хода. Границы шагов и usage шага приходят в
`_meta.codelab.*` по OpenSpec change вместе с расширением usage (`add-usage-extension`, L-11);
форма полей задаётся этим change, не здесь.

1. Строка шага: номер, модель, токены входа и выхода, время, заполненность контекста после шага,
   число вызовов инструментов; сжатие (K-01, K-02) — отдельная строка между шагами.
2. Раскрытие шага показывает его вызовы (`AcpToolRowData`, §12.1.6); клик по вызову прокручивает
   ленту к строке вызова и кратковременно подсвечивает её.
3. Без расширения вкладка скрыта (A13, шаг 6): границы шагов из одного `tool_call` не
   восстанавливаются, и app их не угадывает.
4. Данные строит kit (`TurnTimelineView`, вводится тем же change); app только рисует.

**A15. Доска субагентов и фоновых задач (после MVP, D-25, Could; agent-core-architecture
§17.3.7, §17.9.11).** App объявляет `clientCapabilities._meta.codelab.subagentBoard: true` и
`jobBoard: true`. Доска есть, только если агент объявил ту же capability; иначе дети и задачи
видны только как строки `tool_call` ленты и как ответ команды агента `/tasks` из палитры.

1. **Субагенты.** Строка — снимок `_codelab/subagents/update`: `agent` (A2A — тип
   `a2a:<name>`, E-22), `description`, `state`, время по `startedAt`/`endedAt`, `steps`,
   `toolCalls`, `tokens`, `cost`, `lastActivity`, номер запуска `run` (C-17); фоновые дети
   (`background: true`) остаются на доске вне хода.
2. **Действия ребёнка.** «Open transcript» — `_codelab/subagents/history`; реплей рисуется в
   отдельной панели `AcpTranscriptPanel` только для чтения и в ленту сессии не попадает. «Stop» —
   `_codelab/subagents/cancel`. Отправить сообщение ребёнку (C-17, D-25) в §17.3.7 метода нет:
   кнопка «Message» появляется только после OpenSpec change, который его вводит.
3. **Фоновые задачи (T-10).** Строка — снимок `_codelab/jobs/update`: `command`, `state`,
   `exitCode`, время; хвост вывода — `_codelab/jobs/output` с `tail`; «Kill» —
   `_codelab/jobs/kill`.
4. **Запрос разрешения ребёнка** приходит обычным `session/request_permission` родителя с
   префиксом в `title` и рисуется карточкой одобрения в ленте (§17.3.7). Строка ребёнка на доске
   получает пометку «needs you», клик по ней прокручивает ленту к карточке.
5. Статус-бар показывает чип «N running» при работающих детях или задачах; клик открывает
   вкладку «Agents».
6. CLI (U-21): те же данные kit рисует полноэкранный вид `tasks` (действие реестра клавиш
   `toggle_tasks`, §12.2); без capability — только текст `/tasks`.

## 12.3.4. Примеры

Ответ агента «Исправил:\n\n```dart\nfinal a = 1;\n```\nГотово.» во время стрима, сразу после
прихода «```dart\nfinal a» даёт строки `msg-7#0` (абзац, стабильный) и `msg-7#1` (код,
`isTail`, `closed: false`, моноширинно). Когда приходит закрывающая ограда, `msg-7#1` становится
стабильной и подсвечивается синхронно (одна строка кода). Строка `msg-7#2` («Готово.») — новый
хвост. `msg-7#0` за всё время строится один раз.

Правка `lib/a.dart` на 1200 строк изменений при ширине ленты 1100 px в режиме `normal`: заголовок
`lib/a.dart  +900 −300`, первые 20 строк side-by-side без подсветки (вне лимита) и кнопка
«Показать полностью». Диалог показывает все строки с прокруткой.

Агент без расширения usage: статус-бар показывает `claude-sonnet · standard · usage: —`. Тот же
агент после включения расширения через OpenSpec показывает
`claude-sonnet · standard · ▮▮▮▯ 62 % · 12,3k → 1,2k · $0,042 · сессия $1,20`.

Пользователь перетаскивает `shot.png` (800 КиБ) и `/etc/hosts` в сессию с `cwd = ~/proj`.
Агент объявил `image: true, embeddedContext: false`. Получаются чипы `shot.png · 800 КБ ·
изображение` и `hosts · 1 КБ · ссылка · вне папки проекта`. «Отправить» открывает окно
подтверждения с путём `/etc/hosts`; после «Отправить» уходят блоки `text`, `image` и
`resource_link` для `shot.png` (§12.1.7, шаг 3) и `resource_link` для `/etc/hosts`.

## 12.3.5. Инварианты

1. **DSK-1.** Виджеты `codelab_ui` НЕ ДОЛЖНЫ импортировать `codelab_client_core`, `codelab_acp_protocol` или
   плагины платформы. Модели kit превращает в модели `codelab_ui` только `ui_mappers.dart`.
2. **DSK-2.** Разбор markdown, построение hunks и выбор `ContentBlock` ДОЛЖНЫ выполняться в kit.
   Десктоп НЕ ДОЛЖЕН разбирать markdown или вычислять diff заново.
3. **DSK-3.** Блок стабильного префикса ДОЛЖЕН строиться не больше одного раза за время стрима
   ответа. Обновление хвоста НЕ ДОЛЖНО перестраивать строки стабильного префикса и другие
   элементы ленты.
4. **DSK-4.** Маппер ДОЛЖЕН переиспользовать экземпляр `AcpTranscriptRow` для неизменившегося
   элемента kit (`identical`). Работа на один chunk ДОЛЖНА быть O(размер хвоста).
5. **DSK-5.** Токенизация кода больше синхронного лимита (300 строк или 16 КиБ) НЕ ДОЛЖНА
   выполняться в UI isolate. Код больше 5000 строк или 256 КиБ НЕ ДОЛЖЕН подсвечиваться inline.
6. **DSK-6.** Незакрытый блок кода в хвосте ДОЛЖЕН рисоваться моноширинным текстом без
   подсветки. Подсветка запускается только для стабильного блока.
7. **DSK-7.** Ссылка ДОЛЖНА открываться только по клику пользователя, после показа полного URL,
   и только для `http`, `https`, `mailto`. Изображения из markdown НЕ ДОЛЖНЫ загружаться.
8. **DSK-8.** Diff ДОЛЖЕН показываться unified при ширине строки меньше 960 px и side-by-side
   при ≥ 960 px, если пользователь не выбрал форму вручную. Diff больше 300 строк ДОЛЖЕН быть
   свёрнут inline, а полный просмотр ДОЛЖЕН быть виртуализирован.
9. **DSK-9.** Смысл строк diff НЕ ДОЛЖЕН передаваться только цветом: знаки `+`/`−` и
   семантические подписи обязательны.
10. **DSK-10.** Блок мыслей ДОЛЖЕН быть раскрыт во время стрима и свёрнут после его окончания.
    Исключения: `verbose` и ручной выбор пользователя, который побеждает и переживает уход строки
    с экрана. Мысли НЕ ДОЛЖНЫ попадать в «Копировать ответ».
11. **DSK-11.** При отсутствии данных usage, стоимости или заполнения контекста статус-бар ДОЛЖЕН
    показывать состояние «неизвестно» (скрытое поле или «—») и НЕ ДОЛЖЕН показывать нули.
    Расширение ACP для usage вводится только через OpenSpec.
12. **DSK-12.** Вид доставки на чипе ДОЛЖЕН совпадать с тем, что уйдёт в `session/prompt`:
    оба вычисляет `PromptContentBuilder.build` kit по актуальным `promptCapabilities` (VIEW-13);
    app НЕ ДОЛЖЕН выбирать вид доставки сам.
13. **DSK-13.** Вложение НЕ ДОЛЖНО уходить блоком `image` или `resource` без соответствующей
    возможности агента (VIEW-7). Без возможности файл уходит `resource_link` с пометкой (после
    отказа агента — путём текстом), а изображение без файла не отправляется.
14. **DSK-14.** Лимиты вложений (`AttachmentLimits`: 10 штук, 5 МиБ на изображение, 256 КиБ на
    встраиваемый текст, 20 МиБ встраиваемого на промпт) ДОЛЖНЫ проверяться до отправки. Каждый
    отказ ДОЛЖЕН показываться с причиной.
15. **DSK-15.** Путь вложения ДОЛЖЕН нормализоваться в realpath до проверки «вне папки проекта»;
    вложение вне `cwd` НЕ ДОЛЖНО уходить без подтверждения пользователя (VIEW-8). Предупреждения
    НЕ ДОЛЖНЫ скрываться при понижении вида доставки.
16. **DSK-16.** Presentation НЕ ДОЛЖЕН читать файлы или буфер обмена сам. Чтение выполняют порты
    `core/platform`, плагин drag&drop передаёт только пути.
17. **DSK-17.** Существующее поведение НЕ ДОЛЖНО регрессировать: встроенное одобрение и
    автопрокрутка к новому ожидающему одобрению (D-01, D-02), очередь (R-18), чек-лист (R-19),
    палитра и её сочетания (R-20), вкладки со статусом (R-21), выбор проекта (R-22), инспектор и
    лог-вьюер (R-23). Все существующие интеграционные тесты app проходят без правок сценариев;
    меняются только ожидания `permission_flow_test.dart` о виде diff в карточке одобрения
    (`AcpDiffView` в режиме `preview` вместо текстового `diffSummary`, A5, шаг 6).
18. **DSK-18.** Новые сочетания клавиш НЕ ДОЛЖНЫ переназначать существующие (Cmd/Ctrl+K, Esc,
    Cmd/Ctrl+Enter, Cmd/Ctrl+Backspace, Alt+←/→).
19. **DSK-19.** Цвета ДОЛЖНЫ браться из `FluentTheme`, `AcpTone` и `AcpCodeTheme`; литералы цветов
    в виджетах ленты НЕ ДОЛЖНЫ появляться. Обе темы ДОЛЖНЫ давать контраст не ниже 4,5:1.
20. **DSK-20.** Состояние раскрытия и выбор формы diff НЕ ДОЛЖНЫ храниться в kit и в журнале
    сессии: это UI-состояние текущего запуска.
21. **DSK-21.** App НЕ ДОЛЖЕН фильтровать или искать сессии сам: строки результатов строятся
    только из `SessionSearchView` kit (§12.6.12, UX-26); виджеты `codelab_ui` не вызывают `session/list`
    и `_codelab/session/search`.
22. **DSK-22.** Итог прежнего запроса поиска НЕ ДОЛЖЕН показываться после смены текста, даты или
    области (поколение kit, UX-27); при пустом запросе и фильтре `All` сайдбар ДОЛЖЕН совпадать с
    обычным списком сессий.
23. **DSK-23.** Сессия из результата другой папки ДОЛЖНА открываться с `cwd` этой сессии; подсветка
    совпадений ДОЛЖНА различаться не только цветом.
24. **DSK-24.** Переход между экранами ДОЛЖЕН идти только через `NavigationCubit` (A13). Виджеты НЕ
    ДОЛЖНЫ открывать экраны в обход него. Каждый экран таблицы A13 ДОЛЖЕН быть доступен из рабочего
    места одним действием и из палитры; Esc и «Back» ДОЛЖНЫ возвращать на ту вкладку сессии, с
    которой ушли.
25. **DSK-25.** Модальное окно НЕ ДОЛЖНО открываться поверх другого модального окна. Второй вопрос
    агента и второй запрос разрешения ДОЛЖНЫ ждать в ленте.
26. **DSK-26.** Вкладки Timeline и Agents и действия доски ДОЛЖНЫ появляться только при
    согласованной capability агента (A14, A15). App НЕ ДОЛЖЕН восстанавливать шаги хода или
    состояние детей из строк `tool_call` и НЕ ДОЛЖЕН показывать действие, для которого нет метода
    расширения.
27. **DSK-27.** Транскрипт ребёнка с доски ДОЛЖЕН открываться только для чтения и НЕ ДОЛЖЕН
    попадать в ленту сессии родителя.

## 12.3.6. Обоснование

* **Свои презентационные модели в `codelab_ui`, а не зависимость от kit.** Сегодня `codelab_ui` зависит
  только от `fluent_ui`, `flutter_bloc` и `freezed_annotation`. Превью и widget-тесты строят
  модели без ядра клиента, и задача 5.9 уже требует маппинга в модели `codelab_ui`. Цена —
  зеркальные типы `AcpMdBlock` (~150 строк маппера). Мемоизация по `identical` делает маппинг
  бесплатным для стабильной части. Вариант «`codelab_ui` зависит от kit» отклонён: ui_kit стал бы
  тянуть доменные типы, а изменение view model kit ломало бы ui_kit.
* **Строка ленты на блок markdown.** Если строка — целое сообщение, длинный ответ строится
  целиком, и вложенный `Column` не виртуализируется. При строке на блок список виртуализирует
  и длинные ответы, а граница «стабильный префикс / хвост» естественно совпадает с границей
  строк. Минус: выделение текста через несколько строк требует `SelectionArea` на уровне ленты.
  Flutter это поддерживает.
* **Рендерер markdown свой, без пакета-виджета.** AST уже даёт kit, общий с CLI. Пакеты-виджеты
  разбирают строку сами, а значит вся инкрементальность kit пропала бы, и пришлось бы
  перепарсивать сообщение на каждый chunk. Рендер блоков в `TextSpan` и `Table` — несколько сотен
  строк на теме Fluent без чужой стилизации.
* **Подсветка — в `codelab_ui`, токены — простые данные.** Подсветка нужна только графическому
  клиенту. Если CLI (§12.2) захочет ту же токенизацию для ANSI, токенизатор переносится в kit
  без изменения API `AcpCodeHighlighter`.
* **Пороги.** 960 px — ширина, при которой две колонки по 80 моноширинных символов помещаются
  с полями номеров. 300 строк inline — примерно три экрана: дальше diff мешает читать ленту.
  Лимиты вложений консервативны и меняются константами в одном месте. В OpenSpec change их можно
  уточнить по замерам.
* **Сворачивание мыслей без анимации.** Анимация высоты в середине ленты сдвигает текст, который
  пользователь читает. Резкое сворачивание после конца стрима плюс правило «ручной выбор
  побеждает» предсказуемее.

**Новые зависимости** (каждая требует решения в OpenSpec change; AGENTS.md §4):

| Пакет | Куда | Зачем | Почему не существующее |
|---|---|---|---|
| `re_highlight` | `codelab_ui` | токенизация кода по грамматикам highlight.js, чистый Dart в ядре, работает в `compute` | в проекте нет подсветки; альтернатива на TextMate-грамматиках требует асинхронной загрузки грамматик из assets и тяжелее; собственный токенизатор на десятки языков несоразмерен задаче |
| `desktop_drop` | app (presentation) | приём файлов, перетаскиваемых из ОС, на macOS, Windows, Linux | Flutter не даёт drop внешних файлов на десктопе; `file_selector` покрывает только диалог |
| `pasteboard` | app (`core/platform`) | изображения и файлы из системного буфера | `Clipboard` Flutter читает только текст |
| `url_launcher` | app (`core/platform`) | открытие http/https/mailto по клику | вызов `open`/`xdg-open` через процесс разносит проверки платформ по коду (AGENTS.md §11) |

Для каждого пакета перед добавлением нужно проверить: лицензию (политика §7а), активность
сопровождения, поддержку целевых платформ и отсутствие нативной сборки, ломающей текущий CI
macOS. Пакет-виджет markdown не добавляется.

## 12.3.7. Как проверить

**Widget-тесты `codelab_ui`** (`packages/flutter/codelab_ui/test/`). Для производительности проверяются
счётчики работы, а не время. Виджеты ведут debug-счётчики `AcpRenderStats.blockBuilds`,
`highlightRuns` и `highlightSyncRuns`; их значения учитываются только в `assert`.

| Файл: тест | Цель |
|---|---|
| `acp_markdown_test.dart: renders headings lists tables quotes and inline code` | D-06 |
| `acp_markdown_test.dart: code block shows language and copy puts raw code into clipboard` | D-06 |
| `acp_markdown_test.dart: streaming 200 chunks builds each stable block once` (`blockBuilds`) | D-06, DSK-3 |
| `acp_markdown_test.dart: unclosed fence in tail renders plain and highlights after close` | DSK-6 |
| `acp_markdown_test.dart: large code block is highlighted off the UI isolate` (`highlightSyncRuns == 0`) | DSK-5 |
| `acp_markdown_test.dart: link tap calls onOpenLink and non-http schemes are not tappable` | DSK-7 |
| `acp_markdown_test.dart: markdown image is rendered as link and not fetched` | DSK-7 |
| `acp_diff_view_test.dart: unified below 960 px and side-by-side at 960 px or wider` | D-07, DSK-8 |
| `acp_diff_view_test.dart: diff over 300 lines is collapsed and opens full viewer` | D-07, DSK-8 |
| `acp_diff_view_test.dart: summary normal verbose view modes show line, preview, full` | D-07 |
| `acp_diff_view_test.dart: added and removed lines have sign gutter and semantic labels` | DSK-9 |
| `acp_diff_view_test.dart: created, deleted, binary, tooLarge and budgetExceeded diffs are labelled` | D-07 |
| `acp_thought_block_test.dart: expanded while streaming and collapsed after stream end` | D-08, DSK-10 |
| `acp_thought_block_test.dart: user toggle wins over auto collapse and survives scrolling off screen` | D-08, DSK-10 |
| `acp_thought_block_test.dart: visually distinct from agent answer and excluded from copy` | D-08 |
| `acp_thought_block_test.dart: thought text is shown as is without markdown parsing` | D-08 |
| `acp_thought_block_test.dart: Enter and Space toggle with expanded semantics` | A9 |
| `acp_session_status_bar_test.dart: unknown usage shows dash and never zero` | D-09, DSK-11 |
| `acp_session_status_bar_test.dart: context thresholds switch tone at 80 and 95 percent` | D-09 |
| `acp_prompt_composer_test.dart: chips render delivery and warnings and remove by button and Delete` | D-12 |
| `acp_prompt_composer_test.dart: Cmd+Backspace still rejects approval and does not remove chip` | DSK-18 |
| `acp_transcript_panel_test.dart: pending approval auto-scroll unchanged with row model` | DSK-17 |
| `acp_transcript_panel_test.dart: inserting rows above keeps state of rows below` | DSK-4 |
| `acp_session_search_test.dart: highlights terms with bold and selection, shows snippets and titles-only caption` (после MVP) | D-17, DSK-23 |
| `acp_session_search_test.dart: Esc clears focused field and empty field returns focus` (после MVP) | D-17, DSK-18 |
| `acp_turn_timeline_test.dart: step rows show model tokens time and context, expanding a step lists its tool calls` (после MVP) | D-22 |
| `acp_task_board_test.dart: subagent and job rows render snapshot fields, needs-you mark and no Message button without method` (после MVP) | D-25, DSK-26 |
| существующие `acp_organisms_test.dart`, `acp_molecules_test.dart`, `acp_previews_test.dart` | DSK-17 |

**Unit-тесты app** (`apps/codelab_desktop/test/features/workbench/application/`,
`apps/codelab_desktop/test/core/platform/`):

* `ui_mappers_transcript_test.dart: unchanged kit items map to identical rows` (DSK-4);
* `ui_mappers_transcript_test.dart: agent text item splits into one row per block with tail flag`;
* `ui_mappers_transcript_test.dart: spill marker becomes copyable path and is never opened`;
* `composer_cubit_test.dart: chip view equals plan used by send and is recomputed when promptCapabilities change` (DSK-12);
* `composer_cubit_test.dart: limits reject eleventh attachment and oversize pasted image` (DSK-14);
* `session_search_cubit_test.dart` (после MVP, D-17): ввод склеивается 250 мс; `inactive` при пустом
  тексте и `All`; смена текста отбрасывает итог прежнего поколения; `close()` закрывает
  `SessionSearch` (DSK-21, DSK-22);
* `navigation_cubit_test.dart` (A13): каждый `AppDestination` достижим из рабочего места одним
  переходом; Esc и «Back» возвращают на исходную вкладку сессии; второй запрос модального окна
  при открытом первом ставится в очередь (DSK-24, DSK-25);
* `command_palette_cubit_test.dart` (R-20): группы и метки источника команд; «Go to» вызывает тот
  же переход, что и сайдбар; `/compact` и `/plan` выполняются, остальные команды агента уходят
  `session/prompt`;
* `composer_cubit_test.dart: oversize file is downgraded to link and keeps warnings` (DSK-15);
* `composer_cubit_test.dart: outside cwd attachment asks confirmation and cancel keeps draft` (DSK-15);
* `composer_cubit_test.dart: queued prompt keeps attachments after text edit` (R-18);
* `attachment_intake_test.dart: symlink is resolved to realpath, directory and unreadable file are rejected`.

Сигнатуры файлов, лимиты и пометка «вне папки» проверяются тестами kit (§12.1.10,
`attachments/prompt_content_builder_test.dart`); app их не дублирует.

**Интеграционные тесты** (`apps/codelab_desktop/integration_test/`, macOS, scripted-агент из
`codelab_acp_testing`; во внешнем и во встроенном режиме, §9.12, задача 7.7):

* `app:prompt_attachments_flow_test.dart` (D-12). Нативные drag&drop и буфер ОС в
  `integration_test` не управляются, поэтому тест вызывает обработчик `composer-drop-zone` с
  путями, а вставку выполняет через тестовую реализацию `ClipboardAttachmentReader`, подменённую
  в scope зависимостей. Сценарии:
  1. агент с `image: true, embeddedContext: true`: перетащить `a.txt` и `shot.png` → два чипа →
     удалить `a.txt` → отправить → агент получил ровно `text`, `image` и `resource_link` на
     `shot.png`;
  2. агент без `image` и `embeddedContext`: вставить файл `b.txt` → чип «ссылка» → агент получил
     `resource_link`; вставка изображения без пути → уведомление, чипа нет;
  3. файл вне `cwd` → чип с «вне папки проекта»; «Отправить» открывает подтверждение; «Отмена» —
     агент ничего не получил, черновик на месте; «Отправить» — агент получил `resource_link`;
  4. во время хода промпт с вложением ставится в очередь, после хода агент получает вложение
     (совместно с R-18).
* `app:attach_ws_session_flow_test.dart` (после MVP, D-10, agent-core-architecture §17.6.16):
  CLI-клиент создаёт сессию у fake-агента по WebSocket и запускает ход; app находит сессию в
  сайдбаре, получает реплей и живые события; после хода промпт app виден CLI; сессия, занятая
  другим процессом, — баннер только чтения и кнопка «Fork»; «Rename», «Fork», «Rewind to here»
  (диалог со списком файлов) и панель веток работают через `SessionHandle`.
* `app:session_search_flow_test.dart` (новый, после MVP, D-17, §12.6.12): scripted-агент со
  120 сессиями в двух папках. Без `sessionSearch`: ввод `sso` → в сайдбаре только сессии с `sso`
  в заголовке, подпись `session-search-titles-only`; «Today» с фальшивыми часами — только
  сегодняшние; очистка — обычный список. С `sessionSearch`: агент получает один
  `_codelab/session/search` после склейки (не на каждую букву), строка со сниппетом, клик по
  сниппету открывает сессию и прокручивает к `recordId`; «All projects» → `session/list` без
  `cwd`, `scope: "all"`, открытие сессии другой папки — `session/load` с её `cwd`; ответ поиска,
  пришедший после смены текста, не показывается (DSK-22).
* `app:prompt_steer_flow_test.dart` (после MVP, C-03, agent-core-architecture §17.7.11):
  «Направить» в композере и в строке очереди шлёт `_codelab/session/steer`; пузырь с меткой «во
  время хода»; агент без capability — второй части кнопки нет; «Отправить сейчас» (R-18)
  по-прежнему отменяет ход (`app:prompt_queue_flow_test.dart` не меняется).
* `app:usage_display_flow_test.dart` (D-09):
  1. агент без расширения usage → `status-bar-usage` показывает «—», стоимость скрыта;
  2. агент с расширением (режим scripted-агента после принятия расширения через OpenSpec)
     присылает usage двух ходов → поле хода показывает второй ход, поле сессии — сумму;
     подсказка содержит пять счётчиков; контекст 85 % в тоне `warning`.
* `app:transcript_rendering_flow_test.dart` (новый, D-06/D-07/D-08 сквозь весь стек): scripted
  агент стримит мысли, markdown с блоком кода и правку файла → блок мыслей свёрнут после конца,
  код подсвечен, diff показан и открывается полностью, одобрение правки показывает diff.
* `app:navigation_flow_test.dart` (новый, A13): из рабочего места по сочетаниям и из палитры
  открываются файлы, поиск сессий, инспектор протокола, настройки и список сочетаний; Esc
  возвращает на исходную вкладку; при ожидающем одобрении вопрос агента ждёт в ленте (DSK-25).
* `app:subagent_board_flow_test.dart` (после MVP, D-25): scripted-агент с `subagentBoard` и
  `jobBoard` запускает ребёнка и фоновую команду → строки на вкладке «Agents»; «Open transcript»
  показывает реплей только для чтения, лента родителя не меняется; «Stop» и «Kill» шлют
  `_codelab/subagents/cancel` и `_codelab/jobs/kill`; агент без capability — вкладки нет.
* `app:turn_timeline_flow_test.dart` (после MVP, D-22, после `add-usage-extension`): шаги хода с
  usage, раскрытие шага и прокрутка ленты к вызову.
* Все существующие `app:*` (`permission_flow_test.dart`, `prompt_queue_flow_test.dart`,
  `plan_progress_checklist_flow_test.dart`, `multi_session_concurrency_flow_test.dart`,
  `open_project_flow_test.dart` и остальные) проходят без правок сценариев (DSK-17). Единственное
  изменение ожиданий — в `permission_flow_test.dart`: карточка одобрения правки показывает
  предпросмотр `AcpDiffView` (ключ `diff-open-full-<id>`, строки `+`/`−`) вместо текстового
  `diffSummary`; шаги сценария и проверки кнопок не меняются.

**Scripted-агент `codelab_acp_testing`.** Новые режимы для тестов этого раздела:

* настраиваемые `promptCapabilities` (`image`, `embeddedContext`, `audio`) в ответе `initialize`;
* запись полученных `ContentBlock` каждого `session/prompt`, чтобы тест проверял точный состав
  блоков (сценарии `prompt_attachments_flow_test.dart`);
* отказ `-32602` на промпт с `resource_link` (проверка повтора с путями текстом, §12.1.7, шаг 5);
* usage в форме, утверждённой OpenSpec change `add-usage-extension` — добавляется только после
  принятия расширения; до этого сценарий 2 `usage_display_flow_test.dart` помечен `skip` со
  ссылкой на change;
* стрим мыслей, markdown с оградой и правки с `content` типа `diff` по сценарию из фикстуры
  (`transcript_rendering_flow_test.dart`).

**Скрипты melos** (в корневом `pubspec.yaml`, как остальные `test:e2e:app:*`, §9.5):
`test:e2e:app:attachments` (`prompt_attachments_flow_test.dart`), `test:e2e:app:usage`
(`usage_display_flow_test.dart`), `test:e2e:app:transcript-rendering`
(`transcript_rendering_flow_test.dart`).

---

← [12.2. CLI: отображение и ввод](12-2-cli-display-and-input.md) · [Оглавление](../dart-agent-and-clients.md) · [12.4. Первый запуск и настройки](12-4-first-run-and-settings.md) →
