/// Общая загрузка определений агентов: файлы → каталог моделей → разбор ядра
/// (design.md change `add-settings-agents-modes`, D7, D11; SETUP-8).
///
/// Почему отдельная функция: сборка «файлы проекта → каталог моделей →
/// `parseAgentDefinitions` → диагностика» жила закрытой в `ConfigCommands`, а
/// страница «Agents & modes» должна видеть ровно то же, что `config check` и
/// агент.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'agent_definitions_parse.dart';

/// Результат [loadAgentDefinitions]: принятые определения и диагностика.
///
/// Как использовать: поля только для чтения. [diagnostics] — диагностика
/// порта чтения файлов, затем разбора ядра (`untrusted_project`,
/// `invalid_value`, `duplicate`, `shadowed`…) без тел файлов (D14 change
/// `add-agent-project-files`).
final class AgentDefinitionsReport {
  const AgentDefinitionsReport({
    this.definitions = const [],
    this.diagnostics = const [],
    this.timedOut = false,
  });

  /// Принятые определения всех областей в байтовом порядке имён.
  final List<AgentDefinition> definitions;

  /// Диагностика чтения файлов, затем разбора определений.
  final List<ExtensionDiagnostic> diagnostics;

  /// Чтение не уложилось в `timeout`; остальные поля пусты.
  final bool timedOut;
}

/// Читает и разбирает определения агентов тем же путём, что `config check`.
///
/// Без папки ([cwd] — `null`) читается только `$CODELAB_HOME/agents`: порт
/// получает корень `/` без доверия, а диагностика недоверенного «проекта»
/// отбрасывается. По тайм-ауту источник получает отменённый токен, результат —
/// `timedOut`. Отмена [cancel] снаружи отменяет токен источника. Исключение
/// источника не скрывается: вызывающий переводит его в состояние. Каталог
/// моделей — из провайдеров [config]. [contextMaxBytes] по умолчанию —
/// `config.projectContextMaxBytes` (как у `config check`); странице хватает
/// `0`, контекст ей не нужен.
Future<AgentDefinitionsReport> loadAgentDefinitions({
  required CoreConfig config,
  required String? cwd,
  required bool projectTrusted,
  required ProjectFilesSource source,
  Duration timeout = const Duration(seconds: 5),
  CancelToken? cancel,
  int? contextMaxBytes,
}) async {
  final cancelSource = CancelTokenSource(parent: cancel);
  try {
    final files = await source
        .load(
          ProjectFilesQuery(
            cwd: cwd ?? '/',
            projectTrusted: cwd != null && projectTrusted,
            contextMaxBytes: cwd == null
                ? 0
                : contextMaxBytes ?? config.projectContextMaxBytes,
            cancel: cancelSource.token,
          ),
        )
        .then<ProjectFiles?>((value) => value)
        .timeout(timeout, onTimeout: () => null);
    if (files == null) {
      // Загрузчик перестаёт читать (D6), результат выбрасывается.
      cancelSource.cancel();
      return const AgentDefinitionsReport(timedOut: true);
    }
    final parsed = parseAgentDefinitionsOf(config, files.agents);
    return AgentDefinitionsReport(
      definitions: parsed.agents,
      diagnostics: [
        for (final item in files.diagnostics)
          // Без папки «проекта» нет: его диагностику страница не показывает.
          if (cwd != null || item.code != 'untrusted_project') item,
        ...parsed.diagnostics,
      ],
    );
  } on Object {
    cancelSource.cancel();
    rethrow;
  } finally {
    cancelSource.dispose();
  }
}
