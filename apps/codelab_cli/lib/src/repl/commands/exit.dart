import '../../exit_codes.dart';
import '../repl_command.dart';

/// `/exit` и `/quit` — выход из REPL с кодом `0`; идущий ход отменяется.
final class ExitCommand implements ReplCommand {
  const ExitCommand(this.name);

  @override
  final String name;

  @override
  String get usage => '/$name';

  @override
  String get description => 'exit';

  @override
  Future<void> run(ReplContext context, List<String> args) async =>
      context.exit(okExit);
}
