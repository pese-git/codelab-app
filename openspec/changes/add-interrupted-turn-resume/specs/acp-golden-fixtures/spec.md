## ADDED Requirements

### Requirement: Фикстуры продолжения хода
Корпус SHALL содержать фикстуры change `add-interrupted-turn-resume` со ссылками `spec` на `03-Session Setup.md` (загрузка сессии), `14-Slash Commands.md`, `05-Prompt Turn.md` и `15-Extensibility.md` (поле `_meta` ответа). Расширение `_meta.codelab.unfinishedTurn` не объявляется в `initialize`, поэтому значения `extensions` эти фикстуры не требуют (design.md change `add-interrupted-turn-resume`, D4).

Изменение существующей фикстуры `acp/session-load-interrupted-turn` (по требованию «Правила изменения фикстур», со ссылкой на `15-Extensibility.md` и этот change):
- ответ `session/load` SHALL ожидать `_meta.codelab.unfinishedTurn` с `interruptedToolCalls`, равным id прерванного вызова журнала;
- `available_commands_update` SHALL содержать команду `continue` после `usage`.

Остальные ожидания фикстуры (вызов `failed` с `outcome: "interrupted"`, полное объявление клиента с `usage`, снимок `_codelab/session/usage` с `trigger: "load"`) не меняются. Это единственная существующая фикстура, у которой меняется список команд: в сессиях без незавершённого хода команды `continue` нет.

Новая фикстура `acp/prompt-continue-interrupted-turn`, роли `agent` и `client`, режимы агентского прогона — как у `acp/session-load-interrupted-turn` (фикстура задаёт `setup.sessions`):
- `setup.sessions` — журнал хода с выполненным `write` и вызовом `exec` без результата;
- `session/load` — реплей с `write` `completed` и `exec` `failed`/`interrupted`, ответ с `_meta.codelab.unfinishedTurn`;
- `session/prompt` с текстом `/continue` — кадры хода без `user_message_chunk`, `agent_message_chunk` ответа scripted-модели и ответ `stopReason: end_turn` после последнего уведомления хода (ACP-3);
- `after` агентского прогона SHALL проверять, что последнее сообщение запроса к scripted-модели — служебный `user` с текстом продолжения, а `exec` не вызывался.

#### Scenario: Загрузка прерванного хода в корпусе
- **WHEN** агентский драйвер проигрывает `acp/session-load-interrupted-turn`
- **THEN** ответ `session/load` содержит `_meta.codelab.unfinishedTurn`, `available_commands_update` содержит `continue`; остальные кадры — как до change

#### Scenario: Продолжение в корпусе
- **WHEN** агентский драйвер проигрывает `acp/prompt-continue-interrupted-turn`
- **THEN** кадры совпадают с фикстурой, scripted-модель получила один запрос со служебным сообщением последним, `exec` не исполнялся

#### Scenario: Клиентский прогон продолжения
- **WHEN** клиентский драйвер проигрывает `acp/prompt-continue-interrupted-turn`
- **THEN** после ответа `session/load` у сессии `SessionView.canContinue` истинно, `continueTurn()` отправляет кадр `session/prompt` фикстуры, после хода `unfinishedTurn` равно `null`
