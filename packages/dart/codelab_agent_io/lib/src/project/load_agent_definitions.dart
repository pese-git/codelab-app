/// Общая загрузка определений агентов: файлы → каталог моделей → разбор ядра
/// (design.md change `add-settings-agents-modes`, D7; SETUP-8).
///
/// ЗАГЛУШКА итерации 2, задача 2.3: сигнатуры и поля стабильны (на них
/// опирается мост `codelab_setup`), логики нет — [loadAgentDefinitions]
/// бросает [UnimplementedError]. Красные тесты —
/// `test/project/load_agent_definitions_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Результат [loadAgentDefinitions]: принятые определения и диагностика.
///
/// Почему отдельный тип: `config check` и страница «Agents & modes» должны
/// видеть одно и то же, а пара «определения + диагностика» плюс признак
/// тайм-аута раньше жила закрытой в `ConfigCommands` (D7).
///
/// Как использовать: поля только для чтения. [diagnostics] — диагностика
/// порта чтения файлов и разбора ядра (`untrusted_project`, `model`,
/// `duplicate`, `shadowed`…) без тел файлов (D14 change
/// `add-agent-project-files`). Заглушка итерации 2, задача 2.3.
final class AgentDefinitionsReport {
  const AgentDefinitionsReport({
    this.definitions = const [],
    this.diagnostics = const [],
    this.timedOut = false,
  });

  /// Принятые определения всех областей в байтовом порядке имён.
  final List<AgentDefinition> definitions;

  /// Диагностика чтения и разбора.
  final List<ExtensionDiagnostic> diagnostics;

  /// Чтение не уложилось в `timeout`; [definitions] и [diagnostics] пусты.
  final bool timedOut;
}

/// Читает и разбирает определения агентов тем же путём, что `config check`.
///
/// Без папки ([cwd] — `null`) читается только `$CODELAB_HOME/agents`. По
/// тайм-ауту или отмене [cancel] (`null` — отмены снаружи нет) источник получает отменённый токен, а
/// результат — `timedOut`. Исключение источника не скрывается. Каталог
/// моделей — из провайдеров [config].
///
/// Заглушка итерации 2, задача 2.3: бросает [UnimplementedError].
Future<AgentDefinitionsReport> loadAgentDefinitions({
  required CoreConfig config,
  required String? cwd,
  required bool projectTrusted,
  required ProjectFilesSource source,
  Duration timeout = const Duration(seconds: 5),
  CancelToken? cancel,
}) => throw UnimplementedError('loadAgentDefinitions: задача 2.3');
