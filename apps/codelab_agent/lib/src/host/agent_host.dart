import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../cli/serve_args.dart';

final class AgentHost {
  static Future<AgentHost> build(
    ServeOptions options, {
    required Logger logger,
  }) => throw UnimplementedError();

  BuiltAgentCore get core => throw UnimplementedError();

  AcpServerConfig get serverConfig => throw UnimplementedError();

  AcpAgentServer createServer() => throw UnimplementedError();

  Future<void> shutdown({Duration grace = const Duration(seconds: 5)}) =>
      throw UnimplementedError();
}
