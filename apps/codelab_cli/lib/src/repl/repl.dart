import 'dart:async';
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
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
import '../strings.dart';
import 'command_router.dart';
import 'commands/commands.dart';
import 'picker_spec.dart';
import 'repl_command.dart';
import 'repl_session.dart';

/// Профиль по id для `/profile <id>`.
typedef ProfileResolver = Future<ConnectionProfile> Function(String id);

/// Интерактивный режим `codelab`: ввод промптов, вывод ходов, очередь,
/// одобрения и клиентские команды.
///
/// Почему: REPL — основной режим терминального клиента; состояние сессии,
/// очередь и одобрения у kit, а REPL владеет только терминалом: режимом
/// stdin, строкой ввода, историей, клавишами и командами (spec codelab-cli
/// «Редактор строки и клавиши», «Очередь промптов в REPL», «Рендер хода в
/// REPL», «Одобрение в REPL», «Slash-меню и клиентские команды»; design.md
/// change `add-codelab-cli`, D5–D8).
///
/// Для чего: в TTY — raw-режим и клавиши по таблице [KeyBindings.mvp];
/// без TTY — построчный ввод, а конец ввода завершает REPL после всех ходов.
/// Строка с `/` уходит в [CommandRouter]: клиентская команда, команда
/// агента промптом или «Unknown command». Пока ждёт одобрение, клавиши
/// выбирают вариант (`ApprovalPrompt`), а ввод промпта недоступен. Выход —
/// Ctrl+D на пустой строке, двойной Ctrl+C за [exitWindow], `/exit`, конец
/// ввода (в TTY — сразу, с отменой хода) или [interrupt]; терминал
/// восстанавливается на любом выходе.
///
/// Как использовать: `await Repl(...).run()` — код выхода: `0`, `1` (не
/// удалось подключиться или открыть сессию) или код сигнала из [interrupt].
/// [resolveProfile] — профили `/profile <id>`; без него команда отвечает
/// отказом. Закрывает рабочее пространство вызывающий.
final class Repl implements ReplContext {
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
    List<ReplCommand> commands = mvpReplCommands,
    ProfileResolver? resolveProfile,
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
       _router = CommandRouter(commands),
       _resolveProfile = resolveProfile,
       _escapeTimeout = escapeTimeout,
       _exitWindow = exitWindow,
       _cancelGrace = cancelGrace,
       _clock = clock ?? DateTime.now;

  final ClientWorkspace _workspace;
  final Terminal _terminal;
  ConnectionProfile _profile;
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
  final CommandRouter _router;
  final ProfileResolver? _resolveProfile;
  final Duration _escapeTimeout;

  /// Окно повторного Ctrl+C для выхода (U-07).
  final Duration _exitWindow;

  /// Сколько ждать ответа агента на `session/cancel` при выходе во время
  /// хода (design.md, D13).
  final Duration _cancelGrace;
  final DateTime Function() _clock;

  final _exit = Completer<int>();
  ReplSession? _session;
  StreamSubscription<SessionView>? _views;
  late final LineEditor _editor;
  DateTime? _lastCtrlC;
  var _inputDone = false;

  /// Ввод открыт: режим терминала уже выбран. До этого строка ввода не
  /// рисуется — иначе набранное до raw-режима пришло бы с переводом `\r` в
  /// `\n`, и Enter стал бы Ctrl+J.
  var _inputOpen = false;

  /// Команды выполняются по одной: следующая строка ждёт предыдущую, как в
  /// shell.
  Future<void> _commands = Future.value();

  /// Запись истории идёт по одной, чтобы файл не перезаписывался
  /// вперемешку.
  Future<void> _saving = Future.value();

  @override
  List<SessionSummaryView> listedSessions = const [];

  ReplSession get _active => _session!;

  Future<int> run() async {
    _editor = LineEditor(History(await _loadHistory()));
    try {
      await _open();
    } on _OpenFailed {
      return failureExit;
    }
    final outcomes = _workspace.promptOutcomes.listen((outcome) {
      final session = _session;
      if (session != null && outcome.sessionId == session.handle.id) {
        session.onOutcome(outcome);
        _exitIfInputDone();
      }
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
      _inputOpen = true;
      _active
        ..inputOpen = true
        ..drawInput();
      if (_firstMessage case final text? when text.trim().isNotEmpty) {
        _submit(text);
      }
      return await _exit.future;
    } finally {
      final session = _active
        ..hideInput()
        ..closed = true;
      if (!session.renderer.atLineStart) {
        _terminal.output.write('\n');
      }
      await input?.cancel();
      await _views?.cancel();
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

  // --- ReplContext ---------------------------------------------------------

  @override
  ClientWorkspace get workspace => _workspace;

  @override
  SessionHandle get session => _active.handle;

  @override
  String get cwd => _cwd;

  @override
  ConnectionProfile get profile => _profile;

  @override
  set thoughts(ThoughtsMode mode) => _active.renderer.thoughts = mode;

  @override
  void showPlan(List<PlanEntryView> plan) => _active.renderer.printPlan(plan);

  /// Список печатается строками, текущий пункт — со `*`; пункты под
  /// заголовком — с отступом.
  @override
  void pick(PickerSpec spec) {
    final title = spec.title;
    if (title != null) {
      say(title);
    }
    final indent = title == null ? '' : '  ';
    for (final (i, item) in spec.items.indexed) {
      say('$indent${i == spec.current ? '*' : ' '} ${item.label}');
    }
  }

  @override
  KeyBindings get keys => _keys;

  @override
  List<ReplCommand> get commands => _router.commands;

  @override
  void say(String text) => _active.say(sanitizeTerminalText(text));

  @override
  void exit(int code) => unawaited(_finish(code));

  @override
  void clearScreen() => _active.clearScreenAndRedraw();

  @override
  Future<void> cancelTurn() => _cancel(_active);

  @override
  void forgetQueued(int count) => _active.forgetQueued(count);

  @override
  Future<void> openSession(SessionHandle handle, {required bool replay}) async {
    _attach(handle, replay: replay);
  }

  @override
  Future<ConnectionProfile> resolveProfile(String id) {
    final resolve = _resolveProfile;
    if (resolve == null) {
      throw const UsageError('Agent profiles are not available here.');
    }
    return resolve(id);
  }

  @override
  Future<void> switchProfile(ConnectionProfile profile) async {
    try {
      await _workspace.connect(profile, projectDirectory: _cwd);
    } on Object catch (error) {
      say(
        'codelab: cannot connect to ${describeProfile(profile)}: '
        '${describeFailure(error)}',
      );
      return;
    }
    _profile = profile;
    await _reopenIfDetached();
    say(connectedTo(profile.id));
  }

  @override
  Future<void> reconnect() async {
    try {
      await _workspace.reconnect();
    } on Object catch (error) {
      say('codelab: cannot reconnect: ${describeFailure(error)}');
      return;
    }
    if (!await _reopenIfDetached()) {
      say(reconnected);
    }
  }

  // --- Сессия --------------------------------------------------------------

  Future<void> _open() async {
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
    // Загруженная сессия печатается целиком: пользователь видит, что
    // продолжает (spec codelab-cli «Сессии в REPL»).
    _attach(handle, replay: _resume != null || _continueLast);
  }

  /// Делает [handle] активной сессией: свой рендер, подписка на её
  /// ревизии; строка ввода и режим мыслей переходят к ней.
  void _attach(SessionHandle handle, {required bool replay}) {
    final previous = _session;
    previous?.hideInput();
    unawaited(_views?.cancel());
    final renderer = TerminalRenderer(
      surface: _surface,
      out: _terminal.output,
      err: _terminal.errorOutput,
      unicode: _unicode,
      thoughts: previous?.renderer.thoughts ?? ThoughtsMode.dim,
      clock: _clock,
    );
    if (previous != null && !previous.renderer.atLineStart) {
      previous.renderer.finishTurn();
    }
    if (replay) {
      renderer.replay(handle.current);
    } else {
      renderer.skip(handle.current);
    }
    previous?.closed = true;
    final session = ReplSession(
      handle: handle,
      terminal: _terminal,
      renderer: renderer,
      editor: _editor,
    );
    _session = session;
    _workspace.activate(handle.id);
    _views = handle.view.listen(session.onView);
    session
      ..inputOpen = _inputOpen
      ..drawInput();
  }

  /// После переподключения агент мог не знать активную сессию: открыть
  /// новую в той же папке. `true` — открыта новая.
  Future<bool> _reopenIfDetached() async {
    if (session.current.status != SessionStatusView.detached) {
      return false;
    }
    final handle = await _workspace.newSession(cwd: _cwd);
    _attach(handle, replay: false);
    say(openedNewSession(handle.id.value));
    return true;
  }

  // --- Ввод ----------------------------------------------------------------

  void _onKey(KeyEvent event) {
    final session = _session;
    if (session == null || _exit.isCompleted) {
      return;
    }
    if (session.state == ReplInputState.awaitingApproval) {
      _onApprovalKey(session, event);
      return;
    }
    switch (event) {
      case TextKey(:final text):
        _editor.insert(text);
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

  /// Клавиши блока одобрения: вариант, `?` или отмена; остальное, включая
  /// Enter и клавиши непредложенных вариантов, ничего не делает (D8).
  void _onApprovalKey(ReplSession session, KeyEvent event) {
    final prompt = session.approvalPrompt;
    if (prompt == null) {
      return;
    }
    switch (event) {
      case TextKey(:final text):
        for (final key in text.split('')) {
          if (key == '?') {
            prompt.details.split('\n').forEach(session.say);
            session.say(prompt.hint);
            return;
          }
          final option = prompt.optionFor(key);
          if (option != null) {
            unawaited(
              session.handle
                  .respond(prompt.approval.approvalId, option)
                  .then<void>(
                    (_) {},
                    onError: (Object error) => session.say(
                      sanitizeTerminalText(
                        'codelab: cannot answer the permission request: '
                        '${describeFailure(error)}',
                      ),
                    ),
                  ),
            );
            return;
          }
        }
      case SpecialKey(:final key):
        final action = _keys.actionFor(key, running: true);
        if (action == KeyAction.cancelTurn) {
          unawaited(_cancel(session));
        } else if (action == KeyAction.clearScreen) {
          session.clearScreenAndRedraw();
        }
    }
  }

  void _handle(KeyAction? action) {
    final session = _session;
    if (session == null || action == null || _exit.isCompleted) {
      return;
    }
    switch (action) {
      case KeyAction.submit:
        final text = _editor.submit();
        if (text == null || text.isEmpty) {
          session.redraw();
          return;
        }
        _submit(text, recorded: true);
      case KeyAction.newline:
        _editor.insertNewline();
        session.redraw();
      case KeyAction.cancelTurn:
        unawaited(_cancel(session));
      case KeyAction.clearLine:
        _editor.clear();
        session.redraw();
      case KeyAction.interrupt:
        final now = _clock();
        final last = _lastCtrlC;
        if (last != null && now.difference(last) <= _exitWindow) {
          unawaited(_finish(okExit));
          return;
        }
        _lastCtrlC = now;
        if (_editor.isEmpty) {
          session.say(pressCtrlCAgain);
        }
        _editor.clear();
        session.redraw();
      case KeyAction.exit:
        if (_editor.isEmpty) {
          unawaited(_finish(okExit));
        }
      case KeyAction.historyPrevious:
        _editor.historyPrevious();
        session.redraw();
      case KeyAction.historyNext:
        _editor.historyNext();
        session.redraw();
      case KeyAction.complete:
        _complete(session);
      case KeyAction.clearScreen:
        session.clearScreenAndRedraw();
      case KeyAction.moveLeft:
        _editor.moveLeft();
        session.redraw();
      case KeyAction.moveRight:
        _editor.moveRight();
        session.redraw();
      case KeyAction.moveHome:
        _editor.moveHome();
        session.redraw();
      case KeyAction.moveEnd:
        _editor.moveEnd();
        session.redraw();
      case KeyAction.deleteBackward:
        _editor.deleteBackward();
        session.redraw();
      case KeyAction.deleteForward:
        _editor.deleteForward();
        session.redraw();
      case KeyAction.deleteToStart:
        _editor.deleteToStart();
        session.redraw();
      // Прокрутка — только у полноэкранного режима: в таблице REPL этих
      // действий нет.
      case KeyAction.scrollUp || KeyAction.scrollDown || KeyAction.follow:
        return;
    }
  }

  /// Tab: один кандидат — в строку, несколько — общий префикс и список с
  /// пометкой команд агента (U-03).
  void _complete(ReplSession session) {
    final result = _router.complete(
      _editor.text,
      agentCommands: session.handle.current.agentCommands,
    );
    if (result.replacement case final replacement?) {
      _editor.setText(replacement);
    }
    if (result.candidates.length > 1) {
      final width = result.candidates
          .map((c) => c.label.length)
          .reduce((a, b) => a > b ? a : b);
      for (final candidate in result.candidates) {
        session.say(
          sanitizeTerminalText(
            '  ${candidate.label.padRight(width)}  ${candidate.description}'
            '${candidate.fromAgent ? ' (agent)' : ''}',
          ),
        );
      }
    }
    session.redraw();
  }

  /// Строка без TTY — промпт или команда целиком, как Enter.
  void _onLine(String line) {
    if (_session == null || _exit.isCompleted || line.trim().isEmpty) {
      return;
    }
    _submit(line);
  }

  /// Отправленная строка: промпт, команда агента или клиентская команда.
  /// [recorded] — редактор уже записал строку в историю.
  void _submit(String text, {bool recorded = false}) {
    if (!recorded) {
      _editor.history.add(text);
    }
    _saveHistory(_editor.history);
    final route = _router.route(
      text,
      agentCommands: _active.handle.current.agentCommands,
    );
    switch (route) {
      case PromptRoute(:final text) || AgentPromptRoute(:final text):
        _active.send(text);
      case UnknownCommandRoute(:final name):
        _echo(text);
        say(unknownCommand(name));
      case ClientCommandRoute(:final command, :final args):
        _echo(text);
        _commands = _commands.then(
          (_) => command
              .run(this, args)
              .then<void>(
                (_) {},
                onError: (Object error) => say(
                  error is UsageError
                      ? error.message
                      : 'codelab: /${command.name}: ${describeFailure(error)}',
                ),
              ),
        );
    }
  }

  /// Строка команды остаётся на экране, как промпт: строка ввода при
  /// отправке стирается.
  void _echo(String text) => _active.say(
    '$inputPrompt${sanitizeTerminalText(text).replaceAll('\n', '\n$inputContinuation')}',
  );

  void _onInputDone() {
    _inputDone = true;
    // Команды из pipe ещё могли не завершиться: решать о выходе после них.
    _commands = _commands.then((_) => _exitIfInputDone());
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
      // Агент может не ответить на отмену вовсе, а ход — закончиться между
      // клавишей и отменой: и отмена, и исход ждутся вместе не дольше
      // `cancelGrace`.
      final done = _workspace.promptOutcomes.firstWhere(
        (outcome) =>
            outcome.sessionId == session.handle.id && outcome is! PromptQueued,
      );
      await Future.wait([
        _cancel(session),
        done,
      ]).timeout(_cancelGrace, onTimeout: () => const []);
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
