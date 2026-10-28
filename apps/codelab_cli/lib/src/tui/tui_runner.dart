import 'dart:async';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:dart_tui/dart_tui.dart' as tea;

import '../exit_codes.dart';
import '../input/history.dart';
import '../render/sanitize.dart';
import '../repl/command_router.dart';
import '../repl/commands/commands.dart';
import '../session_setup.dart';
import '../strings.dart';
import 'core/status_line.dart';
import 'core/tui_chrome.dart';
import 'core/tui_model.dart';
import 'core/tui_msg.dart';
import 'core/tui_view.dart';
import 'tui_app.dart';
import 'tui_effects.dart';
import 'tui_input.dart';

/// Последовательности выключения режимов терминала, которые включает
/// `Program`: расширенные клавиши, мышь, фокус, bracketed paste, курсор,
/// альтернативный экран (§12.2.7, шаг 6).
const _restoreSequences =
    '\x1b[>4m\x1b[=0;1u'
    '\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?1004l'
    '\x1b[?2004l\x1b[?25h\x1b[?1049l';

/// Запуск полноэкранного режима `codelab --ui tui`.
///
/// Почему: `Program` `dart_tui` владеет циклом событий и терминалом, но
/// подключение, открытие сессии, подписки на kit и гарантия восстановления
/// терминала — наши; так TUI-4 не зависит от версии пакета (§12.2.7, шаги
/// 1, 2, 6; design.md change `add-cli-tui`, D7).
///
/// Для чего: подключается и открывает сессию, как REPL (`openCliSession`,
/// `--model`/`--mode`); запускает `Program` с [TuiApp]; ревизии
/// `SessionHandle.view` уходят в цикл `DomainMsg`; первое сообщение
/// отправляется сразу. После выхода — повторное восстановление терминала в
/// `finally`, последний ответ агента и статус-строка в обычном экране.
///
/// Как использовать: `await TuiRunner(...).run()` — код выхода: `0`
/// (`/exit`, Ctrl+D, двойной Ctrl+C), `1` (не удалось открыть сессию, три
/// ошибки ядра подряд, исключение адаптера) или код сигнала из [interrupt].
/// [programOptions] добавляются к опциям `Program` — тесты передают
/// `withInput`, `withOutput`, `withWindowSize`, `withoutSignalHandler`.
/// Закрывает рабочее пространство вызывающий.
final class TuiRunner {
  TuiRunner({
    required ClientWorkspace workspace,
    required ConnectionProfile profile,
    required String cwd,
    required HistoryStore history,
    String? firstMessage,
    String? resume,
    bool continueLast = false,
    String? model,
    String? mode,
    bool unicode = true,
    bool color = true,
    IOSink? output,
    StringSink? errorOutput,
    List<tea.ProgramOption> programOptions = const [],
    Duration cancelGrace = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _workspace = workspace,
       _profile = profile,
       _cwd = cwd,
       _history = history,
       _firstMessage = firstMessage,
       _resume = resume,
       _continueLast = continueLast,
       _model = model,
       _mode = mode,
       _unicode = unicode,
       _color = color,
       _output = output ?? stdout,
       _errorOutput = errorOutput ?? stderr,
       _programOptions = programOptions,
       _cancelGrace = cancelGrace,
       _clock = clock ?? DateTime.now;

  final ClientWorkspace _workspace;
  final ConnectionProfile _profile;
  final String _cwd;
  final HistoryStore _history;
  final String? _firstMessage;
  final String? _resume;
  final bool _continueLast;
  final String? _model;
  final String? _mode;
  final bool _unicode;
  final bool _color;
  final IOSink _output;
  final StringSink _errorOutput;
  final List<tea.ProgramOption> _programOptions;
  final Duration _cancelGrace;
  final DateTime Function() _clock;

  final _router = CommandRouter(mvpReplCommands);
  SessionHandle? _handle;
  tea.Program? _program;

  /// Код выхода; первый заданный побеждает (сигнал раньше `QuitMsg`).
  int? _code;

  /// Сигнал процесса: код [code], идущий ход отменяется после выхода из
  /// цикла (`143` — SIGTERM).
  Future<void> interrupt(int code) async {
    _code ??= code;
    _program?.quit();
  }

  Future<int> run() async {
    final entries = await _loadHistory();
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
      _errorOutput.writeln(
        sanitizeTerminalText(
          error is SessionSetupError
              ? 'codelab: ${error.message}'
              : 'codelab: cannot start the agent ${describeProfile(_profile)}: '
                    '${describeFailure(error)}',
        ),
      );
      return failureExit;
    }
    _handle = handle;
    _workspace.activate(handle.id);

    final effects = TuiEffects(
      session: () => _handle!,
      history: _history,
      onQuit: (code) => _code ??= code,
      runCommand: _runCommand,
    );
    final app = TuiApp(
      model: TuiModel.initial(
        profile: _profile.id,
        size: _initialSize(),
        history: entries,
        unicode: _unicode,
        color: _color,
      ),
      input: TuiInput(),
      effects: effects,
      unicode: _unicode,
      clock: _clock,
    );
    final program = tea.Program(
      options: [tea.withAltScreen(), tea.withFps(60), ..._programOptions],
    );
    _program = program;

    // `run` ставит `Program` в рабочее состояние до первого `await`, поэтому
    // сообщения, отправленные сразу после вызова, не теряются (§12.2.7,
    // шаг 2).
    final done = program.run(app);
    void send(SessionView view) =>
        program.send(DomainMsg(SessionViewMsg(view, at: _clock())));
    final views = handle.view.listen(send);
    send(handle.current);
    if (_firstMessage case final text? when text.trim().isNotEmpty) {
      unawaited(
        handle
            .send(text)
            .then<void>(
              (_) {},
              onError: (Object error) =>
                  _note('codelab: ${describeFailure(error)}'),
            ),
      );
    }

    TuiModel? last;
    try {
      final result = await done;
      if (result is TuiApp) {
        last = result.model;
        // Три ошибки ядра подряд уже дали код 1 (`TuiApp`); ошибка
        // печатается после восстановления терминала.
        if (result.lastError case final error? when _code == failureExit) {
          _errorOutput.writeln(
            sanitizeTerminalText('codelab: the screen failed: $error'),
          );
        }
      }
    } on Object catch (error) {
      _code ??= failureExit;
      _errorOutput.writeln(
        sanitizeTerminalText('codelab: the screen failed: $error'),
      );
    } finally {
      await views.cancel();
      _restoreTerminal();
    }
    await _cancelRunningTurn();
    _printSummary(last);
    await _output.flush();
    return _code ?? okExit;
  }

  /// Вывод выхода из TUI в обычный экран: последний ответ и статус-строка
  /// остаются в scrollback.
  void _printSummary(TuiModel? model) {
    final view = _handle?.current;
    if (view == null) {
      return;
    }
    final answer = view.transcript.whereType<AgentTextItem>().lastOrNull;
    if (answer != null) {
      _output.writeln(sanitizeTerminalText(answer.text).trimRight());
    }
    if (model != null) {
      _output.writeln(
        statusLine(
          statusInfoOf(model, TuiChrome(now: _clock())),
          model.size.columns,
        ),
      );
    }
  }

  /// Повторяет выключение режимов поверх `Program`: повтор безвреден, а
  /// TUI-4 не зависит от версии пакета (§12.2.7, шаг 6).
  void _restoreTerminal() {
    _output.write(_restoreSequences);
    try {
      if (stdin.hasTerminal) {
        stdin
          ..echoMode = true
          ..lineMode = true;
      }
    } on StdinException {
      // Терминала уже нет: восстанавливать нечего.
    }
  }

  /// Выход во время хода: отмена и ответ агента ждутся не дольше
  /// `cancelGrace`, как в REPL (design.md change `add-codelab-cli`, D13).
  Future<void> _cancelRunningTurn() async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final status = handle.current.status;
    if (status != SessionStatusView.running &&
        status != SessionStatusView.cancelling) {
      return;
    }
    final done = _workspace.promptOutcomes.firstWhere(
      (outcome) => outcome.sessionId == handle.id && outcome is! PromptQueued,
    );
    try {
      await Future.wait<Object?>([
        handle.cancel(),
        done,
      ]).timeout(_cancelGrace, onTimeout: () => const []);
    } on Object {
      // Ход мог закончиться между выходом и отменой: отменять нечего.
    }
  }

  /// Строка с `/`. Команды агента и `/exit` работают уже здесь; остальные
  /// клиентские команды придут в TUI с контекстом команд (tasks 5.3).
  Future<void> _runCommand(String line) async {
    final handle = _handle!;
    switch (_router.route(line, agentCommands: handle.current.agentCommands)) {
      case PromptRoute(:final text) || AgentPromptRoute(:final text):
        await handle.send(text);
      case UnknownCommandRoute(:final name):
        _note(unknownCommand(name));
      case ClientCommandRoute(:final command)
          when command.name == 'exit' || command.name == 'quit':
        _code ??= okExit;
        _program?.quit();
      case ClientCommandRoute(:final command):
        _note('/${command.name} is not available in the full-screen mode yet.');
    }
  }

  void _note(String text) => _program?.send(DomainMsg(NoteMsg(text)));

  TerminalSize _initialSize() {
    try {
      if (stdout.hasTerminal) {
        return TerminalSize(
          columns: stdout.terminalColumns,
          rows: stdout.terminalLines,
        );
      }
    } on StdoutException {
      // Размер придёт сообщением `WindowSizeMsg`.
    }
    return const TerminalSize(columns: 80, rows: 24);
  }

  Future<List<String>> _loadHistory() async {
    try {
      return await _history.load();
    } on Object catch (error) {
      _errorOutput.writeln(
        sanitizeTerminalText('codelab: cannot read the history: $error'),
      );
      return const [];
    }
  }
}
