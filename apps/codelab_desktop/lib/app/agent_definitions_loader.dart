// IO-барель моста настроек разрешён сторожем только в `lib/app/`
// (design.md change `add-settings-agents-modes`, D13; SETUP-9).
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

import '../features/settings/application/agent_definitions_port.dart';

/// Читает определения агентов для страницы «Agents & modes» (D7, D11).
///
/// Почему в `lib/app/`: `agentDefinitionRowsAt` читает файлы
/// (`$CODELAB_HOME/agents`, `<project>/.codelab/agents`) и живёт в
/// `codelab_setup/io.dart`, который сторож пускает только в composition root;
/// Cubit страницы работает с портом [AgentDefinitionsLoader] и не знает, откуда
/// строки.
///
/// Для чего: тот же разбор, что у `codelab config check` и у агента (SETUP-8),
/// сведённый к значениям порта. Недоверие берётся из `projectTrusted` моста;
/// типы диагностики ядра `features/` не импортирует.
///
/// Как использовать: composition root передаёт эту функцию в
/// `AgentsModesCubit(loadDefinitions:)`; [cancel] обрывает чтение при новой
/// загрузке и закрытии страницы, тайм-аут (5 с) — внутри моста.
Future<AgentDefinitionsLoad> loadAgentDefinitionsForPage({
  required AgentConfigSnapshot snapshot,
  required EditableSettings access,
  required Map<String, String> environment,
  CancelToken? cancel,
}) async {
  final report = await setup.agentDefinitionRowsAt(
    snapshot: snapshot,
    access: access,
    env: environment,
    cancel: cancel,
  );
  return AgentDefinitionsLoad(
    rows: report.rows,
    // Явное поле моста, а не диагностика (SETUP-8).
    projectTrusted: report.projectTrusted,
    timedOut: report.timedOut,
    userDirectory: report.userDirectory,
    userDirectoryExists: report.userDirectoryExists,
    projectDirectory: report.projectDirectory,
    projectDirectoryExists: report.projectDirectoryExists,
  );
}
