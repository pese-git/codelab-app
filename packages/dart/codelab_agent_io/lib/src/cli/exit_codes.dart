/// Коды выхода подкоманд `config` (design.md change `add-agent-configuration`,
/// D13; `agent-core-architecture` §13.10, §17.5.5).
///
/// Почему в `codelab_agent_io`: `codelab-agent config check` и
/// `codelab config check` обязаны возвращать одни и те же коды, поэтому оба
/// бинаря ссылаются на эти константы, а не заводят свои числа.
library;

/// Конфигурация валидна.
const configValidExit = 0;

/// Есть проблемы конфигурации (предупреждения проблемами не считаются).
const configInvalidExit = 1;

/// Ошибка использования: несуществующий `--cwd`, `ConfigUsageException`,
/// ошибка разбора аргументов (стандартный `EX_USAGE`).
const configUsageExit = 64;
