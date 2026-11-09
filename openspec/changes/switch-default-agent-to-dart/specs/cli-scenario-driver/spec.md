## ADDED Requirements

### Requirement: JUnit-отчёт test-scenario
`codelab test-scenario … --junit <файл>` SHALL записывать отчёт прогона в формате JUnit XML. Это машинный отчёт для проверки доказательств матрицы целей: design.md change `switch-default-agent-to-dart`, D8; `dart-agent-and-clients` §9.11.

**Открытие файла.** Путь SHALL открываться на запись до запуска первого агента. Если открыть его нельзя, драйвер SHALL завершаться кодом `64` с текстом `codelab: cannot write --junit <путь>: <текст ОС>` в stderr, и агент НЕ SHALL запускаться.

**Схема.**
- Корень `<testsuites>` содержит один `<testsuite name="codelab test-scenario">` с атрибутами `tests`, `failures`, `skipped` и `time` в секундах.
- На каждую фикстуру — один `<testcase classname="acp" name="<id фикстуры>" time="<секунды>">`, в том же порядке id, что строки stdout:
  - строке `FAIL` соответствует вложенный `<failure message="<первая строка причины>">` с диффом или причиной в тексте элемента;
  - строке `SKIP` — `<skipped message="<причина>"/>`.
- Символы `&`, `<`, `>`, `"` и `'` SHALL экранироваться. Символы, недопустимые в XML 1.0, SHALL заменяться на `U+FFFD`.

**Когда пишется файл.** Файл SHALL записываться после последней фикстуры и в тех случаях, когда:
- есть `FAIL`;
- агент не запустился;
- не сыграна ни одна фикстура (пустой `testsuite`).

Строки stdout, итог и коды выхода (требование «Вывод и коды выхода test-scenario») SHALL оставаться прежними.

**Чего нет в файле.** Значения аргументов stdio-профиля, в том числе подставленный путь `{fixture}`, НЕ SHALL попадать в файл — то же правило, что для stdout и stderr (требование «Ошибка запуска агента в test-scenario без аргументов»).

#### Scenario: Отчёт прогона против встроенного агента
- **WHEN** выполняется `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded --junit <tmp>/r.xml`
- **THEN** `<tmp>/r.xml` содержит по одному `testcase` на каждую строку `PASS|FAIL|SKIP` stdout, атрибуты `testsuite` совпадают с итоговой строкой, а у фикстуры `acp/mcp-stdio-tool-call` есть `skipped` с причиной `setup.mcp cannot be passed to the agent process`

#### Scenario: FAIL в отчёте
- **WHEN** у фикстуры изменён ожидаемый кадр агента, и прогон идёт с `--junit`
- **THEN** у её `testcase` есть `failure` с диффом, код выхода `1`, файл записан

#### Scenario: Ни одна фикстура не сыграна
- **WHEN** передан `--filter 'acp/no-such-*'` вместе с `--junit <tmp>/r.xml`
- **THEN** код выхода `1`, а `<tmp>/r.xml` содержит `testsuite` с `tests="0"`

#### Scenario: Файл нельзя открыть
- **WHEN** передан `--junit /nonexistent-dir/r.xml`
- **THEN** код выхода `64`, stderr содержит `codelab: cannot write --junit /nonexistent-dir/r.xml:`, и ни один агент не запущен

#### Scenario: Аргументы агента не попадают в отчёт
- **WHEN** выполняется `codelab test-scenario <каталог фикстур> --agent 'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 {fixture}' --junit <tmp>/r.xml`
- **THEN** у `testcase` есть `failure` с причиной `the agent did not run the fixture: …`, а файл не содержит `sk-test-leak-0123456789`, `--api-key` и путь фикстуры

#### Scenario: Экранирование
- **WHEN** причина пропуска или дифф содержит `<`, `&` и управляющий символ `U+0001`
- **THEN** файл — корректный XML: `<` и `&` экранированы, `U+0001` заменён на `U+FFFD`
