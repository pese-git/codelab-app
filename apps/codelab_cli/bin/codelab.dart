import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';

/// Точка входа `codelab` (design.md change `add-codelab-cli`, D2). `exit`, а
/// не `exitCode`: подписки на stdin и сигналы держали бы процесс живым после
/// завершения клиента.
Future<void> main(List<String> args) async {
  exit(await runCodelab(args, environment: Platform.environment));
}
