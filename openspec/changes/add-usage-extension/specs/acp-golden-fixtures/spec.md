## ADDED Requirements

### Requirement: Фикстуры расширения usage
Корпус SHALL содержать фикстуры change `add-usage-extension`, у которых `extensions` содержит `usage` (FIX-4; фикстура с инструментом `task_create` несёт ещё `task`) и ссылками `spec` на `15-Extensibility.md` и `05-Prompt Turn.md` (design.md, D13):

| Фикстура | Роли | Режимы агентского прогона |
|---|---|---|
| `acp/prompt-usage-steps` | `agent`, `client` | все |
| `acp/prompt-usage-unpriced` | `agent` | все |
| `acp/prompt-usage-cancelled` | `agent` | все |
| `acp/compact-usage-context` | `agent` | только `conformance:agent` |
| `acp/prompt-usage-compaction-off` | `agent` | только `conformance:agent` |
| `acp/session-load-usage-partial` | `agent` | только `conformance:agent` |

Фикстуры «все» SHALL обходиться без `setup.config` и `setup.sessions`, чтобы их проигрывали и встроенный агент, и `codelab-agent serve --stdio`. `acp/compact-usage-context` SHALL задавать `setup.config.compaction.keep_recent_tokens: 512` (как `acp/slash-compact`): с порогом по умолчанию короткая история не сжимается (design.md, D19 п. 1).

В каждой из них кадр `initialize` клиента SHALL объявлять `clientCapabilities._meta.codelab.usage`. Значения `turnId` SHALL сравниваться через `$capture`, `seq`, токены, стоимость и порядок причин `partial` — точно; `context.used` после шага с инструментом и после сжатия МОЖЕТ сверяться матчером `$any`; scripted-модель SHALL задавать usage шагов в `llm.steps` и цены модели в `llm.model.cost` (объект формата `llmModelCost`: `input`, `output`, необязательные `cacheRead`, `cacheWrite`, доллары за 10⁶ токенов; design.md, D18 Т8, D19 п. 6). Значения `llmModelCost` SHALL быть неотрицательными конечными числами: неизвестный ключ, не число или отрицательное число SHALL давать `FixtureFormatException` с путём поля (`$.llm.model.cost.<ключ>`) при загрузке корпуса; число, которое разбор JSON превращает в бесконечность (`1e999`), отсекает раньше разбора полей канонизация `AcpFixture.fromJson` — `FixtureFormatException` с путём `$` («is not JSON»). Тот же формат читает `--llm-script` (`LlmScript`, требование `agent-binary` «Сценарий --llm-script»): неверное значение SHALL быть ошибкой загрузки сценария с путём поля, а не молчаливым «цен нет» (design.md, D20).

Изменения существующих фикстур:
- `acp/initialize-codelab-extensions` SHALL ожидать `usage: {"version": 1}` в `clientCapabilities._meta.codelab` и в `agentCapabilities._meta.codelab` и объявлять расширение `usage`;
- клиентские фикстуры, в которых kit отправляет `initialize`, SHALL ожидать `usage` в `clientCapabilities._meta.codelab`;
- `acp/prompt-turn-budget-exceeded` SHALL проигрываться и клиентским драйвером;
- фикстуры, где клиент не объявляет `usage`, НЕ SHALL получать кадров `_codelab/session/usage`.

#### Scenario: Расширение не объявлено
- **WHEN** фикстура `acp/prompt-usage-steps` не перечисляет `usage` в `extensions`
- **THEN** тест загрузки корпуса падает (FIX-4)

#### Scenario: Неверная цена модели в фикстуре
- **WHEN** фикстура задаёт `llm.model.cost: {"input": -1, "output": 2}`, другая — `{"input": "1", "output": 2}`, третья — `{"input": 1e999, "output": 2}`
- **THEN** загрузка каждой падает с `FixtureFormatException`: у первых двух путь — `$.llm.model.cost.input`, у третьей — `$` («is not JSON»: канонизация `AcpFixture.fromJson` отсекает не конечное число раньше разбора полей)

#### Scenario: Неверная цена в --llm-script
- **WHEN** `codelab-agent serve --stdio --llm-script` получает файл с `llm.model.cost.output: -0.5`
- **THEN** процесс завершается ошибкой использования (код `64`) с путём `llm.model.cost.output`; запуска без цен нет

#### Scenario: Агентский прогон во всех режимах
- **WHEN** агентский драйвер проигрывает `acp/prompt-usage-steps` против встроенного агента и `codelab-agent serve --stdio`
- **THEN** кадры совпадают в обоих режимах, включая `seq` и десятичные строки `cost`

#### Scenario: Сжатие только в агентском прогоне
- **WHEN** встроенный агент или `codelab-agent serve --stdio` проигрывают корпус
- **THEN** `acp/compact-usage-context` пропускается как фикстура с `setup.config`, а в `conformance:agent` снимок `compaction` и чанк «Compacted…» сверяются без фиксированного порядка

#### Scenario: Клиентский прогон
- **WHEN** клиентский драйвер проигрывает `acp/prompt-usage-steps`
- **THEN** `SessionView.usage` после хода — `reported`, `lastTurn` и `session` равны значениям последнего снимка, клиент не отправляет кадров в ответ на уведомления

#### Scenario: Причина бюджета у клиента
- **WHEN** клиентский драйвер проигрывает `acp/prompt-turn-budget-exceeded`
- **THEN** заметка хода — `The turn stopped: budget exceeded: tokens.`
