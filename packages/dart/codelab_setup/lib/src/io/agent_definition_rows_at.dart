/// Строки определений агентов по настоящим каталогам (design.md change
/// `add-settings-agents-modes`, D7, D11).
///
/// Тесты — `test/io/agent_definition_rows_at_test.dart`.
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show CancelToken, ExtensionDiagnostic, builtinSubagentTypes;
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        AgentDefinitionsReport,
        LocalExecutionEnv,
        ProjectFilesLoader,
        codelabHomeOf,
        loadAgentDefinitions,
        projectTrustAt,
        userHomeOf;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../views/agent_definition_row_view.dart';

/// Результат [agentDefinitionRowsAt].
///
/// Как использовать: клиент показывает [rows], InfoBar по [diagnostics]
/// (`untrusted_project`) и [timedOut], а наличие каталогов берёт из
/// [userDirectoryExists] и [projectDirectoryExists] — сам файловую систему не
/// проверяет.
final class AgentDefinitionRows {
  const AgentDefinitionRows({
    required this.rows,
    required this.diagnostics,
    required this.timedOut,
    required this.projectTrusted,
    required this.userDirectory,
    required this.userDirectoryExists,
    this.projectDirectory,
    this.projectDirectoryExists = false,
  });

  final List<AgentDefinitionRowView> rows;
  final List<ExtensionDiagnostic> diagnostics;

  /// Папка проекта в `trusted_projects` (то же значение, что ушло в
  /// `loadAgentDefinitions`); `false` и без папки. Клиент смотрит на него, а не
  /// на диагностику `untrusted_project`.
  final bool projectTrusted;

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
/// строит строки. Каталоги не создаёт; существование каталога проверяется
/// без следования по symlink (ссылка на каталог или бандл каталогом не
/// считается).
///
/// Дом — `access.paths.codelabHome` (профиль важнее окружения клиента, как у
/// `FileAgentConfigStore`). Доверие — как у `config check`: канонический путь
/// папки входит в `trusted_projects` итогового конфига; путь, который не
/// разрешился, недоверенный. Без `loaded.config` в снимке читать нечего:
/// возвращаются только встроенные строки. Исключение источника не скрывается —
/// клиент переводит его в состояние (D11).
Future<AgentDefinitionRows> agentDefinitionRowsAt({
  required AgentConfigSnapshot snapshot,
  required EditableSettings access,
  required Map<String, String> env,
  Duration timeout = const Duration(seconds: 5),
  CancelToken? cancel,
}) async {
  final environment = {...env, 'CODELAB_HOME': access.paths.codelabHome};
  final home = codelabHomeOf(environment);
  final folder = access.paths.projectDir;
  final userDirectory = '$home/agents';
  final projectDirectory = folder == null ? null : '$folder/.codelab/agents';
  final config = snapshot.loaded.config;

  var report = const AgentDefinitionsReport();
  var trusted = false;
  if (config != null) {
    String? cwd;
    if (folder != null) {
      final trust = await projectTrustAt(
        config: config,
        folder: folder,
        environment: environment,
      );
      cwd = trust.cwd;
      trusted = trust.trusted;
    }
    report = await loadAgentDefinitions(
      config: config,
      cwd: cwd,
      projectTrusted: trusted,
      source: ProjectFilesLoader(
        home: home,
        userHome: userHomeOf(environment),
        local: LocalExecutionEnv(
          cwd: cwd ?? home,
          hostEnvironment: environment,
        ),
      ),
      timeout: timeout,
      cancel: cancel,
      contextMaxBytes: 0,
    );
  }

  return AgentDefinitionRows(
    rows: agentDefinitionRowsOf(
      definitions: report.definitions,
      diagnostics: report.diagnostics,
      builtins: builtinSubagentTypes(),
      subagentsEnabled: config?.subagents.enabled ?? true,
    ),
    diagnostics: report.diagnostics,
    timedOut: report.timedOut,
    projectTrusted: trusted,
    userDirectory: userDirectory,
    userDirectoryExists: await _isDirectory(userDirectory),
    projectDirectory: projectDirectory,
    projectDirectoryExists: projectDirectory == null
        ? false
        : await _isDirectory(projectDirectory),
  );
}

/// Каталог ли [path]; symlink не разыменовывается, поэтому ссылка на каталог
/// или бандл каталогом не считается.
Future<bool> _isDirectory(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) ==
    FileSystemEntityType.directory;
