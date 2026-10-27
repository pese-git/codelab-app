import '../repl_command.dart';

/// `/clear` — очистить экран, как Ctrl+L.
final class ClearCommand implements ReplCommand {
  const ClearCommand();

  @override
  String get name => 'clear';

  @override
  String get usage => '/clear';

  @override
  String get description => 'clear the screen';

  @override
  Future<void> run(ReplContext context, List<String> args) async =>
      context.clearScreen();
}
