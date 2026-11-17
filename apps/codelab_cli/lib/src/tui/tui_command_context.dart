import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart'
    show
        AgentConfigSnapshot,
        ConfigLayer,
        ConfigTarget,
        ProviderSetupEvent,
        ProviderSetupFlow,
        ProviderSetupState,
        Saving,
        EditableSettings,
        Reviewing,
        ReviewEdited;

import '../cli_args.dart';
import '../input/key_bindings.dart';
import '../render/sanitize.dart';
import '../render/terminal_renderer.dart';
import '../repl/commands/commands.dart';
import '../repl/picker_spec.dart';
import '../repl/repl_command.dart';
import '../session_setup.dart';
import '../setup/provider_wizard.dart';
import '../setup/settings_rows.dart';
import '../setup/settings_screen.dart';
import '../setup/wizard_steps.dart';
import '../setup/setup_commands.dart';
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
    List<ReplCommand> commands = replCommands,
    DateTime Function()? clock,
    SecretSource? tokenSource,
    SetupCommands? setup,
  }) : _workspace = workspace,
       _profile = profile,
       _cwd = cwd,
       _send = send,
       _onExit = onExit,
       _resolveProfile = resolveProfile,
       _commands = commands,
       _clock = clock ?? DateTime.now,
       _tokenSource = tokenSource,
       _setup = setup;

  final ClientWorkspace _workspace;
  ConnectionProfile _profile;
  final String _cwd;
  final void Function(TuiMsg msg) _send;
  final void Function(int code) _onExit;
  final Future<ConnectionProfile> Function(String id)? _resolveProfile;
  final List<ReplCommand> _commands;
  final DateTime Function() _clock;

  /// Источник токена профиля для текста отказа по токену
  /// (`describeStartFailure`).
  final SecretSource? _tokenSource;

  final SetupCommands? _setup;

  /// Порт настройки агента для `/provider` и `/settings` (D17): TUI получает
  /// его так же, как построчный REPL, а мастер и экран настроек открывает
  /// оверлеями ([runWizard], [showSettings]).
  @override
  SetupCommands? get setup => _setup;

  /// `false` намеренно (D17): отказ Q14 («Finish or cancel the current
  /// turn…») относится только к построчному REPL, где вопросы мастера
  /// смешались бы с выводом хода. В TUI мастер модальный, а запрос разрешения
  /// ждёт его закрытия.
  @override
  bool get turnRunning => false;

  @override
  bool get hasTerminal => true;

  /// Номера оверлеев: поздние ответы прошлого экрана отбрасывает `reduce`.
  var _overlaySeq = 0;

  /// Автомат открытого мастера: сюда идут `WizardEventCmd` (одна подписка на
  /// его `states` — в [runWizard], D17, D21).
  ProviderSetupFlow? _wizardFlow;
  int? _wizardId;
  void Function()? _abortWizard;

  /// Мастер сейчас в `Saving` и ожидание его итога ([close] ждёт `Done` или
  /// `SaveFailed` не дольше 10 с, D21).
  var _wizardSaving = false;
  Future<ProviderWizardResult>? _wizardResult;

  /// Экран `/settings`, открытый последним, и его свежий снимок.
  SettingsScreen? _settings;
  int? _settingsId;
  AgentConfigSnapshot? _settingsSnapshot;

  /// Событие мастера от эффекта экрана.
  ///
  /// [overlayId] — номер оверлея-отправителя: событие чужого (прошлого)
  /// мастера игнорируется (D21).
  void wizardEvent(ProviderSetupEvent event, {required int overlayId}) {
    if (overlayId != _wizardId) {
      return;
    }
    _wizardFlow?.dispatch(event);
  }

  /// Мастер как модальный экран: единственный владелец подписки на
  /// `flow.states`. Каждое состояние уходит экрану сообщением
  /// `WizardStateMsg`; итог совпадает с построчным мастером (`Done`,
  /// `Cancelled`, отказ записи). Подписка и [flow] освобождаются на любом
  /// выходе, в том числе при закрытии контекста (D21, AGENTS.md §9).
  @override
  Future<ProviderWizardResult> runWizard(
    ProviderSetupFlow flow, {
    String? providerId,
    ConfigTarget? target,
    String Function(ConfigTarget target)? pathOf,
  }) async {
    final id = ++_overlaySeq;
    final done = Completer<ProviderWizardResult>();
    var pendingId = providerId;
    var pendingTarget = target;

    void onState(ProviderSetupState state) {
      if (done.isCompleted) {
        return;
      }
      if (state is Reviewing &&
          (pendingId != null || pendingTarget != null) &&
          state.error == null) {
        // Позиционный id и `--local` применяются один раз (D15).
        final (idValue, targetValue) = (pendingId, pendingTarget);
        pendingId = pendingTarget = null;
        flow.dispatch(ReviewEdited(providerId: idValue, target: targetValue));
        return;
      }
      _wizardSaving = state is Saving;
      _send(WizardStateMsg(id, state));
      final step = wizardStepOf(state);
      if (step.cancelled) {
        done.complete(const ProviderWizardCancelled());
      } else if (step.savedProviderId case final saved?) {
        done.complete(ProviderWizardSaved(saved, hasKey: step.savedHasKey));
      } else if (step.failure case final failure?) {
        done.complete(ProviderWizardFailed(failure));
      }
    }

    final subscription = flow.states.listen(onState);
    _wizardFlow = flow;
    _wizardId = id;
    _wizardResult = done.future;
    _abortWizard = () {
      if (!done.isCompleted) {
        done.complete(const ProviderWizardCancelled());
      }
    };
    _send(OpenWizardMsg(id, flow.current, pathOf: pathOf));
    try {
      return await done.future;
    } finally {
      await subscription.cancel();
      if (identical(_wizardFlow, flow)) {
        _wizardFlow = null;
        _wizardId = null;
        _wizardSaving = false;
        _wizardResult = null;
        _abortWizard = null;
      }
      await flow.dispose();
    }
  }

  @override
  void showSettings(SettingsScreen screen) {
    _settings = screen;
    _settingsSnapshot = screen.snapshot;
    _settingsId = ++_overlaySeq;
    _send(
      OpenSettingsMsg(
        _settingsId!,
        access: screen.access,
        snapshot: screen.snapshot,
      ),
    );
  }

  /// Запись экрана настроек: `applySetting` (все проверки и тексты — там),
  /// затем новый снимок; конфликт — тот же путь, снимок перечитан (D21).
  Future<void> applySettingFor(
    int overlayId,
    String key,
    String? raw,
    ConfigLayer layer, {
    bool explicitLayer = false,
  }) async {
    final screen = _settings;
    final store = screen?.store;
    final scope = screen?.scope;
    final snapshot = _settingsSnapshot;
    if (overlayId != _settingsId ||
        screen == null ||
        store == null ||
        scope == null ||
        snapshot == null) {
      if (overlayId == _settingsId) {
        // Текущий экран остался бы в режиме записи: отвечаем отказом (D21).
        _send(
          SettingsAppliedMsg(
            overlayId,
            line: 'Settings cannot be changed from this screen.',
          ),
        );
      }
      // Ответ чужого (прошлого) экрана не пишет ничего.
      return;
    }
    String line;
    try {
      line = await applySetting(
        store,
        snapshot,
        key,
        raw: raw,
        layer: layer,
        explicitLayer: explicitLayer,
        access: screen.access is EditableSettings
            ? screen.access as EditableSettings
            : null,
      );
    } on Object catch (error) {
      // Экран не должен залипнуть в режиме записи: исход — строкой, без
      // текста исключения (оно могло цитировать значение, CFG-10).
      _send(
        SettingsAppliedMsg(
          overlayId,
          line: 'codelab: $key: write failed (${error.runtimeType})',
        ),
      );
      return;
    }
    try {
      final next = await store.snapshot(cwd: scope.cwd);
      _settingsSnapshot = next;
      _send(SettingsAppliedMsg(overlayId, line: line, snapshot: next));
    } on Object {
      // Запись прошла, снимок перечитать не удалось: исход виден, экран на
      // прежнем снимке.
      _send(
        SettingsAppliedMsg(
          overlayId,
          line: '$line (could not reload the config)',
        ),
      );
    }
  }

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
  Future<void> close() async {
    // Выход из TUI при открытом мастере: подписка и автомат освобождаются. Во
    // время записи ждём её итога (не дольше 10 с), чтобы не бросить запись на
    // середине (D21).
    if (_wizardSaving) {
      await _wizardResult?.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const ProviderWizardCancelled(),
      );
    }
    _abortWizard?.call();
    await _views?.cancel();
  }

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
        '${await describeStartFailure(error, profile, tokenSource: _tokenSource)}',
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
      say(
        'codelab: cannot reconnect: '
        '${await describeStartFailure(error, _profile, tokenSource: _tokenSource)}',
      );
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
