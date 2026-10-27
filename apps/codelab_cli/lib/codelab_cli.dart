/// Терминальный клиент `codelab` (design.md change `add-codelab-cli`, D2):
/// разбор флагов, профили подключения, headless-режим и REPL поверх
/// `ClientWorkspace`. Барель — для `bin/codelab.dart` и тестов.
library;

export 'src/cli_args.dart';
export 'src/cli_io.dart';
export 'src/cli_logger.dart';
export 'src/exit_codes.dart';
export 'src/headless/approval_policy.dart';
export 'src/headless/headless_runner.dart';
export 'src/headless/outcome.dart';
export 'src/headless/prompt_source.dart';
export 'src/home.dart';
export 'src/profiles/profile_arg.dart';
export 'src/profiles/profiles_command.dart';
export 'src/render/sanitize.dart';
export 'src/run.dart';
export 'src/signals.dart';
