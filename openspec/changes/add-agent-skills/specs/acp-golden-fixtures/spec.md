## ADDED Requirements

### Requirement: Фикстуры навыков
Корпус SHALL содержать фикстуры с ролью `agent`, целью `E-06` и ссылками `spec` на `14-Slash Commands.md`, `08-Tool Calls.md` и, для скрипта, `10-Terminal.md` (design.md change `add-agent-skills`, D7, D8; `agent-core-architecture` §17.2.12). Навыки задаются `setup.files` под `.codelab/skills/` доверенного проекта (`setup.config.trusted_projects: ["${cwd}"]`); агентский драйвер SHALL принимать ключ `skills` в `setup.config`:
- `acp/skill-command-listed` (критерий E-06) — два навыка, один с `user-invocable: false`, у другого `argument-hint`: `available_commands_update` после `session/new` содержит после встроенных команд `skill:<name>` только вызываемого навыка с `input.hint` из `argument-hint`; имени `skill` и других инструментов модели в списке нет (SKL-6, R-07);
- `acp/skill-invoke` — `session/prompt` с `/skill:release-notes v1.2 v1.3`: scripted-модель получает сообщение пользователя с обёрткой `invoked.md` и подставленными аргументами; затем `/skill:nope` — один `agent_message_chunk` `Unknown skill: nope. Run /help to list commands.` и `stopReason: end_turn` без запроса к модели; после `session/load` реплей содержит `user_message_chunk` с `/skill:release-notes v1.2 v1.3`;
- `acp/skill-tool-load` — модель вызывает `skill` с `{"name":"release-notes"}`: `tool_call` с `kind: read`, заголовком `Load skill release-notes` и `locations` с путём `SKILL.md` навыка; в режиме `standard` вызов уровня `read` выполняется без `session/request_permission`; `tool_call_update` `completed` содержит тело в блоке `<skill …>`; следующий запрос модели содержит этот результат; второй вызов `skill` с тем же именем завершается строкой повтора `Skill "release-notes" is already loaded in this conversation; follow the instructions above.` (решение Q10);
- `acp/skill-script-exec` (решения Q17, Q24 (а)) — навык проекта `.codelab/skills/pdf` со `scripts/extract.py`; модель вызывает `exec` с `python3 scripts/extract.py` и `cwd` — каталог навыка: `session/request_permission` с обычными вариантами уровня `exec`, включая `allow_always` (критического шаблона нет); после `allow_once` — `terminal/create` с `cwd` каталога навыка и `tool_call_update` `completed` с выводом; вторым шагом — рекомендованный путь (Q26): `exec` с `python3 <cwd>/.codelab/skills/pdf/scripts/extract.py` и `cwd` рабочей папки — тот же обычный вопрос уровня `exec` без критического шаблона (Q25) и `terminal/create` с `cwd` рабочей папки.

Все уведомления хода SHALL идти до ответа на `session/prompt` (ACP-3). Клиентский драйвер SHALL пропускать эти фикстуры с причиной «роль только agent».

#### Scenario: Список команд с навыками в корпусе
- **WHEN** агентский драйвер проигрывает `acp/skill-command-listed`
- **THEN** кадры совпадают с фикстурой, список команд содержит ровно один элемент с префиксом `skill:`

#### Scenario: Неизвестный навык без модели
- **WHEN** агентский драйвер проигрывает `acp/skill-invoke`
- **THEN** на `/skill:nope` scripted-модель не получила запроса, ответ — `end_turn`
