/// Бинарь `codelab-agent` (design.md change `add-codelab-agent-binary`,
/// D1): разбор флагов, сборка хоста, логи и запуск `serve`. Барель — для
/// `bin/codelab_agent.dart` и тестов.
library;

export 'src/cli/serve_args.dart';
export 'src/host/agent_host.dart';
export 'src/log/file_sink.dart';
export 'src/log/host_logger.dart';
export 'src/log/stderr_sink.dart';
export 'src/run.dart';
