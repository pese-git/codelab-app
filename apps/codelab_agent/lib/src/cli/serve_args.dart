import 'package:codelab_agent_core/codelab_agent_core.dart';

enum ServeTransport { stdio, ws }

enum ProviderKind { openaiCompatible, anthropic }

final class UsageError implements Exception {
  const UsageError(this.message);

  final String message;
}

final class ServeOptions {
  ServeTransport get transport => throw UnimplementedError();
  String get host => throw UnimplementedError();
  int get port => throw UnimplementedError();
  String get tokenEnv => throw UnimplementedError();
  ProviderKind? get provider => throw UnimplementedError();
  Uri? get baseUrl => throw UnimplementedError();
  List<ModelId> get models => throw UnimplementedError();
  String? get apiKey => throw UnimplementedError();
  String? get llmScript => throw UnimplementedError();
  ModeId? get mode => throw UnimplementedError();
  bool get autopilot => throw UnimplementedError();
  LogLevel get logLevel => throw UnimplementedError();
  String? get logFile => throw UnimplementedError();
  String get codelabHome => throw UnimplementedError();
  List<String> get warnings => throw UnimplementedError();
}

ServeOptions parseServeArgs(
  List<String> args, {
  required Map<String, String> environment,
}) => throw UnimplementedError();

String serveUsage() => throw UnimplementedError();
