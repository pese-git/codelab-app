import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';

/// Точка входа `codelab-agent` (design.md change `add-codelab-agent-binary`,
/// D1). `exit`, а не `exitCode`: подписка на stdin держала бы процесс живым
/// после завершения сервера.
Future<void> main(List<String> args) async {
  exit(await runCodelabAgent(args, environment: Platform.environment));
}
