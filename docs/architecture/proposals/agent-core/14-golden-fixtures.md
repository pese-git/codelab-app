# 14. Формат golden ACP-фикстур

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Accepted. Общие соглашения, термины и порядок чтения — в оглавлении.

← [13. ACP-адаптер](13-acp-adapter.md) · [Оглавление ядра](../agent-core-architecture.md) · [15. Конфигурация](15-configuration.md) →

## 14.1. Назначение

Эталон поведения агента и клиентов — спецификация ACP. Корпус golden-фикстур закрепляет её
прочтение в исполняемом виде: одна фикстура — один сценарий, упорядоченные кадры с
направлением, ссылка на раздел спецификации. Один корпус проверяет и Dart-агента (драйвер
играет роль клиента), и клиентов (драйвер играет роль агента); поле `roles` (§14.4) говорит, какие
стороны проверяет фикстура. Каждая цель Must из матрицы
паритета ссылается на id фикстуры.

## 14.2. Раскладка и именование

```text
packages/dart/acp_testing/
  fixtures/acp/                     все фикстуры — плоско, без подкаталогов групп; справа — этап появления
    initialize-capabilities.json    этап 0
    session-new-modes-config.json   этап 0
    session-load-replay.json        этап 4
    session-list-cwd-filter.json    этап 4
    prompt-text-end-turn.json       этап 0
    prompt-tool-permission-allow.json  этап 0
    prompt-tool-permission-reject-continues.json  этап 0
    prompt-cancel-mid-tool.json     этап 0
    prompt-max-turn-requests.json   этап 4
    prompt-failed-provider-auth.json  этап 4
    prompt-update-plan.json         этап 0
    tool-status-lifecycle.json      этап 0
    tool-read-range.json            этап 0
    tool-exec-terminal-embed.json   этап 0
    set-config-option-model.json    этап 0
    errors-unknown-session-update-tolerated.json  этап 0
    errors-bad-frame-survives.json  этап 4
    _schema.json                    JSON Schema самого формата фикстуры
  lib/src/fixtures/
    fixture.dart                    модель и загрузчик
    matcher.dart                    сравнение с нормализацией
    agent_conformance.dart          драйвер для агента
    client_conformance.dart         драйвер для клиента

packages/dart/codelab_agent_core/
  lib/testing.dart                  библиотека для тестов: ScriptedStreamFunction, FakeClock, …
  lib/src/testing/
    scripted_stream_function.dart   scripted StreamFunction из блока llm (§14.7)
```

`ScriptedStreamFunction` живёт в ядре (`lib/src/testing/`, экспорт только через
`package:codelab_agent_core/testing.dart`, основной барель его не экспортирует): она нужна с
этапа 1 тестам адаптеров и декораторов LLM, а проигрыватель фикстур `acp_testing` берёт её
оттуда.

* id фикстуры = `acp/` + имя файла без `.json`: `acp/prompt-tool-permission-allow` —
  `fixtures/acp/prompt-tool-permission-allow.json`. Подкаталогов групп нет, включая фикстуры
  расширений ACP.
* Имя — `<область>-<сценарий>[-<исход>]` в kebab-case; область — метод или группа. MVP:
  `initialize`, `session-new`, `session-load`, `session-list`, `prompt`, `set-config-option`,
  `set-mode`, `permission`, `tool` (конкретный инструмент: `acp/tool-read-range`, этап 0),
  `config` (опции конфигурации сессии: `acp/config-effort-option`), `slash` (встроенные
  команды: `acp/slash-help`), `available-commands`, `usage`, `mcp` (`acp/mcp-tool-permission`),
  `compaction`, `errors` (устойчивость к ошибкам протокола: `acp/errors-bad-frame-survives`),
  `stdio`, `ws`, `multi` (несколько сессий одного соединения), `agent-serve` (поведение,
  зависящее от профиля `agent-serve`). После MVP добавляются области `skill`, `steer`, `jobs`,
  `authenticate`, `plugin`, а `tool` — для новых инструментов: `acp/tool-web-fetch-permission`
  и `acp/tool-web-fetch-permission-reject` (§17.1.10), `acp/skill-command-listed`, `acp/skill-invoke` (§17.2.12); субагенты — `acp/prompt-subagent-tool-call`, `acp/prompt-subagent-permission`, `acp/prompt-subagent-background`, `acp/session-load-subagent-interrupted`, `acp/slash-tasks` (§17.3, §17.9.16), `acp/prompt-subagent-follow-up` (§17.3.8.1); `acp/slash-mcp-list` (§17.5); `acp/prompt-image-block` (U-14); `acp/session-seal-on-close` (§8). После MVP также: управление сессиями — `acp/session-rename`,
  `acp/session-fork`, `acp/session-rewind`, `acp/session-leaf-branch-changed`,
  `acp/session-commands-no-extension`, `acp/session-load-locked` (§17.6.16), с `"extensions"` — `acp/session-search` (§17.6.17); steering —
  `acp/prompt-steer-during-tool`, `acp/steer-no-active-turn`, `acp/steer-returned-on-cancel`,
  `acp/initialize-steering-capability` (§17.7.11); LSP — `acp/tool-lsp-rename-permission` и
  `acp/tool-lsp-rename-permission-reject` (§17.8.14, сценарий fake-сервера — блок `setup.lsp`);
  фоновые команды — `acp/tool-exec-background-terminal`, `acp/tool-exec-background-local`,
  `acp/session-load-background-job`, `acp/jobs-board` (§17.9.16). Режим `accept-edits` —
  `acp/set-mode-accept-edits` (P-06, область `set-mode`, §7.11).
* Корпус MVP по этапам (этап — когда фикстура входит в корпус; агентский прогон фикстур с ролью `agent` — с этапа 4, §14.9; клиентский прогон фикстур с ролью `client` — с этапа 0, §14.10). Итого к этапу 4 — 49 фикстур (12 + 37), к этапу 8 — 63 (+ 14):
  * этап 0 — ровно 12 фикстур с клиентским прогоном (dart-agent-and-clients §9.5): `acp/initialize-capabilities`, `acp/session-new-modes-config`, `acp/prompt-text-end-turn`, `acp/prompt-cancel-mid-tool`, `acp/prompt-tool-permission-allow`, `acp/prompt-tool-permission-reject-continues`, `acp/tool-status-lifecycle`, `acp/tool-read-range`, `acp/tool-exec-terminal-embed`, `acp/prompt-update-plan`, `acp/set-config-option-model`, `acp/errors-unknown-session-update-tolerated`;
  * этап 4 — ровно 35 фикстур, возможности этапов 1–4, проверяемые через ACP-адаптер (dart-agent-and-clients §9.9, задача 4.8; 33 — в change `add-dart-agent-acp-server`, транспортные `acp/ws-auth-bearer-required` и `acp/stdio-framing-large-line` — в `add-codelab-agent-binary`): `acp/session-load-replay`, `acp/session-list-cwd-filter`, `acp/prompt-max-turn-requests`, `acp/prompt-failed-provider-auth`, `acp/errors-bad-frame-survives`, `acp/config-effort-option` (опция `effort` — часть `configOptions` этапа 4, §13.6), `acp/prompt-streaming-text`, `acp/prompt-thought-chunk`, `acp/prompt-anthropic-tool-call`, `acp/prompt-network-drop`, `acp/prompt-provider-error`, `acp/prompt-cancel-mid-stream`, `acp/prompt-parallel-tool-calls`, `acp/prompt-turn-budget-exceeded`, `acp/prompt-cancel-during-terminal`, `acp/tool-write-permission-diff`, `acp/tool-edit-exact-replace`, `acp/tool-edit-ambiguous-match-error`, `acp/tool-list-dir`, `acp/tool-search-content`, `acp/tool-invalid-args-error`, `acp/tool-exec-terminal-env-array`, `acp/permission-allow-always-scoped`, `acp/permission-critical-pattern-in-bypass`, `acp/permission-options-all-four`, `acp/permission-outcome-cancelled`, `acp/set-mode-bypass-no-prompt`, `acp/set-mode-plan-rejects-edit`, `acp/set-mode-updates-current-mode`, `acp/session-info-title`, `acp/session-load-interrupted-turn`, `acp/compaction-long-session-continues`, `acp/multi-session-concurrent-prompts`, `acp/ws-auth-bearer-required`, `acp/stdio-framing-large-line`. Фикстуры выноса результата `acp/tool-exec-spill` и `acp/agent-serve-spill-local-read` перенесены в change `add-agent-core-output-spill` (веха 1.0, после P-10). Фикстуры, которые клиентский драйвер не играет (загрузка и список сессий, `session/set_mode`, плохие кадры, параллельные сессии, опция `effort`), имеют роль `agent`; их клиентская сторона — в списке ожидаемого покрытия FIX-2. Встроенных slash-команд на этапе 4 нет (они — этап 8): `available_commands_update` после `session/new` уходит с `availableCommands: []`, и фикстуры этапов 0 и 4 сверяют этот список матчером `{"$any": []}`; состав списка проверяют фикстуры этапа 8. Фикстуры этапа 4, которые ожидают `_meta.codelab.outcome` (например, `acp/permission-outcome-cancelled`, `acp/session-load-interrupted-turn`), объявляют `"extensions": ["outcome"]` (FIX-4); так же `acp/prompt-max-turn-requests` — `"extensions": ["budgetExceeded"]`, `acp/prompt-failed-provider-auth` — `"extensions": ["errorData"]` (`data.codelab`, §13.8). Базовые фикстуры этапа 0 (`acp/prompt-cancel-mid-tool`, `acp/prompt-tool-permission-reject-continues`) `_meta.codelab` в ожидаемых кадрах не пишут: `_meta` сравнивается через `$partial` (§14.6), поэтому агент, который его добавляет, их проходит;
  * этап 8 — ровно 14 фикстур, MCP, конфигурация, команды: `acp/slash-help`, `acp/slash-mode-plan` (встроенные slash-команды — этап 8), `acp/session-new-with-mcp`, `acp/mcp-stdio-tool-call`, `acp/mcp-http-tool-call`, `acp/mcp-tool-permission`, `acp/mcp-result-fenced`, `acp/mcp-prompt-command`, `acp/set-mode-plan-rejects-mcp-write`, `acp/available-commands-no-tools`, `acp/config-model-options-from-endpoint`, `acp/set-config-option-agent`, `acp/slash-compact`, `acp/prompt-template-command`.
* После 9 — `acp/prompt-usage-meta` (`"extensions": ["usage"]`, OpenSpec `add-usage-extension`, §13.12, §16.3), `acp/usage-and-redact-commands` (команды `/usage` и `/redact` — после MVP, §13.4); из §17.10–§17.14 — ещё:
  * провайдеры (§17.10): `acp/authenticate-oauth`, `acp/slash-model-role`; сценарий CLI `cli/login-openrouter-pkce`;
    SSE-фикстуры адаптеров (не ACP, в тестах `codelab_agent_core`) — `gemini/stream-text-thought.sse`,
    `gemini/stream-function-call.sse`, `gemini/error-schema-400.json`, `kimi/think-tags.sse`,
    `minimax/overflow-500.json`, `zai/overflow-silent.sse`, `zai/image-reject-400.json`,
    `openai/prompt-tools.sse`, `openai/rate-limit-429-rpd.json` (заголовки + тело),
    `openai/insufficient-quota-429.json`, `anthropic/rate-limit-429-tokens.json`,
    `gemini/resource-exhausted-retryinfo.json`, `openai/stall-first-byte.sse` (заголовки без
    событий); core-сценарии `core/rate-limit-decoded-once`, `core/rate-limit-raw-body-not-in-journal`,
    `core/stall-escalates-key-then-fallback` (§17.10.4.1, §17.10.10.1);
  * дополнительные инструменты (§17.11): `acp/tool-read-image-block`, `acp/tool-edit-anchors-stale`,
    `acp/tool-ask-options` (`"extensions": ["ask"]`); core-сценарии
    `core/read-image-block`, `core/hashline-stale-anchor-rejected`, `core/memory-add-search`,
    `core/inspect-image-text-only`, `core/rewind-replaces-tail-with-report`,
    `core/session-search-pointers`, `core/discover-tools-mount`; изображения (§17.11.2.1,
    §17.11.2.2) — `images/screen-5120x2880.png`, `images/photo-exif6.jpg`, `images/alpha-1200.png`,
    `images/png-text-gps.png` (генерируются скриптом фикстур, без сторонних фото и без реальных
    EXIF-координат) и core-сценарии `core/image-downscaled-to-limit`,
    `core/image-exif-orientation-applied`, `core/image-dedup-reference-stable`;
  * цикл и безопасность (§17.12): `acp/set-mode-architect-prompt`, `acp/tool-heartbeat-title`,
    `acp/permission-redact-block-read`; с `"extensions"` — `acp/prompt-response-held`,
    `acp/prompt-session-deadline`;
  * масштаб сессий (§17.13.2): `acp/session-load-replay-window`;
  * плагины (§17.14.3.6): `acp/plugin-command-listed`.
* Фикстуры, которые требуют расширения ACP, лежат в том же `fixtures/acp/` и помечены
  `"extensions": [...]`; клиенты без поддержки расширения их пропускают.

## 14.3. Решение о формате: JSON

Формат — JSON, один объект на файл.

| Критерий | JSON | YAML |
|---|---|---|
| Кадры совпадают с проводом | да: кадр копируется из protocol trace (§12.5) без преобразования | нужна конвертация, кавычки и типы (`"1"` vs `1`, `on` vs `true`) легко исказить |
| Зависимости | `dart:convert` | `package:yaml` в `acp_testing` и в каждом клиенте |
| Многострочный текст | `\n` в строках — терпимо, фикстуры короткие | удобнее |
| Проверка схемы | `_schema.json` + тот же валидатор | так же |

Решающее — первое: фикстура — это контракт провода, и его запись не должна проходить через
второй формат с собственными правилами типов. Комментарии заменяет поле `note` в кадре.

## 14.4. Схема фикстуры

| Поле | Тип | Обязательно | Смысл |
|---|---|---|---|
| `id` | string | да | совпадает с путём (`acp/<имя>`); загрузчик сверяет |
| `spec` | string[] | да, непустой | ссылки на разделы спецификации: `"05-Prompt Turn.md#5-tool-invocation-and-status-reporting"` (путь относительно `docs/acp/protocol/`) |
| `description` | string | да | что проверяется, одним абзацем |
| `goals` | string[] | нет | id целей паритета (`P-02`, `C-01`) |
| `extensions` | string[] | нет | используемые расширения (§13.12): имя — ключ после `codelab.` (`outcome`, `budgetExceeded`, `usage`, …), для `data.codelab` — `errorData` |
| `roles` | string[] | нет, по умолчанию `["agent", "client"]` | какие проверки берут фикстуру: `agent` — conformance агента (§14.9), `client` — проверка клиента (§14.10). Только `client` — сценарии, которые агент не порождает (`acp/errors-unknown-session-update-tolerated`); только `agent` — сценарии, которые клиент не принимает от агента (`acp/errors-bad-frame-survives`: мусор шлёт клиент) |
| `setup` | object | да | начальные условия (ниже) |
| `llm` | object | нет | scripted-модель для conformance агента (§14.7); клиентская проверка его игнорирует |
| `frames` | array | да | упорядоченные кадры (ниже) |
| `normalize` | object | нет | дополнительные правила нормализации сверх стандартных (§14.5) |
| `after` | object | нет | состояние после сценария: `files` — ожидаемое содержимое файлов рабочей папки; агентская проверка сверяет его с последним `content` кадра `fs/write_text_file` на этот путь, клиентская — с файловой системой клиента |

`setup`:

| Поле | Смысл |
|---|---|
| `cwd` | рабочая папка сценария; в кадрах пишется как `${cwd}` |
| `files` | `{ "относительный путь": "содержимое" }` — файлы рабочей папки до начала. Клиентская проверка кладёт их в файловую систему клиента. Агентская проверка создаёт их во временном каталоге `cwd` (нужен локальному листингу `ls`/`search`, §10.4), но содержимое агент получает только кадрами `fs/read_text_file`, ответы на которые записаны в фикстуре; загрузчик проверяет, что такой ответ совпадает с `files` (с учётом `line`/`limit`) |
| `profile` | профиль агента (`agent-serve` по умолчанию) |
| `mode` | режим сессии на старте (`standard` по умолчанию) |
| `config` | фрагмент конфига (§15) в виде JSON-объекта с той же структурой, что дерево YAML после разбора |
| `clientCapabilities` | что объявит клиент в `initialize` (по умолчанию `fs` чтение и запись, `terminal: true`) |
| `terminal` | только для клиентской проверки: сценарий процессов fake-порта клиента — `{ "<команда>": {"output": "…", "exitCode": 0} }`, ключ — `command` и `args` через пробел (`"/bin/sh -c dart test"`) или только `command`; без `exitCode` процесс не завершается сам и работает до `terminal/kill` или `terminal/release` (сценарии отмены); агентская проверка его не читает, вывод команды приходит ей кадрами `terminal/output` (§14.10) |
| `web` | после MVP: fake-ответы HTTP для web-инструментов — `{ "<URL>": {"status": 200, "headers": {...}, "body": "..."} }`; драйвер conformance агента подставляет `MockClient`, запрос к URL вне карты — ошибка сети; реальная сеть не используется (§17.1.10, WEB-11) |
| `skipInitialize` | `true` — фикстура сама содержит кадры `initialize`; иначе драйвер выполняет стандартный handshake и `session/new` до `frames` и подставляет `${sessionId}` |
| `sessions` | только для агентской проверки: журналы сессий до сценария — `{ "<sessionId>": [<заголовок session>, <записи>…] }` в формате журнала (§8.2), `${cwd}` подставляется; так задаётся состояние, которого не получить кадрами (прерванный ход, §8.8). Клиентская проверка поле не читает |

Кадр `frames[i]`:

| Поле | Смысл |
|---|---|
| `dir` | `"c2a"` (клиент → агент) или `"a2c"` (агент → клиент) |
| `frame` | JSON-RPC-объект кадра; может содержать матчеры (§14.6) и переменные `${…}` |
| `note` | пояснение для человека |
| `unordered` | вместо `frame`: массив кадров одного направления, которые могут прийти в любом порядке (параллельные вызовы) |
| `optional` | `true` — кадр может отсутствовать (например, `agent_thought_chunk` у модели без рассуждений) |
| `repeat` | `"+"` — кадр повторяется один или более раз подряд (дельты текста); проверяется склейка `text` (§14.6) |
| `match` | проверка склейки для `repeat`: `{"$text": "…"}` — конкатенация `content.text` всех повторов |

`_schema.json` описывает эти поля (JSON Schema draft 2020-12, `additionalProperties: false` на
верхнем уровне, в `setup` и в кадре). Поле `roles`:

```json
"roles": {"type": "array", "items": {"enum": ["agent", "client"]}, "minItems": 1, "uniqueItems": true, "default": ["agent", "client"]}
```

Фикстура, в которой есть кадры `fs/*` или `terminal/*`, — обычная фикстура обеих ролей: агент
обязан отправить эти запросы, клиент — ответить на них (§14.9, §14.10).

## 14.5. Нормализация

Перед сравнением ожидаемый и фактический кадры проходят одинаковую нормализацию:

1. **Переменные.** `${cwd}` → абсолютный `cwd` прогона; `${sessionId}` → id сессии из ответа
   `session/new`; `${name}` → значение, захваченное матчером `$capture` (ниже).
2. **JSON-RPC id.** Числовые id запросов клиента берутся из фикстуры как есть. id запросов
   агента (`perm-1`, `term-2`) не сравниваются буквально: в ожидаемом кадре пишется
   `{"$capture": "permId"}`, а ответ клиента в фикстуре использует `"${permId}"`.
3. **Время.** Значения полей `updatedAt`, `timestamp`, `created` и любой строки формата
   ISO-8601 заменяются на `"<ts>"`, если в ожидаемом кадре на этом месте стоит `"<ts>"`.
4. **Пути.** Префикс фактического `cwd` в строках заменяется на `${cwd}`; разделители
   приводятся к `/`.
5. **`sessionId` и `toolCallId`.** `toolCallId` из scripted-модели детерминирован (`call_1`),
   поэтому сравнивается буквально.
6. **Порядок ключей** объекта не важен; порядок массивов важен, кроме `unordered`.
7. `normalize` фикстуры может добавить замены: `{"replace": [{"path": "$.params.update.content.text", "regex": "\\d+ мс", "with": "<N> мс"}]}`.

## 14.6. Матчеры

По умолчанию сравнение **точное**: лишний ключ в фактическом кадре — расхождение (так ловятся
поля вне спецификации). Отступления задаются объектами-матчерами на месте значения:

| Матчер | Значение |
|---|---|
| `{"$any": true}` | любое значение, ключ должен быть; `{"$any": <пример>}` — то же, а клиентский драйвер (§14.10) отправляет клиенту `<пример>` вместо строки-заглушки (нужно там, где клиент декодирует значение: список, объект) |
| `{"$absent": true}` | ключа быть не должно |
| `{"$capture": "имя"}` | любое значение; сохранить в переменную `${имя}` |
| `{"$regex": "…"}` | строка, соответствующая выражению |
| `{"$contains": "…"}` | строка, содержащая подстроку |
| `{"$partial": { … }}` | объект, содержащий как минимум перечисленные ключи; лишние ключи допускаются |
| `{"$oneOf": [ … ]}` | одно из перечисленных значений |
| `{"$text": "…"}` | для кадров с `repeat: "+"`: склейка `content.text` всех повторов равна строке |

`_meta` всегда сравнивается через `$partial`: спецификация разрешает реализациям добавлять туда
свои ключи.

## 14.7. Scripted-модель в фикстуре

Блок `llm` описывает ответы модели по шагам. Драйвер агента строит из него `StreamFunction`,
которая отдаёт события по грамматике §2.3.

```json
"llm": {
  "model": {"provider": "scripted", "modelId": "scripted-1", "contextWindow": 32768},
  "steps": [
    {
      "expect": {"lastMessage": {"role": "user", "$textContains": "README"}},
      "reply": [
        {"text": "Сделаю замену."},
        {"toolCall": {"id": "call_1", "name": "edit", "arguments": {"path": "README.md", "oldText": "foo", "newText": "bar"}}}
      ],
      "stopReason": "toolUse",
      "usage": {"input": 900, "output": 40}
    }
  ]
}
```

| Поле шага | Смысл |
|---|---|
| `expect` | проверка запроса к модели: `lastMessage.role`, `$textContains`, `toolResult: {"toolCallId", "isError"}`, `tools: ["read", "edit", ...]` (список схем); после MVP `systemPrompt: {"$textContains": "…"}` — подстрока системного промпта запроса (режимы-промпты, §17.12.2) |
| `reply` | блоки ответа по порядку: `text`, `thinking`, `toolCall`; текст режется на дельты по 16 символов (детерминированно) |
| `stopReason` | `stop`, `toolUse`, `length`, `error`, `aborted` |
| `error` | вместо `reply`: `{"class": "auth", "message": "401"}` — шаг заканчивается `ErrorEvent` |
| `delayMs` | пауза перед ответом по `FakeClock` (для сценариев отмены) |
| `waitForCancel` | `true` — шаг не отвечает, пока токен не отменён, затем `ErrorEvent(aborted)`; вместе с `reply` — сначала отдаёт блоки ответа, затем ждёт отмены (отмена посреди стрима без гонки с запросом) |
| `usage` | usage ответа |

Шаги отдаются строго по порядку: n-й запрос к модели получает n-й шаг, выбора шага по условию
нет. `expect` — утверждение о запросе, а не условие: несовпадение — провал (в тесте — исключение
с diff ожидаемого и фактического запроса; в бинаре с `--llm-script` — `ErrorEvent` класса
`badRequest` с текстом расхождения, ход завершается `failed`). Шагов в запросах должно быть ровно
столько, сколько в `steps`: лишний запрос к модели или неиспользованный шаг — провал фикстуры
(бинарь неиспользованные шаги не проверяет; лишний запрос — `ErrorEvent(badRequest)`).

В строках `text` и `thinking` блока `reply` допустимы переменные `${cwd}` и `${sessionId}`
(§14.5): `ScriptedStreamFunction` подставляет `cwd` и id сессии запроса. Так интеграционные тесты
клиентов получают ответ, зависящий от сессии, без логики в сценарии.

Тот же блок — формат файла сценария для бинаря: `codelab-agent serve --stdio --llm-script <файл>`
читает JSON-объект `{"llm": {...}}` с полями этого раздела (dart-agent-and-clients §9.9, задача
4.6). `llm.model` необязателен: без него модель берётся из `--model`, иначе `scripted/scripted-1`.

## 14.8. Пример: `acp/prompt-tool-permission-allow`

```json
{
  "id": "acp/prompt-tool-permission-allow",
  "spec": [
    "05-Prompt Turn.md#5-tool-invocation-and-status-reporting",
    "08-Tool Calls.md#requesting-permission",
    "05-Prompt Turn.md#4-check-for-completion",
    "09-File System.md#reading-files",
    "09-File System.md#writing-files"
  ],
  "description": "Модель правит файл; агент читает его через fs/read_text_file, сообщает tool_call, запрашивает разрешение с rawInput, locations и diff, после allow_once перечитывает файл и пишет его через fs/write_text_file, отправляет in_progress и completed с diff, продолжает ход и отвечает end_turn после всех уведомлений.",
  "goals": ["P-01", "P-02", "C-01"],
  "roles": ["agent", "client"],
  "setup": {
    "cwd": "/work/demo",
    "files": {"README.md": "# foo\n"},
    "profile": "agent-serve",
    "mode": "standard"
  },
  "llm": {
    "model": {"provider": "scripted", "modelId": "scripted-1", "contextWindow": 32768},
    "steps": [
      {
        "expect": {"lastMessage": {"role": "user", "$textContains": "README"}},
        "reply": [
          {"text": "Заменю слово."},
          {"toolCall": {"id": "call_1", "name": "edit", "arguments": {"path": "README.md", "oldText": "foo", "newText": "bar"}}}
        ],
        "stopReason": "toolUse"
      },
      {
        "expect": {"toolResult": {"toolCallId": "call_1", "isError": false}},
        "reply": [{"text": "Готово: README.md обновлён."}],
        "stopReason": "stop"
      }
    ]
  },
  "frames": [
    {"dir": "c2a", "frame": {"jsonrpc": "2.0", "id": 2, "method": "session/prompt",
      "params": {"sessionId": "${sessionId}", "prompt": [{"type": "text", "text": "Замени в README.md слово foo на bar"}]}}},
    {"dir": "a2c", "repeat": "+", "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": {"$any": true}}}}},
      "match": {"$text": "Заменю слово."}},
    {"dir": "a2c", "note": "present() строит diff для запроса разрешения: файл читается через клиента",
      "frame": {"jsonrpc": "2.0", "id": {"$capture": "read1"}, "method": "fs/read_text_file",
      "params": {"sessionId": "${sessionId}", "path": "${cwd}/README.md"}}},
    {"dir": "c2a", "frame": {"jsonrpc": "2.0", "id": "${read1}", "result": {"content": "# foo\n"}}},
    {"dir": "a2c", "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "tool_call", "toolCallId": "call_1",
        "title": {"$contains": "README.md"}, "kind": "edit", "status": "pending",
        "rawInput": {"path": "README.md", "oldText": "foo", "newText": "bar"},
        "locations": [{"path": "${cwd}/README.md", "line": 1}]}}}},
    {"dir": "a2c", "note": "запрос разрешения: rawInput, locations и diff обязательны (PERM-6)",
      "frame": {"jsonrpc": "2.0", "id": {"$capture": "permId"}, "method": "session/request_permission",
      "params": {"sessionId": "${sessionId}",
        "toolCall": {"toolCallId": "call_1", "title": {"$contains": "README.md"}, "kind": "edit", "status": "pending",
          "rawInput": {"path": "README.md", "oldText": "foo", "newText": "bar"},
          "locations": [{"path": "${cwd}/README.md", "line": 1}],
          "content": [{"type": "diff", "path": "${cwd}/README.md", "oldText": "# foo\n", "newText": "# bar\n"}]},
        "options": [
          {"optionId": {"$capture": "allowOnce"}, "name": {"$any": true}, "kind": "allow_once"},
          {"optionId": {"$any": true}, "name": {"$contains": "README.md"}, "kind": "allow_always"},
          {"optionId": {"$any": true}, "name": {"$any": true}, "kind": "reject_once"},
          {"optionId": {"$any": true}, "name": {"$contains": "README.md"}, "kind": "reject_always"}]}}},
    {"dir": "c2a", "frame": {"jsonrpc": "2.0", "id": "${permId}",
      "result": {"outcome": {"outcome": "selected", "optionId": "${allowOnce}"}}}},
    {"dir": "a2c", "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "tool_call_update", "toolCallId": "call_1", "status": "in_progress"}}}},
    {"dir": "a2c", "note": "edit перечитывает файл под блокировкой пути (§6.4)",
      "frame": {"jsonrpc": "2.0", "id": {"$capture": "read2"}, "method": "fs/read_text_file",
      "params": {"sessionId": "${sessionId}", "path": "${cwd}/README.md"}}},
    {"dir": "c2a", "frame": {"jsonrpc": "2.0", "id": "${read2}", "result": {"content": "# foo\n"}}},
    {"dir": "a2c", "frame": {"jsonrpc": "2.0", "id": {"$capture": "write1"}, "method": "fs/write_text_file",
      "params": {"sessionId": "${sessionId}", "path": "${cwd}/README.md", "content": "# bar\n"}}},
    {"dir": "c2a", "frame": {"jsonrpc": "2.0", "id": "${write1}", "result": null}},
    {"dir": "a2c", "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "tool_call_update", "toolCallId": "call_1", "status": "completed",
        "content": [
          {"type": "content", "content": {"type": "text", "text": {"$any": true}}},
          {"type": "diff", "path": "${cwd}/README.md", "oldText": "# foo\n", "newText": "# bar\n"}]}}}},
    {"dir": "a2c", "repeat": "+", "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": {"$any": true}}}}},
      "match": {"$text": "Готово: README.md обновлён."}},
    {"dir": "a2c", "optional": true, "frame": {"jsonrpc": "2.0", "method": "session/update",
      "params": {"sessionId": "${sessionId}", "update": {"sessionUpdate": "session_info_update", "title": {"$any": true}, "updatedAt": "<ts>"}}}},
    {"dir": "a2c", "note": "ответ последним кадром хода (ACP-3)",
      "frame": {"jsonrpc": "2.0", "id": 2, "result": {"stopReason": "end_turn"}}}
  ],
  "after": {"files": {"README.md": "# bar\n"}}
}
```

`after.files` — проверка состояния файлов после сценария: у агента — по последнему кадру
`fs/write_text_file` на путь, у клиента — по его файловой системе. Кадры `fs/*` в фикстуре
— не подробность реализации, а часть контракта `agent-serve`: файлы читаются и пишутся через
клиента (§4.7, §10.4).

## 14.9. Алгоритм: conformance агента

Агентская проверка запускает агента так же, как его видит настоящий клиент: профиль
`agent-serve`, транспорт в памяти, файлы и команды — через ACP (`AcpClientExecutionEnv`, §4.7).
Поэтому кадры `fs/*` и `terminal/*` — часть фикстуры, а ответы клиента на них берутся из её
кадров `c2a`. `MemoryExecutionEnv` здесь не используется: он — env тестов ядра `core/*` через
прямой API, без ACP. Драйвер `agent_conformance.dart` не зависит от пакетов агента: тест
`codelab_agent_acp/test/conformance_test.dart` передаёт ему фабрику, которая по `fx.setup`
поднимает `AcpAgentServer` на агентском конце `InProcessAcpLink`.

```text
runAgentFixture(fx, startAgent):
1. загрузить и провалидировать фикстуру по _schema.json; id == путь; spec не пуст;
   неполная фикстура → громкий провал загрузчика, а не пропуск
   fx.roles не содержит "agent" → фикстура в этом прогоне не участвует (строка в отчёте, не провал)
2. cwd := временный каталог; записать в него fx.setup.files — только для локального листинга
   ls/search (fileListing transport local, §10.4); содержимое файлов агент получает кадрами fs/*
3. stream := ScriptedStreamFunction(fx.llm); clock := FakeClock; ids := SequentialIdGenerator
4. link := InProcessAcpLink() (копирование сообщений, §13.11; на этапе 4 — тестовая копия из
   contract test, dart-agent-and-clients §9.9, задача 4.7); client := link.client
5. startAgent(link.agent, AgentFixtureSetup(profile: fx.setup.profile ?? "agent-serve", cwd,
          config: defaults + fx.setup.config, streamFunction: stream, clock, ids)):
     core := buildAgentCore(profile: HostProfile.of(profile),
          services: AgentCoreServices(sessions: MemorySessionStore, clock, ids, ...),
          config, streamFunction: stream)                                        (§10.7)
     server := AcpAgentServer(core, localListing: (root) => LocalExecutionEnv(root))  // как бинарь по stdio
     server.serve(link.agent)
   env сессии создаёт сервер по clientCapabilities из initialize: BoundedEnv над
   ListingOverlayEnv(AcpClientExecutionEnv, localListing) (§4.7, §10.4); gate — AcpPermissionGate
6. если не skipInitialize: отправить initialize с setup.clientCapabilities, session/new;
   проверить protocolVersion и sessionId ответов; vars.sessionId := ответ; необязательный
   available_commands_update после ответа — часть handshake
7. для каждого кадра f в fx.frames по порядку:
   c2a → подставить vars, отправить client.send(frame); это и промпты, и ответы клиента на
         запросы агента (fs/*, terminal/*, session/request_permission)
   a2c → получить следующий кадр client.inbound (таймаут 5 с по реальным часам);
         нормализовать (§14.5); сравнить (§14.6); repeat "+": читать, пока кадры совпадают
         с шаблоном, затем проверить $text; optional: при несовпадении не потреблять кадр
         и перейти к следующему ожидаемому; unordered: собрать N кадров, найти паросочетание
         расхождение → провал с diff ожидаемого и фактического кадра и индексом f
8. тишина: 200 мс без новых кадров (лишний кадр — провал; лишний запрос fs/* или terminal/* —
   тоже провал: агент сделал больше, чем закреплено)
9. ScriptedStreamFunction: все шаги использованы, лишних запросов не было
10. после: для каждого пути из fx.after.files — content последнего кадра fs/write_text_file
    на ${cwd}/<путь> (без записи — содержимое setup.files) равен ожидаемому
11. в конце (и при провале) сначала закрыть client: ожидания агента завершаются разрывом,
    а не таймаутами FakeClock; затем остановить агента
```

## 14.10. Алгоритм: проверка клиента

```text
runClientFixture(fx, clientFactory):
1. загрузка как в 14.9, блок llm игнорируется; fx.roles не содержит "client" → фикстура в
   этом прогоне не участвует; fx.setup.files — файловая система клиента (fake fs-порт или
   временный каталог)
2. transport := FakeAcpTransport(autoRespondToInitialize: false); client := clientFactory(transport)
   (AcpClientApplication или ClientWorkspace из acp_client_kit; в UI-тестах — app целиком)
3. для каждого кадра f по порядку (роли зеркальны):
   a2c → подставить vars; transport.emitInbound(frame)
   c2a → дождаться следующего кадра в transport.sent (таймаут 5 с), нормализовать, сравнить;
         $capture работает в обе стороны: id запроса клиента, взятый из фактического кадра,
         подставляется в последующие a2c-ответы
   для кадров c2a, которые клиент шлёт по действию пользователя (session/prompt,
   ответ на request_permission), тест клиента выполняет действие через свой API до ожидания:
   хук onBeforeExpect(f) — например, «нажать Разрешить один раз»
4. после: тест клиента проверяет своё состояние (карточка вызова completed, diff показан,
   ход завершён) — эти проверки пишутся в тесте клиента, а не в фикстуре
```

Одна фикстура проверяет обе стороны: агент обязан **отправлять** кадры `a2c`, клиент обязан
**принимать** их и отвечать кадрами `c2a`.

## 14.11. Инварианты корпуса

1. **FIX-1.** У каждой фикстуры есть непустой `spec`, и каждая ссылка указывает на существующий файл `docs/acp/protocol/` (тест загрузчика).
2. **FIX-2.** Каждый вид `sessionUpdate` из `acp_protocol` и каждый метод из `acp_method_codec.dart`, включая запросы агента `fs/*`, `terminal/*` и `session/request_permission`, встречается хотя бы в одной фикстуре с ролью `agent` и хотя бы в одной с ролью `client` (тест покрытия; вид, который агент не порождает, — только в `client`). `available_commands_update` закрывает `acp/session-new-modes-config` (этап 0, список — `$any`).
3. **FIX-3.** Каждая цель Must матрицы паритета с ACP-проявлением ссылается на существующий id фикстуры.
4. **FIX-4.** Фикстуры без `extensions` не содержат `_meta.codelab`, `data.codelab` и методов `_codelab/*`. Фикстура, ожидающая `_meta.codelab.outcome`, объявляет `"extensions": ["outcome"]` (§14.2, этап 4); агент шлёт `outcome` всегда, а фикстуры без расширения его не проверяют (`_meta` — `$partial`, §14.6).

## 14.12. Обоснование решения

* **Кадры, а не утверждения.** Последовательность кадров — то, что видит любой ACP-клиент, в
  том числе Zed; утверждения о внутреннем состоянии агента в фикстуре сделали бы её
  неприменимой к клиентам.
* **Точное сравнение по умолчанию.** Лишнее поле в кадре — частая форма нарушения
  спецификации; матчеры ослабляют сравнение только там, где спецификация оставляет свободу.
* **Scripted-модель внутри фикстуры.** Сценарий и ответы модели лежат в одном файле: фикстуру
  читают и правят целиком, не сверяя с отдельным файлом сценария.

## 14.13. Как проверить

* `acp_testing/test/fixtures_load_test.dart`: все фикстуры проходят схему, FIX-1, FIX-4.
* `acp_testing/test/fixtures_coverage_test.dart`: FIX-2, FIX-3.
* `codelab_agent_acp/test/conformance_test.dart`: `runAgentFixture` на каждой фикстуре.
* Тесты codelab-app и `acp_client_kit`: `runClientFixture` на фикстурах с ролью `client`.
* Тест самого матчера: мутации кадра (лишний ключ, другой статус, другой порядок) дают провал с понятным diff.

---

← [13. ACP-адаптер](13-acp-adapter.md) · [Оглавление ядра](../agent-core-architecture.md) · [15. Конфигурация](15-configuration.md) →
