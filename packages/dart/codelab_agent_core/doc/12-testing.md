# Тестирование агента

Глава о том, как проверяется ядро агента и всё, что стоит на нём: какие бывают уровни тестов, чем пользоваться, чтобы тест был быстрым и детерминированным, и как запустить нужную проверку. Общую стратегию и выбор уровня задаёт [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md), требования к проверкам — спецификация [`testing-quality`](../../../../openspec/specs/testing-quality/spec.md). Здесь они не пересказываются: глава показывает, как это устроено в коде ядра.

Перед главой прочитайте [02-assembly-and-hosts.md](02-assembly-and-hosts.md) (сборка ядра) и [04-turn-loop.md](04-turn-loop.md) (цикл хода): тесты ниже строятся на них.

## Уровни тестов

Принцип стратегии: тест лежит на минимально необходимом уровне. Нижние уровни быстрее и не зависят от сети, процессов и файловой системы. В таблице уровни идут снизу вверх.

| Уровень | Что проверяет | Где лежит | Как запустить |
|---|---|---|---|
| Юнит ядра | цикл хода, инструменты, разрешения, сессии, сжатие, конфигурация — на чистом Dart, с моделью по сценарию и средой в памяти | `packages/dart/codelab_agent_core/test/<область>/` | `fvm dart test` в каталоге пакета |
| Golden-тексты | то, что видит модель: вывод инструментов, системный промпт, матрица возможностей профилей | `test/tools/golden/`, `test/prompts/golden/`, `test/host/profiles/` | те же тесты; обновление — `UPDATE_GOLDEN=1` |
| Сборка ядра | `buildAgentCore`: набор инструментов, сужение возможностей, `HostWiringException` | `test/host/` | `fvm dart test test/host` |
| web-smoke | ядро собирается в JavaScript и WebAssembly и проводит ход без `dart:io` | `test/web_smoke/main.dart`, `test/web_smoke_turn_test.dart` | `melos run web-compile` |
| Проекция ACP | события ядра становятся кадрами `session/update`; запрос разрешения идёт по ACP | `packages/dart/codelab_agent_acp/test/` (`projection/`, обвязка `support/server_harness.dart`) | `fvm dart test` в каталоге пакета |
| Conformance агента | `AcpAgentServer` отвечает кадрами golden-фикстур ACP | `packages/dart/codelab_agent_acp/test/conformance_test.dart` | `melos run conformance:agent` |
| Conformance встроенного агента | те же фикстуры против встроенного агента в процессе CLI | `apps/codelab_cli/lib/src/scenario/` | `melos run conformance:embedded` |
| Транспорты бинаря | фикстуры с `setup.transport` через stdio и WebSocket | `apps/codelab_agent/test/transport_conformance_test.dart` | `fvm dart test` в каталоге приложения |
| e2e CLI | терминальный клиент под псевдотерминалом против `codelab-agent --llm-script` и встроенного агента | `apps/codelab_cli/test/e2e/` | `melos run test:e2e:cli:dart-agent`, `melos run test:e2e:cli:embedded` |

Граница ядра охраняется не тестами пакета, а сторожем: импорты `dart:io`, `package:flutter` и другие запрещённые зависимости ловит `melos run guard` (правила — `packages/dart/codelab_architecture_tests/test/support/rules.dart`). Что делать, если он упал, — в [главе 13](13-troubleshooting.md#сторож-melos-run-guard-упал-на-импорте).

Фикстуры корпуса играют сразу три проверки: клиентская (`conformance:client`, проверяет клиента, а не агента), агентская и встроенная. Устройство корпуса и таблица «кто проигрывает» — в [README `codelab_acp_testing`](../../codelab_acp_testing/README.md#кто-проигрывает-корпус).

## Что даёт `package:codelab_agent_core/testing.dart`

Тестовый барель ядра не входит в основной: хосту он нужен только для тестов и сценариев (`lib/testing.dart`). Он отдаёт четыре детерминированных замены для портов, которые ядро получает от хоста (PKG-6, [02-assembly-and-hosts.md](02-assembly-and-hosts.md)).

| Класс | Что заменяет | Как пользоваться |
|---|---|---|
| `FakeClock` | `Clock` | Время стоит, пока тест не вызовет `await clock.elapse(Duration(...))`. Таймеры срабатывают по порядку срока. `pendingTimers` показывает, сколько таймеров не сработало |
| `RecordingLogger` | `Logger` | Копит записи в памяти. `records` — все записи, `eventsOf('host.plan')` — записи с одним именем события. У записи есть `level`, `event`, `fields` |
| `ScriptedStreamFunction` | модель (`StreamFunction`) | Сценарная модель: n-й запрос получает n-й шаг. `fromJson` принимает тот же объект `llm`, что и golden-фикстура ACP; `call` подставляется как функция модели; `verify()` бросает `ScriptedLlmFailure`, если шаг не использован, запрос лишний или `expect` не совпал; `requests` — полученные запросы |
| `SequentialIdGenerator` | `IdGenerator` | `nextId()` даёт `id-1`, `id-2`, …; префикс задаёт `prefix`. `nextChars(count, alphabet)` ведёт отдельный счётчик: номер вызова записывается в системе счисления алфавита и дополняется слева его первым символом (`00000001` для восьми символов). Оттуда берутся id сессии (16 символов), id записей журнала (8) и id субагентов (`sub_…`). Журнал и события получаются побайтово одинаковыми между прогонами |

Остальное в тестах берётся из основного барела: `MemoryExecutionEnv` — файловая система в памяти с рабочей папкой `cwd` (без shell), `MemorySessionStore` — журнал сессий в памяти.

Формат шага сценария — `reply` (блоки `text`, `thinking`, `toolCall`), `stopReason`, `error`, `usage`, `delayMs`, `waitForCancel` и проверка запроса `expect` — описан в [`14-golden-fixtures.md`](../../../../docs/architecture/proposals/agent-core/14-golden-fixtures.md#147-scripted-модель-в-фикстуре). Сценарная модель не бросает исключений: расхождение она отдаёт ответом `ErrorEvent(badRequest)` с текстом `scripted model: …`, а `verify()` собирает все расхождения в одно исключение.

## Харнессы в `test/`

Харнесс — вспомогательный класс теста, который собирает типичное окружение за один вызов. Харнессы лежат в `test/` пакета и снаружи не доступны; новый тест импортирует их относительным путём.

| Харнесс | Что собирает | Файл |
|---|---|---|
| `LoopHarness` | сценарная модель, инструменты над `BoundedEnv` с памятью, `AgentLoopConfig`; помощники `script`, `textStep`, `callStep`, `user` | `test/loop/loop_harness.dart` |
| `ExecutorHarness` | `ToolCallExecutor` над `BoundedEnv`, запись событий, `run(имя, аргументы)` | `test/tools/executor_harness.dart` |
| `CoreHarness` | `buildAgentCore` с профилем, сценарной моделью и журналом в памяти | `test/host/core_harness.dart` |
| `PolicyHarness` | `PermissionPolicy` поверх `ExecutorHarness` | `test/permissions/policy_harness.dart` |
| `FakeGate` | `PermissionGate`, который записывает запросы и отвечает заданным решением | `test/permissions/fake_gate.dart` |
| `FakeMcpConnector` | коннектор MCP без процессов и сети | `test/mcp/fake_mcp_connector.dart` |
| `ProviderHarness` | адаптеры провайдеров против поддельного HTTP | `test/support/provider_harness.dart` |

Перед своим харнессом поищите готовый: правило «сначала существующие паттерны» (`AGENTS.md` §14) действует и для тестов.

## Пример: ход со сценарной моделью, которая вызывает инструмент

Тест кладёт файл в память, просит сценарную модель вызвать `read`, дожидается ответа и проверяет три вещи: все шаги сценария использованы, инструмент вернул нумерованный текст, ход завершился `completed`.

Файл можно положить в любой подкаталог `test/` пакета (путь `../loop/…` в импорте рассчитан на соседний каталог).

```dart
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart';

void main() {
  test('ход: модель вызывает read и отвечает', () async {
    final h = await LoopHarness.create(
      tools: [ReadTool()],
      llm: script([
        callStep([
          ('c1', 'read', {'path': 'notes.txt'}),
        ]),
        {
          ...textStep('Файл прочитан.'),
          'expect': {
            'toolResult': {'toolCallId': 'c1', 'isError': false},
          },
        },
      ]),
    );
    await h.env.writeText('/proj/notes.txt', 'привет\n');
    final agent = Agent(
      config: h.config(),
      systemPrompt: 'You are CodeLab.',
      tools: h.tools,
    );
    final events = <AgentEvent>[];
    agent.subscribe(events.add);

    await agent.prompt([user('прочитай notes.txt')]);

    h.scripted!.verify();
    final result = agent.messages.whereType<ToolResultMessage>().single;
    expect((result.content.single as TextContent).text, '1| привет');
    expect((events.last as TurnEnded).reason, TurnEndReason.completed);
  });
}
```

Что здесь важно.

- Первый шаг сценария отвечает вызовом инструмента (`callStep`), второй — текстом (`textStep`). Второй шаг с `expect.toolResult` проверяет, что результат `read` дошёл до модели и не был ошибкой.
- Рабочая папка харнесса — `/proj`. Относительный путь `notes.txt` инструмент разрешает в `/proj/notes.txt`.
- Без `h.scripted!.verify()` тест не заметил бы пропущенный шаг или лишний запрос к модели.
- Тот же ход с `read` и `edit` и проверкой изменённого файла — `test/loop/read_edit_turn_test.dart`.

## Пример: инструмент через харнесс

Тест инструмента не нужен ни цикл, ни модель. `ExecutorHarness` исполняет вызов так же, как цикл: через проверку аргументов и `BoundedEnv`.

```dart
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';

void main() {
  test('read через харнесс', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/a.txt', 'one\ntwo\n');
    final h = await ExecutorHarness.create([ReadTool()], memory: memory);

    final ok = await h.run('read', {'path': 'a.txt'});
    expect(ok.outcome, ToolOutcome.completed);
    expect(textOf(ok), '1| one\n2| two');

    final bad = await h.run('read', {'path': '../outside.txt'}, id: 'call_2');
    expect(bad.outcome, ToolOutcome.failed);
    expect(textOf(bad), 'Path is outside the workspace: ../outside.txt');
  });
}
```

Второй вызов проверяет границу: путь за пределами рабочей папки отклоняется сообщением `Path is outside the workspace: …`, а не исключением (то же сообщение стоит в golden-файле `test/tools/golden/write.txt`).

## Golden-тесты и `UPDATE_GOLDEN`

Golden-тест сравнивает текст, который видит модель, с файлом в репозитории. Любая правка такого текста становится правкой golden-файла в diff, и ревьюер замечает её.

| Golden | Тест | Файлы |
|---|---|---|
| вывод встроенных инструментов | `test/tools/builtin_tools_golden_test.dart` | `test/tools/golden/*.txt` |
| системный промпт на профиль и режим | `test/prompts/compose_test.dart` | `test/prompts/golden/*.txt` |
| матрица возможностей профиля | `test/host/host_profile_test.dart` | `test/host/profiles/*.golden.json` |
| промпт субагента | `test/prompts/subagent_prompt_test.dart`, `test/prompts/subagent_prompt_skills_test.dart` | `test/prompts/golden/subagent-*.txt` |
| раздел каталога навыков в промпте | `test/skills/catalog_section_golden_test.dart` | `test/prompts/golden/agent-serve-standard-skills.txt` |

Если тест красный, сначала решите, что неверно: код или файл. Если текст изменён намеренно, перегенерируйте файлы и посмотрите diff в `git`:

```bash
UPDATE_GOLDEN=1 fvm dart test test/tools/builtin_tools_golden_test.dart
```

Команду запускайте в каталоге пакета. Переменная `UPDATE_GOLDEN=1` переписывает файлы вместо сравнения, поэтому сама по себе зелёный тест она не гарантирует: после обновления запустите тест ещё раз без неё. Если файла нет, тест падает с текстом `нет golden-файла; запустите с UPDATE_GOLDEN=1`.

## Golden-фикстуры ACP

Фикстура — JSON-файл со сценарием: исходные файлы, скрипт модели и список кадров обмена между клиентом и агентом. Одна и та же фикстура проверяет обе стороны протокола. Формат принят в [`14-golden-fixtures.md`](../../../../docs/architecture/proposals/agent-core/14-golden-fixtures.md), поля описывает схема [`fixtures/acp/_schema.json`](../../codelab_acp_testing/fixtures/acp/_schema.json), как добавить фикстуру — [README `codelab_acp_testing`](../../codelab_acp_testing/README.md#как-добавить-фикстуру). Корпус лежит в [`fixtures/acp/`](../../codelab_acp_testing/fixtures/acp).

Пример — `fixtures/acp/tool-read-range.json`: файл из 100 строк, модель вызывает `read` с `offset: 10` и `limit: 5`, агент читает диапазон через клиента (`fs/read_text_file`). Фикстура показана в компактной записи; поле `description`, содержимое `setup.files` и часть кадров опущены (`…`).

```json
{
  "id": "acp/tool-read-range",
  "spec": [
    "09-File System.md#reading-files",
    "09-File System.md#checking-support",
    "08-Tool Calls.md#following-the-agent"
  ],
  "goals": ["T-01"],
  "setup": {
    "cwd": "/work/demo",
    "profile": "agent-serve",
    "mode": "standard",
    "files": { "a.txt": "line 1\nline 2\n…\nline 100\n" }
  },
  "llm": {
    "model": { "provider": "scripted", "modelId": "scripted-1", "contextWindow": 32768 },
    "steps": [
      {
        "expect": { "lastMessage": { "role": "user", "$textContains": "a.txt" } },
        "reply": [
          { "toolCall": { "id": "call_1", "name": "read",
                          "arguments": { "path": "a.txt", "offset": 10, "limit": 5 } } }
        ],
        "stopReason": "toolUse"
      },
      {
        "expect": { "toolResult": { "toolCallId": "call_1", "isError": false } },
        "reply": [ { "text": "Прочитал строки 10–14." } ],
        "stopReason": "stop"
      }
    ]
  },
  "frames": [
    { "dir": "c2a", "frame": { "jsonrpc": "2.0", "id": { "$capture": "promptId" },
        "method": "session/prompt",
        "params": { "sessionId": "${sessionId}",
                    "prompt": [ { "type": "text", "text": "Покажи строки 10–14 файла a.txt" } ] } } },
    …
    { "dir": "a2c", "frame": { "jsonrpc": "2.0", "id": "${promptId}",
        "result": { "stopReason": "end_turn" } } }
  ]
}
```

Как читать фикстуру.

- `setup` задаёт рабочую папку, профиль хоста, режим и файлы. Профиль `agent-serve` — тот же, что у `codelab-agent serve`.
- Блок `llm` — это сценарная модель из `testing.dart`: n-й запрос получает n-й шаг. Здесь два шага — вызов инструмента и итоговый текст.
- `frames` — кадры по порядку. `dir: c2a` — клиент пишет агенту, `a2c` — агент клиенту. Сравнение точное: лишний ключ в кадре считается расхождением. Отступления задают матчеры (`$any`, `$capture`, `$contains`, `$oneOf`, `$text` и другие) и переменные `${cwd}`, `${sessionId}`. Список — в разделе 14.6 документа формата.
- `$capture` запоминает значение (`promptId`), а `"${promptId}"` подставляет его в ответ: так последний кадр привязан к тому же запросу.

Запуск одной фикстуры:

```bash
fvm dart test packages/dart/codelab_agent_acp/test/conformance_test.dart -n "acp/tool-read-range"
```

Для встроенного агента — командой CLI (из каталога `apps/codelab_cli`):

```bash
fvm dart run bin/codelab.dart test-scenario ../../packages/dart/codelab_acp_testing/fixtures/acp/tool-read-range.json --agent embedded
```

Результат прогона на текущем коде:

```text
PASS acp/tool-read-range (0.4s)
1 passed, 0 failed, 0 skipped
```

Команда `test-scenario` описана в [руководстве по эксплуатации CLI](../../../../apps/codelab_cli/doc/operations.md#проверка-агента-фикстурами-test-scenario). Расхождение исправляется в коде агента; фикстура меняется только со ссылкой на спецификацию ACP (требование «Правила изменения фикстур» в спецификации `acp-golden-fixtures`).

## Какие проверки запускать

Какие скрипты Melos относятся к какому изменению, задано в [`AGENTS.md`](../../../../AGENTS.md) корня: раздел 21, подраздел «Проверка перед pull request», пункт 4. Для ядра чаще всего нужны `guard` (импорты и `pubspec.yaml`), `prompts:check` (промпты), `web-compile` (web-безопасный код), `conformance:agent` и `conformance:embedded` (проекция событий, ACP-слой и встроенный агент). Не копируйте список в свои заметки: правило меняется, и верна только его исходная формулировка.

Полный `melos run check` запускается по просьбе пользователя и в ветке `release/*`; перед обычным pull request проверяется только затронутое.

## Правила TDD пакетов

Каждый пакет агентской стороны ведёт задачи по TDD: сначала красный тест из критерия приёмки, затем минимальный код. Правила и исключения (рефакторинг, интеграционные тесты, UI, реальные провайдеры) записаны во вложенных `AGENTS.md`:

- ядро — [`AGENTS.md`](../AGENTS.md), раздел 2;
- остальные пакеты и приложения — `AGENTS.md` в их каталогах, например [`codelab_agent_acp`](../../codelab_agent_acp/AGENTS.md) и [`apps/codelab_agent`](../../../../apps/codelab_agent/AGENTS.md).

Перед PR красный тест коммитится отдельно до кода, но сам коммит делается только по явной просьбе (`AGENTS.md` корня, §19).

## Смотрите также

- [13. Частые проблемы](13-troubleshooting.md) — что делать, когда тест или проверка красные.
- [11. Расширение](11-extending.md) — какие тесты приложить к новому инструменту, провайдеру или ключу конфигурации.
- [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md) — стратегия, уровни, CI.
