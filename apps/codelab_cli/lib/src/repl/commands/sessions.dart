import 'package:codelab_client_core/codelab_client_core.dart';

import '../picker_spec.dart';
import '../repl_command.dart';

/// `/sessions` — сессии папки с номерами для `/resume <n>`: открытые в этом
/// запуске и сессии агента из `session/list` (все страницы, но не больше
/// [_maxPages]). Список — через `ReplContext.pick`: REPL печатает его, TUI
/// открывает пикер, выбор которого — `/resume <n>`.
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
    final active = sessions.indexWhere((s) => s.id == context.session.id);
    context.pick(
      PickerSpec(
        items: [
          for (final (i, summary) in sessions.indexed)
            PickerItem(
              label:
                  '${i + 1}. ${summary.title ?? summary.id.value} '
                  '(${summary.id.value})${_updated(summary)}',
              line: '/resume ${i + 1}',
            ),
        ],
        current: active < 0 ? null : active,
      ),
    );
  }

  static String _updated(SessionSummaryView summary) {
    final updated = summary.updatedAt;
    return updated == null
        ? ''
        : '  ${updated.toLocal().toString().substring(0, 16)}';
  }
}
