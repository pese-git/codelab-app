## ADDED Requirements

### Requirement: Незавершённый ход в REPL
После загрузки сессии в REPL (`--resume`, `--continue`, `/resume`, `/reconnect`) CLI SHALL печатать после истории одну строку, если у сессии есть `SessionView.unfinishedTurn` (capability `acp-client-kit`, «Продолжение незавершённого хода»; design.md change `add-interrupted-turn-resume`, D8):
- `The last turn did not finish (interrupted tool calls: <n>). Type /continue to resume it.` при `n > 0`, где `n` — длина `interruptedToolCalls`;
- `The last turn did not finish. Type /continue to resume it.` при `n = 0`.

Строка SHALL печататься только при истинном `canContinue`. Отдельной клиентской команды CLI НЕ SHALL вводить: `/continue` — команда агента из `available_commands_update` и отправляется как обычный промпт. Поведение headless `-p` — capability `cli-headless`, «Продолжение хода в headless».

#### Scenario: Подсказка после --resume
- **WHEN** `codelab --resume <id>` загружает сессию, оборванную во время одного вызова `exec`, и агент объявил `continue`
- **THEN** после истории напечатана строка `The last turn did not finish (interrupted tool calls: 1). Type /continue to resume it.`; ввод `/continue` отправляет промпт агенту

#### Scenario: Без незавершённого хода
- **WHEN** загружается сессия, последний ход которой завершён
- **THEN** строки о незавершённом ходе нет
