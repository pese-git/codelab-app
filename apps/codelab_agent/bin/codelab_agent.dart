import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';

/// Точка входа `codelab-agent` (design.md change `add-codelab-agent-binary`,
/// D1): код выхода — от [runCodelabAgent].
Future<void> main(List<String> args) async {
  exitCode = await runCodelabAgent(args, environment: Platform.environment);
}
