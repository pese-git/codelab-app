## ADDED Requirements

### Requirement: Фикстуры расширения usage
Корпус SHALL содержать фикстуры change `add-usage-extension` с `extensions: ["usage"]` (FIX-4) и ссылками `spec` на `15-Extensibility.md` и `05-Prompt Turn.md` (design.md, D13):

| Фикстура | Роли |
|---|---|
| `acp/prompt-usage-steps` | `agent`, `client` |
| `acp/prompt-usage-unpriced` | `agent` |
| `acp/prompt-usage-cancelled` | `agent` |
| `acp/compact-usage-context` | `agent` |
| `acp/prompt-usage-compaction-off` | `agent` |
| `acp/session-load-usage-partial` | `agent` |

В каждой из них кадр `initialize` клиента SHALL объявлять `clientCapabilities._meta.codelab.usage`. Значения `turnId` SHALL сравниваться через `$capture`, `seq`, токены и стоимость — точно; scripted-модель SHALL задавать usage шагов и цены модели в `llm`.

Изменения существующих фикстур:
- `acp/initialize-codelab-extensions` SHALL ожидать `usage: {"version": 1}` в `clientCapabilities._meta.codelab` и в `agentCapabilities._meta.codelab` и объявлять расширение `usage`;
- клиентские фикстуры, в которых kit отправляет `initialize`, SHALL ожидать `usage` в `clientCapabilities._meta.codelab`;
- `acp/prompt-turn-budget-exceeded` SHALL проигрываться и клиентским драйвером;
- фикстуры, где клиент не объявляет `usage`, НЕ SHALL получать кадров `_codelab/session/usage`.

#### Scenario: Расширение не объявлено
- **WHEN** фикстура `acp/prompt-usage-steps` не перечисляет `usage` в `extensions`
- **THEN** тест загрузки корпуса падает (FIX-4)

#### Scenario: Агентский прогон во всех режимах
- **WHEN** агентский драйвер проигрывает `acp/prompt-usage-steps` против встроенного агента и `codelab-agent serve --stdio`
- **THEN** кадры совпадают в обоих режимах, включая `seq` и десятичные строки `cost`

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/prompt-usage-steps`
- **THEN** `SessionView.usage` после хода — `reported`, `lastTurn` и `session` равны значениям последнего снимка, клиент не отправляет кадров в ответ на уведомления

#### Scenario: Причина бюджета у клиента
- **WHEN** клиентский драйвер проигрывает `acp/prompt-turn-budget-exceeded`
- **THEN** заметка хода — `The turn stopped: budget exceeded: tokens.`
