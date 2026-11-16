/// Общая загрузка определений агентов: файлы → каталог моделей → разбор ядра
/// (design.md change `add-settings-agents-modes`, D7, D11; SETUP-8).
///
/// Почему отдельная функция: сборка «файлы проекта → каталог моделей →
/// `parseAgentDefinitions` → диагностика» жила закрытой в `ConfigCommands`, а
/// страница «Agents & modes» должна видеть ровно то же, что `config check` и
/// агент.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../util/silent_logger.dart';

/// Результат [loadAgentDefinitions]: принятые определения и диагностика.
///
/// Как использовать: поля только для чтения. [diagnostics] — диагностика
/// порта чтения файлов и разбора ядра (`untrusted_project`,
/// `invalid_value`, `duplicate`, `shadowed`…) без тел файлов (D14 change
/// `add-agent-project-files`). [files] и [parseDiagnostics] нужны `config
/// check`, чтобы сохранить прежний порядок строк вывода (диагностика
/// шаблонов команд стоит между ними).
final class AgentDefinitionsReport {
  const AgentDefinitionsReport({
    this.definitions = const [],
    this.files = ProjectFiles.empty,
    this.parseDiagnostics = const [],
    this.timedOut = false,
  });

  /// Принятые определения всех областей в байтовом порядке имён.
  final List<AgentDefinition> definitions;

  /// Сырые файлы, как их отдал порт; пусты при [timedOut].
  final ProjectFiles files;

  /// Диагностика разбора определений (`parseAgentDefinitions`).
  final List<ExtensionDiagnostic> parseDiagnostics;

  /// Чтение не уложилось в `timeout`; остальные поля пусты.
  final bool timedOut;

  /// Диагностика чтения файлов, затем разбора определений.
  List<ExtensionDiagnostic> get diagnostics => [
    ...files.diagnostics,
    ...parseDiagnostics,
  ];
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
    final visible = cwd == null
        ? ProjectFiles(
            agents: files.agents,
            templates: files.templates,
            diagnostics: [
              for (final item in files.diagnostics)
                if (item.code != 'untrusted_project') item,
            ],
          )
        : files;
    final parsed = parseAgentDefinitions(
      visible.agents,
      models: StaticModelCatalog(
        config.providers,
        logger: const SilentLogger(),
      ),
    );
    return AgentDefinitionsReport(
      definitions: parsed.agents,
      files: visible,
      parseDiagnostics: parsed.diagnostics,
    );
  } on Object {
    cancelSource.cancel();
    rethrow;
  } finally {
    cancelSource.dispose();
  }
}
