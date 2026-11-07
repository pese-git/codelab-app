import 'package:codelab_setup/codelab_setup.dart';

/// Снимки конфига с MCP-серверами для тестов моста (design.md change
/// `add-provider-setup-ui`, D11, «Сверка с кодом»): слои `user`, `project`
/// (слой 3) и `projectLocal` задаются списками сырых элементов `mcp.servers`,
/// как они лежат в файлах (со ссылками `${secret:…}` и `${VAR}`).

const mcpCwd = '/work/project';

/// Снимок: [user], [project] и [projectLocal] — элементы `mcp.servers` слоя
/// (`null` — слоя нет). [untrustedProject] имитирует проект вне
/// `trusted_projects`: загрузчик отбросил весь `mcp.servers` слоя 3 и записал
/// предупреждение `config.project.untrusted_key` (CFG-3).
AgentConfigSnapshot mcpSnapshot({
  List<Map<String, Object?>>? user,
  List<Map<String, Object?>>? project,
  List<Map<String, Object?>>? projectLocal,
  bool untrustedProject = false,
  SecretBackendInfo backend = const SecretBackendInfo(
    id: 'file',
    writable: true,
  ),
}) {
  Map<String, Object?> values(List<Map<String, Object?>> servers) => {
    'mcp': {'servers': servers},
  };
  return AgentConfigSnapshot.fromLayers(
    cwd: mcpCwd,
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/h/config.yaml',
        fingerprint: 'fp-user',
        values: values(user ?? const []),
      ),
      if (project != null)
        ConfigLayer.project: ConfigSnapshot(
          target: const ConfigTarget.project(mcpCwd),
          path: '$mcpCwd/.codelab/config.yaml',
          fingerprint: 'fp-project',
          values: values(project),
        ),
      if (projectLocal != null)
        ConfigLayer.projectLocal: ConfigSnapshot(
          target: const ConfigTarget.projectLocal(mcpCwd),
          path: '$mcpCwd/.codelab/config.local.yaml',
          fingerprint: 'fp-local',
          values: values(projectLocal),
        ),
    },
    loaded: ConfigLoadResult(
      warnings: [
        if (untrustedProject)
          const ConfigIssue(
            kind: ConfigIssueKind.semantic,
            key: 'mcp.servers',
            source: '$mcpCwd/.codelab/config.yaml',
            message: 'ignored: the project is not in trusted_projects',
            event: 'config.project.untrusted_key',
          ),
      ],
    ),
    secrets: backend,
  );
}

/// Сервер `http` с заголовками.
Map<String, Object?> httpServer(
  String name, {
  String url = 'https://mcp.test/mcp',
  Map<String, String>? headers,
  Map<String, Object?> extra = const {},
}) => {'name': name, 'type': 'http', 'url': url, 'headers': ?headers, ...extra};

/// Сервер `stdio` с аргументами и окружением.
Map<String, Object?> stdioServer(
  String name, {
  String command = '/usr/bin/server',
  List<String>? args,
  Map<String, String>? env,
  Map<String, Object?> extra = const {},
}) => {
  'name': name,
  'type': 'stdio',
  'command': command,
  'args': ?args,
  'env': ?env,
  ...extra,
};
