import 'package:codelab_client_core/codelab_client_core.dart';

import '../../render/ansi.dart';
import '../../render/plan_format.dart';
import '../../render/sanitize.dart';
import '../../render/terminal_renderer.dart';
import '../../render/tool_row.dart';
import '../../strings.dart';
import 'frame.dart';

/// Строка клиента в транскрипте TUI: вывод команды, подсказка, ошибка.
///
/// Почему: kit не знает о выводе клиентских команд, а в полноэкранном
/// режиме его некуда напечатать, кроме транскрипта (design.md change
/// `add-cli-tui`, D5).
///
/// Для чего: [after] — сколько элементов транскрипта было, когда заметка
/// появилась; она показывается после элемента с этим номером, поэтому
/// новые элементы не сдвигают её вниз.
final class TuiNote {
  const TuiNote({required this.after, required this.text});

  final int after;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TuiNote && other.after == after && other.text == text;

  @override
  int get hashCode => Object.hash(after, text);

  @override
  String toString() => 'TuiNote($after, $text)';
}

/// Строки транскрипта TUI с кэшем переносов по элементам.
///
/// Почему: стрим меняет обычно только последний элемент, а перенос всего
/// транскрипта на каждой дельте занял бы кадр целиком (§12.2.7,
/// «Транскрипт и прокрутка»; design.md change `add-cli-tui`, D6).
///
/// Для чего: правила строк — те же, что у построчного REPL: промпт `> `,
/// ответ с переносом по ширине, мысли по [ThoughtsMode], вызов инструмента
/// строкой `toolRow` без `rawInput` (TUI-6), заметки kit и клиента, план. Текст
/// сессии проходит `sanitizeTerminalText` (TUI-11).
///
/// Как использовать: один экземпляр на модель экрана; [lines] вызывают и
/// `reduce` (прокрутка), и `render`. Кэш — мемоизация: результат зависит
/// только от аргументов. [computed] — сколько элементов перенесено заново.
final class TranscriptLayout {
  final _cache = <String, _Entry>{};

  /// Сколько раз строки элемента строились заново, а не из кэша.
  var computed = 0;

  List<String> lines(
    SessionView view, {
    List<TuiNote> notes = const [],
    required int width,
    ThoughtsMode thoughts = ThoughtsMode.dim,
    bool unicode = true,
    bool color = true,
    bool expandDetails = false,
  }) {
    final out = <String>[];
    void addNotes(int after) {
      for (final note in notes) {
        if (note.after == after) {
          for (final line in sanitizeTerminalText(note.text).split('\n')) {
            out.addAll(wrapLine(line, width));
          }
        }
      }
    }

    addNotes(0);
    TranscriptItem? previous;
    for (final (index, item) in view.transcript.indexed) {
      // Ответ после показанных мыслей — с пустой строкой, как в REPL
      // (§12.2.3).
      if (item is AgentTextItem &&
          previous is ThoughtItem &&
          thoughts != ThoughtsMode.hidden) {
        out.add('');
      }
      out.addAll(
        _itemLines(item, width, thoughts, unicode, color, expandDetails),
      );
      addNotes(index + 1);
      previous = item;
    }
    for (final note in notes) {
      // Заметка «после» элемента, которого уже нет (новая сессия), — в конец.
      if (note.after > view.transcript.length) {
        out.addAll(wrapLine(sanitizeTerminalText(note.text), width));
      }
    }
    if (view.plan.isNotEmpty) {
      for (final line in planLines(view.plan)) {
        out.addAll(wrapLine(line, width));
      }
    }
    return out;
  }

  /// План строками без переноса: заголовок и запись на строку (`[x]`,
  /// `[~]`, `[ ]`) — для блока в конце транскрипта и для `/plan`.
  static List<String> planLines(List<PlanEntryView> plan) => [
    planHeader,
    for (final entry in plan) '  ${planEntryText(entry)}',
  ];

  List<String> _itemLines(
    TranscriptItem item,
    int width,
    ThoughtsMode thoughts,
    bool unicode,
    bool color,
    bool expanded,
  ) {
    final cached = _cache[item.id];
    if (cached != null &&
        cached.item == item &&
        cached.width == width &&
        cached.thoughts == thoughts &&
        cached.expanded == expanded) {
      return cached.lines;
    }
    computed++;
    final lines = _build(item, width, thoughts, unicode, color, expanded);
    _cache[item.id] = _Entry(item, width, thoughts, expanded, lines);
    return lines;
  }

  static List<String> _build(
    TranscriptItem item,
    int width,
    ThoughtsMode thoughts,
    bool unicode,
    bool color,
    bool expanded,
  ) {
    List<String> wrapped(String text) => [
      for (final line in sanitizeTerminalText(text).split('\n'))
        ...wrapLine(line, width),
    ];
    String dim(String line) =>
        color && line.isNotEmpty ? '$sgrDim$line$sgrReset' : line;

    return switch (item) {
      UserItem(:final text) => [
        for (final (i, line) in sanitizeTerminalText(text).split('\n').indexed)
          ...wrapLine(
            '${i == 0 ? inputPrompt : inputContinuation}$line',
            width,
          ),
      ],
      AgentTextItem(:final text) => wrapped(text),
      ThoughtItem(:final text) => switch (thoughts) {
        ThoughtsMode.dim => wrapped(text).map(dim).toList(),
        ThoughtsMode.collapsed => [dim(unicode ? 'thinking…' : 'thinking...')],
        ThoughtsMode.hidden => const [],
      },
      ToolCallItem() => _toolLines(item, width, unicode, color, expanded),
      // Тихая строка операций со списком: без рамки и статуса (D27).
      TaskOpsItem() => [
        dim('${unicode ? '☰ ' : '- '}${sanitizeTerminalText(item.text)}'),
      ],
      NoticeItem(:final kind) => wrapped(
        '${kind == NoticeKind.error ? errorPrefix : notePrefix}'
        '${noticeText(item)}',
      ),
    };
  }
}

/// Предел строк отчёта субагента в раскрытой строке (D27, D48 п. 2).
const _maxReportLines = 20;

/// Строки вызова: обычный вызов — одна строка; `agent` — строка статуса,
/// исход одобрений потомков, «хвост» работающего (D25) и в раскрытом виде
/// вложенные вызовы потомков и отчёт (D48 п. 2).
///
/// Почему: пока потомок работает, нужно видеть, что он делает, а полное
/// дерево и отчёт — по запросу (Ctrl+O), иначе длинный отчёт съел бы экран.
List<String> _toolLines(
  ToolCallItem item,
  int width,
  bool unicode,
  bool color,
  bool expanded,
) {
  if (item.details?.subagentCall == null) {
    return [toolRow(item, unicode: unicode)];
  }
  final tail = item.tail;
  final tailShown =
      !isFinalToolCall(item) && !expanded && tail.calls.isNotEmpty;
  return [
    // Вызов `agent`: итог в самой строке статуса (D24, D27); с хвостом
    // строки прогресса нет — он показывает, что делает потомок, без токенов
    // (Q15).
    subagentStatusRow(item, unicode: unicode, showProgress: !tailShown),
    // Исход одобрений потомков под строкой корня (D43 п. 2).
    for (final (_, line) in childOutcomeLines(item)) ...wrapLine(line, width),
    if (expanded) ...[
      ..._stepLines(item.children, 1, width, unicode, color),
      ..._reportLines(item, width),
    ] else if (tailShown) ...[
      for (final call in tail.calls)
        // Операция со списком задач — тихая строка, как в раскрытом виде
        // (D48 п. 3); остальные — обычная строка вызова.
        if (tail.operations[call.toolCallId] case final operation?)
          _quietLine(operation, 1, unicode, color)
        else
          '${_stepPrefix(1, unicode)}${toolRow(call, unicode: unicode)}',
      if (tail.moreCount > 0) '  +${tail.moreCount} more tool calls',
    ],
  ];
}

/// Отступ и маркер вложенной строки: два пробела на уровень и `↳ ` (без
/// UTF-8 — `> `).
String _stepPrefix(int depth, bool unicode) =>
    '${'  ' * depth}${unicode ? '↳ ' : '> '}';

/// Вложенные строки раскрытого `agent`: вызовы потомков по порядку, вложенный
/// `agent` — строкой с итогом без отчёта, операция со списком — тихой строкой
/// (D48 п. 3, 4).
List<String> _stepLines(
  List<TranscriptItem> children,
  int depth,
  int width,
  bool unicode,
  bool color,
) {
  final prefix = _stepPrefix(depth, unicode);
  return [
    for (final child in children)
      ...switch (child) {
        ToolCallItem() => [
          // Вложенный `agent` — та же строка с итогом в скобках, что в REPL
          // (`toolRow`), без отчёта (D48 п. 4).
          '$prefix${toolRow(child, unicode: unicode)}',
          ..._stepLines(child.children, depth + 1, width, unicode, color),
        ],
        TaskOpsItem() => [_quietLine(child, depth, unicode, color)],
        _ => const <String>[],
      },
  ];
}

/// Тихая строка операции со списком задач: приглушённый текст без значка.
String _quietLine(TaskOpsItem item, int depth, bool unicode, bool color) {
  final text =
      '${_stepPrefix(depth, unicode)}${sanitizeTerminalText(item.text)}';
  return color ? '$sgrDim$text$sgrReset' : text;
}

/// Отчёт `agent` корня до [_maxReportLines] строк и `… (<n> more lines)`.
List<String> _reportLines(ToolCallItem item, int width) {
  final report = ToolRowFormatter.format(item, cwd: '').report;
  if (report == null) {
    return const [];
  }
  final lines = report.split('\n');
  return [
    for (final line in lines.take(_maxReportLines))
      ...wrapLine('  ${sanitizeTerminalText(line)}', width),
    if (lines.length > _maxReportLines)
      '  … (${lines.length - _maxReportLines} more lines)',
  ];
}

final class _Entry {
  const _Entry(this.item, this.width, this.thoughts, this.expanded, this.lines);

  final TranscriptItem item;
  final int width;
  final bool expanded;
  final ThoughtsMode thoughts;
  final List<String> lines;
}
