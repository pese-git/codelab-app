## ADDED Requirements

### Requirement: Незавершённый ход в TUI
После загрузки сессии TUI SHALL показывать в транскрипте после истории заметку с тем же текстом, что REPL (capability `codelab-cli`, «Незавершённый ход в REPL»), если `SessionView.canContinue` истинно (design.md change `add-interrupted-turn-resume`, D8). Заметка SHALL проходить очистку `sanitizeTerminalText`. Отправка `/continue` из композера SHALL идти как обычный промпт. После отправки любого промпта новой заметки о незавершённом ходе SHALL не появляться до следующей загрузки.

#### Scenario: Заметка в TUI
- **WHEN** TUI загружает сессию с незавершённым ходом без прерванных вызовов, и агент объявил `continue`
- **THEN** последняя строка транскрипта после истории — `The last turn did not finish. Type /continue to resume it.`

#### Scenario: Продолжение из композера
- **WHEN** пользователь вводит `/continue` и отправляет
- **THEN** агент получает `session/prompt` с текстом `/continue`, а заметка остаётся в истории без повторного вывода
