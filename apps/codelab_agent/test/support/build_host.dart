import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:http/http.dart' as http;

/// Собирает [AgentHost] с конфигом, загруженным для [cwd].
///
/// Почему: `AgentHost.build` требует готовый результат загрузки, а тест не
/// должен читать `.codelab/` каталога, из которого его запустили, поэтому
/// корень проектных слоёв — всегда временный каталог теста.
Future<AgentHost> buildHost(
  ServeOptions options, {
  required String cwd,
  required Logger logger,
  http.Client? httpClient,
}) => AgentHost.build(
  options,
  logger: logger,
  loaded: loadServeConfig(options, cwd: cwd),
  httpClient: httpClient,
);
