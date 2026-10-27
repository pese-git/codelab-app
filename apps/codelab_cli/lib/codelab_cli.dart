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
export 'src/input/history.dart';
export 'src/input/io_terminal.dart';
export 'src/input/key_bindings.dart';
export 'src/input/key_decoder.dart';
export 'src/input/line_editor.dart';
export 'src/input/terminal.dart';
export 'src/profiles/profile_arg.dart';
export 'src/profiles/profiles_command.dart';
export 'src/render/ansi.dart';
export 'src/render/output_surface.dart';
export 'src/render/sanitize.dart';
export 'src/render/terminal_renderer.dart';
export 'src/render/tool_row.dart';
export 'src/repl/repl.dart';
export 'src/repl/repl_session.dart';
export 'src/run.dart';
export 'src/session_setup.dart';
export 'src/signals.dart';
export 'src/strings.dart';
