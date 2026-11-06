import '../repl_command.dart';
import 'cancel.dart';
import 'clear.dart';
import 'config.dart';
import 'exit.dart';
import 'help.dart';
import 'mode.dart';
import 'model.dart';
import 'new_session.dart';
import 'plan.dart';
import 'profile.dart';
import 'provider.dart';
import 'queue.dart';
import 'reconnect.dart';
import 'resume.dart';
import 'sessions.dart';
import 'settings.dart';
import 'thoughts.dart';

/// Клиентские команды MVP в порядке `/help` (spec codelab-cli «Slash-меню и
/// клиентские команды»; U-04).
const List<ReplCommand> mvpReplCommands = [
  HelpCommand(),
  ExitCommand('exit'),
  ExitCommand('quit'),
  NewSessionCommand(),
  SessionsCommand(),
  ResumeCommand(),
  modeCommand,
  modelCommand,
  ConfigCommand(),
  CancelCommand(),
  QueueCommand(),
  ProfileCommand(),
  ReconnectCommand(),
  PlanCommand(),
  ClearCommand(),
  ThoughtsCommand(),
];

/// Команды построчного REPL: клиентские команды MVP и настройка агента.
///
/// Почему отдельный список: `/provider add` ведёт построчный мастер, которому
/// нет места внутри кадра `--ui tui`, поэтому в 4a TUI остаётся на
/// [mvpReplCommands], а `/provider` и `/settings` появятся там вместе с
/// оверлеями 4b (design.md change `add-provider-setup-ui`, D17).
const List<ReplCommand> replCommands = [
  ...mvpReplCommands,
  ProviderCommand(),
  SettingsCommand(),
];
