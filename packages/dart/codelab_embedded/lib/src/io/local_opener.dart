import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:http/http.dart' as web;

import '../create_embedded_agent.dart';
import '../embedded_agent.dart';
import '../embedded_agent_config.dart';

/// Открыватель встроенного агента для настольных хостов: загрузка
/// конфигурации, секреты, журнал, файлы проекта и MCP (design.md change
/// `add-embedded-agent-mode`, D2, D5; `agent-core-architecture` §10.1).
///
/// Почему одна функция: оба клиента (CLI и desktop) всегда вызывают загрузку
/// конфигурации и сборку служб подряд, а `secrets.backend` и `sessions.dir`
/// известны только из загруженного конфига. Своего загрузчика, хранилища
/// секретов и формата журнала у пакета нет: всё переиспользует
/// `codelab_agent_io`, как бинарь `codelab-agent` (D1, в).
///
/// Для чего: на каждый вызов [EmbeddedAgentOpener] —
/// `ConfigLoader().load` → `openHostSecrets` → `createEmbeddedAgent`. Сетевой
/// клиент и прочие ресурсы создаются только после успешной загрузки
/// конфигурации: невалидный конфиг не оставляет ни сокетов, ни процессов (D5).
///
/// Как использовать: [environment] — `Platform.environment` процесса
/// (`CODELAB_HOME`, `CODELAB_SECRET_*`, `CODELAB_CONFIG`); тест передаёт
/// временный. [debugSecrets] включает `secrets.lookup` (`--debug-secrets`;
/// `CODELAB_DEBUG_SECRETS=1` читается здесь же). [httpClient] — шов тестов
/// (`MockClient`): переданный клиент агент не закрывает, созданный
/// самостоятельно — закрывает в `dispose` (D6). Невалидный конфиг, `~user` в
/// `CODELAB_HOME` и недоступное хранилище секретов дают
/// [EmbeddedAgentConfigException]; профиль вне `embedded-*` —
/// `HostWiringException`. Нет ключа провайдера — не ошибка открытия: первый ход
/// завершается ошибкой провайдера с именем секрета (D13, п. 2).
EmbeddedAgentOpener localEmbeddedAgentOpener({
  required Map<String, String> environment,
  required Logger logger,
  bool debugSecrets = false,
  web.Client? httpClient,
}) => ({required String cwd, required String hostProfile}) async {
  // Чужой профиль отвергается до загрузки конфига, чтения секретов и
  // создания HTTP-клиента.
  checkEmbeddedProfile(hostProfile);
  final home = _homeOf(environment);
  final ConfigLoadResult loaded;
  try {
    loaded = ConfigLoader().load(cwd: cwd, environment: environment);
  } on ConfigUsageException catch (error) {
    throw EmbeddedAgentConfigException([
      _usageIssue(error.source, error.message),
    ], home: home);
  }
  // Предупреждения пишутся и при невалидном конфиге, до исключения: так же
  // делает бинарь в `_reportInvalidConfig`, и опечатка в `CODELAB_*` видна
  // рядом с проблемами.
  logConfigWarnings(logger, loaded);
  if (loaded.issues.isNotEmpty) {
    throw EmbeddedAgentConfigException(loaded.issues, home: home);
  }
  final config = loaded.config!;
  final settings = loaded.host!;

  // Один резолвер на агента: им пользуются и функция модели, и ядро
  // (MCP-серверы конфигурации); `selectionReason` не передаётся (D15
  // change `add-agent-secret-store`).
  final SecretResolver secrets;
  try {
    secrets = openHostSecrets(
      codelabHome: home,
      environment: environment,
      backend: settings.secretsBackend,
      debug: debugSecrets || environment['CODELAB_DEBUG_SECRETS'] == '1',
      logger: logger,
      testStorePath: testSecretStorePath(environment),
    );
  } on SecretStoreUnavailableException catch (error) {
    throw EmbeddedAgentConfigException([
      _usageIssue('secrets.backend', error.reason),
    ], home: home);
  }

  // Ресурсы — только после успешной загрузки конфига и выбора хранилища.
  final owned = httpClient == null;
  final http = httpClient ?? web.Client();
  const clock = SystemClock();
  final env = LocalExecutionEnv(cwd: cwd, hostEnvironment: environment);
  try {
    return await createEmbeddedAgent(
      config: EmbeddedAgentConfig(
        hostProfile: hostProfile,
        core: config,
        host: settings,
      ),
      services: EmbeddedHostServices(
        baseEnv: env,
        localEnv: (sessionCwd) =>
            LocalExecutionEnv(cwd: sessionCwd, hostEnvironment: environment),
        sessions: openHostSessions(
          codelabHome: home,
          settings: settings,
          clock: clock,
          logger: logger,
        ),
        secrets: secrets,
        http: http,
        closeHttpOnDispose: owned,
        logger: logger,
        clock: clock,
        ids: RandomIdGenerator(Random.secure()),
        random: Random.secure(),
        platform: Platform.operatingSystem,
        // Процессы stdio запускает `codelab_agent_io`, streamable HTTP —
        // `codelab_agent_mcp` на HTTP-клиенте хоста; закрываются вместе
        // с сессией (change `add-agent-mcp-client`, D3, D6, D9).
        mcp: McpClientConnector(
          transports: McpTransports(
            // Одно окружение для `exec` и MCP-процессов: источник — аргумент
            // открывателя, а не скрытый `Platform.environment`.
            stdio: StdioMcpTransportFactory(hostEnvironment: environment),
            http: StreamableHttpTransportFactory(client: http, clock: clock),
          ),
          clock: clock,
        ),
        projectFiles: ProjectFilesLoader(home: home, local: env),
      ),
    );
  } catch (_) {
    // Ошибка до готовности агента (неверный профиль, сбой сборки): агента
    // у вызывающего не будет, поэтому созданный здесь клиент закрывается.
    // `close` у клиентов идемпотентен, повторное закрытие внутри сборки
    // безвредно.
    if (owned) {
      http.close();
    }
    rethrow;
  }
};

/// `$CODELAB_HOME` с раскрытием `~`; недопустимое значение — проблема
/// конфигурации с текстом загрузчика (D5).
String _homeOf(Map<String, String> environment) {
  try {
    return codelabHomeOf(environment);
  } on ConfigUsageException catch (error) {
    throw EmbeddedAgentConfigException(
      [_usageIssue(error.source, error.message)],
      // Раскрыть каталог нельзя: подсказка называет его как задан.
      home: environment['CODELAB_HOME'] ?? '~/.codelab',
    );
  }
}

/// Проблема использования (не файл конфигурации) в форме `ConfigIssue`.
ConfigIssue _usageIssue(String? source, String message) => ConfigIssue(
  kind: ConfigIssueKind.value,
  key: '',
  source: source ?? 'config',
  message: message,
);
