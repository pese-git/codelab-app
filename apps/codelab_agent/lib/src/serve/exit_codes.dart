/// Коды выхода `codelab-agent` (документ ядра §13.10; design.md change
/// `add-codelab-agent-binary`, D7).
library;

/// Штатное завершение: EOF stdin в режиме `--stdio`.
const okExit = 0;

/// Ошибка запуска вне ошибок использования (например, занятый порт).
const failureExit = 1;

/// Неверные флаги, переменные или сценарий.
const usageExit = 64;

/// Завершение по `SIGINT`.
const sigintExit = 130;

/// Завершение по `SIGTERM`.
const sigtermExit = 143;
