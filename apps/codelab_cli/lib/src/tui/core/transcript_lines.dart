import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../../render/ansi.dart';
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
    for (final (index, item) in view.transcript.indexed) {
      out.addAll(_itemLines(item, width, thoughts, unicode, color));
      addNotes(index + 1);
    }
    for (final note in notes) {
      // Заметка «после» элемента, которого уже нет (новая сессия), — в конец.
      if (note.after > view.transcript.length) {
        out.addAll(wrapLine(sanitizeTerminalText(note.text), width));
      }
    }
    if (view.plan.isNotEmpty) {
      out.add(planHeader);
      for (final entry in view.plan) {
        out.addAll(
          wrapLine(
            '  ${_planMark(entry.status)} ${sanitizeTerminalText(entry.content)}',
            width,
          ),
        );
      }
    }
    return out;
  }

  List<String> _itemLines(
    TranscriptItem item,
    int width,
    ThoughtsMode thoughts,
    bool unicode,
    bool color,
  ) {
    final cached = _cache[item.id];
    if (cached != null &&
        cached.item == item &&
        cached.width == width &&
        cached.thoughts == thoughts) {
      return cached.lines;
    }
    computed++;
    final lines = _build(item, width, thoughts, unicode, color);
    _cache[item.id] = _Entry(item, width, thoughts, lines);
    return lines;
  }

  static List<String> _build(
    TranscriptItem item,
    int width,
    ThoughtsMode thoughts,
    bool unicode,
    bool color,
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
      ToolCallItem() => [toolRow(item, unicode: unicode)],
      NoticeItem(:final kind) => wrapped(
        '${kind == NoticeKind.error ? errorPrefix : notePrefix}'
        '${noticeText(item)}',
      ),
    };
  }

  static String _planMark(PlanEntryStatus status) => switch (status) {
    PlanEntryStatus.completed => '[x]',
    PlanEntryStatus.inProgress => '[~]',
    PlanEntryStatus.pending => '[ ]',
  };
}

final class _Entry {
  const _Entry(this.item, this.width, this.thoughts, this.lines);

  final TranscriptItem item;
  final int width;
  final ThoughtsMode thoughts;
  final List<String> lines;
}
