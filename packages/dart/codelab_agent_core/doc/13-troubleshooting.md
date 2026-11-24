# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет ядро или встраивает его в хост. Каждый случай записан одинаково: симптом, причина, что сделать. Имена событий лога, тексты ошибок и исключения взяты из кода пакета; рядом указан файл, где они появляются.

События лога читаются в журнале хоста: ключи полей и маскирование описаны в [10-observability-and-errors.md](10-observability-and-errors.md). В тестах те же записи отдаёт `RecordingLogger.eventsOf('<событие>')` ([12-testing.md](12-testing.md)).

Случаи по теме:

- сборка и инструменты: [инструмент не виден модели](#инструмент-не-виден-модели), [`HostWiringException`](#hostwiringexception-при-сборке), [вызов заблокирован `MisuseBreaker`](#вызов-заблокирован-misusebreaker);
- разрешения: [ход ждёт ответа на запрос разрешения](#ход-ждёт-ответа-на-запрос-разрешения);
- конфигурация и секреты: [`config.key.not_applied`](#configkeynot_applied), [секрет не найден](#секрет-не-найден), [ключ проекта игнорируется](#ключ-проекта-игнорируется);
- контекст: [контекст переполнен](#контекст-переполнен), [сжатие не сработало](#сжатие-не-сработало);
- MCP: [сервер в состоянии `disabled`](#mcp-сервер-в-состоянии-disabled);
- проверки: [`prompts:check` красный](#promptscheck-красный), [golden-тест разошёлся](#golden-тест-разошёлся), [сценарная модель падает в тесте](#сценарная-модель-падает-в-тесте), [сторож `melos run guard` упал на импорте](#сторож-melos-run-guard-упал-на-импорте), [`web-compile` упал](#web-compile-упал).

## Инструмент не виден модели

**Симптом.** Модель отвечает, что у неё нет `exec`, `ls`, `search` или MCP-инструментов; в схемах запроса этих инструментов нет. Либо вызов инструмента даёт `Tool "<имя>" is not available. Available tools: …` (`lib/src/tools/executor.dart`).

**Причина.** Инструмент регистрируется только при включённой возможности хоста (`HostCapability`), и возможность выключена: хост не передал нужный порт или профиль её сузил (HOST-4, [02-assembly-and-hosts.md](02-assembly-and-hosts.md)). Правила — `lib/src/host/build_agent_core.dart`:

| Нет инструмента | Возможность выключена, потому что |
|---|---|
| `exec` | `shellExec`: в профиле `agent-serve` она включена (транспорты `acp-terminal` и `local`), бинарь её не сужает; выключена, если профиль сужен в конфигурации (`profile.agent-serve`) или хостом. Флага `--local-exec` нет: это слово есть только в описании профиля (`host_profile.dart`) |
| `ls`, `search` | `fileListing`: `baseEnv` не реализует `DirectoryListing` (причина `env без листинга каталога`) |
| инструменты `mcp__…` | `mcp`: в `AgentCoreServices` нет коннектора (`сервис MCP не передан`) |
| навыки | профиль выключил `profile.<имя>.skills: off`; настройка `skills.enabled` возможность не сужает (HOST-4) |

**Что сделать.** Найти запись `host.plan` (уровень `info`, пишется один раз при сборке): поле `off` называет каждую выключенную возможность и причину, поле `tools` — итоговый набор. Пример из теста `CoreHarness` с профилем `agent-serve` без shell (список `tools` сокращён):

```text
info host.plan {"profile":"agent-serve","tools":["read","write","edit",…,"search"],"off":{"shellExec":"тест без shell","sessionPersistence":"журнал теста в памяти","mcp":"сервис MCP не передан"}}
```

Если возможность нужна, передайте порт хосту (`AgentCoreServices`). Профиль может только сужать возможности (HOST-2), расширить его конфигом нельзя. Если инструмент есть в `host.plan`, но модель получает отказ `Tool not available for agent <имя>: <инструмент>`, то набор инструментов сужен определением выбранного агента (`lib/src/runtime/agent_runtime.dart`, `_unavailableText`; [09-config-prompts-commands.md](09-config-prompts-commands.md)).

## `HostWiringException` при сборке

**Симптом.** `buildAgentCore` бросает `HostWiringException: …` (`lib/src/host/host_profile.dart`) до первого запроса. Сессия не создаётся.

**Причина.** Хост собрал несовместимые части. Исключение значит ошибку программиста, а не пользователя: сборка отвергает неверную связку сразу, а не при первом запросе. Тексты проверены запуском на текущем коде:

| Текст исключения | Что не так |
|---|---|
| `capability shellExec требует сервис baseEnv с настоящим Shell.exec: у MemoryExecutionEnv его нет` | профиль включает `shellExec`, а окружение — `MemoryExecutionEnv` |
| `capability sessionPersistence требует постоянного SessionStore: MemorySessionStore теряет журнал при выходе процесса` | профиль `embedded-cli` с журналом в памяти |
| `capability mcp: нельзя расширить {http, stdio} до {smtp} в профиле agent-serve` | `narrowed()` пытается расширить возможность |
| `capability mcp требует транспорты …: McpConnector не умеет …` | коннектор не поддерживает транспорт включённой возможности (HOST-3) |
| `AgentCoreServices.config требует modelsFor: …` и `AgentCoreServices.projectConfig требует modelsFor: …` | перезагрузка и сессии других папок строят модель по новой конфигурации и без `modelsFor` её не получат |

**Что сделать.** Сузьте возможность явно: `profile.narrowed({HostCapability.shellExec: CapabilityOff('причина')})`. В тестах для этого есть `noExec` и `inMemoryJournal` в `test/host/core_harness.dart`. Настоящему хосту передайте настоящий порт: окружение с shell, постоянное хранилище, коннектор нужных транспортов.

## Вызов заблокирован `MisuseBreaker`

**Симптом.** К ошибкам вызова приписывается `[Warning: this exact call has failed 3 times in this turn. …]`; на шестом неверном вызове — `[Warning: … is now blocked until the turn ends.]`, а начиная с седьмого модель получает `Blocked: this exact call to read has already failed 6 times in this turn and will not be run again until the turn ends. Change the arguments or use another approach.`

**Причина.** `MisuseBreaker` считает неверные вызовы одного хода (`lib/src/tools/misuse.dart`). Ключ вызова — имя инструмента и сырые аргументы модели. На третьем неверном вызове с одним ключом он дописывает предупреждение, на шестом блокирует ключ до конца хода. Считается только то, что упало на поиске инструмента, проверке аргументов или `preflight`: отказ разрешения, отмена и ошибка исполнения в счёт не идут. В логе — `tool.misuse.warned` (`debug`) и `tool.misuse.blocked` (`warning`) с полями `tool`, `n`, `tool_call_id`.

**Что сделать.** Это защита от модели, которая повторяет один и тот же вызов, а не сбой ядра. Если модель ошибается в аргументах, поправьте описание или схему инструмента (`lib/src/tools/`, тексты — `prompts/tool_descriptions/`). Следующий ход начинает со счётчиком с нуля. Пределы `loop.misuse.enabled`, `warn_after` и `block_after` есть в схеме, но пока не применяются: ключ даёт предупреждение [`config.key.not_applied`](#configkeynot_applied), а ядро берёт значения по умолчанию 3 и 6. В тесте пределы задаются через `h.config(misuse: MisuseLimits(...))` у `LoopHarness`; пример — `test/tools/misuse_breaker_test.dart`.

## Ход ждёт ответа на запрос разрешения

**Симптом.** Ход не завершается, новых событий нет. В логе есть `permission.asked` (`debug`: `tool_call_id`, `tool`, `tier`, `critical`), а `permission.decided` нет. В тесте ход «зависает» до таймаута теста.

**Причина.** Политика (`lib/src/permissions/policy.dart`) отправила вопрос в `PermissionGate` и ждёт его решения. Ожидание не ограничено по времени: время человека не входит в бюджет хода (`ApprovalWaitMeter`, D6). Через ACP вопрос уходит клиенту как `session/request_permission` ([03-request-flow.md](03-request-flow.md), [07-permissions.md](07-permissions.md#как-вопрос-доходит-до-пользователя)). В тесте gate, который не отвечает, обычно значит, что вы подставили собственную реализацию без ответа.

**Что сделать.**

- В диалоге клиента ответьте на вопрос или отмените ход: отмена хода превращается в решение `cancelled` и закрывает ожидание.
- Если gate не передан, зависания нет, а есть отказ: вызов получает `Denied('no approval interface is available')`, в логе — `permission.denied` с полем `reason`. Для автоматических запусков выберите режим, который не спрашивает, или передайте gate ([07-permissions.md](07-permissions.md)).
- В тесте подставляйте `FakeGate` (`test/permissions/fake_gate.dart`): он отвечает заданным решением; с `FakeClock` и `wait` — после паузы на поддельных часах.
- Любой сбой клиента при вопросе (ошибка, недекодируемый ответ, обрыв соединения) становится отказом, а не разрешением. Исключение — режим `waitForReconnect`: вопрос ждёт нового соединения и задаётся заново с тем же `toolCallId`.

## `config.key.not_applied`

**Симптом.** `codelab config check` или запуск агента печатает предупреждение `this key is read but not applied by this version of the agent`, хотя ключ описан в схеме и принят без ошибок.

**Причина.** Ключ есть в схеме (`lib/src/config/schema.dart`) с признаком `applied: false`: схема его знает, но потребителя в этой версии нет (D6). Критерий готовности итерации требует вводить ключ вместе с потребителем ([`AGENTS.md`](../AGENTS.md), раздел 3 (г)) и правило CFG-5: ключ схемы без потребителя даёт это предупреждение. Событие — `config.key.not_applied`, найденное предупреждение несёт путь ключа, источник, строку и столбец (`ConfigIssue`).

Реальный вывод `fvm dart run bin/codelab.dart config check` в `apps/codelab_cli` с конфигом `exec.shell` (домашний каталог в сообщении заменён на `~/.codelab`):

```text
warning: ~/.codelab/config.yaml:2:3: exec.shell: this key is read but not applied by this version of the agent
```

**Что сделать.** Пользователю: ключ можно убрать, он ничего не меняет. Разработчику: если вы добавляете ключ, в том же change добавьте потребителя и переведите узел схемы на `applied: true` (рецепт — [11-extending.md](11-extending.md)). Если ключ нужен только как заготовка, оставьте `applied: false` и напишите об этом в документации ключа, а не в тексте для пользователя.

## Секрет не найден

**Симптом.** Первый запрос к модели заканчивается ошибкой класса `auth` с одним из текстов:

- `API key secret <имя> is not set. Run: codelab secret set <имя>`;
- `API key variable <ПЕРЕМЕННАЯ> is not set`;
- `API key secret <имя> cannot be read: <хранилище> is unavailable (<причина>). Set CODELAB_SECRET_<ИМЯ> or fix the secret store`.

`codelab config check` заранее показывает `config.provider.key_missing`, если переменная из `api_key_env` не задана.

**Причина.** Ссылка провайдера (`api_key_env`, `api_key_secret`, `${secret:…}` в заголовках) не раскрылась: значения нет в окружении или хранилище секретов, либо хранилище недоступно (`lib/src/llm/provider_factory.dart`, `lib/src/config/resolve.dart`). Порядок поиска секрета: кэш, переменная переопределения `CODELAB_SECRET_<ИМЯ>`, хранилище. Имя в переменной — имя секрета заглавными буквами, всё кроме букв и цифр заменено на `_`: секрет `codelab/demo` читается из `CODELAB_SECRET_CODELAB_DEMO` (`lib/src/secrets/secret_names.dart`).

Реальный вывод `config check` для провайдера с `api_key_env: DEMO_API_KEY` при незаданной переменной (путь сокращён до `~/.codelab`):

```text
warning: ~/.codelab/config.yaml:7:5: providers.demo.api_key_env: the environment variable with the API key is not set
```

**Что сделать.** Задайте секрет: `codelab secret set <имя>` или переменную окружения. Если хранилище недоступно, используйте переменную переопределения. Если пишет `config.provider.key_unbound`, провайдер из слоя проекта ссылается на ключ другого адреса: перенесите его в `config.local.yaml` или пользовательский конфиг (тест — `test/config/config_provider_key_binding_test.dart`). Значение секрета не попадает ни в лог, ни в текст ошибки; в тестах ключи подставляет `FakeSecretStore` (`test/support/fake_secret_store.dart`).

## Ключ проекта игнорируется

**Симптом.** Настройка в `.codelab/` проекта не действует. В выводе `config check` или логе — `ignored: …` с событием `config.project.untrusted_key`.

**Причина.** Конфигурация проекта — слой, которому доверяют не целиком (`lib/src/config/trust.dart`, CFG-3). Три вида отказа:

- ключ не читается из проекта вообще: `trusted_projects is read only from the global config`, `secrets is read only from the global config`, `<раздел> is not read from a project config` для `sessions`, `logging`, `exec`, `config`: они определяют, куда агент пишет и что запускает;
- ключ читается только у доверенного проекта: `mcp.servers`, `providers`, `model_catalog`, `prompts`, `hooks` и другие; причина — `the project is not trusted; add it to trusted_projects in the global config`;
- ключ ограничен: проект не может смягчить запреты и режим пользователя (`permissions.deny`, режим разрешений).

**Что сделать.** Перенесите ключ первого вида в пользовательскую конфигурацию. Для второго вида добавьте папку проекта в `trusted_projects` глобальной конфигурации, но только если доверяете её содержимому.

## Контекст переполнен

**Симптом.** Ход заканчивается ошибкой `context window exhausted` без обращения к провайдеру (`TurnEnded` с причиной `failed`), либо провайдер отвечает ошибкой переполнения контекста.

**Причина.** Запрос не помещается в окно модели. Цикл отвечает на это один раз за ход: аварийно сжимает контекст и повторяет шаг (причины `preflight` — оценка больше окна, `overflow` — провайдер ответил `errorClass: overflow`; `lib/src/loop/agent_loop.dart`, CMP-8). Если сжатие недоступно (возможность `compaction` выключена: `compaction.enabled: false` либо хост её сузил), уже было использовано в этом ходу или не уменьшило контекст, цикл возвращает синтетический ответ `overflow` с текстом `context window exhausted`. Порог и окно считает `effectiveContextWindow`: меньшее из окна модели и `compaction.context_window_cap` ([08-sessions-and-compaction.md](08-sessions-and-compaction.md#сжатие-контекста)).

**Что сделать.** Выполните `/compact` (с указанием фокуса — `/compact <фокус>`) вне хода и повторите запрос. Проверьте, что в `host.plan` нет `compaction` в `off`. Если окно маленькое, проверьте `context_window` модели в каталоге и `compaction.context_window_cap`: слишком малый предел делает окно меньше реального. Если один инструмент возвращает огромный вывод, исправляйте его усечение (`test/tools/truncate_test.dart`), а не пороги.

## Сжатие не сработало

**Симптом.** После хода контекст не уменьшился, в логе `compaction.skipped` или `compaction.failed`; в событиях сессии — `AgentError` класса `compaction` с текстом `compaction failed: …`.

**Причина.** У записей `compaction.skipped` есть поле `reason` (`lib/src/compaction/compactor.dart`):

- `no cut point` — сжимать нечего: в области сжатия нет места среза, свежий хвост занимает всё;
- `no reduction` — резюме не вышло короче сжатого фрагмента;
- `stale` — пока шло сжатие, журнал изменился (например, сессия продолжилась), результат отброшен.

`compaction.failed` с полями `session_id`, `trigger`, `error` — сбой модели резюме или фоновая ошибка; ошибка фонового сжатия не теряется и уходит в события как `AgentError`.

**Что сделать.** Для `no cut point` и `no reduction` уменьшите `compaction.keep_recent_tokens` или `keep_recent_user_turns`: хвост, который остаётся дословно, слишком велик для окна. Для `failed` проверьте доступность модели резюме и текст в поле `error`. Фоновое сжатие запускается после `completed` и `maxTokens`, а не после `cancelled` и `failed` ([08-sessions-and-compaction.md](08-sessions-and-compaction.md#когда-запускается)).

## MCP-сервер в состоянии `disabled`

**Симптом.** В таблице `/mcp list` сервер стоит в состоянии `disabled`, а в колонке `LAST ERROR` — `tool name collision: mcp__my_srv__t`. В логе — `mcp.server.failed` (`warning`) с полем `reason`.

**Причина.** Коннектор отключает сервер целиком, если имя его инструмента совпало с чужим (`packages/dart/codelab_agent_mcp/lib/src/connector.dart`, E-05, HOST-5). Три вида коллизии, текст — в поле `reason`:

- `tool name <имя> collides with built-in tool <имя>` — совпало с встроенным инструментом;
- `tool name <имя> collides with MCP server "<другой>"` — совпало с инструментом сервера, который стоит в списке раньше;
- `tool name <имя> collides with another tool of MCP server "<сервер>"` — два инструмента одного сервера дают одно имя.

Имя инструмента для модели строится как `mcp__<сервер>__<инструмент>`, при этом точка и подобные символы в имени сервера приводятся к `_`. Поэтому серверы `my.srv` и `my_srv` с инструментом `t` дают одно имя `mcp__my_srv__t`: оставшимся сервером становится тот, что стоит в списке раньше (тест `connector_test.dart`, группа `name collisions disable the later server`).

Так выглядит таблица `/mcp list` с отключённым сервером; сервер `local-db` выключен ключом `enabled: false` (фикстура `fixtures/acp/slash-mcp-list.json`, кадр после `/mcp list`):

```text
MCP servers (3)
ID        SOURCE   TRANSPORT  STATE      TOOLS  LAST ERROR
github    config   stdio      connected  2      -
local-db  config   stdio      disabled   0      -
docs      session  stdio      connected  1      -
```

Выключение ключом `enabled: false` отличается от коллизии пустым `LAST ERROR`; у коллизии в нём стоит текст `tool name collision: …`, а у сервера, выключенного командой `/mcp disable`, — `disabled by /mcp disable`.

**Что сделать.** Переименуйте сервер в конфигурации или инструмент на стороне сервера, чтобы имена перестали совпадать. Повторная попытка происходит при следующем применении конфигурации: сервер, отключённый коллизией, перезапускается при перезагрузке (`connector_replace_servers_test.dart`).

## `prompts:check` красный

**Симптом.** `melos run prompts:check` падает с кодом выхода 1 и сообщением `lib/src/prompts/prompts.g.dart is out of date: run tool/gen_prompts.dart`. Либо падает генератор: `<файл>: unknown placeholder {{имя}}`, `<файл>: declared but not used: <имя>`, `<файл>: bad placeholder {{имя}}`.

**Причина.** Промпты исполняются как константы из сгенерированного `prompts.g.dart`, а источник — файлы `prompts/**/*.md` ([09-config-prompts-commands.md](09-config-prompts-commands.md)). Вы правили `.md`, но не перегенерировали файл, либо плейсхолдер `{{имя}}` в тексте не совпадает с объявленными переменными (`tool/gen_prompts.dart`).

**Что сделать.** В каталоге пакета:

```bash
fvm dart run tool/gen_prompts.dart
fvm dart run tool/gen_prompts.dart --check
```

Первая команда переписывает `prompts.g.dart`, вторая убеждается, что файл совпадает с источником (на текущем коде завершается кодом 0). Если поменялся текст системного промпта, дальше обновите golden-файлы `test/prompts/golden/` ([следующий случай](#golden-тест-разошёлся)). Правьте только `.md`, `prompts.g.dart` руками не меняют.

## Golden-тест разошёлся

**Симптом.** Тест вроде `read matches test/tools/golden/read.txt`, `agent-serve-standard matches test/prompts/golden/…` или `the golden matrix matches test/host/profiles/…` красный: `expect` показывает различие текста или JSON. Или тест падает с `нет golden-файла; запустите с UPDATE_GOLDEN=1`.

**Причина.** Изменился текст, который видит модель: вывод инструмента, системный промпт или матрица возможностей профиля. Golden-файлы нужны, чтобы такая правка была видна в diff (`test/tools/builtin_tools_golden_test.dart`, `test/prompts/compose_test.dart`, `test/host/host_profile_test.dart`).

**Что сделать.** Сначала решите, что неверно: код или файл. Если правка намеренная, перегенерируйте файлы в каталоге пакета и посмотрите `git diff`:

```bash
UPDATE_GOLDEN=1 fvm dart test test/tools test/prompts test/host test/skills
```

Затем запустите те же тесты без `UPDATE_GOLDEN`: переписанный файл всегда совпадает с кодом, и только повторный прогон показывает, что сравнение работает. Если разошёлся golden-файл профиля, проверьте, что `embedded-cli` и `embedded-app-desktop` остались одинаковыми: паритет профилей закреплён тестом. Подробности — [12-testing.md](12-testing.md#golden-тесты-и-update_golden).

## Сценарная модель падает в тесте

**Симптом.** Ход в тесте заканчивается ошибкой `scripted model: step 1: expect.lastMessage: expected {"role":"user","$textContains":"README"}, got user message "turn debug on"`, либо `verify()` бросает `ScriptedLlmFailure` с перечнем расхождений.

**Причина.** `ScriptedStreamFunction` отдаёт n-му запросу n-й шаг и сверяет запрос с `expect` (`lib/src/testing/scripted_stream_function.dart`). Он не бросает исключений в ходе: расхождение становится ответом `badRequest`, чтобы ход завершился предсказуемо, а `verify()` собирает всё в одно исключение. Типичные причины: шагов меньше, чем запросов (`request 3: the script has only 2 steps`); шаг не использован (`step 2 was not used`); `expect` не совпал с реальным последним сообщением.

Пример `verify()` для сценария, где первый шаг ждёт `README`, а ход получил другой промпт:

```text
ScriptedLlmFailure:
  - step 1: expect.lastMessage: expected {"role":"user","$textContains":"README"}, got user message "turn debug on"
  - step 2 was not used
```

**Что сделать.** Сопоставьте шаги сценария с реальными запросами хода: каждый ход агента делает запрос на каждый шаг цикла (после вызова инструмента — ещё один). Лишний шаг уберите, недостающий добавьте, а `expect` сделайте менее строгим (`$textContains` вместо точного текста). Всегда вызывайте `verify()` в конце теста: без него пропущенный шаг не виден.

## Сторож `melos run guard` упал на импорте

**Симптом.** `melos run guard` красный. Причина в тексте проверки (`reason`) строкой вида `<файл>:<строка> -> <импорт>`, например `packages/dart/codelab_agent_core/lib/src/x.dart:1 -> dart:io` (путь от корня репозитория). Или `not in allowlist: <пакет>` для зависимости в `pubspec.yaml`.

**Причина.** Файл в `lib/` ядра импортирует запрещённое (PKG-1): `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_protocol/`, `package:codelab_acp_transports/` или парсер конфигурации (`package:yaml/`, `package:yaml_edit/`, `package:toml/`, CFG-5). Запрет действует и на `export`, `part` и условные импорты. Либо в `dependencies` ядра появился пакет вне allowlist PKG-2 (`http`, `meta`, `collection`, `async`, `crypto`). Правила — `packages/dart/codelab_architecture_tests/test/support/rules.dart`, `test/pubspec_allowlist_test.dart`.

**Что сделать.** Не отключайте правило. Перенесите код, которому нужен `dart:io`, в `codelab_agent_io` и подключите через порт (`ExecutionEnv`, `SessionStore` и другие, [02-assembly-and-hosts.md](02-assembly-and-hosts.md)). Если нужна новая зависимость, это решение OpenSpec change: расширение allowlist без него недопустимо. Клиентам запрещено импортировать `package:codelab_agent_*` напрямую: они идут через мосты `codelab_setup` и `codelab_embedded` (`AGENTS.md` корня, §5).

## `web-compile` упал

**Симптом.** `melos run web-compile` падает при компиляции `test/web_smoke/main.dart` в JavaScript или WebAssembly: `Error: Dart library 'dart:ffi' is not available on this platform.` и цепочка импортов.

**Причина.** Ядро (или то, что оно импортирует) использует библиотеку, недоступную на web. Компилятор показывает цепочку импортов, которая ведёт к ней. Это проверено запуском: `dart:ffi` в Dart на JS даёт именно эту ошибку.

Но `dart:io` компилятор принимает: отдельный файл с `import 'dart:io'` собирается в JavaScript и WebAssembly без ошибок (проверено на текущем SDK). Поэтому `dart:io` в ядре ловит не `web-compile`, а сторож — см. [предыдущий случай](#сторож-melos-run-guard-упал-на-импорте).

**Что сделать.** Запустите `melos run guard` и уберите найденный импорт. Если сторож зелёный, посмотрите цепочку в выводе компилятора: нежелательная библиотека может прийти через зависимость. Точка входа `test/web_smoke/main.dart` проводит ход через `buildAgentCore` на `MemoryExecutionEnv`; тот же код на VM проверяет `test/web_smoke_turn_test.dart`, так что падение на VM указывает на ошибку логики, а не на платформу.

## Смотрите также

- [12. Тестирование](12-testing.md) — уровни тестов, харнессы, фикстуры.
- [10. Наблюдаемость и ошибки](10-observability-and-errors.md) — как читать лог и как ошибка доходит до клиента.
- [`AGENTS.md`](../AGENTS.md) пакета — инварианты PKG-1…PKG-6 и CFG-5, которые проверяет сторож.
