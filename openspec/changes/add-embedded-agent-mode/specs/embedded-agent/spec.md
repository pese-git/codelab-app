## ADDED Requirements

### Requirement: Пакет codelab_embedded и его точки входа
Встроенный агент SHALL собираться пакетом `packages/dart/codelab_embedded` — мостом между сторонами без префикса стороны (ADR-0002; design.md, D1). У пакета три точки входа (D2):
- основной барель `package:codelab_embedded/codelab_embedded.dart` SHALL экспортировать `createEmbeddedAgent`, `EmbeddedAgent`, `EmbeddedAgentConfig`, `EmbeddedHostServices`, `EmbeddedAgentOpener`, `EmbeddedAgentConfigException`, а из ядра — только `Logger` и `LogLevel`. Он НЕ SHALL транзитивно тянуть `dart:io`, `dart:isolate`, `package:codelab_agent_io/` и `package:codelab_acp_transports/io.dart`;
- `package:codelab_embedded/io.dart` SHALL давать `localEmbeddedAgentOpener` для настольных хостов;
- `package:codelab_embedded/testing.dart` SHALL давать `scriptedEmbeddedAgentOpener` (требование «Сценарий модели для тестов»).

Основной барель НЕ SHALL ссылаться на файлы `lib/io.dart`, `lib/src/io/`, `lib/testing.dart` и `lib/src/testing/`. Пакет НЕ SHALL зависеть от `codelab_client_*` и Flutter.

#### Scenario: Основной барель собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_embedded/test/web_smoke/main.dart` компилируется в JavaScript и в WebAssembly без ошибок. Она импортирует только основной барель `codelab_embedded`, `package:codelab_agent_core/codelab_agent_core.dart`, `package:codelab_agent_core/testing.dart` и `package:http/http.dart` и вызывает `createEmbeddedAgent` с профилем `embedded-cli`, суженным до памяти (`shellExec` и `sessionPersistence` выключены), на `MemoryExecutionEnv` (design.md, D3). Компиляция доказывает, что основной барель `codelab_embedded` не тянет `dart:io`

#### Scenario: dart:io в основном бареле
- **WHEN** файл `packages/dart/codelab_embedded/lib/src/agent.dart` импортирует `dart:io` или `package:codelab_agent_io/`
- **THEN** `fvm dart run melos run guard` падает и называет файл, строку и URI

### Requirement: Сборка встроенного агента
`createEmbeddedAgent(config:, services:)` SHALL собирать ядро только через `buildAgentCore` (HOST-6). Профиль хоста SHALL браться как `HostProfile.of(config.hostProfile)`, суженный ключами `profile.<hostProfile>.*` конфигурации. Соединение SHALL быть парой `InProcessAcpLink`: агентский конец обслуживает `AcpAgentServer`, клиентский возвращается как `EmbeddedAgent.clientTransport` (design.md, D2, D6). Конфигурация сервера:
- `agentInfo` — `name: codelab-agent`, `title: CodeLab Agent`, версия пакета (D4);
- `detachGrace` — ноль;
- для профилей `embedded-*` — `localEnv` (требование «Локальное исполнение и containment»).

`createEmbeddedAgent` SHALL принимать только профили `embedded-*`: иной профиль (в том числе `agent-serve`) SHALL завершать возвращённый `Future` ошибкой `HostWiringException` до создания ресурсов, без синхронного исключения (D2, D8).

В `lib/` пакета НЕ SHALL встречаться `ToolRegistry(`, `Agent(` и `AgentRuntime(`. Методов, полей и состояний ACP встроенный режим НЕ SHALL добавлять.

#### Scenario: Ход через встроенного агента
- **WHEN** тест открывает агента `scriptedEmbeddedAgentOpener` со сценарием «ответить текстом `hello`» и профилем `embedded-cli`, а затем через `clientTransport` выполняет `initialize`, `session/new` с временным `cwd` и `session/prompt`
- **THEN** клиент получает `agent_message_chunk` с `hello` и ответ `session/prompt` с `stopReason: end_turn`, а `initialize` возвращает `agentInfo.name == "codelab-agent"`

#### Scenario: Профиль agent-serve через основной барель
- **WHEN** хост вызывает `createEmbeddedAgent` с `hostProfile: agent-serve`
- **THEN** вызов возвращает `Future`, который завершается `HostWiringException`; ядро, пара транспортов и сервер не создаются

#### Scenario: Ручная сборка ядра запрещена
- **WHEN** файл в `packages/dart/codelab_embedded/lib/` содержит `AgentRuntime(`
- **THEN** `host_assembly_guard_test.dart` падает и называет файл и строку

### Requirement: Конфигурация и секреты встроенного агента
`localEmbeddedAgentOpener` SHALL загружать конфигурацию загрузчиком `ConfigLoader` из `codelab_agent_io` (задача 8.5): `cwd` — папка проекта из `open`, окружение — окружение процесса хоста. Своего загрузчика у пакета НЕ SHALL быть (design.md, D5). При невалидном конфиге открыватель SHALL бросать `EmbeddedAgentConfigException` со всеми проблемами загрузчика. Текст исключения SHALL содержать строки `<location>: [<key>: ]<message>` в форме `config check` и последней строкой подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — `codelabHomeOf(environment)` (design.md, D5; D13, п. 2). Значения секретов и подставленных переменных НЕ SHALL в него попадать. Сетевые клиенты и процессы до этой точки НЕ SHALL создаваться.

Предупреждения загрузчика открыватель SHALL писать в лог и тогда, когда конфиг невалиден, — до броска исключения, как бинарь (design.md change `add-agent-configuration`, D16). Профиль хоста открыватель SHALL проверять первым шагом, до загрузки конфига и создания ресурсов (design.md, D2). Окружение процесса открыватель SHALL брать только из своего параметра `environment`: из него же — окружение процессов `exec` и MCP-серверов stdio.

Резолвер секретов SHALL быть один на агента и строиться только через `openHostSecrets` из `codelabHomeOf(environment)`, окружения, `HostSettings.secretsBackend` и признака отладки. Его SHALL получать и функция модели, и `AgentCoreServices.secrets` (design.md change `add-agent-secret-store`, D15). Функцию модели из `CoreConfig` (ключи провайдеров, шаблоны заголовков, маршруты) SHALL строить та же публичная функция `codelab_agent_core`, что у `codelab-agent serve`; своей проекции конфига у пакета НЕ SHALL быть (design.md, D1, в).

Переменная `CODELAB_TEST_SECRET_STORE=<каталог>` SHALL выбирать бэкенд `file` с путём `<каталог>/secrets.yaml` (`backend.id == "file"`, причина выбора `test store`) только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`. В обычной сборке она НЕ SHALL читаться. Разбор переменной и проверка define SHALL жить в `codelab_agent_io` рядом с загрузчиком (design.md, D5).

#### Scenario: Ключ провайдера из secrets.yaml
- **WHEN** временный `CODELAB_HOME` содержит `config.yaml` с провайдером `openai-compatible` на адресе `MockClient` теста, `api_key_secret: codelab/p` и `secrets.backend: file`, а `secrets.yaml` (права `0600`) — значение `codelab/p`; открыватель получает этот `CODELAB_HOME` и проводит ход
- **THEN** запрос к провайдеру несёт заголовок `Authorization: Bearer <значение>`, а ни одна запись лога и ни одно событие клиента не содержат значения

#### Scenario: Невалидный конфиг
- **WHEN** проектный `.codelab/config.yaml` содержит `budget.max_steps: 0`, и открыватель вызывается для этого `cwd`
- **THEN** бросается `EmbeddedAgentConfigException`, текст которого называет файл, строку и ключ `budget.max_steps`; HTTP-клиент не создан, ни один процесс не запущен

#### Scenario: Нет конфигурации
- **WHEN** `CODELAB_HOME` пуст, и открыватель вызывается
- **THEN** бросается `EmbeddedAgentConfigException` с проблемой загрузчика и подсказкой `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`

#### Scenario: Нет ключа провайдера
- **WHEN** конфиг валиден и задаёт провайдера модели по умолчанию с `api_key_secret: codelab/p`, а секрет не задан ни в одном бэкенде
- **THEN** открыватель возвращает агента без исключения; первый `session/prompt` завершается ошибкой провайдера, текст которой называет `codelab/p` и не содержит значения, как у `codelab-agent serve` (D13, п. 2)

#### Scenario: Тестовое хранилище только в тестовой сборке
- **WHEN** процесс собран с `-DCODELAB_ALLOW_TEST_SECRETS=true`, окружение содержит `CODELAB_TEST_SECRET_STORE=<tmp>/s`, а `<tmp>/s/secrets.yaml` (права `0600`) — ключ провайдера
- **THEN** ход использует этот ключ, `secrets.backend.selected` называет бэкенд `file`; без define та же переменная даёт `config.env.unknown`, и каталог не читается

### Requirement: Локальное исполнение и containment
В профилях `embedded-app-desktop` и `embedded-cli` файлы и команды встроенного агента SHALL исполняться через `LocalExecutionEnv` хоста (`AcpServerConfig.localEnv`), даже если клиент объявил `fs` и `terminal`: `fs/*` и `terminal/*` клиенту НЕ SHALL отправляться (design.md, D4). Каждый путь и каталог команды SHALL ограничиваться корнем `cwd` сессии через `BoundedEnv` ядра (ENV-2). Выход за корень SHALL давать результат инструмента с ошибкой `outsideWorkspace`, без чтения, записи и запуска процесса.

#### Scenario: Файлы без fs/* клиента
- **WHEN** клиент объявил `fs.readTextFile`, `fs.writeTextFile` и `terminal`, а сценарий модели в профиле `embedded-cli` с режимом `bypass` зовёт `read` и `exec` в `cwd` сессии
- **THEN** клиент не получает ни одного запроса `fs/*` и `terminal/*`, а результаты вызовов содержат содержимое файла и вывод команды

#### Scenario: Путь вне рабочей папки
- **WHEN** сценарий модели зовёт `read` с путём `../outside.txt` или через symlink, указывающий наружу `cwd`
- **THEN** вызов завершается ошибкой `outsideWorkspace`, файл снаружи не прочитан, ход продолжается

### Requirement: Разрешения во встроенном режиме
Встроенный агент SHALL спрашивать одобрение тем же `session/request_permission` через клиентский конец (`AcpPermissionGate`), что и внешний агент. Решение SHALL применяться только к своему `toolCallId` (PERM-4). Пакет НЕ SHALL принимать извне `PermissionGate` или режим разрешений через основной барель и `io.dart`. Режим новой сессии задаёт профиль или `permissions.mode` конфига (HOST-7), а `autopilot` через конфиг недоступен (CFG-4).

#### Scenario: Отказ клиента
- **WHEN** в режиме `standard` сценарий модели зовёт `write`, а клиент отвечает на `session/request_permission` вариантом `reject_once`
- **THEN** файл не изменён, вызов завершается отказом с причиной, ход продолжается

#### Scenario: Одобрение клиента
- **WHEN** тот же вызов `write` одобрен вариантом `allow_once`
- **THEN** файл записан в `cwd` сессии, следующий вызов `write` с другим `toolCallId` снова спрашивает

### Requirement: Жизненный цикл встроенного агента
`EmbeddedAgent.dispose()` SHALL быть идемпотентным и устойчивым к ошибкам своих шагов: ошибка одного шага НЕ SHALL отменять следующие, а `closed` SHALL завершаться в любом случае (design.md, D6). Он SHALL выполнить `AcpAgentServer.shutdown` и только после этого:
- освободить runtime, MCP-серверы сессий и созданный хостом HTTP-клиент;
- закрыть агентский конец.

`shutdown` отвечает на новые запросы `-32603`, переводит ожидающие разрешения в `cancelled` → отказ, отменяет ходы и дожидается `TurnEnded`, дописывает журнал.

Закрытие клиентского конца клиентом SHALL запускать тот же `dispose`. `EmbeddedAgent.closed` SHALL завершаться после него.

Необработанная ошибка асинхронной работы агента или завершение `serve` с ошибкой SHALL перехватываться зоной агента. На первую такую ошибку агент SHALL:
- записать `embedded.agent.failed {error_class}` уровня `error`, без текста ошибки;
- закрыть агентский конец, чтобы клиентский перешёл в `failed` с кодом `disconnected`;
- выполнить `dispose`.

Вторая и последующие ошибки зоны, а также ошибки, пришедшие во время уже начатой остановки (`dispose`, закрытие клиентом или отказ), НЕ SHALL запускать повторный отказ: агент SHALL записать `embedded.agent.late_error {error_class}` уровня `warning`, без текста ошибки. Сбой шага `dispose` SHALL записываться `embedded.agent.dispose_failed {step, error_class}` уровня `error`, без текста. Поля событий — snake_case; `error_class` — класс ошибки (design.md, D6).

Ошибка агента, в том числе поздняя, НЕ SHALL доходить до обработчика ошибок приложения. После `dispose` клиент НЕ SHALL получать кадров этого агента.

#### Scenario: dispose при ожидающем разрешении
- **WHEN** ход ждёт ответа на `session/request_permission` для `write`, и хост вызывает `dispose()`
- **THEN** вызов `write` завершается отказом, ход — `cancelled`, журнал сессии в `$CODELAB_HOME/sessions` содержит итоговую запись хода, клиентский транспорт в `failed` с `disconnected`, повторный `dispose()` завершается без ошибок

#### Scenario: Клиент закрыл соединение
- **WHEN** клиент вызывает `close()` своего конца во время хода
- **THEN** ход отменяется, `closed` завершается, MCP-процессы сессии остановлены

#### Scenario: Ошибка внутри агента
- **WHEN** тестовая функция модели бросает ошибку асинхронно вне `Future` хода
- **THEN** клиентский транспорт переходит в `failed` с `disconnected`, лог содержит `embedded.agent.failed` уровня `error` с единственным полем `error_class`, без текста ошибки, тестовый обработчик ошибок зоны приложения ничего не получает

#### Scenario: Поздняя ошибка не запускает повторный отказ
- **WHEN** после первой ошибки в зоне агента, пока идёт остановка, тестовая функция модели асинхронно бросает вторую ошибку
- **THEN** лог содержит ровно одно `embedded.agent.failed` и одно `embedded.agent.late_error` уровня `warning` с единственным полем `error_class`, без текста ошибки; `dispose` выполнен один раз, `closed` завершён, тестовый обработчик ошибок зоны приложения ничего не получает

### Requirement: Сценарий модели для тестов
`scriptedEmbeddedAgentOpener` (`package:codelab_embedded/testing.dart`) SHALL открывать агента со сценарием модели — блоком `llm` формата фикстур (`agent-core-architecture` §14). Разбор сценария и слой провайдеров сценария SHALL быть тем же кодом `codelab_agent_io`, что у `codelab-agent serve --llm-script` (design.md, D8). Только этот открыватель SHALL принимать профиль `agent-serve` (файлы и команды через клиента, как у бинаря по stdio) и тестовый режим разрешений. Основной барель и `io.dart` НЕ SHALL принимать функцию модели или сценарий.

#### Scenario: Сценарий бинаря и встроенного агента разбирается одинаково
- **WHEN** один и тот же файл `test/e2e/llm_scripts/*.json` разбирается для `codelab-agent serve --llm-script` и для `scriptedEmbeddedAgentOpener`
- **THEN** оба получают одинаковый список моделей сценария, а невалидный файл даёт одинаковый текст ошибки с путём поля

### Requirement: Нагрузка встроенного агента на UI-isolate
Пакет SHALL содержать замер `benchmark/stream_latency_benchmark.dart`. Он прогоняет ход с 10 000 чанков ответа через встроенного агента и клиентскую проекцию `ClientWorkspace` в одном isolate и печатает p50, p99 и максимум задержки цикла событий (design.md, D11). Решение по критериям SHALL фиксироваться в design.md change с числами, машиной и режимом сборки:
- p99 > 8 мс или максимум > 50 мс — ядро переносится в отдельный isolate (`IsolateAcpLink`);
- иначе остаётся `InProcessAcpLink`.

Разбор журнала JSONL при `session/load` в `dart:io`-хостах SHALL выполняться через `Isolate.run`, с тем же реплеем, что до переноса.

#### Scenario: Замер печатает метрики
- **WHEN** запускается `fvm dart run packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart`
- **THEN** вывод содержит число чанков `10000`, p50, p99 и максимум задержки в миллисекундах и время хода

#### Scenario: Реплей после переноса разбора
- **WHEN** журнал с 1000 записей загружается `session/load` до и после переноса разбора в `Isolate.run`
- **THEN** последовательности кадров реплея совпадают
