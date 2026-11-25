## ADDED Requirements

### Requirement: Команда /continue
`AgentSession` SHALL объявлять встроенную команду `continue` тогда и только тогда, когда при открытии сессии через `AgentRuntime.loadSession` (после лечения журнала) `unfinishedTurnOf` вернул незавершённый ход (capability `agent-sessions`, «Незавершённый ход»; design.md change `add-interrupted-turn-resume`, D4). Объявление — `{"name":"continue","description":"Resume the turn that was interrupted"}` без `input`. Сессия, созданная `createSession`, и сессия без незавершённого хода команды НЕ SHALL объявлять; набранный в ней `/continue` — неизвестная команда (требование «Неизвестная команда»).

Распознавание — по правилам требования «Встроенные команды MVP». Исполнение:
- аргумент не пуст → ответ без модели `Usage: /continue`, журнал не меняется;
- в слоте хода по текущему снимку писателя `unfinishedTurnOf` вернул `null` (ход уже продолжен или завершён) → ответ без модели `Nothing to continue: the last turn finished.`, журнал не меняется, лог `command.continue.nothing` (debug, `session_id`);
- иначе сессия SHALL начинать обычный ход цикла через тот же внутренний вход, что `prompt()` (capability `agent-runtime`, «AgentRuntime и AgentSession»), с сообщением `UserMessage` с фиксированным английским текстом продолжения (design.md, D6) и `origin` `TurnResumeOrigin`. Журнал получает запись `user` с `origin: "turn_resume"`, текст `/continue` в журнал НЕ SHALL попадать. Ход SHALL иметь свежий `TurnBudget` и очищенные разрешения на ход (PERM-8). Отмена, сбой, бюджет, события и итог — как у любого хода цикла. По ACP итог — обычный ответ `session/prompt` со своим `stopReason`. `user_message_chunk` по служебному сообщению не отправляется.

Ход `/continue` НЕ SHALL исполнять вызовы журнала заново. Начало хода SHALL давать лог `session.turn.resumed` (info) с `session_id`.

#### Scenario: Продолжение после сбоя
- **WHEN** сессия, оборванная во время `exec`, загружена, в `available_commands_update` есть `continue`, и приходит `/continue`
- **THEN** scripted-модель получает запрос, последнее сообщение которого — служебный `user` с текстом продолжения; ответ модели и вызовы уходят клиенту как обычный ход; в журнале запись `user` с `origin: turn_resume`; `exec` сам не вызывался

#### Scenario: Повторный /continue
- **WHEN** ход `/continue` завершился финальным ответом, и снова приходит `/continue`
- **THEN** ответ — ровно `Nothing to continue: the last turn finished.`, модель не вызвана, журнал без новых записей

#### Scenario: Новая сессия без команды
- **WHEN** в сессии, созданной `session/new`, приходит `/continue`
- **THEN** ответ — `Unknown command: /continue. Run /help to list commands.`, модель не вызвана

#### Scenario: Аргумент не принимается
- **WHEN** в сессии с незавершённым ходом приходит `/continue but skip tests`
- **THEN** ответ — ровно `Usage: /continue`, модель не вызвана, `unfinishedTurnOf` по-прежнему не `null`

#### Scenario: Отмена продолжения
- **WHEN** во время хода `/continue` приходит `session/cancel` после результатов пакета инструментов
- **THEN** ход завершается `cancelled`, в журнале запись `codelab.turn_stopped` с `reason: cancelled`, следующий `/continue` отвечает `Nothing to continue: the last turn finished.`

## MODIFIED Requirements

### Requirement: Резервные имена команд
Имена встроенных команд §13.4 (`compact`, `mode`, `model`, `status`, `usage`, `continue`, `redact`, `config`, `mcp`, `rename`, `branches`, `branch`, `rewind`, `fork`, `label`, `approve`, `timer`, `memory`, `tasks`, `help`) и `skill` SHALL быть зарезервированы. Шаблон с таким именем НЕ SHALL загружаться и SHALL давать диагностику `warning` `reserved_name` (SKL-7). Имя `continue` зарезервировано всегда, даже в сессии, которая команду не объявляет (design.md change `add-interrupted-turn-resume`, D4).

#### Scenario: Шаблон с именем встроенной команды
- **WHEN** в `$CODELAB_HOME/prompts` лежит `help.md`
- **THEN** команды `help` из шаблона нет, есть диагностика `reserved_name`, промпт `/help` не разворачивается этим файлом

#### Scenario: Шаблон continue
- **WHEN** в `$CODELAB_HOME/prompts` лежит `continue.md`, а сессия создана `session/new`
- **THEN** команды `continue` в списке нет, есть диагностика `reserved_name`, промпт `/continue` — неизвестная команда

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требования «Встроенные команды MVP», «Встроенные команды config и mcp» и «Команда /continue») в порядке §13.4 — `compact`, `mode`, `model`, `status`, `usage`, `continue`, `config`, `mcp`, `help` (`usage` — change `add-usage-ledger`, D5; `continue` — только в сессии, загруженной с незавершённым ходом, change `add-interrupted-turn-resume`, D4); отсутствующая команда пропускается, порядок остальных не меняется (design.md change `add-agent-builtin-slash-commands`, D2), — затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён, затем команды навыков `skill:<name>` (`source: skill`) для навыков с `user-invocable` в байтовом порядке имён навыков (capability `agent-skills`, «Команды навыков»; design.md change `add-agent-skills`, D8). `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`; `inputHint` навыка — `argument-hint`, иначе `"arguments"`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9) и после продолжения хода командой `/continue`. Инструменты модели, в том числе `skill`, в список НЕ SHALL попадать (R-07, SKL-6).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource`, capability `compaction` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help`, `review`

#### Scenario: Без capability compaction и без конфига
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, шаблонов нет
- **THEN** список — `mode`, `model`, `status`, `usage`, `help`

#### Scenario: Навыки после шаблонов
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, у сессии есть шаблон `review`, навыки `release-notes` (с `argument-hint: "<from-tag> <to-tag>"`) и `flutter-golden` (без подсказки) и навык `internal` с `user-invocable: false`
- **THEN** список — `mode`, `model`, `status`, `usage`, `help`, `review`, `skill:flutter-golden` (`inputHint: "arguments"`), `skill:release-notes` (`inputHint: "<from-tag> <to-tag>"`); `skill:internal` и `skill` в списке нет

#### Scenario: Перезагрузка не меняет список
- **WHEN** после открытия сессии перезагрузка добавляет проект в `trusted_projects`, и у проекта есть `.codelab/prompts/fix.md`
- **THEN** список живой сессии не изменился; новая сессия того же `cwd` тоже без `fix` до перезапуска (доверие закреплено, R0-1); `/config reload` отвечает строкой `Restart required: trusted_projects`

#### Scenario: Загруженная сессия с незавершённым ходом
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, и `loadSession` открывает журнал, оборванный во время инструмента
- **THEN** список — `mode`, `model`, `status`, `usage`, `continue`, `help`; после хода `/continue` список не меняется
