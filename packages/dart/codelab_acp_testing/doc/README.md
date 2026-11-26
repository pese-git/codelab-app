# Руководство по `codelab_acp_testing`

Руководство для разработчика объясняет, как устроена общая тестовая инфраструктура ACP (Agent Client Protocol, протокол, по которому клиент и агент обмениваются сообщениями): корпус golden-фикстур, драйверы, которые проигрывают его против клиента и агента, матчер кадров и двойники для тестов. Прочитав его, вы запустите нужную проверку, найдёте причину падения фикстуры, напишете новую фикстуру и расширите формат или драйверы.

Руководство описывает код как он есть. Формат и алгоритмы приняты в [`14-golden-fixtures.md`](../../../../docs/architecture/proposals/agent-core/14-golden-fixtures.md), требования — в спецификации [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md); если они расходятся с кодом, прав код. Правила пакета — в [`AGENTS.md`](../AGENTS.md), обзор API и быстрый старт — в [README пакета](../README.md).

## Порядок чтения

1. [Начало работы](00-getting-started.md) — подготовка, тесты пакета, кто и как проигрывает корпус, одна фикстура, как читать отчёт о падении.
2. [Формат фикстуры](01-fixture-format.md) — поля `setup`, `llm`, `frames`, `after`, переменные, нормализация, матчеры, загрузчик, `_schema.json`.
3. [Драйверы, матчер и двойники](02-drivers.md) — клиентский, агентский и транспортный драйверы по шагам, `optional` и `repeat`, `test-scenario`, агент-повторитель, `FakeAcpTransport`, скриптовый stdio-агент.
4. [Тесты пакета и покрытие корпуса](03-testing-and-coverage.md) — что проверяет каждый тест, инварианты FIX-1, FIX-2, FIX-4, что регистрируется при добавлении фикстуры.
5. [Рецепты и частые проблемы](04-recipes-and-troubleshooting.md) — новая фикстура сквозным примером, изменение формата, новый матчер, действие пользователя, новая сторона, «симптом → причина → что сделать».

## Главы

| Глава | О чём |
|---|---|
| [00. Начало работы](00-getting-started.md) | подготовка репозитория, `fvm dart test`, скрипты `conformance:*`, одна фикстура против клиента, агента и встроенного агента, отчёт о падении и как его читать |
| [01. Формат фикстуры](01-fixture-format.md) | поля и кто их читает, стандартный handshake, переменные, `<ts>`, матчеры, `normalize`, загрузчик и его ошибки, согласование схемы |
| [02. Драйверы, матчер и двойники](02-drivers.md) | `runClientFixture`, `ClientFixtureUser`, `runAgentFixture`, `runAgentFixtureOver`, открытые шаблоны, `FixtureReplayAgent`, двойники |
| [03. Тесты пакета и покрытие корпуса](03-testing-and-coverage.md) | карта тестов, инварианты корпуса, проверка покрытия, регистрация фикстуры |
| [04. Рецепты и частые проблемы](04-recipes-and-troubleshooting.md) | рецепты со скелетами кода и выводом настоящих прогонов, симптомы и причины |

## Кому что читать

| Задача | Главы |
|---|---|
| запустить проверки и понять отчёт | 00 |
| понять, что значит поле или матчер | 01 |
| понять, как фикстура проигрывается против клиента или агента | 02 |
| добавить фикстуру | 00, 01, 03, [рецепт](04-recipes-and-troubleshooting.md#как-написать-новую-фикстуру) |
| изменить формат или добавить матчер | 01, 03, [рецепты](04-recipes-and-troubleshooting.md#как-изменить-формат-фикстуры) |
| проверить новую реализацию агента или клиента корпусом | 02, [рецепт](04-recipes-and-troubleshooting.md#как-добавить-действие-пользователя-или-новую-сторону) |
| написать тест с процессом агента | 02 (скриптовый stdio-агент) |
| разобраться с упавшим тестом | 00, [частые проблемы](04-recipes-and-troubleshooting.md#частые-проблемы) |

## Что где лежит

| Путь | Содержимое |
|---|---|
| `lib/codelab_acp_testing.dart` | единственный барель: двойники, модель и загрузчик фикстур, матчер, драйверы, повторитель |
| `lib/src/fixtures/` | формат, загрузчик, матчер, драйверы клиента и агента, повторитель |
| `lib/src/fake_acp_transport.dart`, `fake_terminal_process_runner.dart` | двойники транспорта и процессов |
| `lib/src/codelab_compatible_stdio_agent.dart` | исходник скриптового stdio-агента |
| `fixtures/acp/` | корпус фикстур и `_schema.json` |
| `test/`, `test/support/` | тесты пакета и их помощники |

## Смежные документы

- Соседние руководства: [`codelab_acp_protocol`](../../codelab_acp_protocol/doc/README.md) (модели и кодеки, по которым собираются кадры), [`codelab_acp_transports`](../../codelab_acp_transports/doc/README.md) (транспорты и `InProcessAcpLink`), [`codelab_architecture_tests`](../../codelab_architecture_tests/doc/README.md) (сторож: импорты этого пакета и доказательства матрицы целей), [ядро агента](../../codelab_agent_core/doc/README.md), в частности [главу о тестировании](../../codelab_agent_core/doc/12-testing.md) и сценарную модель.
- Команда `codelab test-scenario`: [эксплуатация CLI](../../../../apps/codelab_cli/doc/operations.md#проверка-агента-фикстурами-test-scenario) и [разработка CLI](../../../../apps/codelab_cli/doc/01-overview.md).
- Стратегия тестов: [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md).
- Спецификации: [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md), [`cli-scenario-driver`](../../../../openspec/specs/cli-scenario-driver/spec.md), [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md).
