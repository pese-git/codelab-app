import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
import '../input/key_bindings.dart';
import '../render/sanitize.dart';
import '../render/terminal_renderer.dart';
import '../repl/commands/commands.dart';
import '../repl/picker_spec.dart';
import '../repl/repl_command.dart';
import '../session_setup.dart';
import '../strings.dart';
import 'core/transcript_lines.dart';
import 'core/tui_msg.dart';

/// `ReplContext` полноэкранного режима: те же команды, вывод — сообщениями
/// ядра экрана.
///
/// Почему: команды MVP написаны против `ReplContext`, и в TUI они должны
/// работать так же, а печатать некуда, кроме транскрипта; сессия при
/// `/new`, `/resume`, `/profile` и `/reconnect` меняется, и подписку на её
/// ревизии должен вести один владелец (spec codelab-tui «Команды и пикеры
/// TUI»; design.md change `add-cli-tui`, D10).
///
/// Для чего: [say] → `NoteMsg`, [clearScreen] → `ClearNotesMsg`, [pick] →
/// `OpenPickerMsg`, [thoughts] → `ThoughtsMsg`, [showPlan] — план заметкой;
/// [attach] делает сессию активной и подписывает её ревизии на [send];
/// [switchProfile] и [reconnect] — как в REPL, при `detached` открывается
/// новая сессия.
///
/// Как использовать: `TuiRunner` создаёт контекст после открытия сессии,
/// вызывает [attach], отдаёт [session] в `TuiEffects` и закрывает [close]
/// после выхода из цикла. [send] — `Program.send` с обёрткой `DomainMsg`.
final class TuiCommandContext implements ReplContext {
  TuiCommandContext({
    required ClientWorkspace workspace,
    required ConnectionProfile profile,
    required String cwd,
    required void Function(TuiMsg msg) send,
    required void Function(int code) onExit,
    Future<ConnectionProfile> Function(String id)? resolveProfile,
    List<ReplCommand> commands = mvpReplCommands,
    DateTime Function()? clock,
  }) : _workspace = workspace,
       _profile = profile,
       _cwd = cwd,
       _send = send,
       _onExit = onExit,
       _resolveProfile = resolveProfile,
       _commands = commands,
       _clock = clock ?? DateTime.now;

  final ClientWorkspace _workspace;
  ConnectionProfile _profile;
  final String _cwd;
  final void Function(TuiMsg msg) _send;
  final void Function(int code) _onExit;
  final Future<ConnectionProfile> Function(String id)? _resolveProfile;
  final List<ReplCommand> _commands;
  final DateTime Function() _clock;

  SessionHandle? _session;
  StreamSubscription<SessionView>? _views;

  /// Делает [handle] активной сессией: отменяет подписку прошлой, шлёт
  /// текущую ревизию `SessionAttachedMsg` и подписывает следующие.
  void attach(SessionHandle handle) {
    unawaited(_views?.cancel());
    _session = handle;
    _workspace.activate(handle.id);
    _send(SessionAttachedMsg(handle.current, at: _clock()));
    _views = handle.view.listen(
      (view) => _send(SessionViewMsg(view, at: _clock())),
    );
  }

  /// Отменяет подписку на ревизии; после выхода из цикла экрана.
  Future<void> close() async => _views?.cancel();

  @override
  ClientWorkspace get workspace => _workspace;

  @override
  SessionHandle get session => _session!;

  @override
  String get cwd => _cwd;

  @override
  ConnectionProfile get profile => _profile;

  @override
  KeyBindings get keys => KeyBindings.tui;

  @override
  List<ReplCommand> get commands => _commands;

  @override
  List<SessionSummaryView> listedSessions = const [];

  @override
  set thoughts(ThoughtsMode mode) => _send(ThoughtsMsg(mode));

  @override
  void showPlan(List<PlanEntryView> plan) =>
      say(TranscriptLayout.planLines(plan).join('\n'));

  @override
  void pick(PickerSpec spec) => _send(OpenPickerMsg(spec));

  @override
  void say(String text) => _send(NoteMsg(sanitizeTerminalText(text)));

  @override
  void exit(int code) => _onExit(code);

  @override
  void clearScreen() => _send(const ClearNotesMsg());

  @override
  Future<void> cancelTurn() => session.cancel();

  /// У TUI нет своего счёта ходов без исхода: выход не ждёт очередь.
  @override
  void forgetQueued(int count) {}

  /// История сессии видна в транскрипте и так: ревизия kit содержит её
  /// целиком, поэтому [replay] не нужен.
  @override
  Future<void> openSession(
    SessionHandle handle, {
    required bool replay,
  }) async => attach(handle);

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

  /// После переподключения агент мог не знать активную сессию: открыть
  /// новую в той же папке. `true` — открыта новая.
  Future<bool> _reopenIfDetached() async {
    if (session.current.status != SessionStatusView.detached) {
      return false;
    }
    final handle = await _workspace.newSession(cwd: _cwd);
    attach(handle);
    say(openedNewSession(handle.id.value));
    return true;
  }
}
