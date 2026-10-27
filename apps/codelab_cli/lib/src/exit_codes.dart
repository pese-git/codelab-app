/// Коды выхода `codelab` (`09-11-stage-6-cli-mvp.md`, «Headless»; документ
/// ядра §13.10; design.md change `add-codelab-cli`, D2, D9).
///
/// Почему один файл: REPL, headless и `test-scenario` выходят с одними и теми
/// же кодами, а скрипты и CI различают по ним исход прогона (H-02).
library;

/// Успех: ход завершён `end_turn` с ответом, команда выполнена.
const okExit = 0;

/// Ошибка хода или соединения: ошибка агента, пустой ответ, обрыв,
/// агент не запустился; в `test-scenario` — есть `FAIL`.
const failureExit = 1;

/// Ошибка использования: неверные флаги, нет промпта, нет профиля.
const usageExit = 64;

/// Отмена: `SIGINT` или истёкший `--timeout`.
const sigintExit = 130;

/// Завершение по `SIGTERM`.
const sigtermExit = 143;
