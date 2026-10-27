import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../input/line_editor.dart';
import '../input/terminal.dart';
import '../render/ansi.dart';
import '../render/sanitize.dart';
import '../render/terminal_renderer.dart';
import '../strings.dart';
import 'approval_prompt.dart';

/// Состояние ввода REPL.
///
/// [editing] — хода нет, строка ввода открыта; [running] — ход идёт, ввод
/// открыт и уходит в очередь kit; [awaitingApproval] — агент ждёт ответа на
/// одобрение, ввод промпта недоступен (spec codelab-cli «Одобрение в REPL»;
/// design.md change `add-codelab-cli`, D7).
enum ReplInputState { editing, running, awaitingApproval }

/// Активная сессия REPL: вывод ревизий, строка ввода и учёт ходов.
///
/// Почему: состояние хода, очередь и одобрения принадлежат kit; REPL
/// выводит их и перерисовывает свою строку ввода так, чтобы она не
/// смешивалась с выводом агента (design.md change `add-codelab-cli`, D6,
/// D7).
///
/// Для чего: [onView] — каждая ревизия `SessionView`, [onOutcome] — исход
/// каждого хода сессии; [send] отправляет промпт или ставит его в очередь;
/// [drawInput] и [hideInput] — строка ввода в терминале. Строка ввода
/// рисуется только в TTY и только когда вывод стоит в начале строки: пока
/// ответ дописывается, она скрыта, а набранный текст остаётся в редакторе.
///
/// Как использовать: создаёт `Repl` после открытия сессии; ввод клавиш —
/// через [editor] и [send]. [outstanding] — промпты без исхода: по нему REPL
/// ждёт конца ходов перед выходом в конце ввода.
final class ReplSession {
  ReplSession({
    required this.handle,
    required Terminal terminal,
    required this.renderer,
    required this.editor,
  }) : _terminal = terminal;

  final SessionHandle handle;
  final Terminal _terminal;
  final TerminalRenderer renderer;
  final LineEditor editor;

  /// Запрос одобрения, блок которого показан сейчас; запросы показываются
  /// по одному в порядке `pendingApprovals` (D8).
  ApprovalRequestId? _shownApproval;

  /// Строка ввода нарисована; [_cursorRow] — строка экрана с курсором,
  /// считая от первой строки ввода.
  var _inputShown = false;
  var _cursorRow = 0;
  var _outstanding = 0;

  /// Вывод больше не нужен: REPL выходит.
  var closed = false;

  /// Режим терминала выбран, и строку ввода можно рисовать: набранное до
  /// raw-режима пришло бы с переводом `\r` в `\n`.
  var inputOpen = false;

  int get outstanding => _outstanding;

  ReplInputState get state {
    final view = handle.current;
    return switch (view.status) {
      // Одобрение ждёт ответа только внутри хода: запрос, который остался
      // в представлении после конца хода, ввод не блокирует.
      SessionStatusView.running when view.pendingApprovals.isNotEmpty =>
        ReplInputState.awaitingApproval,
      SessionStatusView.running ||
      SessionStatusView.cancelling => ReplInputState.running,
      _ => ReplInputState.editing,
    };
  }

  /// Новая ревизия: вывод изменений, строка о новом одобрении, строка ввода.
  void onView(SessionView view) {
    if (closed) {
      return;
    }
    hideInput();
    renderer.render(view);
    final approval = state == ReplInputState.awaitingApproval
        ? view.pendingApprovals.firstOrNull
        : null;
    if (approval == null) {
      _shownApproval = null;
    } else if (approval.approvalId != _shownApproval) {
      _shownApproval = approval.approvalId;
      approvalPrompt!.block.forEach(renderer.line);
    }
    drawInput();
  }

  /// Исход хода сессии, в том числе промпта из очереди.
  void onOutcome(PromptOutcome outcome) {
    if (outcome is PromptQueued || closed) {
      return;
    }
    if (_outstanding > 0) {
      _outstanding--;
    }
    hideInput();
    renderer
      ..render(handle.current)
      ..finishTurn();
    switch (outcome) {
      case PromptCompleted(:final turn)
          when turn.stopReason == StopReason.cancelled:
        renderer.line(turnCancelled);
      case PromptFailed(:final error) when !_endsWithErrorNotice():
        // Заметку об ошибке хода kit уже вывел транскриптом; без неё —
        // причина сама.
        renderer.line(sanitizeTerminalText(turnFailed(describeFailure(error))));
      case _:
        break;
    }
    drawInput();
  }

  /// Отправляет [text]; во время хода kit ставит его в очередь, и REPL
  /// печатает `queued: <n>` (U-15). Промпт выводится строкой `> текст`, когда
  /// его ход начинается.
  void send(String text) {
    hideInput();
    final queued = handle.current.queue.length;
    _outstanding++;
    unawaited(
      handle
          .send(text)
          .then<void>(
            (_) {},
            onError: (Object error) {
              // Ошибка отправки до исхода хода (например, сессия отсоединена):
              // kit публикует её исходом, но на всякий случай она не теряется.
              renderer.line(sanitizeTerminalText(turnFailed('$error')));
            },
          ),
    );
    final now = handle.current.queue.length;
    if (now > queued) {
      renderer.line(queuedMessage(now));
    }
    drawInput();
  }

  /// Блок первого ожидающего одобрения; `null` — одобрений нет.
  ApprovalPrompt? get approvalPrompt {
    final view = handle.current;
    final approval = view.pendingApprovals.firstOrNull;
    return approval == null
        ? null
        : ApprovalPrompt(
            approval,
            title: _titleOf(view, approval),
            cwd: handle.cwd,
          );
  }

  /// Промпты убраны из очереди командой: исхода у них не будет.
  void forgetQueued(int count) {
    _outstanding = (_outstanding - count).clamp(0, _outstanding);
  }

  /// Строка клиента (подсказки, ошибки команд) вне транскрипта.
  void say(String text) {
    hideInput();
    renderer.line(text);
    drawInput();
  }

  /// Перерисовывает строку ввода после правки в редакторе.
  void redraw() {
    hideInput();
    drawInput();
  }

  /// Ctrl+L: очистить экран и нарисовать строку ввода заново.
  void clearScreenAndRedraw() {
    if (!_terminal.hasTerminal) {
      return;
    }
    _inputShown = false;
    _terminal.output.write(clearScreen);
    drawInput();
  }

  /// Рисует строку ввода: `> ` и текст редактора, курсор — на его позиции.
  void drawInput() {
    if (closed ||
        !inputOpen ||
        _inputShown ||
        !_terminal.hasTerminal ||
        state == ReplInputState.awaitingApproval ||
        !renderer.atLineStart) {
      return;
    }
    final columns = _terminal.columns < 1 ? 80 : _terminal.columns;
    final lines = editor.text.split('\n');
    final out = StringBuffer();
    // Строки экрана до начала каждой строки ввода, с учётом переноса по
    // ширине терминала.
    var row = 0;
    var cursorRow = 0;
    var cursorColumn = 0;
    var endRow = 0;
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final prefix = i == 0 ? inputPrompt : inputContinuation;
      final line = sanitizeTerminalText(lines[i]);
      if (i > 0) {
        out.write('\n');
      }
      out.write('$prefix$line');
      final width = prefix.length + lines[i].runes.length;
      final cursorInLine = editor.cursor - offset;
      if (cursorInLine >= 0 && cursorInLine <= lines[i].runes.length) {
        final column = prefix.length + cursorInLine;
        cursorRow = row + column ~/ columns;
        cursorColumn = column % columns;
      }
      endRow = row + (width - 1) ~/ columns;
      row = endRow + 1;
      offset += lines[i].runes.length + 1;
    }
    out
      ..write(cursorUp(endRow - cursorRow))
      ..write('\r')
      ..write(cursorForward(cursorColumn));
    _terminal.output.write(out);
    _cursorRow = cursorRow;
    _inputShown = true;
  }

  /// Стирает строку ввода, чтобы вывод агента пошёл на её место.
  void hideInput() {
    if (!_inputShown) {
      return;
    }
    _terminal.output.write('${cursorUp(_cursorRow)}\r$clearToScreenEnd');
    _inputShown = false;
  }

  bool _endsWithErrorNotice() => switch (handle.current.transcript.lastOrNull) {
    NoticeItem(kind: NoticeKind.error) => true,
    _ => false,
  };

  static String _titleOf(SessionView view, PendingApprovalView approval) {
    for (final item in view.transcript) {
      if (item case ToolCallItem(
        :final title,
        approval: PendingApprovalView(:final approvalId),
      ) when approvalId == approval.approvalId) {
        return title;
      }
    }
    return 'tool call';
  }
}
