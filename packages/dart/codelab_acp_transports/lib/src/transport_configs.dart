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

const codelabAgentStdioProfile = StdioAcpAgentProfile(
  name: 'Codelab Agent',
  command: 'codelab',
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
