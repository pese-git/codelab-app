import 'package:freezed_annotation/freezed_annotation.dart';

part 'transport_configs.freezed.dart';

@freezed
abstract class StdioAcpTransportConfig with _$StdioAcpTransportConfig {
  const factory StdioAcpTransportConfig({
    required String command,
    @Default([]) List<String> args,
    String? cwd,
    @Default({}) Map<String, String> env,
  }) = _StdioAcpTransportConfig;
}

@freezed
abstract class StdioAcpAgentProfile with _$StdioAcpAgentProfile {
  const StdioAcpAgentProfile._();

  const factory StdioAcpAgentProfile({
    required String name,
    @Default('custom') String type,
    required String command,
    @Default([]) List<String> args,
    String? cwd,
    @Default({}) Map<String, String> env,
  }) = _StdioAcpAgentProfile;

  StdioAcpTransportConfig toTransportConfig() =>
      StdioAcpTransportConfig(command: command, args: args, cwd: cwd, env: env);
}

/// Встроенное описание stdio-агента CodeLab — Dart-агент `codelab-agent`.
///
/// Почему: после переключения агента по умолчанию на Dart (change
/// `switch-default-agent-to-dart`, D10) команда `codelab` принадлежит
/// терминальному клиенту, а ACP-сервер запускается бинарём `codelab-agent`.
/// Прежнее описание (`codelab serve --stdio`) вело к Python-агенту.
///
/// Для чего: единственный источник значений по умолчанию для запуска
/// своего stdio-агента — стартовый транспорт app и черновик «Add profile»
/// (`ProfileDraft`, `codelab_client_core`). В `profiles.json` не
/// сохраняется и отдельной строкой на странице «Connection» не показывается:
/// профиль по умолчанию — встроенный агент (D10, решение Q1).
/// `CODELAB_LOG_LEVEL=DEBUG` оставлен, чтобы stderr внешнего агента в
/// диагностике app был подробным.
///
/// Как использовать: брать значения через `copyWith` (путь к бинарю
/// у пользователя свой) или `toTransportConfig()`. Константа `const` без IO
/// и остаётся в web-безопасном барреле. Команду `codelab` вместе с `serve`
/// сюда возвращать нельзя (agent-transports «Нет умолчаний Python-агента»).
const codelabAgentStdioProfile = StdioAcpAgentProfile(
  name: 'codelab-agent (stdio)',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
  env: {'CODELAB_LOG_LEVEL': 'DEBUG'},
);

@freezed
abstract class WebSocketAcpTransportConfig with _$WebSocketAcpTransportConfig {
  const WebSocketAcpTransportConfig._();

  const factory WebSocketAcpTransportConfig({
    required Uri uri,
    @Default({}) Map<String, String> headers,
    String? token,
    @Default('Authorization') String tokenHeader,
    @Default('Bearer') String tokenPrefix,
  }) = _WebSocketAcpTransportConfig;

  Map<String, String> get effectiveHeaders {
    final token = this.token;
    if (token == null || token.isEmpty) {
      return headers;
    }

    final value = tokenPrefix.isEmpty ? token : '$tokenPrefix $token';
    return {...headers, tokenHeader: value};
  }
}
