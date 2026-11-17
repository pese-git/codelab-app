import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart'
    show ConfigTarget, ProviderSetupFlow;

import '../input/key_bindings.dart';
import '../render/terminal_renderer.dart';
import '../setup/provider_wizard.dart';
import '../setup/settings_screen.dart';
import '../setup/setup_commands.dart';
import 'picker_spec.dart';

/// Клиентская команда REPL (`/new`, `/model`, …).
///
/// Почему: команды MVP — по файлу на команду, а маршрутизатор и `/help`
/// перечисляют их из одного списка (design.md change `add-codelab-cli`,
/// D7).
///
/// Как использовать: команда реализует [run] через [ReplContext] и не
/// обращается к терминалу и kit в обход него; [usage] — строка справки,
/// [description] — что делает.
abstract interface class ReplCommand {
  String get name;

  String get usage;

  String get description;

  Future<void> run(ReplContext context, List<String> args);
}

/// Что REPL даёт командам.
///
/// Почему: команды меняют сессию, профиль и вывод, а владелец этого — `Repl`;
/// интерфейс отделяет команды от его устройства (design.md, D7).
///
/// Для чего: [session] — активная сессия; [say] печатает строку клиента;
/// [openSession] делает сессию активной; [switchProfile] и [reconnect]
/// подключаются заново и при `detached` открывают новую сессию;
/// [listedSessions] — последний вывод `/sessions` для `/resume <n>`.
/// Вывод, который различается у REPL и TUI, — узкими членами [thoughts],
/// [showPlan] и [pick], а не рендером целиком: так те же команды работают
/// в полноэкранном режиме (design.md change `add-cli-tui`, D10).
abstract interface class ReplContext {
  ClientWorkspace get workspace;

  SessionHandle get session;

  String get cwd;

  ConnectionProfile get profile;

  /// Режим показа мыслей до конца процесса (`/thoughts`).
  set thoughts(ThoughtsMode mode);

  /// План целиком (`/plan`).
  void showPlan(List<PlanEntryView> plan);

  /// Выбор из списка для команды без аргумента: REPL печатает список, TUI
  /// открывает пикер.
  void pick(PickerSpec spec);

  KeyBindings get keys;

  List<ReplCommand> get commands;

  List<SessionSummaryView> get listedSessions;

  set listedSessions(List<SessionSummaryView> sessions);

  void say(String text);

  void exit(int code);

  void clearScreen();

  Future<void> cancelTurn();

  /// Делает [handle] активной сессией REPL; [replay] — напечатать её
  /// историю.
  Future<void> openSession(SessionHandle handle, {required bool replay});

  /// Профиль по id из `profiles.json` или по форме значения `--agent`;
  /// ошибка — `UsageError` с текстом для человека.
  Future<ConnectionProfile> resolveProfile(String id);

  Future<void> switchProfile(ConnectionProfile profile);

  Future<void> reconnect();

  /// Промпты убраны из очереди командой: у них не будет исхода хода.
  void forgetQueued(int count);

  /// Порт настройки агента для `/provider` и `/settings`; `null` — хост его
  /// не собрал (design.md change `add-provider-setup-ui`, D17).
  SetupCommands? get setup;

  /// Экран `/settings` без аргументов: REPL печатает список, TUI открывает
  /// оверлей (D17).
  void showSettings(SettingsScreen screen);

  /// У активной сессии идёт ход или ждётся одобрение: мастеру `/provider add`
  /// в это время не место (решение Q14, D17).
  bool get turnRunning;

  /// Есть терминал с посимвольным вводом; без него мастер невозможен.
  bool get hasTerminal;

  /// Отдаёт клавиши мастеру до его завершения. Подписку на `Terminal.input`
  /// ведёт сам контекст (D15, D17): здесь второй подписки не появляется.
  /// [pathOf] — путь файла слоя для сводки.
  Future<ProviderWizardResult> runWizard(
    ProviderSetupFlow flow, {
    String? providerId,
    ConfigTarget? target,
    String Function(ConfigTarget target)? pathOf,
  });
}
