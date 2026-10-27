import '../repl_command.dart';

/// `/sessions` — сессии папки с номерами для `/resume <n>`: открытые в этом
/// запуске и сессии агента из `session/list` (все страницы, но не больше
/// [_maxPages]).
final class SessionsCommand implements ReplCommand {
  const SessionsCommand();

  /// Предел страниц `session/list`: список для человека, а не выгрузка.
  static const _maxPages = 10;

  @override
  String get name => 'sessions';

  @override
  String get usage => '/sessions';

  @override
  String get description => 'list the sessions of this folder';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final workspace = context.workspace;
    for (
      var page = 0;
      page < _maxPages && workspace.current.hasMoreSessions;
      page++
    ) {
      await workspace.loadMoreSessions();
    }
    final sessions = [
      for (final summary in workspace.current.sessions)
        if (summary.cwd == context.cwd) summary,
    ];
    context.listedSessions = sessions;
    if (sessions.isEmpty) {
      context.say('No sessions in ${context.cwd}.');
      return;
    }
    final active = context.session.id;
    for (final (i, summary) in sessions.indexed) {
      final mark = summary.id == active ? '*' : ' ';
      final title = summary.title ?? summary.id.value;
      final updated = summary.updatedAt == null
          ? ''
          : '  ${summary.updatedAt!.toLocal().toString().substring(0, 16)}';
      context.say('$mark ${i + 1}. $title (${summary.id.value})$updated');
    }
  }
}
