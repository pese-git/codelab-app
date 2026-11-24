# Начало работы с `codelab_acp_testing`

Глава для разработчика, который впервые открыл пакет. Она отвечает на практические вопросы: как подготовить репозиторий, как запустить тесты пакета, как прогнать корпус фикстур против клиента, агента и встроенного агента, как сыграть одну фикстуру и что делать, когда она упала. Устройство формата и драйверов — в следующих главах.

## Что это за пакет

`codelab_acp_testing` — общая тестовая инфраструктура ACP (Agent Client Protocol, протокол, по которому клиент и агент обмениваются сообщениями). В нём три вещи:

- корпус golden-фикстур — JSON-файлы со сценариями обмена кадрами `fixtures/acp/*.json`;
- драйверы, которые проигрывают фикстуру против клиента или против агента, и матчер, который сравнивает кадры;
- двойники для тестов: `FakeAcpTransport`, `FakeTerminalProcessRunner`, скриптовый stdio-агент и агент-повторитель.

Пакет не содержит ни клиента, ни агента. Он подключается к другим пакетам только как `dev_dependency`; исключение — `apps/codelab_cli`, где команда `codelab test-scenario` проигрывает фикстуры в рабочем бинаре (правила — [`AGENTS.md`](../AGENTS.md) пакета и корневой `AGENTS.md` §5). Общий обзор и таблица API — в [README пакета](../README.md).

## Подготовка репозитория

Шаги — в [запуске из исходников](../../../../docs/user/run-from-source.md#1-подготовка). Коротко, из корня репозитория:

1. Поставьте SDK и свяжите пакеты:

   ```bash
   fvm install
   fvm flutter pub get
   fvm dart run melos bootstrap
   ```

2. Создайте сгенерированный код. В git его нет, без него не компилируются зависимости пакета (`codelab_acp_protocol`, `codelab_client_acp`):

   ```bash
   fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
   ```

   Без этого шага `fvm dart test` в пакете падает на загрузке каждого файла с ошибками вида `'JsonRpcResponse' isn't a type`.

## Тесты пакета

```bash
cd packages/dart/codelab_acp_testing
fvm dart test
```

В репозитории на 2026-11-25 это 383 теста; прогон занимает около 45 секунд, из них большая часть — тесты, которые поднимают процессы (`*_agent_test.dart`, `fixture_replay_agent_test.dart`). Один файл или одно имя:

```bash
fvm dart test test/matcher_test.dart
fvm dart test test/matcher_test.dart -n 'unordered'
```

Что проверяет каждая группа тестов — [глава 3](03-testing-and-coverage.md).

## Кто проигрывает корпус

Корпус играют четыре места; как ядро агента использует тот же корпус со сценарной моделью, описано в [главе ядра о тестировании](../../codelab_agent_core/doc/12-testing.md). Скрипты Melos берутся из секции `melos` корневого `pubspec.yaml`, запуск — `fvm dart run melos run <скрипт>`; все они входят в `melos run check`.

| Проверка | Скрипт | Кто играет | Драйвер |
|---|---|---|---|
| клиент | `conformance:client` | `packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` | `runClientFixture` |
| агент | `conformance:agent` | `packages/dart/codelab_agent_acp/test/conformance_test.dart` | `runAgentFixture` |
| встроенный агент | `conformance:embedded` | `codelab test-scenario … --agent embedded` | `runAgentFixtureOver` |
| транспорты бинаря | нет скрипта | `apps/codelab_agent/test/transport_conformance_test.dart` | `runAgentFixtureOver` |

`melos run protocol-conformance` корпус не проигрывает: он запускает только тесты `codelab_acp_protocol`.

Прогон всего корпуса встроенным агентом занимает около 17 секунд и без ключей провайдеров, так как модель — сценарий из самой фикстуры. Итог на 2026-11-25: 85 фикстур дают 50 `PASS`, 0 `FAIL`, 35 `SKIP`. Пропуски объяснены в отчёте:

| Сколько | Причина в строке `SKIP` |
|---|---|
| 18 | `embedded: setup.config cannot be played by the embedded agent` |
| 8 | `setup.mcp cannot be passed to the agent process` |
| 4 | `embedded: setup.sessions cannot be played by the embedded agent` |
| 3 | `… has roles [client] without "agent"` |
| 2 | `… has setup.transport: the transport driver of codelab-agent plays it against the binary process` |

## Как прогнать одну фикстуру

Имя теста в корпусных прогонах — `id` фикстуры. Флаг `-n` — регулярное выражение, которое ищется внутри имени теста; чтобы не захватить соседей с общим началом, заканчивайте образец знаком `$`.

Против клиента (из корня репозитория):

```bash
fvm dart test packages/dart/codelab_client_acp/test/fixtures -n 'acp/prompt-text-end-turn$'
```

Против агента:

```bash
fvm dart test packages/dart/codelab_agent_acp/test/conformance_test.dart -n 'acp/prompt-text-end-turn$'
```

Против встроенного агента — запустить `test-scenario` на файле. Для этого перейдите в `apps/codelab_cli`:

```bash
cd apps/codelab_cli
fvm dart run bin/codelab.dart test-scenario ../../packages/dart/codelab_acp_testing/fixtures/acp/prompt-text-end-turn.json
```

```text
PASS acp/prompt-text-end-turn (0.4s)
1 passed, 0 failed, 0 skipped
```

Без `--agent` играет встроенный агент. Папка вместо файла играет весь корпус, `--filter '<glob>'` выбирает фикстуры по `id` (`*` — любые символы, `?` — один), `--timeout <длительность>` задаёт ожидание кадра агента (по умолчанию 30 секунд), `--junit <файл>` пишет отчёт JUnit. Код выхода: `0` — нет `FAIL`; `1` — есть `FAIL` или не сыграно ни одной фикстуры; `64` — ошибка использования, в том числе битая фикстура.

Транспортные фикстуры — единственные, которые играет только последнее место:

```bash
fvm dart test apps/codelab_agent/test/transport_conformance_test.dart -n 'acp/stdio-framing-large-line$'
```

Фикстура с обеими ролями должна проходить и клиентский, и агентский прогон. Фикстуру с одной ролью другая сторона пропускает с причиной.

## Отладка падения фикстуры

Все драйверы печатают расхождение в одном виде: id фикстуры, индекс кадра, пометка `note`, причина, строки `- <путь>: <что не так>`, затем ожидаемый и фактический кадры. Ниже — настоящий вывод `test-scenario` на копии `prompt-text-end-turn.json` с намеренно испорченным значением.

Агент ответил `end_turn`, а в копии ожидался `max_tokens`:

```text
FAIL acp/prompt-text-end-turn (0.2s)
    frame #3 (ответ последним кадром хода (ACP-3)): a2c frame differs
    - $.result.stopReason: expected "max_tokens", got "end_turn"
    expected:
    {
      "jsonrpc": "2.0",
      "id": "fixture-promptId",
      "result": {
        "stopReason": "max_tokens"
      }
    }
    actual:
    {
      "jsonrpc": "2.0",
      "id": "fixture-promptId",
      "result": {
        "stopReason": "end_turn"
      }
    }
0 passed, 1 failed, 0 skipped
```

Как читать:

1. `frame #3` — индекс в массиве `frames` фикстуры, считая с нуля. Рукопожатие, которое драйвер делает сам, в индекс не входит: его кадры показываются как `handshake frame`. Индекс, равный числу кадров (`frame #4 (after the scenario)` при четырёх кадрах), — проверки после сценария: тишина, `after`, `verify()` агента.
2. Скобки после индекса — поле `note` кадра.
3. Строки `- $.result.stopReason: …` — расхождения с JSON-путём внутри кадра. Матчер перечисляет их все, а не только первое.
4. `expected` — шаблон с подставленными переменными; `"id": "fixture-promptId"` — значение, которое драйвер сам подставил вместо `$capture`. `actual` — кадр так, как он пришёл.

Частые виды расхождений:

| Строка в отчёте | Значение |
|---|---|
| `$.…: expected X, got Y` | значение отличается |
| `$.…: unexpected key (got …)` | агент прислал ключ, которого нет в шаблоне (сравнение точное) |
| `$.…: missing key (expected …)` | в кадре нет ожидаемого ключа |
| `…: expected N items, got M` | разная длина массива |
| `repeated frames differ`, `expected concatenated text …, got …` | склейка дельт не равна `match.$text` |
| `timed out after N ms waiting for an a2c frame` | кадр не пришёл; в скобках указано, сколько кадров поглотили `optional` и `repeat` |
| `unexpected frames from the agent after the scenario` | в конце пришёл кадр, которого фикстура не описывает |
| `unknown variable ${имя}` | переменная не захвачена: опечатка или `$capture` стоит позже |

### Поиграть с копией

Испортить файл прямо в корпусе нельзя: он нужен всем. Скопируйте фикстуру в свой каталог, сохранив имя файла (`id` обязан быть `acp/<имя файла>`), правьте копию и играйте её:

```bash
mkdir -p ~/scratch/fx
cp packages/dart/codelab_acp_testing/fixtures/acp/prompt-text-end-turn.json ~/scratch/fx/
cd apps/codelab_cli
fvm dart run bin/codelab.dart test-scenario ~/scratch/fx/prompt-text-end-turn.json
```

Так воспроизводятся все примеры отчётов в этом руководстве.

### Против клиента

Клиентский драйвер печатает тот же отчёт, но компактно. Пример — к кадру `session/prompt` добавлено поле `foo`, которого клиент не отправляет:

```text
ClientFixtureFailure: acp/prompt-text-end-turn frame #0 (пользователь отправляет промпт): c2a frame differs
  - $.params.foo: missing key (expected 1)
  expected: {"jsonrpc":"2.0","id":{"$capture":"promptId"},"method":"session/prompt","params":{"sessionId":"fixture-session-1","prompt":[{"type":"text","text":"Привет"}],"foo":1}}
  actual:   {"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"fixture-session-1","prompt":[{"type":"text","text":"Привет"}]}}
```

Перед отчётом тест клиента печатает в stdout структурные записи журнала клиента (JSON). Это обычный шум прогона, ищите строку `ClientFixtureFailure`.

### Кто виноват: фикстура или код

Фикстура фиксирует прочтение спецификации ACP. Если кадр фикстуры соответствует разделу из её `spec`, чинится код клиента или агента, а не фикстура; расхождение клиента со спецификацией оформляется отдельным change. Менять ожидаемый кадр «под поведение реализации» без ссылки на раздел спецификации запрещено ([`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md), «Правила изменения фикстур»). Если ACP нужного поведения не определяет, остановитесь и предложите OpenSpec change, а не угадывайте (корневой `AGENTS.md` §3.4).

## Карта: что изменить — куда смотреть

| Задача | Куда |
|---|---|
| новая фикстура | `fixtures/acp/`, [рецепт](04-recipes-and-troubleshooting.md#как-написать-новую-фикстуру) |
| новое поле формата | `lib/src/fixtures/fixture.dart` и `fixtures/acp/_schema.json`, [рецепт](04-recipes-and-troubleshooting.md#как-изменить-формат-фикстуры) |
| новый матчер или правило нормализации | `lib/src/fixtures/matcher.dart`, `test/matcher_test.dart` |
| клиентский прогон: новое действие пользователя | `lib/src/fixtures/client_fixture_user.dart` |
| агентский прогон: новая настройка агента | фабрика `startAgent` в `packages/dart/codelab_agent_acp/test/conformance_test.dart` |
| ожидаемое состояние клиента после фикстуры | `_stateChecks` в `packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` |
| двойник транспорта или процессов | `lib/src/fake_acp_transport.dart`, `lib/src/fake_terminal_process_runner.dart` |
| поведение `test-scenario` | `apps/codelab_cli/lib/src/scenario/` |
| правило импорта пакета | `packages/dart/codelab_architecture_tests/test/support/rules.dart` |
