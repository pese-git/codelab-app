import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../repl_command.dart';

/// `/resume <n или id>` — открыть сессию из списка `/sessions` или по id
/// (`session/load`) и напечатать её историю. Агент без `loadSession` — отказ
/// kit без запроса.
final class ResumeCommand implements ReplCommand {
  const ResumeCommand();

  @override
  String get name => 'resume';

  @override
  String get usage => '/resume <n|id>';

  @override
  String get description => 'open a session from /sessions or by id';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    if (args.isEmpty) {
      context.say('Usage: $usage');
      return;
    }
    final id = _idOf(context, args.first);
    if (id == null) {
      context.say('No session ${args.first} in the last /sessions list.');
      return;
    }
    final open = context.workspace.session(id);
    try {
      final handle =
          open ?? await context.workspace.loadSession(id, cwd: context.cwd);
      await context.openSession(handle, replay: true);
    } on Object catch (error) {
      context.say('codelab: ${describeFailure(error)}');
    }
  }

  static SessionId? _idOf(ReplContext context, String value) {
    final number = int.tryParse(value);
    if (number == null) {
      return SessionId(value);
    }
    final listed = context.listedSessions.isNotEmpty
        ? context.listedSessions
        : [
            for (final summary in context.workspace.current.sessions)
              if (summary.cwd == context.cwd) summary,
          ];
    return number >= 1 && number <= listed.length
        ? listed[number - 1].id
        : null;
  }
}
