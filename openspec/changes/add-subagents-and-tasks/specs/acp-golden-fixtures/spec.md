## ADDED Requirements

### Requirement: Фикстуры субагентов и списка задач
Корпус SHALL содержать фикстуры change `add-subagents-and-tasks` с объявленными `extensions` (FIX-4; имена по используемым данным: `capabilities` — блок `_meta.codelab` в `initialize`, `task` — `_meta.codelab.task`, `subagent` — `_meta.codelab.subagent`) и ссылками `spec` на `11-Agent Plan.md`, `15-Extensibility.md`, `08-Tool Calls.md` и `02-Initialization.md`:

| Фикстура | Роли | Цели |
|---|---|---|
| `acp/initialize-codelab-extensions` | `agent`, `client` | схема объявления |
| `acp/prompt-task-plan` | `agent`, `client` | C-20, C-05 |
| `acp/session-load-legacy-plan` | `agent` | C-05; журнал старого формата задаётся `setup.sessions` |
| `acp/prompt-subagent-tool-call` | `agent`, `client` | C-06 |
| `acp/prompt-subagent-permission` | `agent`, `client` | C-06, P-02 |
| `acp/prompt-subagent-nested-permission` | `agent` | C-06 |
| `acp/prompt-subagent-tool-tree` | `agent`, `client` | C-06, этап 2 (`extensions`: `capabilities`, `subagent`, `parentToolCallId`) |
| `acp/session-load-subagent-tool-tree` | `agent`, `client` | C-06, этап 2; журналы корня и ребёнка задаются `setup.sessions` |

Изменения существующих фикстур:
- `acp/prompt-update-plan` SHALL остаться в корпусе только с ролью `client`: клиент по-прежнему показывает план агента без `_meta`;
- `acp/initialize-capabilities` SHALL остаться вариантом «клиент без `_meta`» с ролью `agent`;
- клиентские фикстуры, в которых kit отправляет `initialize`, SHALL ожидать `clientCapabilities._meta.codelab` и объявлять `extensions`;
- фикстуры с ожидаемыми схемами запроса к модели SHALL ожидать `task_*` вместо `update_plan`;
- первый `tool_call` вызова `agent` в фикстурах субагентов (те же пять, включая реплей) SHALL ожидать `_meta.codelab.subagent` с `type` и `id` через `$capture` (D28);
- финальный `tool_call_update` вызова `agent` в фикстурах субагентов (`acp/prompt-subagent-tool-call`, `acp/prompt-subagent-permission`, `acp/prompt-subagent-nested-permission`, `acp/prompt-subagent-tool-tree`, реплей `acp/session-load-subagent-tool-tree`) SHALL ожидать `_meta.codelab.subagent.summary` с точными `toolCalls` и токенами scripted-модели; `durationMs` сравнивается через `$any` (время недетерминировано).

Scripted-модель субагента SHALL задаваться тем же блоком `llm.steps`, что и модель корня. Шаги ребёнка различаются проверкой `expect` по системному промпту или первому сообщению ребёнка; нового формата фикстуры не вводится.

#### Scenario: Расширение не объявлено
- **WHEN** фикстура `acp/prompt-task-plan` не перечисляет `task` в `extensions`
- **THEN** тест загрузки корпуса падает (FIX-4)

#### Scenario: Клиент показывает план стороннего агента
- **WHEN** клиентский драйвер проигрывает `acp/prompt-update-plan`
- **THEN** `SessionView.plan` дважды заменяется тремя пунктами без `taskId`

#### Scenario: Агентский прогон запроса ребёнка
- **WHEN** агентский драйвер проигрывает `acp/prompt-subagent-permission` против встроенного агента и `codelab-agent serve --stdio`
- **THEN** кадры совпадают в обоих режимах, включая `toolCallId` `call_1/call_1` и `_meta.codelab.subagent`
