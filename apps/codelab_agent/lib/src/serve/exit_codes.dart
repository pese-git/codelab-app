/// Коды выхода `codelab-agent` (документ ядра §13.10; design.md change
/// `add-codelab-agent-binary`, D7).
library;

import 'package:codelab_agent_io/codelab_agent_io.dart' show configUsageExit;

/// Штатное завершение: EOF stdin в режиме `--stdio`.
const okExit = 0;

/// Ошибка запуска вне ошибок использования (например, занятый порт).
const failureExit = 1;

/// Неверные флаги, переменные или сценарий. Значение общее с `config check`
/// (`configUsageExit` из `codelab_agent_io`): оба бинаря возвращают один код.
const usageExit = configUsageExit;

/// Завершение по `SIGINT`.
const sigintExit = 130;

/// Завершение по `SIGTERM`.
const sigtermExit = 143;
