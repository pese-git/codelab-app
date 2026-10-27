import '../repl_command.dart';

/// `/new` — новая сессия в папке REPL (`session/new`), она становится
/// активной.
final class NewSessionCommand implements ReplCommand {
  const NewSessionCommand();

  @override
  String get name => 'new';

  @override
  String get usage => '/new';

  @override
  String get description => 'start a new session in this folder';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final handle = await context.workspace.newSession(cwd: context.cwd);
    await context.openSession(handle, replay: false);
    context.say('New session ${handle.id.value}.');
  }
}
