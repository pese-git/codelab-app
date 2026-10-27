import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../strings.dart';
import 'ansi.dart';
import 'output_surface.dart';
import 'sanitize.dart';
import 'tool_row.dart';

/// Показ мыслей модели: `/thoughts dim|collapsed|hidden` (§12.2.3).
///
/// [dim] — текст по мере прихода приглушённо; [collapsed] — одна строка
/// `thought for <n>s` после мыслей; [hidden] — ничего.
enum ThoughtsMode { dim, collapsed, hidden }

/// Печать хода из ревизий `SessionView` построчно, без перерисовки экрана.
///
/// Почему: состояние хода — у kit, а терминал умеет только дописывать;
/// рендер помнит, что уже напечатано, и выводит только изменения, не
/// повторяя текст (U-01; spec codelab-cli «Рендер хода в REPL»; design.md
/// change `add-codelab-cli`, D6).
///
/// Для чего: ответ — хвост сверх напечатанного; мысли — до ответа по
/// [thoughts]; вызов инструмента — строка при появлении и итоговая строка со
/// временем; план — целиком при изменении; заметка и промпт пользователя
/// (`> текст`) — строкой. Весь текст сессии проходит `sanitizeTerminalText`,
/// кроме ответа на [OutputSurface.raw]: там он байт в байт, а мысли,
/// промпты и ANSI не выводятся, строки инструментов, план и заметки идут в
/// [err].
///
/// Как использовать: REPL создаёт рендер на сессию и вызывает [render] на
/// каждую ревизию, [finishTurn] — по исходу хода; загруженную сессию
/// печатает [replay] или пропускает [skip]. [atLineStart] — можно ли сейчас
/// рисовать строку ввода. [clock] — часы времени вызовов и мыслей.
final class TerminalRenderer {
  TerminalRenderer({
    required OutputSurface surface,
    required StringSink out,
    required StringSink err,
    this.unicode = true,
    this.thoughts = ThoughtsMode.dim,
    DateTime Function()? clock,
  }) : _surface = surface,
       _out = out,
       _err = err,
       _clock = clock ?? DateTime.now;

  final OutputSurface _surface;
  final StringSink _out;
  final StringSink _err;
  final DateTime Function() _clock;

  /// Значки инструментов в UTF-8 или ASCII (§12.2.4).
  final bool unicode;

  /// Показ мыслей; меняется командой `/thoughts` до конца процесса.
  ThoughtsMode thoughts;

  /// Последний обработанный экземпляр каждого элемента: `identical` — без
  /// изменений (правило проекции §12.5.4).
  final _seen = <String, TranscriptItem>{};

  /// Длина уже обработанного текста ответа и мыслей по id элемента.
  final _printed = <String, int>{};

  /// Когда вызов появился и какие вызовы уже напечатаны итоговой строкой.
  final _toolStarted = <String, DateTime>{};
  final _toolDone = <String>{};

  /// Напечатанные промпты и заметки.
  final _lines = <String>{};

  /// Когда начались свёрнутые мысли; [_openThought] — ещё без итоговой
  /// строки.
  final _thoughtStarted = <String, DateTime>{};
  String? _openThought;

  var _plan = const <PlanEntryView>[];

  /// Элемент, текст которого дописывается сейчас: следующий элемент
  /// начинается с новой строки.
  String? _openId;
  var _atLineStart = true;

  /// Последними напечатаны мысли: перед ответом — пустая строка (§12.2.3).
  var _afterThoughts = false;

  bool get _raw => _surface == OutputSurface.raw;

  /// Курсор в начале строки: последнее напечатанное в stdout кончается
  /// переводом строки или ничего не напечатано.
  bool get atLineStart => _atLineStart;

  /// Выводит изменения ревизии [view] по сравнению с прошлыми.
  void render(SessionView view) {
    for (final item in view.transcript) {
      if (identical(_seen[item.id], item)) {
        continue;
      }
      _seen[item.id] = item;
      switch (item) {
        case UserItem(:final id, :final text):
          if (!_raw && _lines.add(id)) {
            _closeThought();
            _line(
              '$inputPrompt${sanitizeTerminalText(text).replaceAll('\n', '\n$inputContinuation')}',
            );
          }
        case ThoughtItem():
          _thought(item);
        case AgentTextItem():
          _text(item);
        case ToolCallItem():
          _tool(item);
        case NoticeItem(:final id, :final kind):
          if (_lines.add(id)) {
            _closeThought();
            final prefix = kind == NoticeKind.error ? errorPrefix : notePrefix;
            _line(sanitizeTerminalText('$prefix${noticeText(item)}'), _raw);
          }
      }
    }
    if (!_samePlan(view.plan)) {
      _plan = view.plan;
      if (_plan.isNotEmpty) {
        printPlan(_plan);
      }
    }
  }

  /// План целиком: заголовок и строка на запись (`[x]`, `[~]`, `[ ]`); на
  /// [OutputSurface.raw] — в stderr. Для изменения плана и `/plan`.
  void printPlan(List<PlanEntryView> plan) {
    _closeThought();
    _line(planHeader, _raw);
    for (final entry in plan) {
      _line(
        '  ${_planMark(entry.status)} ${sanitizeTerminalText(entry.content)}',
        _raw,
      );
    }
  }

  /// Ход закончился: свёрнутые мысли получают итоговую строку, открытая
  /// строка закрывается переводом строки.
  void finishTurn() {
    _closeThought();
    if (!_atLineStart) {
      _out.write('\n');
      _atLineStart = true;
    }
    _openId = null;
    _afterThoughts = false;
  }

  /// Строка клиента вне транскрипта (`queued: 1`, `cancelled`): с новой
  /// строки в stdout, а на [OutputSurface.raw] — в stderr, чтобы stdout
  /// оставался ответом агента.
  void line(String text) => _line(text, _raw);

  /// Печатает уже загруженную сессию целиком, с промптами пользователя
  /// (`--continue`, `/resume`).
  void replay(SessionView view) {
    render(view);
    finishTurn();
  }

  /// Считает транскрипт [view] напечатанным, ничего не выводя.
  void skip(SessionView view) {
    final now = _clock();
    for (final item in view.transcript) {
      _seen[item.id] = item;
      switch (item) {
        case AgentTextItem(:final id, :final text) ||
            ThoughtItem(:final id, :final text):
          _printed[id] = text.length;
        case ToolCallItem(:final id):
          _toolStarted[id] = now;
          if (isFinalToolCall(item)) {
            _toolDone.add(id);
          }
        case UserItem(:final id) || NoticeItem(:final id):
          _lines.add(id);
      }
    }
    _plan = view.plan;
  }

  void _text(AgentTextItem item) {
    final printed = _printed[item.id] ?? 0;
    if (item.text.length <= printed) {
      return;
    }
    final tail = item.text.substring(printed);
    _printed[item.id] = item.text.length;
    _closeThought();
    if (_openId != item.id) {
      if (!_atLineStart) {
        _out.write('\n');
      }
      if (_afterThoughts) {
        _out.write('\n');
      }
    }
    _afterThoughts = false;
    _out.write(_raw ? tail : sanitizeTerminalText(tail));
    _openId = item.id;
    _atLineStart = tail.endsWith('\n');
  }

  void _thought(ThoughtItem item) {
    if (_raw || thoughts == ThoughtsMode.hidden) {
      _printed[item.id] = item.text.length;
      return;
    }
    if (thoughts == ThoughtsMode.collapsed) {
      if (!_thoughtStarted.containsKey(item.id)) {
        _thoughtStarted[item.id] = _clock();
        _openThought = item.id;
      }
      _printed[item.id] = item.text.length;
      return;
    }
    final printed = _printed[item.id] ?? 0;
    if (item.text.length <= printed) {
      return;
    }
    final tail = sanitizeTerminalText(item.text.substring(printed));
    _printed[item.id] = item.text.length;
    if (_openId != item.id && !_atLineStart) {
      _out.write('\n');
    }
    _out.write(_styled(tail, sgrDim));
    _openId = item.id;
    _atLineStart = tail.endsWith('\n');
    _afterThoughts = true;
  }

  void _tool(ToolCallItem item) {
    final now = _clock();
    final started = _toolStarted[item.id];
    if (started == null) {
      _toolStarted[item.id] = now;
      if (isFinalToolCall(item)) {
        _toolDone.add(item.id);
      }
      _closeThought();
      _line(toolRow(item, unicode: unicode), _raw);
      return;
    }
    if (_toolDone.contains(item.id) || !isFinalToolCall(item)) {
      return;
    }
    _toolDone.add(item.id);
    _closeThought();
    _line(
      toolRow(item, unicode: unicode, elapsed: now.difference(started)),
      _raw,
    );
  }

  /// Итоговая строка свёрнутых мыслей, если они ещё открыты.
  void _closeThought() {
    final id = _openThought;
    if (id == null) {
      return;
    }
    _openThought = null;
    final elapsed = _clock().difference(_thoughtStarted[id]!);
    _line(_styled(thoughtFor(elapsed), sgrDim));
  }

  /// Целая строка [text]: в stdout с новой строки или в stderr ([toErr]).
  void _line(String text, [bool toErr = false]) {
    if (toErr) {
      _err.writeln(text);
      return;
    }
    if (!_atLineStart) {
      _out.write('\n');
    }
    _out.write('$text\n');
    _atLineStart = true;
    _openId = null;
    _afterThoughts = false;
  }

  String _styled(String text, String sgr) =>
      _surface == OutputSurface.ansi ? styleLines(text, sgr) : text;

  bool _samePlan(List<PlanEntryView> plan) {
    if (identical(plan, _plan)) {
      return true;
    }
    if (plan.length != _plan.length) {
      return false;
    }
    for (var i = 0; i < plan.length; i++) {
      if (plan[i] != _plan[i]) {
        return false;
      }
    }
    return true;
  }

  static String _planMark(PlanEntryStatus status) => switch (status) {
    PlanEntryStatus.completed => '[x]',
    PlanEntryStatus.inProgress => '[~]',
    PlanEntryStatus.pending => '[ ]',
  };
}

/// Текст заметки для человека: у сорвавшегося хода — причина агента из
/// `PromptFailure`, а не общий текст ошибки запроса. Общий для REPL и
/// headless (stderr).
String noticeText(NoticeItem notice) => switch (notice.failure) {
  AgentPromptFailure(:final errorClass, :final message) =>
    errorClass == null ? message : '$message ($errorClass)',
  RequestPromptFailure(:final code, :final message) =>
    'agent error $code: $message',
  ConnectionLostPromptFailure() => 'the connection to the agent was lost',
  UnknownPromptFailure() || null => notice.text,
};
