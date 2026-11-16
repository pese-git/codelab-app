/// Строки определений агентов по настоящим каталогам (design.md change
/// `add-settings-agents-modes`, D7, D11).
///
/// ЗАГЛУШКА итерации 2, задача 2.4: [agentDefinitionRowsAt] бросает
/// [UnimplementedError]. Красные тесты —
/// `test/io/agent_definition_rows_at_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show CancelToken, ExtensionDiagnostic;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../views/agent_definition_row_view.dart';

/// Результат [agentDefinitionRowsAt].
///
/// Как использовать: клиент показывает [rows], InfoBar по [diagnostics]
/// (`untrusted_project`) и [timedOut], а наличие каталогов берёт из
/// [userDirectoryExists] и [projectDirectoryExists] — сам файловую систему не
/// проверяет. Заглушка итерации 2, задача 2.4.
final class AgentDefinitionRows {
  const AgentDefinitionRows({
    required this.rows,
    required this.diagnostics,
    required this.timedOut,
    required this.userDirectory,
    required this.userDirectoryExists,
    this.projectDirectory,
    this.projectDirectoryExists = false,
  });

  final List<AgentDefinitionRowView> rows;
  final List<ExtensionDiagnostic> diagnostics;

  /// Чтение не уложилось в тайм-аут; [rows] — только встроенные строки.
  final bool timedOut;

  /// `$CODELAB_HOME/agents` (абсолютный путь с раскрытым `~`).
  final String userDirectory;
  final bool userDirectoryExists;

  /// `<проект>/.codelab/agents`; `null` — папки проекта нет.
  final String? projectDirectory;
  final bool projectDirectoryExists;
}

/// Читает определения функцией `codelab_agent_io`, общей с `config check`, и
/// строит строки. Каталоги не создаёт. Заглушка итерации 2, задача 2.4.
Future<AgentDefinitionRows> agentDefinitionRowsAt({
  required AgentConfigSnapshot snapshot,
  required EditableSettings access,
  required Map<String, String> env,
  Duration timeout = const Duration(seconds: 5),
  CancelToken? cancel,
}) => throw UnimplementedError('agentDefinitionRowsAt: задача 2.4');
