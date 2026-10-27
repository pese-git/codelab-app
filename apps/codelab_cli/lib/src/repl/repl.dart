import 'dart:async';
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../exit_codes.dart';
import '../input/history.dart';
import '../input/key_bindings.dart';
import '../input/key_decoder.dart';
import '../input/line_editor.dart';
import '../input/terminal.dart';
import '../render/output_surface.dart';
import '../render/sanitize.dart';
import '../render/terminal_renderer.dart';
import '../session_setup.dart';
import 'repl_session.dart';

/// Интерактивный режим `codelab`: ввод промптов, вывод ходов, очередь и
/// отмена.
///
/// Почему: REPL — основной режим терминального клиента; состояние сессии,
/// очередь и одобрения у kit, а REPL владеет только терминалом: режимом
/// stdin, строкой ввода, историей и клавишами (spec codelab-cli «Редактор
/// строки и клавиши», «Очередь промптов в REPL», «Рендер хода в REPL»;
/// design.md change `add-codelab-cli`, D5–D7).
///
/// Для чего: в TTY — raw-режим и клавиши по таблице [KeyBindings.mvp];
/// без TTY — построчный ввод, а конец ввода завершает REPL после всех ходов.
/// Выход — Ctrl+D на пустой строке, двойной Ctrl+C за [exitWindow], конец
/// ввода (в TTY — сразу, с отменой хода) или [interrupt]; терминал
/// восстанавливается на любом выходе.
///
/// Как использовать: `await Repl(...).run()` — код выхода: `0`, `1` (не
/// удалось подключиться или открыть сессию) или код сигнала из [interrupt].
/// Закрывает рабочее пространство вызывающий.
final class Repl {
  Repl({
    required ClientWorkspace workspace,
    required Terminal terminal,
    required ConnectionProfile profile,
    required String cwd,
    required HistoryStore history,
    OutputSurface surface = OutputSurface.ansi,
    bool unicode = true,
    String? firstMessage,
    String? resume,
    bool continueLast = false,
    String? model,
    String? mode,
    KeyBindings? keys,
    Duration escapeTimeout = const Duration(milliseconds: 50),
    Duration exitWindow = const Duration(seconds: 1),
    Duration cancelGrace = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _workspace = workspace,
       _terminal = terminal,
       _profile = profile,
       _cwd = cwd,
       _historyStore = history,
       _surface = surface,
       _unicode = unicode,
       _firstMessage = firstMessage,
       _resume = resume,
       _continueLast = continueLast,
       _model = model,
       _mode = mode,
       _keys = keys ?? KeyBindings.mvp,
       _escapeTimeout = escapeTimeout,
       _exitWindow = exitWindow,
       _cancelGrace = cancelGrace,
       _clock = clock ?? DateTime.now;

  final ClientWorkspace _workspace;
  final Terminal _terminal;
  final ConnectionProfile _profile;
  final String _cwd;
  final HistoryStore _historyStore;
  final OutputSurface _surface;
  final bool _unicode;
  final String? _firstMessage;
  final String? _resume;
  final bool _continueLast;
  final String? _model;
  final String? _mode;
  final KeyBindings _keys;
  final Duration _escapeTimeout;

  /// Окно повторного Ctrl+C для выхода (U-07).
  final Duration _exitWindow;

  /// Сколько ждать ответа агента на `session/cancel` при выходе во время
  /// хода (design.md, D13).
  final Duration _cancelGrace;
  final DateTime Function() _clock;

  final _exit = Completer<int>();
  ReplSession? _session;
  DateTime? _lastCtrlC;
  var _inputDone = false;

  /// Запись истории идёт по одной, чтобы файл не перезаписывался
  /// вперемешку.
  Future<void> _saving = Future.value();

  Future<int> run() async {
    final history = History(await _loadHistory());
    final StreamSubscription<SessionView> views;
    final StreamSubscription<PromptOutcome> outcomes;
    final ReplSession session;
    try {
      session = await _open(history);
    } on _OpenFailed {
      return failureExit;
    }
    _session = session;
    views = session.handle.view.listen(session.onView);
    outcomes = _workspace.promptOutcomes
        .where((outcome) => outcome.sessionId == session.handle.id)
        .listen((outcome) {
          session.onOutcome(outcome);
          _exitIfInputDone();
        });

    StreamSubscription<Object?>? input;
    try {
      if (_terminal.hasTerminal) {
        _terminal.enableRawMode();
        final decoder = KeyDecoder(_onKey, escapeTimeout: _escapeTimeout);
        input = _terminal.input.listen(
          decoder.add,
          // Конец ввода терминала — как Ctrl+D: выход, идущий ход
          // отменяется. Ждать ходов имеет смысл только построчному вводу,
          // где промпты пришли из pipe целиком.
          onDone: () {
            decoder.close();
            unawaited(_finish(okExit));
          },
        );
      } else {
        input = _terminal.input
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(_onLine, onDone: _onInputDone);
      }
      session.drawInput();
      if (_firstMessage case final text? when text.trim().isNotEmpty) {
        history.add(text);
        _saveHistory(history);
        session.send(text);
      }
      return await _exit.future;
    } finally {
      session
        ..hideInput()
        ..closed = true;
      if (!session.renderer.atLineStart) {
        _terminal.output.write('\n');
      }
      await input?.cancel();
      await views.cancel();
      await outcomes.cancel();
      _terminal.restore();
      await _saving;
    }
  }

  /// Сигнал процесса: отменяет идущий ход, ждёт ответа агента не дольше
  /// `cancelGrace` и выходит с кодом [code] (`143` — SIGTERM).
  Future<void> interrupt(int code) => _finish(code);

  /// SIGINT вне raw-режима ведёт себя как Ctrl+C (spec codelab-cli «Сигналы
  /// CLI»).
  void onSigint() {
    final session = _session;
    if (session == null) {
      unawaited(_finish(sigintExit));
      return;
    }
    _handle(
      _keys.actionFor(
        Key.ctrlC,
        running: session.state != ReplInputState.editing,
      ),
    );
  }

  Future<ReplSession> _open(History history) async {
    final SessionHandle handle;
    try {
      await _workspace.connect(_profile, projectDirectory: _cwd);
      handle = await openCliSession(
        _workspace,
        _cwd,
        resume: _resume,
        last: _continueLast,
      );
      await applyConfigFlag(handle, 'model', _model);
      await applyConfigFlag(handle, 'mode', _mode);
    } on Object catch (error) {
      _terminal.errorOutput.writeln(
        sanitizeTerminalText(
          error is SessionSetupError
              ? 'codelab: ${error.message}'
              : 'codelab: cannot start the agent ${describeProfile(_profile)}: '
                    '${describeFailure(error)}',
        ),
      );
      throw const _OpenFailed();
    }
    final renderer = TerminalRenderer(
      surface: _surface,
      out: _terminal.output,
      err: _terminal.errorOutput,
      unicode: _unicode,
      clock: _clock,
    );
    // Загруженная сессия печатается целиком: пользователь видит, что
    // продолжает (spec codelab-cli «Сессии в REPL»).
    if (_resume != null || _continueLast) {
      renderer.replay(handle.current);
    } else {
      renderer.skip(handle.current);
    }
    return ReplSession(
      handle: handle,
      terminal: _terminal,
      renderer: renderer,
      editor: LineEditor(history),
    );
  }

  void _onKey(KeyEvent event) {
    final session = _session;
    if (session == null || _exit.isCompleted) {
      return;
    }
    switch (event) {
      case TextKey(:final text):
        if (session.state == ReplInputState.awaitingApproval) {
          return;
        }
        session.editor.insert(text);
        session.redraw();
      case SpecialKey(:final key):
        _handle(
          _keys.actionFor(
            key,
            running: session.state != ReplInputState.editing,
          ),
        );
    }
  }

  void _handle(KeyAction? action) {
    final session = _session;
    if (session == null || action == null || _exit.isCompleted) {
      return;
    }
    // Пока ждёт одобрение, ввод промпта недоступен: работает только отмена
    // хода (spec codelab-cli «Одобрение в REPL»).
    if (session.state == ReplInputState.awaitingApproval &&
        action != KeyAction.cancelTurn &&
        action != KeyAction.clearScreen) {
      return;
    }
    final editor = session.editor;
    switch (action) {
      case KeyAction.submit:
        final text = editor.submit();
        if (text == null || text.isEmpty) {
          session.redraw();
          return;
        }
        _saveHistory(editor.history);
        session.send(text);
      case KeyAction.newline:
        editor.insertNewline();
        session.redraw();
      case KeyAction.cancelTurn:
        unawaited(_cancel(session));
      case KeyAction.clearLine:
        editor.clear();
        session.redraw();
      case KeyAction.interrupt:
        final now = _clock();
        final last = _lastCtrlC;
        if (last != null && now.difference(last) <= _exitWindow) {
          unawaited(_finish(okExit));
          return;
        }
        _lastCtrlC = now;
        editor.clear();
        session.redraw();
      case KeyAction.exit:
        if (editor.isEmpty) {
          unawaited(_finish(okExit));
        }
      case KeyAction.historyPrevious:
        editor.historyPrevious();
        session.redraw();
      case KeyAction.historyNext:
        editor.historyNext();
        session.redraw();
      case KeyAction.complete:
        // Дополнение `/команд` по каталогу — задача 7.4 tasks.md.
        break;
      case KeyAction.clearScreen:
        session.clearScreenAndRedraw();
      case KeyAction.moveLeft:
        editor.moveLeft();
        session.redraw();
      case KeyAction.moveRight:
        editor.moveRight();
        session.redraw();
      case KeyAction.moveHome:
        editor.moveHome();
        session.redraw();
      case KeyAction.moveEnd:
        editor.moveEnd();
        session.redraw();
      case KeyAction.deleteBackward:
        editor.deleteBackward();
        session.redraw();
      case KeyAction.deleteForward:
        editor.deleteForward();
        session.redraw();
      case KeyAction.deleteToStart:
        editor.deleteToStart();
        session.redraw();
    }
  }

  /// Строка без TTY — промпт целиком, как Enter.
  void _onLine(String line) {
    final session = _session;
    if (session == null || _exit.isCompleted || line.trim().isEmpty) {
      return;
    }
    session.editor.history.add(line);
    _saveHistory(session.editor.history);
    session.send(line);
  }

  void _onInputDone() {
    _inputDone = true;
    _exitIfInputDone();
  }

  /// Конец ввода выходит, когда у отправленных промптов, включая
  /// очередь, есть исход.
  void _exitIfInputDone() {
    final session = _session;
    if (_inputDone && session != null && session.outstanding == 0) {
      unawaited(_finish(okExit));
    }
  }

  /// Выход с [code]: идущий ход отменяется, ответ ждётся не дольше
  /// `cancelGrace`.
  Future<void> _finish(int code) async {
    if (_exit.isCompleted) {
      return;
    }
    final session = _session;
    if (session != null && session.state != ReplInputState.editing) {
      // Агент может не ответить на отмену вовсе: ждём не дольше
      // `cancelGrace`.
      final done = _workspace.promptOutcomes
          .firstWhere(
            (outcome) =>
                outcome.sessionId == session.handle.id &&
                outcome is! PromptQueued,
          )
          .then<void>((_) {})
          .timeout(_cancelGrace, onTimeout: () {});
      await _cancel(session);
      await done;
    }
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
  }

  Future<void> _cancel(ReplSession session) async {
    try {
      await session.handle.cancel();
    } on Object catch (error) {
      // Ход мог уже закончиться: отменять нечего.
      session.say(
        sanitizeTerminalText('codelab: cancel: ${describeFailure(error)}'),
      );
    }
  }

  Future<List<String>> _loadHistory() async {
    try {
      return await _historyStore.load();
    } on Object catch (error) {
      _terminal.errorOutput.writeln(
        sanitizeTerminalText('codelab: cannot read the history: $error'),
      );
      return const [];
    }
  }

  void _saveHistory(History history) {
    final entries = history.entries;
    _saving = _saving.then((_) => _historyStore.save(entries)).catchError((
      Object error,
    ) {
      _terminal.errorOutput.writeln(
        sanitizeTerminalText('codelab: cannot save the history: $error'),
      );
    });
  }
}

/// Подключение или открытие сессии не удалось; причина уже в stderr.
final class _OpenFailed implements Exception {
  const _OpenFailed();
}
