## MODIFIED Requirements

### Requirement: Агентский драйвер фикстур
`codelab_acp_testing` SHALL предоставлять драйвер `runAgentFixture(fixture, startAgent)`, который проигрывает фикстуру с ролью `agent` против агента по алгоритму §14.9 документа ядра:
- агент поднимается фабрикой теста на агентском конце пары транспортов в памяти (`InProcessAcpLink` из основного бареля `codelab_acp_transports`; design.md change `add-in-process-acp-transport`, D5) с `ScriptedStreamFunction` из блока `llm`, `FakeClock` и `SequentialIdGenerator`;
- файлы и команды агент получает через ACP: кадры `fs/*` и `terminal/*` — часть фикстуры, ответы клиента берутся из её кадров `c2a`; `setup.files` пишутся во временный `cwd` только для локального листинга;
- кадры `c2a` отправляются агенту, кадры `a2c` ожидаются (таймаут 5 с) и сравниваются после нормализации с матчерами `repeat`, `optional`, `unordered`;
- после последнего кадра 200 мс тишины: лишний кадр или лишний запрос агента — провал;
- все шаги scripted-модели использованы, лишних запросов нет; `after.files` сверяются с последним `fs/write_text_file`.

Драйвер НЕ SHALL зависеть от пакетов агента и НЕ SHALL содержать собственную реализацию пары транспортов в памяти. Фикстура без роли `agent` и фикстура с `setup.transport` SHALL пропускаться с указанием причины: транспортные фикстуры играет транспортный драйвер. Скрипт `melos run conformance:agent` SHALL входить в `melos run check`.

#### Scenario: Ход с разрешением
- **WHEN** драйвер проигрывает `acp/prompt-tool-permission-allow` против `AcpAgentServer`
- **THEN** запрос `session/request_permission` агента совпадает с ожидаемым кадром, ответ клиента из фикстуры приводит к `tool_call_update` `completed` и ответу `end_turn`

#### Scenario: Лишний кадр агента
- **WHEN** агент после последнего ожидаемого кадра отправляет ещё одно уведомление
- **THEN** драйвер падает и показывает лишний кадр

#### Scenario: Фикстура только для клиента
- **WHEN** у фикстуры `roles` равно `["client"]`
- **THEN** агентский драйвер её пропускает и сообщает причину

#### Scenario: Транспортная фикстура в памяти
- **WHEN** агентский драйвер получает `acp/stdio-framing-large-line`
- **THEN** он её пропускает и сообщает, что её играет транспортный драйвер

#### Scenario: Пара транспортов из codelab_acp_transports
- **WHEN** агентский драйвер поднимает агента для фикстуры
- **THEN** агентский конец — `InProcessAcpLink().agent` из `package:codelab_acp_transports/codelab_acp_transports.dart`, а в `packages/dart/codelab_acp_testing/lib/` нет определения классов `InProcessAcpLink` и `InProcessAcpTransport`
