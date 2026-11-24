# Тесты пакета и покрытие корпуса

Глава объясняет, как проверяется сам пакет и сам корпус: какие тесты за что отвечают, какие инварианты корпус обязан соблюдать, как работает проверка покрытия и что нужно зарегистрировать при добавлении фикстуры. Общую стратегию тестов задаёт [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md), требования — спецификации [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md) и [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md).

Тесты лежат в `test/`, двойники и помощники тестов — в `test/support/`. Запуск — `fvm dart test` в каталоге пакета ([глава 0](00-getting-started.md#тесты-пакета)).

## Что проверяет каждый файл

| Файл теста | Что проверяет |
|---|---|
| `fixture_loader_test.dart` | загрузчик: неполная фикстура падает громко (с файлом и путём поля), полная загружается с `roles` по умолчанию; `setup.mcp` и `after.mcpCalls`; `loadFixtureCorpus` (плоский каталог, файлы с `_`) |
| `fixture_transport_test.dart` | блок `setup.transport` (`stdio`, `ws`, `attempts`) и генератор `$repeat` |
| `fixtures_schema_sync_test.dart` | совпадение `_schema.json` и `fixtureFormatKeys` загрузчика |
| `fixtures_load_test.dart` | корпус целиком: точный список `id`, роли групп фикстур, инварианты FIX-1 и FIX-4 на каждой фикстуре, `llm.model.cost`, проверки инвариантов на временном корпусе |
| `fixtures_coverage_test.dart` | FIX-2, клиентская часть |
| `fixtures_agent_coverage_test.dart` | FIX-2, агентская часть |
| `matcher_test.dart` | матчер: мутации кадров ловятся с понятным путём, каждый матчер, `$capture`, нормализация, `materialize` |
| `client_conformance_test.dart` | клиентский драйвер на заглушках клиента: совпадение, расхождение с индексом кадра и путём, таймауты, `fs/*` из `setup.files`, `terminal/*` из `setup.terminal`, `after.files`, поздние кадры клиента, объявление клиента как подмножество |
| `agent_conformance_test.dart` | агентский драйвер на заглушках агента: совпадение, поздние необязательные кадры, лишний кадр, лишний `fs/*`, неиспользованный шаг модели, `after.files`, пропуск по роли и по транспорту, `setup.mcp` до фабрики |
| `fixture_replay_agent_test.dart` | агент-повторитель: весь агентский корпус проходит против него, испорченная копия даёт расхождение, лишний кадр клиента — `-32600`, процессный вариант отвечает на `initialize` |
| `codelab_acp_testing_test.dart` | экспорты барела, исходник скриптового агента, `FakeAcpTransport` (захват кадров, события, закрытие) |
| `*_agent_test.dart` (`available_commands`, `cli_modes`, `markdown_reply`, `session_list`, `usage`, `usage_budget`) | режимы скриптового stdio-агента на настоящем процессе Dart VM; общий помощник — `test/support/agent_process.dart` |

Драйверы проверяются на заглушках, а не на настоящих клиенте и агенте: пакет не знает пакетов агента, а настоящего клиента (`AcpClientApplication`) проверяет `conformance:client`. Так тесты драйвера не рушатся из-за регрессии стороны.

## Инварианты корпуса

Инварианты FIX-1, FIX-2 и FIX-4 описаны в [§14.11](../../../../docs/architecture/proposals/agent-core/14-golden-fixtures.md#1411-инварианты-корпуса), помощники — `test/support/corpus_invariants.dart`.

| Инвариант | Что требует | Где проверяется |
|---|---|---|
| FIX-1 | каждая ссылка `spec` — существующий файл `docs/protocols/acp/protocol/` и существующий якорь (заголовок или `<a id="…">`) в нём | `fixtures_load_test.dart`, тест `acp/<имя> FIX-1: spec references exist` на каждую фикстуру |
| FIX-4 | фикстура без `extensions` не содержит `_meta.codelab`, `data.codelab` и методов `_codelab/*` | `fixtures_load_test.dart`, тест `acp/<имя> FIX-4: no undeclared extensions` |
| FIX-2 | каждый метод из `acpMethodRegistry` и каждый вид `sessionUpdate` из `codelab_acp_protocol` встречается хотя бы в одной фикстуре роли `client` и хотя бы в одной роли `agent` (кроме явного списка ожидаемого покрытия) | `fixtures_coverage_test.dart`, `fixtures_agent_coverage_test.dart` |

Пример провала FIX-1: в учебной фикстуре `tool-read-whole-file` из [рецепта](04-recipes-and-troubleshooting.md#как-написать-новую-фикстуру) якорь `reading-files` заменён на `reading-file`:

```text
acp/tool-read-whole-file FIX-1: spec references exist [E]
  Expected: empty
    Actual: [
              'acp/tool-read-whole-file: spec "09-File System.md#reading-file": no anchor #reading-file in 09-File System.md'
            ]
```

Якорь — заголовок файла спецификации в виде slug (строчные буквы, без знаков препинания, пробелы — дефисы) или явный `<a id="…">`. Если не уверены, как выглядит якорь, откройте файл в `docs/protocols/acp/protocol/` и найдите заголовок.

### Как работает проверка покрытия

Тест собирает «покрытые элементы»: обходит `frame` и `unordered` каждой фикстуры нужной роли и записывает все значения ключа `method` и ключа `sessionUpdate` (`coveredProtocolElements`). «Все элементы» берёт из протокола: методы — из `acpMethodRegistry` в `codelab_acp_protocol`, виды обновлений — регулярным выражением из исходника `session_update.dart` (`'<вид>' => SessionUpdate.…`, `protocolSessionUpdateKinds`). Если в `session_update.dart` изменить форму этой записи, тест увидит пустой набор и упадёт на проверке `the protocol lists are read`.

Исключения лежат в двух константах:

- `pendingCoverage` в `fixtures_coverage_test.dart` — для клиентской роли. Сейчас там `session/list` и `session/set_mode`: клиентской фикстуры для них нет. Агентскую сторону покрывают `acp/session-list-cwd-filter` и `acp/set-mode-*`. Комментарий в файле объясняет `session/list` тем, что клиент метод не вызывает, но `AcpClientApplication.listSessions` в коде есть;
- `agentPendingCoverage` в `fixtures_agent_coverage_test.dart` — для агентской роли; сейчас пуст.

Списки только сокращаются: тест `a covered element leaves pendingCoverage` падает, если элемент уже покрыт, и требует его убрать. Добавлять в список новый элемент ради зелёного теста нельзя без причины: вместо этого пишется фикстура.

## Что регистрируется при добавлении фикстуры

Корпус защищён от тихих изменений. После добавления файла упадут тесты в трёх местах, и каждое надо сознательно обновить:

| Где | Что сделать |
|---|---|
| `test/fixtures_load_test.dart` | тест `the corpus holds exactly …` сравнивает множество `id` корпуса с объединением именованных множеств (`_stage0Fixtures`, `_tasksFixtures`, …): добавить `id` в подходящее множество или завести новое и включить в объединение. Множество `_stage4Fixtures` ещё проверяется на длину 35 — туда новые фикстуры не добавляют |
| `packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` | для фикстуры роли `client` добавить запись в `_stateChecks` с проверками состояния клиента после прогона; без записи тест падает с сообщением `add a state check for <id>` |
| `pendingCoverage` или `agentPendingCoverage` | убрать элемент, который фикстура теперь покрывает |

Фабрика агента (`startAgent` в `packages/dart/codelab_agent_acp/test/conformance_test.dart`) и `test-scenario` новых записей не требуют, если фикстура обходится уже поддержанными полями `setup`.

Ещё одна связь вне пакета: строки матрицы целей паритета ссылаются на фикстуры видом `acp/<id>`, и сторож репозитория проверяет, что файл существует ([`docs/architecture/testing.md`](../../../../docs/architecture/testing.md), «Проверка доказательств матрицы целей», тест `parity_evidence_test.dart` в [`codelab_architecture_tests`](../../codelab_architecture_tests/doc/README.md)). Переименование или удаление фикстуры ломает матрицу: `melos run guard` покажет, какая строка осталась без доказательства.

## Правила пакета для тестов

- Тест проверяет драйвер или формат, а не поведение клиента и агента: для этого есть корпус.
- Новая возможность формата идёт вместе с тестом загрузчика (`fixture_loader_test.dart`, `fixture_transport_test.dart`), записью в `fixtureFormatKeys`, записью в `_schema.json` и, если это матчер, тестом `matcher_test.dart` ([рецепт](04-recipes-and-troubleshooting.md#как-изменить-формат-фикстуры)).
- Новую фикстуру проигрывают обе роли, если `roles` её не сужает (`AGENTS.md` пакета): `conformance:client` и `conformance:agent`.
- Драйверы ждут кадры по реальным часам (`frameTimeout`, `quietPeriod`), а не по поддельным. Тесты драйверов задают маленькие значения (например, `quietPeriod` 30 мс, `frameTimeout` 300 мс в `agent_conformance_test.dart`), чтобы прогон был быстрым.
- Тесты, которые поднимают процессы, пишут временные файлы в `Directory.systemTemp.createTemp(...)` и удаляют их в `tearDown`.

## Тесты в других пакетах, которые опираются на этот

| Где | Что использует |
|---|---|
| `codelab_client_acp/test/` | `FakeAcpTransport`, `FakeTerminalProcessRunner` почти во всех тестах протокольного клиента |
| `codelab_client_core/test/` | `FakeAcpTransport`, `ClientFixtureUser`, скриптовые агенты (`test/support/kit_agent.dart`, `usage_agent.dart`) |
| `codelab_client_io/test/transport/` | исходник скриптового stdio-агента для проверки настоящего транспорта |
| `codelab_acp_transports/test/` | скриптовый stdio-агент для проверки транспорта stdio |
| `codelab_agent_acp/test/` | корпус для `AcpAgentServer` и контрактный тест клиентского приложения |
| `codelab_agent_core/test/` | пакет не импортируется; один тест читает файл `acp/prompt-tool-permission-allow.json` и проверяет, что `ScriptedStreamFunction.fromJson` играет его блок `llm` |
| `apps/codelab_cli/` | `test-scenario` в рабочем коде; `test/support/replay_agent.dart` и PTY-e2e на скриптовых агентах |
| `apps/codelab_agent/test/` | транспортные фикстуры |
| `apps/codelab_desktop/integration_test/` | скриптовый stdio-агент (`support/e2e_agent.dart`) |
