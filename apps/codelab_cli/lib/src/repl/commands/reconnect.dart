import '../repl_command.dart';

/// `/reconnect` — переподключиться к тому же агенту и перезагрузить
/// активную сессию.
final class ReconnectCommand implements ReplCommand {
  const ReconnectCommand();

  @override
  String get name => 'reconnect';

  @override
  String get usage => '/reconnect';

  @override
  String get description => 'reconnect and reload the session';

  @override
  Future<void> run(ReplContext context, List<String> args) =>
      context.reconnect();
}
