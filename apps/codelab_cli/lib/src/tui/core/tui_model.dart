import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../../render/terminal_renderer.dart';
import '../../repl/approval_prompt.dart';
import '../../repl/picker_spec.dart';
import '../../repl/repl_command.dart';
import 'composer.dart';
import 'frame.dart';
import 'transcript_lines.dart';

/// Размер терминала в колонках и строках.
final class TerminalSize {
  const TerminalSize({required this.columns, required this.rows});

  final int columns;
  final int rows;

  @override
  bool operator ==(Object other) =>
      other is TerminalSize && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => '${columns}x$rows';
}

/// Прокрутка транскрипта: следование за выводом или удержание окна.
///
/// [top] — первая видимая строка при удержании; [holdTotal] — сколько строк
/// было, когда удержание началось: разница с текущим числом — «↓ N new»
/// (§12.2.7, «Транскрипт и прокрутка»).
final class ScrollState {
  const ScrollState({this.follow = true, this.top = 0, this.holdTotal = 0});

  final bool follow;
  final int top;
  final int holdTotal;
}

/// Состояние экрана полноэкранного режима.
///
/// Почему: kit — владелец сессии, очереди и одобрений, а экрану нужно своё
/// локальное состояние (композер, прокрутка, заметки) рядом с последним
/// `SessionView`; неизменяемая модель и чистый `reduce` проверяются без
/// терминала (§12.2.7, «Архитектура Model–Update–View»; design.md change
/// `add-cli-tui`, D5).
///
/// Для чего: [session] — последняя ревизия; [notes] — строки клиента;
/// [turnStartedAt] — начало идущего хода для статус-строки; [lastInterrupt] —
/// первый Ctrl+C вне хода (выход по второму за 1 с, U-07). [layout] —
/// мемоизация строк транскрипта, общая для `reduce` и `render`. [overlay] —
/// открытый пикер (D10); [detailsFor] — одобрение, у которого по `?`
/// раскрыт `rawInput` (D9); [cwd] — папка сессии для зоны одобрения;
/// [commands] — клиентские команды для дополнения Tab.
///
/// Как использовать: `TuiModel.initial(...)` у `TuiRunner`; дальше — только
/// `reduce`.
final class TuiModel {
  TuiModel._({
    required this.profile,
    required this.size,
    required this.layout,
    this.session,
    this.composer = const ComposerState(),
    this.scroll = const ScrollState(),
    this.notes = const [],
    this.thoughts = ThoughtsMode.dim,
    this.turnStartedAt,
    this.lastInterrupt,
    this.unicode = true,
    this.color = true,
    this.cwd = '',
    this.commands = const [],
    this.overlay,
    this.detailsFor,
  });

  factory TuiModel.initial({
    required String profile,
    required TerminalSize size,
    List<String> history = const [],
    bool unicode = true,
    bool color = true,
    ThoughtsMode thoughts = ThoughtsMode.dim,
    String cwd = '',
    List<ReplCommand> commands = const [],
  }) => TuiModel._(
    profile: profile,
    size: size,
    layout: TranscriptLayout(),
    composer: ComposerState(history: history),
    unicode: unicode,
    color: color,
    thoughts: thoughts,
    cwd: cwd,
    commands: commands,
  );

  final String profile;
  final TerminalSize size;
  final TranscriptLayout layout;
  final SessionView? session;
  final ComposerState composer;
  final ScrollState scroll;
  final List<TuiNote> notes;
  final ThoughtsMode thoughts;
  final DateTime? turnStartedAt;
  final DateTime? lastInterrupt;
  final bool unicode;
  final bool color;
  final String cwd;
  final List<ReplCommand> commands;
  final PickerSpec? overlay;
  final ApprovalRequestId? detailsFor;

  /// Идёт ли ход: клавиши Esc и Ctrl+C отменяют его.
  bool get running => switch (session?.status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    _ => false,
  };

  TuiModel copyWith({
    TerminalSize? size,
    SessionView? session,
    ComposerState? composer,
    ScrollState? scroll,
    List<TuiNote>? notes,
    ThoughtsMode? thoughts,
    DateTime? Function()? turnStartedAt,
    DateTime? Function()? lastInterrupt,
    PickerSpec? Function()? overlay,
    ApprovalRequestId? Function()? detailsFor,
  }) => TuiModel._(
    profile: profile,
    size: size ?? this.size,
    layout: layout,
    session: session ?? this.session,
    composer: composer ?? this.composer,
    scroll: scroll ?? this.scroll,
    notes: notes ?? this.notes,
    thoughts: thoughts ?? this.thoughts,
    turnStartedAt: turnStartedAt == null ? this.turnStartedAt : turnStartedAt(),
    lastInterrupt: lastInterrupt == null ? this.lastInterrupt : lastInterrupt(),
    unicode: unicode,
    color: color,
    cwd: cwd,
    commands: commands,
    overlay: overlay == null ? this.overlay : overlay(),
    detailsFor: detailsFor == null ? this.detailsFor : detailsFor(),
  );
}

/// Пустая сессия до первой ревизии.
const _noSession = SessionView(revision: 0, status: SessionStatusView.idle);

/// Строки транскрипта модели по ширине терминала.
List<String> transcriptLines(TuiModel model) => model.layout.lines(
  model.session ?? _noSession,
  notes: model.notes,
  width: model.size.columns,
  thoughts: model.thoughts,
  unicode: model.unicode,
  color: model.color,
);

/// Одобрение, которого ждёт идущий ход; `null` — композер открыт.
///
/// Запрос, оставшийся в представлении после конца хода, ввод не блокирует —
/// как в REPL (D9).
ApprovalPrompt? approvalOf(TuiModel model) {
  final session = model.session;
  return session != null && session.status == SessionStatusView.running
      ? ApprovalPrompt.first(session, cwd: model.cwd)
      : null;
}

/// Строки зоны одобрения: заголовок, команда, папка, по `?` — `rawInput`
/// не выше половины экрана, затем подсказка (D9). Строки переносятся по
/// ширине: обрезка спрятала бы клавиши подсказки, а подсказка переносится
/// целыми пунктами, чтобы клавиша не оторвалась от подписи.
List<String> approvalLines(TuiModel model, ApprovalPrompt prompt) {
  final block = prompt.block;
  var lines = block;
  if (model.detailsFor == prompt.approval.approvalId) {
    final limit = model.size.rows ~/ 2;
    var details = prompt.details.split('\n');
    if (details.length > limit) {
      details = [...details.take(limit - 1), '  …'];
    }
    lines = [
      ...block.take(block.length - 1),
      for (final line in details) '  $line',
      block.last,
    ];
  }
  final width = model.size.columns;
  return [
    for (final line in lines.take(lines.length - 1)) ...wrapLine(line, width),
    ..._wrapEntries(lines.last, width),
  ];
}

/// Подсказка `  [y] allow once  [n] …` строками не шире [width]: пункты,
/// разделённые двумя пробелами, не рвутся; отступ повторяется.
List<String> _wrapEntries(String hint, int width) {
  const indent = '  ';
  final entries = hint.trimLeft().split('  ');
  final out = <String>[];
  var line = indent;
  for (final entry in entries) {
    final next = line == indent ? '$line$entry' : '$line  $entry';
    if (line != indent && displayWidth(next) > width) {
      out.add(line);
      line = '$indent$entry';
    } else {
      line = next;
    }
  }
  return [...out, line];
}

/// Сколько строк занимает низ экрана: зона одобрения или композер (не
/// больше 10 строк, дальше он прокручивается).
int composerRows(TuiModel model) {
  final prompt = approvalOf(model);
  if (prompt != null) {
    return approvalLines(model, prompt).length;
  }
  return model.composer.lines.length > 10 ? 10 : model.composer.lines.length;
}

/// Видна ли строка подсказок: при высоте меньше 15 строк — нет; в зоне
/// одобрения и в пикере тоже нет — её клавиши там не действуют, а у зоны и
/// пикера свои подсказки.
bool hintsVisible(TuiModel model) =>
    model.size.rows >= 15 && model.overlay == null && approvalOf(model) == null;

/// Высота окна транскрипта. При удержании одна строка уходит под «↓ N new»,
/// поэтому окно не прыгает, когда счётчик появляется.
int transcriptHeight(TuiModel model) {
  final height =
      model.size.rows -
      composerRows(model) -
      (hintsVisible(model) ? 1 : 0) -
      1 -
      (model.scroll.follow ? 0 : 1);
  return height < 0 ? 0 : height;
}

/// Сколько строк пришло с начала удержания; при следовании — `0`.
int newSinceHold(TuiModel model) {
  if (model.scroll.follow) {
    return 0;
  }
  final count = transcriptLines(model).length - model.scroll.holdTotal;
  return count < 0 ? 0 : count;
}
