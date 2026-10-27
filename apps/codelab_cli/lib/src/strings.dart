/// Строки REPL для человека.
///
/// Почему: строки MVP — английские константы в одном месте, чтобы каталог
/// языков (`--lang`, TUI-12) пришёл позже заменой этого файла, а не поиском
/// по коду (design.md change `add-codelab-cli`, D15).
library;

/// Метка строки ввода и продолжение многострочного ввода.
const inputPrompt = '> ';
const inputContinuation = '  ';

/// Промпт встал в очередь kit: `queued: <n>` (spec codelab-cli «Редактор
/// строки и клавиши»).
String queuedMessage(int count) => 'queued: $count';

/// Ход завершился отменой (`stopReason: cancelled`).
const turnCancelled = 'cancelled';

/// Ход не завершился: причина из `PromptFailed`.
String turnFailed(String reason) => 'error: $reason';

/// Повторный Ctrl+C в течение секунды выходит.
const pressCtrlCAgain = 'Press Ctrl+C again to exit.';

/// Строка — `/команда`, которой не знают ни клиент, ни агент.
String unknownCommand(String name) => 'Unknown command /$name';

/// Подключение к профилю `/profile <id>`.
String connectedTo(String id) => 'Connected to $id.';

/// Переподключение `/reconnect`.
const reconnected = 'Reconnected.';

/// Новое соединение не знает активную сессию: открыта новая.
String openedNewSession(String id) =>
    'The agent cannot reload the session; opened a new session $id.';

/// Свёрнутые мысли: `thought for <n>s` (design.md, D6).
String thoughtFor(Duration elapsed) => 'thought for ${elapsed.inSeconds}s';

/// Заголовок блока плана.
const planHeader = 'Plan:';

/// Префиксы заметок по виду.
const errorPrefix = 'error: ';
const notePrefix = 'note: ';
