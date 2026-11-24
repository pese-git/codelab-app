# Рецепты и частые проблемы

Глава собирает пошаговые рецепты (новая фикстура, изменение формата, новый матчер, новое действие пользователя, новая сторона проверки) и случаи «симптом, причина, что сделать». Все выводы команд в главе получены настоящими прогонами; пути и случайные идентификаторы заменены на `<session-id>` и `/tmp/agent_fixture_<id>`. Перед рецептами прочитайте [главу 1](01-fixture-format.md) и [главу 2](02-drivers.md).

## Как написать новую фикстуру

Рецепт сквозной: учебная фикстура `acp/tool-read-whole-file` проверяет, что агент читает файл целиком через клиента (`fs/read_text_file`), а клиент отвечает содержимым. Она нужна только для рецепта и в корпус не входит. Образец, по которому её строят, — настоящая фикстура `fixtures/acp/tool-read-range.json` (чтение диапазона строк). Тот же порядок работы подходит для любой фикстуры.

### 1. Выберите сценарий, роли и имя

- Сценарий — одна наблюдаемая цепочка кадров по спецификации ACP: «пользователь просит прочитать файл → агент читает через клиента → отвечает».
- Роли. По умолчанию фикстуру играют обе стороны. Сузьте `roles`, только если сценарий нужен одной стороне (клиент не вызывает метод; агент не порождает кадр).
- Имя `<область>-<сценарий>[-<исход>]` в kebab-case: `tool-read-whole-file`. Файл — `fixtures/acp/tool-read-whole-file.json`, `id` — `acp/tool-read-whole-file`.
- Найдите в корпусе близкую фикстуру и держитесь её порядка кадров: промпт (`c2a`), обновления и запросы агента (`a2c`), ответы клиента (`c2a`), дельты текста с `repeat`, необязательное название сессии, ответ на промпт.

### 2. Определите ссылки `spec`

Фикстура обязана ссылаться на разделы `docs/protocols/acp/protocol/`, которые обосновывают её кадры. Формат — `<файл>.md#<якорь>`, якорь — заголовок раздела в виде slug или явный `<a id="…">`. Для чтения файла это `09-File System.md#reading-files` и `08-Tool Calls.md#following-the-agent`. Проверка FIX-1 упадёт на несуществующем файле или якоре.

Методы и поля нельзя придумывать: каждый кадр должен быть в спецификации и в `codelab_acp_protocol` (корневой `AGENTS.md` §3.4).

### 3. Напишите начало и запустите против агента

Первый вариант: `setup`, скрипт модели и два первых кадра. Остальное мы пока не знаем.

```json
{
  "id": "acp/tool-read-whole-file",
  "spec": [
    "09-File System.md#reading-files",
    "08-Tool Calls.md#following-the-agent"
  ],
  "description": "Файл из трёх строк; модель вызывает read только с path; агент читает файл целиком через клиента fs/read_text_file и показывает результат с номерами строк.",
  "setup": {
    "cwd": "/work/demo",
    "files": {"a.txt": "one\ntwo\nthree\n"}
  },
  "llm": {
    "steps": [
      {
        "reply": [
          {"toolCall": {"id": "call_1", "name": "read", "arguments": {"path": "a.txt"}}}
        ],
        "stopReason": "toolUse"
      },
      {
        "expect": {"toolResult": {"toolCallId": "call_1", "isError": false}},
        "reply": [{"text": "Прочитал a.txt."}],
        "stopReason": "stop"
      }
    ]
  },
  "frames": [
    {
      "dir": "c2a",
      "note": "пользователь просит прочитать файл",
      "frame": {
        "jsonrpc": "2.0",
        "id": {"$capture": "promptId"},
        "method": "session/prompt",
        "params": {
          "sessionId": "${sessionId}",
          "prompt": [{"type": "text", "text": "Прочитай a.txt"}]
        }
      }
    },
    {
      "dir": "a2c",
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "tool_call",
            "toolCallId": "call_1",
            "title": {"$contains": "a.txt"},
            "kind": "read",
            "status": "pending",
            "rawInput": {"path": "a.txt"},
            "locations": [{"path": "${cwd}/a.txt"}]
          }
        }
      }
    }
  ]
}
```

Запустите агентский прогон (команда в [главе 0](00-getting-started.md#как-прогнать-одну-фикстуру)):

```bash
fvm dart test packages/dart/codelab_agent_acp/test/conformance_test.dart -n 'acp/tool-read-whole-file$'
```

```text
AgentFixtureFailure: acp/tool-read-whole-file frame #2 (after the scenario): unexpected frames from the agent after the scenario: the agent did more than the fixture records (fs/read_text_file)
    actual:   [{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"<session-id>","update":{"sessionUpdate":"tool_call_update","toolCallId":"call_1","status":"in_progress"}}},{"jsonrpc":"2.0","id":"fs-1","method":"fs/read_text_file","params":{"sessionId":"<session-id>","path":"/tmp/agent_fixture_<id>/a.txt","line":1,"limit":2001}}]
```

Фикстура с двумя кадрами кончилась, а агент продолжил: драйвер так и сообщает «агент сделал больше, чем закреплено». В `actual` — следующие кадры агента: обновление `in_progress` и запрос `fs/read_text_file`.

Важно: отчёт показывает, что агент делает, а не что требует спецификация. Не копируйте `actual` в фикстуру не глядя. Сверьте каждое поле с `docs/protocols/acp/protocol/` и убедитесь, что оно там есть: эталоном служит спецификация, а не поведение реализации. Допустимые отклонения выражайте матчерами (`$oneOf`, `$contains`, `$any`), а не подгонкой значений. Так, `limit` 2001 в нашем примере — деталь инструмента `read` (лишняя строка показывает, что файл продолжается). Если она не принципиальна, замените её на `{"$any": true}`; если фиксирует контракт ядра, оставьте число.

### 4. Допишите кадры по отчётам

Добавляйте кадры в порядке прихода, запуская прогон после каждого. Ответ клиента на запрос агента — кадр `c2a`, его `id` берётся из захваченного значения:

```json
{
  "dir": "a2c",
  "note": "файл читает клиент",
  "frame": {
    "jsonrpc": "2.0",
    "id": {"$capture": "read1"},
    "method": "fs/read_text_file",
    "params": {"sessionId": "${sessionId}", "path": "${cwd}/a.txt", "line": 1, "limit": 2001}
  }
},
{
  "dir": "c2a",
  "note": "клиент отдаёт содержимое файла",
  "frame": {"jsonrpc": "2.0", "id": "${read1}", "result": {"content": "one\ntwo\nthree"}}
}
```

Если остановиться до ответа клиента, прогон скажет другое: агент ждёт ответа, второй шаг модели не выполнен.

```text
AgentFixtureFailure: acp/tool-read-whole-file frame #4 (after the scenario): the agent check after the scenario failed: ScriptedLlmFailure:
    - step 2 was not used
```

Дальше идут `tool_call_update` со статусом `completed`, дельты ответа (`repeat` с `match.$text`), необязательный `session_info_update` и ответ на промпт `end_turn`. Образцы для каждого кадра — в `tool-read-range.json`.

<details>
<summary>Фикстура целиком</summary>

```json
{
  "id": "acp/tool-read-whole-file",
  "spec": [
    "09-File System.md#reading-files",
    "08-Tool Calls.md#following-the-agent"
  ],
  "description": "Файл из трёх строк; модель вызывает read только с path; агент читает файл целиком через клиента fs/read_text_file и показывает результат с номерами строк.",
  "setup": {
    "cwd": "/work/demo",
    "files": {"a.txt": "one\ntwo\nthree\n"}
  },
  "llm": {
    "steps": [
      {
        "reply": [
          {"toolCall": {"id": "call_1", "name": "read", "arguments": {"path": "a.txt"}}}
        ],
        "stopReason": "toolUse"
      },
      {
        "expect": {"toolResult": {"toolCallId": "call_1", "isError": false}},
        "reply": [{"text": "Прочитал a.txt."}],
        "stopReason": "stop"
      }
    ]
  },
  "frames": [
    {
      "dir": "c2a",
      "note": "пользователь просит прочитать файл",
      "frame": {
        "jsonrpc": "2.0",
        "id": {"$capture": "promptId"},
        "method": "session/prompt",
        "params": {
          "sessionId": "${sessionId}",
          "prompt": [{"type": "text", "text": "Прочитай a.txt"}]
        }
      }
    },
    {
      "dir": "a2c",
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "tool_call",
            "toolCallId": "call_1",
            "title": {"$contains": "a.txt"},
            "kind": "read",
            "status": "pending",
            "rawInput": {"path": "a.txt"},
            "locations": [{"path": "${cwd}/a.txt"}]
          }
        }
      }
    },
    {
      "dir": "a2c",
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call_1",
            "status": "in_progress"
          }
        }
      }
    },
    {
      "dir": "a2c",
      "note": "файл читает клиент",
      "frame": {
        "jsonrpc": "2.0",
        "id": {"$capture": "read1"},
        "method": "fs/read_text_file",
        "params": {
          "sessionId": "${sessionId}",
          "path": "${cwd}/a.txt",
          "line": 1,
          "limit": 2001
        }
      }
    },
    {
      "dir": "c2a",
      "note": "клиент отдаёт содержимое файла",
      "frame": {
        "jsonrpc": "2.0",
        "id": "${read1}",
        "result": {"content": "one\ntwo\nthree"}
      }
    },
    {
      "dir": "a2c",
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call_1",
            "status": "completed",
            "content": [
              {
                "type": "content",
                "content": {"type": "text", "text": {"$contains": "1| one"}}
              }
            ]
          }
        }
      }
    },
    {
      "dir": "a2c",
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "agent_message_chunk",
            "content": {"type": "text", "text": {"$any": true}}
          }
        }
      },
      "repeat": "+",
      "match": {"$text": "Прочитал a.txt."}
    },
    {
      "dir": "a2c",
      "note": "агент может назвать сессию после первого хода",
      "optional": true,
      "frame": {
        "jsonrpc": "2.0",
        "method": "session/update",
        "params": {
          "sessionId": "${sessionId}",
          "update": {
            "sessionUpdate": "session_info_update",
            "title": {"$any": "Fixture"},
            "updatedAt": "<ts>"
          }
        }
      }
    },
    {
      "dir": "a2c",
      "note": "ответ последним кадром хода",
      "frame": {
        "jsonrpc": "2.0",
        "id": "${promptId}",
        "result": {"stopReason": "end_turn"}
      }
    }
  ]
}
```

</details>

### 5. Проверьте клиентскую роль

```bash
fvm dart test packages/dart/codelab_client_acp/test/fixtures -n 'acp/tool-read-whole-file$'
```

Если клиент читает файл с `line` и `limit`, `InMemoryFixtureFileSystem` отдаёт выбранные строки через `\n` без завершающего перевода строки. Поэтому в нашей фикстуре `content` — `"one\ntwo\nthree"`, а не `"one\ntwo\nthree\n"`. Первая версия фикстуры, где ответ клиента заканчивался переводом строки, прошла агентский прогон (агент берёт ответ клиента из кадра как есть) и упала на клиентском:

```text
ClientFixtureFailure: acp/tool-read-whole-file frame #4 (клиент отдаёт содержимое файла): c2a frame differs
  - $.result.content: expected "one\ntwo\nthree\n", got "one\ntwo\nthree"
  expected: {"jsonrpc":"2.0","id":"fixture-read1","result":{"content":"one\ntwo\nthree\n"}}
  actual:   {"jsonrpc":"2.0","id":"fixture-read1","result":{"content":"one\ntwo\nthree"}}
```

После исправления кадров прогон доходит до последней проверки: клиентскому тесту нужна запись о состоянии.

```text
  Expected: not null
    Actual: <null>
  add a state check for acp/tool-read-whole-file
```

### 6. Зарегистрируйте фикстуру

Фикстура с ролью `client` требует записи в `_stateChecks` — таблице проверок состояния клиента после прогона (`packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart`). Состояние проверяет тест, а не фикстура: фикстура закрепляет кадры.

```dart
'acp/tool-read-whole-file': (user, _) {
  expect(_lastTurn(user).status, PromptTurnStatus.completed);
  expect(_toolCall(user, 'call_1').status, ToolCallStatus.completed);
},
```

Второе место — список корпуса в `packages/dart/codelab_acp_testing/test/fixtures_load_test.dart`: тест `the corpus holds exactly …` падает, пока `id` не внесён в одно из множеств. Заведите множество и включите его в объединение в этом тесте:

```dart
/// Фикстуры чтения файла целиком.
const _readFixtures = {'acp/tool-read-whole-file'};
// … в объединении теста: ..._readFixtures,
```

Если фикстура закрывает метод или вид `sessionUpdate` из списка `pendingCoverage` (клиент) или `agentPendingCoverage` (агент), уберите элемент из списка: [глава 3](03-testing-and-coverage.md#как-работает-проверка-покрытия).

### 7. Прогоните все стороны

```bash
cd packages/dart/codelab_acp_testing && fvm dart test
cd ../../..
fvm dart run melos run conformance:client
fvm dart run melos run conformance:agent
fvm dart run melos run conformance:embedded
fvm dart run melos run guard
```

Для учебной фикстуры были запущены тесты пакета (385 тестов вместо 383), клиентский прогон, агентский прогон и `test-scenario` на её файле: всё прошло. Скрипты Melos целиком и `guard` для неё не запускались. Перед pull request запускают только то, что затронуто изменением (`AGENTS.md` §21).

После рецепта учебную фикстуру и записи в `_stateChecks` и `fixtures_load_test.dart` удаляют: в этом репозитории она не хранится.

### Фикстура, которой нужен ключ `setup.config` или `setup.sessions`

Эти поля читает только агентский прогон. Фабрика `startAgent` в `packages/dart/codelab_agent_acp/test/conformance_test.dart` разбирает `setup.config` строго: неизвестный ключ — `FormatException: config.<ключ>`. Нужен новый ключ — добавьте его в `_FixtureConfig.parse` вместе с потребителем и тестом. Для встроенного агента и `codelab-agent` `codelab test-scenario` фикстуры с `setup.config`, `setup.sessions` и `setup.mcp` пропускает (`SKIP`): их играет только `conformance:agent`. Исключение — агент-повторитель с `{fixture}` в аргументах профиля: он получает фикстуру целиком.

## Как изменить формат фикстуры

Пример — новое необязательное поле `setup.env` (переменные окружения процесса агента). Порядок такой, чтобы загрузчик, схема и тесты не разошлись.

1. Загрузчик, `lib/src/fixtures/fixture.dart`: добавьте ключ в `fixtureFormatKeys['setup']`, поле в `FixtureSetup` и разбор в `FixtureSetup._parse`:

   ```dart
   // fixtureFormatKeys['setup'] = { …, 'skipInitialize', 'env', … }

   // конструктор FixtureSetup: this.env = const {},
   // разбор в _parse:
   env: r.stringMap(json, path, 'env') ?? const {},

   /// Переменные окружения процесса агента.
   final Map<String, String> env;
   ```

   Помощники `_Reader` (`string`, `integer`, `boolean`, `object`, `list`, `stringMap`) сами бросают `FixtureFormatException` с файлом и путём.

2. Схема, `fixtures/acp/_schema.json`: добавьте свойство в `$defs.setup.properties`:

   ```json
   "env": {
     "description": "Environment variables of the agent process.",
     "type": "object",
     "additionalProperties": {"type": "string"}
   }
   ```

   Пока схема отстаёт, `fixtures_schema_sync_test.dart` падает так:

   ```text
   Expected: Set:['cwd', 'files', …, 'skipInitialize', 'env', 'sessions', 'transport', 'mcp']
     Actual: Set:['cwd', 'files', …, 'skipInitialize', 'sessions', 'transport', 'mcp']
      Which: does not contain 'env'
   test/fixtures_schema_sync_test.dart 48:7  main.<fn>
   Failing tests:
     test/fixtures_schema_sync_test.dart: properties of "setup" match the loader
   ```

3. Тест загрузчика: в `fixture_loader_test.dart` добавьте случаи «поле принимается» и «неверный тип даёт `FixtureFormatException` с путём `$.setup.env`». Если поле влияет на сравнение, добавьте случай в `matcher_test.dart`.
4. Драйвер: решите, кто читает поле, и подключите его — `AgentFixtureSetup` для агентского прогона (геттер, как у `profile` и `config`) или `ClientFixtureEnvironment` для клиентского. Поле, которое не читает ни один драйвер (как `web`), создавать не стоит.
5. Потребители: если поле нельзя передать агенту процессом, `ScenarioAgent.skipReason` в `apps/codelab_cli/lib/src/scenario/agent_connector.dart` должен пропускать такие фикстуры с причиной; фабрика `startAgent` должна понимать поле или отвергать его.
6. Документы: формат закреплён в `docs/architecture/proposals/agent-core/14-golden-fixtures.md` и спецификации `acp-golden-fixtures`. Изменение формата — изменение контракта, поэтому оно проходит через OpenSpec change (`AGENTS.md` §17), а описание в этих документах правит автор change.

Правки схемы без правок загрузчика бессмысленны: загрузчик — то, что реально разбирает файл.

## Как добавить матчер

Матчер — объект с одним ключом `$…`. Скелет для `$startsWith` (префикс строки); код проверен компиляцией и тестом, в репозитории его нет. В `lib/src/fixtures/matcher.dart` три места:

```dart
// 1. Список известных матчеров: без него ключ — «unknown matcher».
const _matcherKeys = {
  // …
  r'$repeat',
  r'$startsWith',
};

// 2. Сравнение в _compareMatcher: ещё один case в switch (key).
case r'$startsWith':
  final prefix = value is String
      ? _substitute(value, captures: captures)
      : throw FixtureMatchException('$path: \$startsWith must be a string');
  if (actual is! String || !actual.startsWith('$prefix')) {
    out.add(
      FrameMismatch(
        path,
        'expected a string starting with ${_encode(prefix)}, '
        'got ${_encode(actual)}',
      ),
    );
  }

// 3. Материализация, case в switch (key) метода materialize: нужна, когда
// драйвер сам отправляет кадр с таким матчером.
r'$startsWith' => materialize(value, path),
```

Без третьего пункта матчер можно писать только в кадрах, которые драйвер лишь сравнивает. В кадре, который драйвер отправляет сам (`a2c` у клиентского драйвера, `c2a` у агентского), будет `FixtureMatchException: … cannot be turned into a value for the client run`. Тест — в `matcher_test.dart`: успех, расхождение с текстом сообщения, результат `materialize`. Описание матчера добавьте в [главу 1](01-fixture-format.md#матчеры), а в спецификации `acp-golden-fixtures` его фиксирует автор change.

## Как добавить действие пользователя или новую сторону

### Новое действие клиента

Кадр клиента появляется после действия пользователя. Если сценарию нужен метод, которого нет в `ClientFixtureUser.act` ([глава 2](02-drivers.md#clientfixtureuser)), прогон упадёт по таймауту ожидания кадра. Добавьте `case` в `lib/src/fixtures/client_fixture_user.dart`. Скелет для `session/list`, который клиент поддерживает (`AcpClientApplication.listSessions`); проверен компиляцией:

```dart
case 'session/list':
  final params = expected['params'] as Map<String, Object?>? ?? const {};
  step.track(
    app.listSessions(
      cwd: params['cwd'] as String?,
      cursor: params['cursor'] as String?,
    ),
  );
```

Действие обязано идти через `step.track(...)`: драйвер не ждёт его перед кадром, но провалит прогон при ошибке и дождётся в конце. Исход (ответ, ошибка) складывайте в поле `ClientFixtureUser`, как это сделано для `configResults` и `usageLedgerResults`, чтобы тест клиента мог его проверить.

### Новая реализация агента

Чтобы проиграть корпус против нового агента, пишут фабрику `AgentFixtureStarter` и тест-цикл по корпусу. Скелет (в примере агента изображает `FixtureReplayAgent`; код проверен запуском на трёх фикстурах):

```dart
Future<AgentUnderTest> startMyAgent(
  AcpTransport transport,
  AgentFixtureSetup setup,
) async {
  // Соберите агента из setup.profile, setup.config, setup.llm, setup.cwd
  // и запустите его на transport (агентский конец пары в памяти).
  final agent = await FixtureReplayAgent.start(
    setup.fixture,
    transport,
    cwd: setup.cwd,
  );
  return _MyAgentUnderTest(agent);
}

final class _MyAgentUnderTest implements AgentUnderTest {
  _MyAgentUnderTest(this._agent);

  final FixtureReplayAgent _agent;

  @override
  void verify() {
    // После сценария: все шаги модели использованы, поддельные серверы
    // получили ожидаемые вызовы (setup.after.mcpCalls). Бросьте исключение
    // с понятным текстом, если нет.
  }

  @override
  Future<void> stop() => _agent.stop();
}

void main() {
  for (final fixture in loadFixtureCorpus()) {
    test(fixture.id, () async {
      final result = await runAgentFixture(fixture, startMyAgent);
      if (result.skipped) {
        markTestSkipped(result.skipReason!);
      }
    });
  }
}
```

Фабрика отвечает за всё, что драйвер сознательно не знает: сборку агента, сценарную модель из `setup.llm`, поддельные MCP-серверы из `setup.mcp`, журналы сессий из `setup.sessions`, режим и профиль. Пакет агента в зависимости `codelab_acp_testing` не попадает, поэтому такая фабрика всегда живёт в тестах пакета агента, а `codelab_acp_testing` — его `dev_dependency`. Подключение к процессу или WebSocket строится тем же способом через `AgentFixtureConnector` и `runAgentFixtureOver` ([глава 2](02-drivers.md#транспортный-драйвер-и-test-scenario)).

Новая сторона вне клиента и агента (третья роль в `roles`) — изменение формата и обоих драйверов: это отдельный OpenSpec change.

### Новый скриптовый режим stdio-агента

Нужен тесту, которому нужен процесс с известным поведением. Добавьте значение `CodelabCompatibleStdioAgentMode` с документирующим комментарием (почему, для чего, как использовать), ветку в исходник агента (`_codelabCompatibleStdioAgentSource` в `lib/src/codelab_compatible_stdio_agent.dart`) и тест по образцу `test/markdown_reply_agent_test.dart` на `AgentProcess` из `test/support/agent_process.dart`. Исходник — строка; `__CODELAB_TEST_AGENT_MODE__` в ней подставляется именем режима.

## Частые проблемы

### Тесты пакета не загружаются

**Симптом.** `fvm dart test` печатает ошибки компиляции вида `'JsonRpcResponse' isn't a type` в файлах `codelab_client_acp/lib/…`; все тесты падают на загрузке.

**Причина.** Нет сгенерированного кода (`*.freezed.dart`) в зависимостях пакета.

**Что сделать.** Шаг генерации из [запуска из исходников](../../../../docs/user/run-from-source.md#1-подготовка) (команда есть в [главе 0](00-getting-started.md#подготовка-репозитория)).

### `FixtureFormatException` при загрузке

**Симптом.** Прогон не начинается: `FixtureFormatException: <файл>: <путь>: <причина>`; `test-scenario` выходит с кодом 64. Примеры причин: `unknown key; allowed: cwd, files, …`, `expected "acp/<имя>" to match the file`, `expected "c2a" or "a2c", got "a2d"`, `must have exactly one of "frame" or "unordered"`.

**Причина.** Файл нарушает формат: опечатка в ключе, `id` не совпал с именем файла, неверное значение. Нарушение ловится сразу, чтобы фикстура не проверяла меньше, чем задумано.

**Что сделать.** По пути в сообщении найти место в файле и сверить его с [главой 1](01-fixture-format.md) или `_schema.json`. Если нужное поле в формате отсутствует, формат расширяют ([рецепт](#как-изменить-формат-фикстуры)).

### `unknown variable ${имя}` и `unknown matcher "$…"`

**Симптом.** Провал с текстом `unknown variable ${sessionIdd}` на кадре или `the agent did not run the fixture: FixtureMatchException: unknown matcher "$text"`.

**Причина.** Переменная не определена (опечатка или `$capture` стоит в более позднем кадре, чем использование); или матчер не из списка. Частая ошибка — `{"$text": …}` вместо `match: {"$text": …}` у кадра с `repeat`: `$text` не матчер, а ключ поля `match`.

**Что сделать.** Поправить имя. Допустимые переменные — `${cwd}`, `${sessionId}` и захваты; матчеры — таблица в [главе 1](01-fixture-format.md#матчеры).

### `unexpected frames … the agent did more than the fixture records`

**Симптом.** `frame #N (after the scenario): unexpected frames from the agent after the scenario: the agent did more than the fixture records (fs/read_text_file)`; в `actual` лежат кадры, которых нет в фикстуре.

**Причина.** Фикстура закончилась раньше сценария: агент продолжает отправлять кадры или запросы клиенту. Либо агент действительно делает лишнее — регрессия.

**Что сделать.** Сравнить `actual` со спецификацией. Если кадры закономерны, дописать их в фикстуру; если лишние — чинить агента ([рецепт, шаг 3](#3-напишите-начало-и-запустите-против-агента)).

### `ScriptedLlmFailure: step N was not used`

**Симптом.** `the agent check after the scenario failed: ScriptedLlmFailure: - step 2 was not used`.

**Причина.** В `llm.steps` больше шагов, чем запросов к модели сделал агент: сценарий оборвался раньше (фикстура не дала ответа клиента, агент ждёт) или лишний шаг записан зря. Обратная ситуация — лишний запрос к модели — тоже провал.

**Что сделать.** Проверить, что кадры `c2a` доводят сценарий до конца; сверить число шагов `llm` с числом запросов модели.

### Таймаут ожидания кадра

**Симптом.** `timed out after 5000 ms waiting for an a2c frame` (агент) или `waiting for a c2a frame` (клиент); `test-scenario` называет срок из `--timeout` (по умолчанию 30 секунд).

**Причина.** Ожидаемый кадр не пришёл. У агента — не сработал шаг (модель не вызвала инструмент, ждёт ответа клиента). У клиента — пользовательское действие не выполнено: в `ClientFixtureUser.act` нет `case` для метода кадра.

**Что сделать.** В агентском прогоне посмотреть, на каком кадре встал агент; в клиентском — проверить `act`. В скобках отчёта указано, сколько кадров поглотили `optional` и `repeat` до таймаута.

### `add a state check for acp/<имя>`

**Симптом.** Клиентский прогон новой фикстуры проходит кадры, но тест падает с `Expected: not null … add a state check`.

**Причина.** Для каждой фикстуры роли `client` обязана быть запись в `_stateChecks`.

**Что сделать.** Добавить запись ([рецепт, шаг 6](#6-зарегистрируйте-фикстуру)).

### `the corpus holds exactly …` и `a covered element leaves pendingCoverage`

**Симптом.** Падает `fixtures_load_test.dart` (`Expected: Set:[…] … Which: larger than expected`) или тест покрытия.

**Причина.** Новый `id` не внесён в список корпуса; либо фикстура покрыла элемент из `pendingCoverage` и он должен уйти из списка.

**Что сделать.** [Что регистрируется при добавлении фикстуры](03-testing-and-coverage.md#что-регистрируется-при-добавлении-фикстуры).

### FIX-1: `no anchor #… in …`

**Симптом.** `acp/<имя>: spec "09-File System.md#reading-file": no anchor #reading-file in 09-File System.md`.

**Причина.** В `spec` якорь, которого нет среди заголовков файла.

**Что сделать.** Открыть файл в `docs/protocols/acp/protocol/`, найти заголовок раздела и записать его slug.

### Клиент ответил не тем содержимым файла

**Симптом.** Клиентский прогон: `$.result.content: expected "…\n", got "…"` — нет завершающего перевода строки.

**Причина.** При чтении с `line` или `limit` файловая система клиентского драйвера отдаёт выбранные строки через `\n` без завершающего перевода строки (так же ведёт себя адаптер приложения `apps/codelab_desktop/lib/core/platform/text_file_io.dart`). Агентский драйвер ответ клиента берёт из кадра `c2a` фикстуры как есть, поэтому разница заметна только клиентскому прогону.

**Что сделать.** Писать в `c2a`-ответе содержимое так, как его вернёт клиент.

### `SKIP` в `test-scenario` и `no fixtures were played`

**Симптом.** Много строк `SKIP`; в конце `codelab: no fixtures were played`, код выхода 1.

**Причина.** `SKIP` — не провал: фикстуру агент профиля сыграть не может (`setup.config`, `setup.mcp`, `setup.sessions`, роль `client`, `setup.transport`). Код 1 — когда не сыграно ни одной: фильтр `--filter` не совпал ни с чем или всё пропущено.

**Что сделать.** Проверить glob в `--filter` и причину в строке под `SKIP`. Фикстуры с `setup.config` и `setup.sessions` играет `conformance:agent`.

### Кадр потерян в тесте с `FakeAcpTransport`

**Симптом.** Тест клиента подаёт `emitInbound(...)`, а клиент кадр «не видит».

**Причина.** `inbound` — синхронный broadcast-поток: подписчик, который появился после `emitInbound`, кадр не получает. Клиент подписывается при `connect`.

**Что сделать.** Подавать кадры после подключения клиента; подписки тестов на `sent` и `events` делать до действий.

### Расхождение после правки фикстуры «под агента»

**Симптом.** Хочется поправить ожидаемое значение в фикстуре, потому что агент отвечает иначе.

**Причина.** Это обратный порядок: фикстура — прочтение спецификации.

**Что сделать.** Свериться с разделом из `spec`. Кадр фикстуры соответствует спецификации — исправлять код стороны отдельным change. Кадр противоречит спецификации — менять кадр вместе со ссылкой `spec` на раздел, который обосновывает новое значение ([`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md), «Правила изменения фикстур»).

## Нормы и ссылки

- Спецификации: [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md) (формат, нормализация, инварианты, драйверы, повторитель), [`cli-scenario-driver`](../../../../openspec/specs/cli-scenario-driver/spec.md) (`test-scenario`), [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md) (проверки workspace, клиентская conformance, встроенный режим), [`agent-acp-server`](../../../../openspec/specs/agent-acp-server/spec.md), [`acp-client-kit`](../../../../openspec/specs/acp-client-kit/spec.md).
- Архитектура: [формат и алгоритмы фикстур](../../../../docs/architecture/proposals/agent-core/14-golden-fixtures.md) (§14.4 схема, §14.5 нормализация, §14.6 матчеры, §14.9 и §14.10 алгоритмы, §14.11 инварианты), [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md).
- Правила пакета: [`AGENTS.md`](../AGENTS.md) и корневой [`AGENTS.md`](../../../../AGENTS.md) (§3.4 ACP не придумывать, §5 границы, §21 проверки).
- Соседние руководства: [`codelab_acp_protocol`](../../codelab_acp_protocol/doc/README.md), [`codelab_acp_transports`](../../codelab_acp_transports/doc/README.md), [`codelab_architecture_tests`](../../codelab_architecture_tests/doc/README.md), [тестирование ядра агента](../../codelab_agent_core/doc/12-testing.md).
