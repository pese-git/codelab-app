import 'package:codelab_client_core/codelab_client_core.dart';

import '../input/key_bindings.dart';
import '../render/terminal_renderer.dart';

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
abstract interface class ReplContext {
  ClientWorkspace get workspace;

  SessionHandle get session;

  String get cwd;

  ConnectionProfile get profile;

  TerminalRenderer get renderer;

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
}
