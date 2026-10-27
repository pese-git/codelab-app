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
import 'queue.dart';
import 'reconnect.dart';
import 'resume.dart';
import 'sessions.dart';
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
