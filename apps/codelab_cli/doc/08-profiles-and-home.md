# Профили подключения и домашний каталог

Профиль подключения отвечает на вопрос «к какому агенту подключаться»; домашний каталог `CODELAB_HOME` — «где лежат файлы клиента». Глава объясняет, как `--agent` превращается в профиль, что умеет подкоманда `profiles`, как CLI обращается с токенами и аргументами агента, где хранит историю и недавние проекты и что делает переходный алиас `codelab serve`. Оглавление руководства — [README](README.md). Пользовательский взгляд — [руководство пользователя](user-guide.md#выбрать-агента); файлы и права — [эксплуатация](operations.md#файлы).

Код — `lib/src/profiles/` (`profile_arg.dart`, `profiles_command.dart`), `lib/src/home.dart`, `lib/src/session_setup.dart`, `lib/src/serve_alias.dart`. Типы профилей (`ConnectionProfile`, `ProfileStore`, `ProfileSecretSource`) принадлежат клиентскому слою; CLI даёт им разбор строки и вывод.

## Формы `--agent`

`resolveAgentProfile(value, store:, onWarning:)` превращает значение `--agent` в профиль. Правило одно для REPL, TUI, `-p` и `test-scenario`.

| Значение | Профиль | Читается ли `profiles.json` |
|---|---|---|
| нет `--agent`, `embedded` | `embeddedCliProfile`: встроенный агент, профиль хоста `embedded-cli` | нет |
| `default` | тот же встроенный агент | только ради предупреждения о прежней записи `default`; любая ошибка чтения молчит |
| `stdio:<команда> [аргументы]` | разовый `StdioProfile` с id `inline`; слова разбирает `parseShellWords`; агент стартует в папке сессии (`runInProjectDirectory`) | нет |
| `ws://…`, `wss://…` | разовый `WebSocketProfile`; токен — ссылка `env:CODELAB_AGENT_TOKEN` | нет |
| любое другое слово | профиль с таким id из `profiles.json` | да |

`embedded` и `default` — зарезервированные id (`reservedProfileIds` клиентского слоя): запись `default` из файла для выбора агента не используется никогда. Встроенного агента нельзя сохранить профилем (`embedded is built in; use --agent embedded`), поэтому битый `profiles.json` ему не мешает: файл читается только при `-a <id>` и в `codelab profiles …`.

Ошибки (`UsageError`, код `64`) не повторяют значение `--agent`: без префикса `stdio:` оно может оказаться командной строкой с токеном (`-a 'my-agent --token sk-…'`). Поэтому текст фиксированный:

```bash
codelab -a nope -p hi
```

```text
codelab: Unknown agent profile. Run "codelab profiles list".
```

Ошибки формы: `Invalid agent command: …` (не разобрались слова `stdio:`; значение не повторяется), `Invalid agent URL "<значение>"` (единственное сообщение, которое цитирует значение целиком), `Cannot read agent profiles: …` (битый файл при `-a <id>`).

Внешний агент выбирается явно. Если он не запустился, режимы пишут `codelab: cannot start the agent <описание профиля>: <причина>` и выходят с кодом `1`:

```bash
codelab -a stdio:/nonexistent/agent -p hi
```

```text
codelab: cannot start the agent "/nonexistent/agent": Failed to connect ACP transport.
```

## Что печатается о профиле

Значения аргументов stdio-профиля не печатаются нигде — ни в ошибках запуска и подключения, ни в `/profile`, `profiles list|show`, ни в ошибке разбора `stdio:…`. Среди аргументов бывает токен (`--token sk-…`), а по строке секретный аргумент не отличить от обычного. Печатаются команда и число аргументов. Единые формулировки:

| Функция | Что даёт | Пример |
|---|---|---|
| `describeProfile(profile)` | коротко, для сообщений об ошибке | `"my-agent" with 2 arguments`; для WebSocket — только `scheme://host[:port]`; для встроенного — `embedded agent (embedded-cli)` |
| `argumentCount(n)` | число аргументов | `1 argument`, `2 arguments` |
| `describeStartFailure(error, profile, tokenSource:)` | причина отказа | отказ рукопожатия HTTP 401 или 403 — `the agent rejected the token (HTTP 401).` или `the agent requires a token (HTTP 401).`; сырая `ProcessException` — только её `message`, без `Command: <аргументы>` |

Адрес WebSocket в выводе — только origin: `query` вида `?t=<токен>` и `user:pass@` несут секреты, путь тоже отбрасывается. `label` профиля из `--agent` — исходная командная строка, поэтому `/profile` не печатает его в скобках (`isLabelFromAgentValue`). Значения аргументов видны только в `$CODELAB_HOME/profiles.json`.

### Токены

Токен WebSocket-профиля берёт общий `ProfileSecretSource` клиентского слоя; значение не попадает ни в вывод, ни в `profiles.json`. Ссылки двух видов:

- `env:<ИМЯ>` — переменная окружения; для `--agent ws://…` это `CODELAB_AGENT_TOKEN`.
- `secret:<имя>` — хранилище секретов агента (то же, что у CodeLab app): `run.dart` открывает `ClientSecretAccess` и отдаёт адаптер порта `ProfileSecrets` в `buildCliRuntime(profileSecrets:)`. Чтение каждый раз заново, без кэша; хранилище открывается лениво, только для профиля с `secret:`.

Профиль с `secret:` без значения перед подключением REPL, TUI, headless и `test-scenario` даёт в stderr `codelab: profile <id> has no stored secret value; connecting without a token.`, а с `--verbose` ещё и событие `connection_profile.token_secret_missing` (поле `profile_id`). `profiles show` печатает `token: env <ИМЯ>`, `token: secret <имя> (set|missing)` (наличие через `isSet`, значение не читается) или `token: unrecognized token reference (not supported in this version)`.

## Подкоманда `profiles`

`runProfilesCommand(args, store:, stdout:, stderr:, openSecrets:)` работает без запуска агента. `run.dart` перед ней вызывает `CodelabHome.ensureExists` и создаёт `JsonFileProfileStore(home.profilesFile)`.

| Форма | Что делает |
|---|---|
| `list` | таблица `id  описание`; пусто — подсказка `codelab profiles add <id> stdio:<command>` |
| `show <id>` | поля профиля: `id`, `type`, `command`, `args: N (values hidden)` (при нуле аргументов — `args: 0`), `env:` (только имена), `uri`, `token:` |
| `add <id> <agent>` | сохраняет профиль; значение — `stdio:…` или `ws://…` |
| `remove <id>` | удаляет профиль |

Проверки `add`: `embedded` и `default` как id или как значение — код `64` (`embedded is built in; use --agent embedded`, `default is the built-in agent; use --agent embedded`); id должен соответствовать `isValidProfileId` (строчные буквы, цифры, `.`, `_`, `-`, до 64 символов, начинается с буквы или цифры); неверная форма значения — `Invalid agent: use "stdio:<command> [args]", ws:// or wss://.`. Неизвестный профиль у `show` и `remove` — `codelab: Unknown agent profile "<id>".` и код `1`.

Прежняя запись `default` в `profiles.json` игнорируется с одним предупреждением в stderr при `profiles list`, `profiles show default` и `-a default` (`ignoredDefaultProfileWarning`); `profiles remove default` удаляет её; файл автоматически не меняется.

Снимок (бинарь `codelab`, пустой `CODELAB_HOME`):

```bash
codelab profiles add demo "stdio:codelab-agent serve --stdio"
codelab profiles add side ws://127.0.0.1:9/acp
codelab profiles list
codelab profiles show side
```

```text
Saved profile demo.
Saved profile side.
demo  stdio: codelab-agent (2 arguments)
side  ws: ws://127.0.0.1:9/acp
id: side
type: webSocket
uri: ws://127.0.0.1:9/acp
token: env CODELAB_AGENT_TOKEN
```

Попытка сохранить зарезервированное имя:

```bash
codelab profiles add default stdio:x
```

```text
codelab: default is the built-in agent; use --agent embedded
```

Код `64`.

## Домашний каталог

`CodelabHome.resolve(environment)` (`home.dart`) — единственное место путей CLI. Он оборачивает общую `resolveCodelabHome` из `codelab_client_io` (то же правило, что у CodeLab app) и переводит `CodelabHomeException` в `UsageError` с тем же текстом (код `64`). `CODELAB_HOME` вида `~` и `~/…` раскрывается в `HOME`, иначе в `USERPROFILE`; `~user/…`, `~\…` и тильда без домашнего каталога — ошибка. Агентский `codelabHomeOf` даёт тот же результат, но CLI не импортирует `codelab_agent_*`, поэтому одинаковость проверяют `test/home_test.dart` и `test/config_command_test.dart`.

| Свойство | Файл |
|---|---|
| `profilesFile` | `profiles.json` |
| `historyFile` | `cli_history` |
| `recentProjectsFile` | `recent_projects.json` (общий с app) |

`ensureExists` создаёт каталог с правами `0700`: в нём история промптов. В `dart:io` нет API прав доступа, поэтому вызывается `chmod 700`; в Windows права не меняются. Вызывают его только интерактивные режимы и `profiles`.

### История ввода

`HistoryFile` (`home.dart`) хранит историю REPL и TUI в `$CODELAB_HOME/cli_history`. Файл создаётся с правами `0600` до записи содержимого: промпты могут содержать то, что не должны читать другие пользователи машины. Формат — `encodeHistory`: по записи на строку в виде JSON-строки. Один файл на REPL и TUI; запись идёт после каждой отправки.

### Недавние проекты

Только REPL и TUI (в том числе с `--resume` и `--continue`) пишут папку сессии в общий с app `recent_projects.json` через `JsonFileRecentProjectsStore`. `_recordRecentProject` передаётся обратным вызовом `onConnected` и вызывается после успешного `connect` и до `openCliSession`. Запуск, не подключившийся к агенту (нет модели, сбой запуска, мастер первого запуска завершил процесс), папку не пишет. Метод не бросает: сбой записи не меняет код выхода; с `--verbose` — одна строка `codelab: cannot record a recent project: <тип ошибки>`, а нечитаемый файл не перезаписывается. Список CLI не показывает. Каждый тест, запускающий REPL или TUI, должен иметь свой временный `CODELAB_HOME`.

## Открытие сессии

`openCliSession(workspace, cwd, resume:, last:)` (`session_setup.dart`) общая для REPL, TUI и headless:

- без флагов — `workspace.newSession(cwd:)`;
- `--resume <id>` — `workspace.loadSession(SessionId(id), cwd:)`;
- `--continue` — последняя по `updatedAt` сессия папки из `workspace.current.sessions`; нет такой — `SessionSetupError('No session to continue in <папка>.')`.

`applyConfigFlag(session, name, value)` до первого промпта ставит опцию `model` или `mode`: опция ищется по id, затем по категории; неизвестная опция или значение — `SessionSetupError` (`The agent has no "model" option.`, `Unknown model "x". Available: …`) без запроса к агенту, текущее значение не отправляется. `SessionSetupError` печатается как есть, без префикса `cannot start the agent`: агент запустился, не сошлись аргументы.

## Алиас `codelab serve`

`codelab serve …` — переходный алиас на `codelab-agent serve …`: скрипты и настройки редакторов запускали Python-агента командой `codelab serve --stdio`. `parseCliArgs` распознаёт `serve` по первому слову до `ArgParser` и возвращает `CliCommand.serveAlias`; ни один флаг `codelab` к алиасу не применяется. `run.dart` сразу вызывает `runServeAlias` (`serve_alias.dart`) — домашний каталог, профили и логгер не открываются.

Алиас запускает отдельный бинарь `codelab-agent` (`Process.start` в режиме `inheritStdio`), а не встроенный сервер: протокольного кода здесь нет, и кадры ACP совпадают с прямым запуском.

- **Поиск.** `locateAgentExecutable`: каталог, где лежит `codelab`, затем абсолютные записи `PATH`. Относительные и пустые записи пропускаются (текущая папка не должна подставить свой `codelab-agent`); кандидат, канонический путь которого совпал с самим `codelab`, отбрасывается. Чистая функция: файловая система приходит замыканиями.
- **Код выхода** — код агента (`serveAliasExitCode`: смерть от сигнала `N` — `128 + N`); не найден или сбой запуска — `1`; предупреждение (`serveAliasWarning`) — одна строка в stderr до запуска, stdout алиас не пишет.
- **Рекурсия.** Переменная-маркер `CODELAB_SERVE_ALIAS_ACTIVE` в окружении дочернего процесса: если `codelab serve` видит её у себя, значит `codelab-agent` — обёртка вокруг `codelab serve`, и запуск отклоняется (`serveAliasRecursion`).
- **Сигналы.** Через `SignalSeam`: `SIGTERM` пересылается агенту, `SIGHUP` тоже, `SIGINT` перехватывается без пересылки (терминал доставляет его всей группе).

Алиас временный: `codelab --help` его не упоминает. Что использовать вместо него — [переход с Python-агента](../../../docs/user/migrating-from-python-agent.md#профили-и-скрипты-с-codelab-serve).

## Тесты

`test/profiles/` (`profile_arg_test`, `profiles_command_test`, `profile_token_test`, `cli_profile_secrets_test`), `test/home_test.dart`, `test/session_setup_test.dart`, `test/serve_alias_test.dart`; процессные — `test/e2e/connect_profiles_test.dart`, `recent_projects_test.dart`, `serve_alias_test.dart`, `codelab_home_tilde_test.dart`. Хранилища профилей и истории в модульных тестах — в памяти (`test/support/memory_profile_store.dart`).

## Смотрите также

- [Глава 02: выбор режима и коды выхода](02-startup-and-composition.md)
- [`codelab_client_io`](../../../packages/dart/codelab_client_io/README.md) — `JsonFileProfileStore`, `JsonFileRecentProjectsStore`, `resolveCodelabHome`
- [Каталог `CODELAB_HOME`](../../../docs/ops/codelab-home.md) — общие файлы с CodeLab app
- Спецификация [`codelab-cli`](../../../openspec/specs/codelab-cli/spec.md): «Профили подключения CLI», «Домашний каталог CLI CODELAB_HOME», «Недавние проекты CLI», «Алиас codelab serve»
