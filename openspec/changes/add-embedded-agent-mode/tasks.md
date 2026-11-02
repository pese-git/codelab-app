Задачи идут парами «красный тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование и сценарий спецификации этого change и решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent` и новый пакет `codelab_embedded` (design.md, D1);
- `[protocol]` — `codelab_acp_*` и `codelab_agent_acp` (зона `acp-protocol-engineer` по `CLAUDE.md`);
- `[client]` — `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `codelab_ui`;
- `[docs]` — `docs/architecture/**`, `README.md`, корневой `AGENTS.md`, вложенные `AGENTS.md`.

Правила сторожа (`codelab_architecture_tests`) пишет исполнитель той итерации, в которой появляется ограничиваемый код.

Итерации — по design.md, D12. Каждая итерация — отдельный PR:
- итерация 0 — группа 0, документы;
- итерация 1 — группа 1, встроенный агент отвечает на ход в памяти;
- итерация 2 — группа 2, настоящий хост: конфиг, секреты, журнал, жизненный цикл;
- итерация 3 — группа 3, CLI;
- итерация 4 — группа 4, codelab-app;
- итерация 5 — группа 5, замер 7.8 и разбор журнала в isolate;
- итерация 6 — группа 6, документы и Definition of Done.

Итерации 3 и 4 независимы друг от друга после итерации 2. Открытых вопросов нет: решения пользователя 2026-11-02 — design.md, D13. Решение L4 (отмена подключения в app без нового API `codelab_client_core`, D6) пользователь подтверждает при старте итерации 4.

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` (для app — `fvm flutter analyze`) затронутых пакетов;
- `fvm dart test` затронутых пакетов;
- `fvm dart run melos run guard`, если меняются импорты или `pubspec.yaml`.

Полный `melos run check` — в CI pull request. `test:e2e:app:*` в feature-ветке не запускаются (`AGENTS.md` §21).

## 0. Документы (итерация 0)

- [x] 0.1 `[docs]` `agent-core/13-acp-adapter.md` §13.1 — поле `AcpServerConfig.localEnv` в эскизе и правило: при заданном `localEnv` env сессии даёт хост, `fs/*` и `terminal/*` не отправляются (design.md, D4). **Сделано при подготовке change.**
- [x] 0.2 `[docs]` `dart-agent-and-clients/09-12-stage-7-embedded.md` — под эскизом API отмечены уточнения design.md, D2, D5, D8: `CoreConfig` вместо `ProviderConfig`, один открыватель вместо `loadEmbeddedAgentConfig` и `desktopHostServices`, сценарий модели через `testing.dart` вместо dart-define, `memoryHostServices` — этап 10. **Сделано при подготовке change.**

## 1. Встроенный агент отвечает на ход в памяти (итерация 1)

- [x] 1.1 `[agent]` Тест `codelab_agent_core/test/host/host_profile_test.dart` и golden `test/host/profiles/embedded-app-desktop.golden.json` (agent-runtime «Профили хостов и сужение», сценарий «Профиль встроенного агента приложения»; D4). Красный: `HostProfile.of('embedded-app-desktop')` бросает `ArgumentError`.
- [x] 1.2 `[agent]` Профиль `embedded-app-desktop` в `host_profile.dart` с причинами по §10.4.
- [x] 1.3 `[protocol]` Тесты `codelab_agent_acp/test/` (agent-acp-server «Локальное окружение сессии от хоста», все три сценария; D4):
  - клиент объявил `fs`/`terminal`, сервер с `localEnv` не шлёт `fs/*`/`terminal/*`;
  - `write` в `standard` по-прежнему спрашивает клиента;
  - без `localEnv` — прежние кадры;
  - `fileListing` при `localEnv` без листинга — `HostWiringException`.

  Красный: поля `localEnv` нет.
- [x] 1.4 `[protocol]` `AcpServerConfig.localEnv` и ветка в `_wire` (`agent_server.dart`). Doc-комментарии по-русски со ссылкой на D4 и §13.1.
- [x] 1.5 `[agent]` Тест `codelab_agent_io/test/scripted/llm_script_test.dart` — случаи `apps/codelab_agent/test` про разбор `--llm-script` и слой провайдеров сценария переносятся на новый API (embedded-agent «Сценарий модели для тестов», сценарий «Сценарий бинаря и встроенного агента разбирается одинаково»; D8). Красный: API нет в `codelab_agent_io`.
- [x] 1.6 `[agent]` Перенести `LlmScript` и `_withScriptedProviders` в `codelab_agent_io/lib/src/scripted/` (`LlmScriptException` вместо `UsageError`); `apps/codelab_agent` переводит исключение в код `64`. Тесты бинаря (`llm_scripts_load_test.dart`, `agent_host_*_test.dart`, процессные) остаются зелёными без правок ожиданий.
- [x] 1.7 `[agent]` Сторож до кода пакета (workspace-architecture «Автоматический сторож границ пакетов», сценарии «Основной барель встроенного агента импортирует IO-пакет», «Встроенный агент собирает ядро вручную», «Зависимость моста встроенного агента вне allowlist»; D3):
  - два правила `packages/dart/codelab_embedded` в `rules.dart` вместо комментария `stage 7`;
  - `embeddedAllowlist` и тест в `pubspec_allowlist_test.dart`;
  - сканирование `packages/dart/codelab_embedded/lib` в `host_assembly_guard_test.dart`;
  - негативные тесты на временном пакете.

  Красный: пакета нет, тест allowlist не находит `pubspec.yaml`.
- [x] 1.8 `[agent]` Тесты `packages/dart/codelab_embedded/test/embedded_agent_test.dart` на `scriptedEmbeddedAgentOpener` и `MemorySessionStore`/временном каталоге (embedded-agent:
  - «Сборка встроенного агента», сценарий «Ход через встроенного агента»;
  - «Локальное исполнение и containment», оба сценария;
  - «Разрешения во встроенном режиме», оба сценария;
  - D2, D4).

  Красный: пакета нет.
- [x] 1.9 `[agent]` Пакет `packages/dart/codelab_embedded`:
  - `pubspec.yaml` по `embeddedAllowlist`, запись в `workspace:` корневого `pubspec.yaml`;
  - основной барель (`createEmbeddedAgent`, `EmbeddedAgent`, `EmbeddedAgentConfig`, `EmbeddedHostServices`, `EmbeddedAgentOpener`, `EmbeddedAgentConfigException`, реэкспорт `Logger`/`LogLevel`);
  - `lib/testing.dart` (`scriptedEmbeddedAgentOpener`);
  - вложенный `AGENTS.md` (назначение, границы, TDD, готовность итерации — §9.0, правило 7).

  Сборка — только `buildAgentCore`, сервер на `InProcessAcpLink` с `agentInfo` бинаря и `detachGrace: zero` (D2, D4).
- [x] 1.10 `[agent]` Web-smoke `packages/dart/codelab_embedded/test/web_smoke/main.dart` и строка в скрипте `web-compile` корневого `pubspec.yaml` (workspace-architecture «Границы пакетов monorepo», сценарий «Основной барель встроенного агента собирается для web»; embedded-agent «Пакет codelab_embedded и его точки входа», сценарий «Основной барель собирается для web»; D3). Красный: файла нет, `web-compile` падает на отсутствующей точке входа после правки скрипта.

- [x] 1.11 `[protocol]` По ревью итерации 1 (agent-acp-server «Локальное окружение сессии от хоста», сценарии «Несуществующий cwd при localEnv», «Команда в standard спрашивает клиента»; D4):
  - тест: при `localEnv` `session/new` и `session/load` с несуществующим `cwd` → `-32602`, сессия не создана; красный — сейчас `_checkCwd` смотрит только `localListing`;
  - `_checkCwd` проверяет `cwd` листингом `localEnv(cwd)`, если `localEnv` задан;
  - тест: `exec` в `standard` при `localEnv` спрашивает клиента `session/request_permission`, `terminal/create` не уходит;
  - doc-комментарий `localEnv`: фабрика вызывается с `/` при создании сервера и должна быть без побочных эффектов.
- [x] 1.12 `[agent]` По ревью итерации 1, пары «тест → правка» (embedded-agent «Сборка встроенного агента», сценарий «Профиль agent-serve через основной барель»; «Локальное исполнение и containment»; «Разрешения во встроенном режиме»; «Жизненный цикл встроенного агента»; D2, D6, D8):
  - тесты ветки `agent-serve` в `scriptedEmbeddedAgentOpener` (файлы через клиента) и отказа `createEmbeddedAgent` на `agent-serve` через `Future`, без синхронного исключения; `createEmbeddedAgent` — `async`;
  - `EmbeddedHostServices.localEnv` — non-null тип;
  - устойчивый `dispose`: каждый шаг в своём `try`, `closed` в `finally`, ошибка `serve` логируется без текста (D6); тест с падающим шагом;
  - утечка при `start()`: если `link.agent.start()` бросает, ядро и пара транспортов освобождаются (D6, сборка п. 4); тест;
  - тесты `write` и `exec` вне корня (`../`, symlink) → `outsideWorkspace` без записи и запуска;
  - тест `dispose` при ожидающем разрешении: вызов отклонён, ход `cancelled`, повторный `dispose` без ошибок (полный сценарий с журналом JSONL — 2.5);
  - тексты ошибок и логов — по-английски (`AGENTS.md` §15);
  - doc-комментарий `lib/src/testing/scripted_opener.dart` (почему/для чего/как, D8).
- [x] 1.13 `[docs]` Правки артефактов change по двойному ревью итерации 1: web-smoke в спеках embedded-agent и workspace-architecture и D3 (импорты, профиль `embedded-cli`, JS и Wasm); поля `EmbeddedHostServices` и уточнения API в D2; устойчивый `dispose` и граница итераций 1/2 в D6; `-32602` для `cwd` и чистая фабрика `localEnv` в agent-acp-server и D4; место `LlmScript` в D8 и Risks; задачи 1.11, 1.12, 2.9.

## 2. Настоящий хост: конфиг, секреты, журнал, жизненный цикл (итерация 2)

- [x] 2.1 `[agent]` Тесты `codelab_embedded/test/io/local_opener_test.dart` с временным `CODELAB_HOME`, `MockClient` и окружением теста (embedded-agent «Конфигурация и секреты встроенного агента», сценарии «Ключ провайдера из secrets.yaml», «Невалидный конфиг», «Нет конфигурации»; D5):
  - ключ через `openHostSecrets` и `secrets.backend: file`;
  - ключ из `CODELAB_SECRET_*`;
  - `EmbeddedAgentConfigException` без значений, HTTP-клиент не создан;
  - журнал JSONL в `$CODELAB_HOME/sessions`;
  - сужение `profile.embedded-cli.*`.

  Красный: `io.dart` нет.
- [x] 2.2 `[agent]` `lib/io.dart` и `lib/src/io/`: `localEmbeddedAgentOpener`:
  - `ConfigLoader` и `codelabHomeOf`, затем `openHostSecrets`;
  - `createRoutedStreamFunction` и `StaticModelCatalog`;
  - `JsonlSessionStore`, `LocalExecutionEnv`, `ProjectFilesLoader`;
  - `McpClientConnector` (stdio и streamable HTTP);
  - `createEmbeddedAgent`.

  Ресурсы создаются после успешной загрузки конфига.
- [x] 2.3 `[agent]` Тест `codelab_agent_io/test/secrets/host_secrets_test.dart`: `openHostSecrets(testStorePath:)` даёт `FileSecretStore` по пути с `backend.id == "file"`. Процессный тест `codelab_embedded/test/io/test_secret_store_process_test.dart` запускает `fvm dart run -DCODELAB_ALLOW_TEST_SECRETS=true` и проверяет обратный случай без define (embedded-agent, сценарий «Тестовое хранилище только в тестовой сборке»; D5). Красный: параметра нет.
- [x] 2.4 `[agent]` Параметр `testStorePath` (путь к `secrets.yaml`, причина выбора `test store`) у `openHostSecrets` и `openSecretStore`; `CODELAB_TEST_SECRET_STORE` читается только при `const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')` — разбор и проверка define в `codelab_agent_io` рядом с загрузчиком (перенос из открывателя — задача 2.10; D5). `skip` у обычных тестов `codelab_agent_io` про `CODELAB_TEST_SECRET_STORE` оставлен осознанно: в обычной сборке define выключен, ветку с define покрывает процессный тест `codelab_embedded/test/io/test_secret_store_process_test.dart`. Парный тест «под define» в `config_loader_test.dart` удалён — в обычном `fvm dart test` он не исполнялся бы.
- [x] 2.5 `[agent]` Тесты `codelab_embedded/test/lifecycle_test.dart` (embedded-agent «Жизненный цикл встроенного агента», все три сценария; D6):
  - `dispose` при ожидающем разрешении — отказ, `cancelled`, итог хода в журнале;
  - повторный `dispose`;
  - закрытие клиентом — `closed`, MCP-процесс fake-сервера остановлен;
  - асинхронная ошибка в зоне — клиентский `failed`/`disconnected`, `embedded.agent.failed` уровня `error` только с `error_class`, без текста ошибки; внешняя зона и обработчик ошибок приложения ничего не получают;
  - ошибка `serve` — тот же путь: `embedded.agent.failed`, закрытие агентского конца, `dispose`.

  Красный: зоны `runZonedGuarded` и события `embedded.agent.failed` нет (устойчивый `dispose` уже есть с итерации 1, задача 1.12).
- [x] 2.6 `[agent]` Охраняемая зона `runZonedGuarded` вокруг `serve` и асинхронной работы агента; при отказе — `embedded.agent.failed {error_class}` без текста, закрытие агентского конца, `dispose` (D6, «Отказ агента»). Подписка на закрытие агентского конца, порядок `dispose` по D6, `closed`.
- [x] 2.7 `[agent]` Тест паритета профилей (agent-runtime, сценарий «Паритет профилей»; §10.12). Красный до 2.2, если ядро и сервер расходятся; иначе тест закрывает критерий и фиксируется ссылкой в PR. Написан как `codelab_embedded/test/profile_parity_test.dart`; по ревью итерации 2 паритет — свойство ядра, тест переносится в `codelab_agent_core/test/host/` (задача 2.10; D1, в).
- [x] 2.8 `[agent]` Рефакторинг по итогам итерации: общая часть сборки `apps/codelab_agent` и `codelab_embedded` сверена (D1, в). Сверено:
  - проекция `CoreConfig` → функция модели (ключи, `headerTemplates`, маршруты) совпадала строка в строку — выносится в одну публичную функцию `codelab_agent_core`, её зовут оба хоста (задача 2.10);
  - сценарий модели — уже общий, `codelab_agent_io/testing.dart` (2.9);
  - `openHostSecrets`, `ConfigLoader`, `codelabHomeOf`, `JsonlSessionStore`, `LocalExecutionEnv`, `ProjectFilesLoader`, `buildAgentCore` — вызовы готовых API, своей логики у хостов нет;
  - различия — только профиль, транспорт (`InProcessAcpLink` и `localEnv` против stdio/ws) и сценарий.

  Оставлено сознательно: проводка `McpClientConnector` (stdio из `codelab_agent_io`, HTTP из `codelab_agent_mcp`, около 12 строк) — общего пакета без нового ребра `codelab_agent_io` ↔ `codelab_agent_mcp` нет. Расхождение хостов на уровне ACP ловит `test-scenario --agent embedded` на корпусе фикстур (3.5–3.6).

- [x] 2.9 `[agent]` Вынести сценарий модели из основного бареля `codelab_agent_io` в `package:codelab_agent_io/testing.dart` (D8, «Где лежит `LlmScript`»; Risks «Сценарий модели в графе рабочей сборки»):
  - красный тест сторожа: основной барель `codelab_agent_io` не экспортирует и не импортирует `lib/src/scripted/`; импорт `codelab_agent_io/testing.dart` разрешён только `apps/codelab_agent`, `codelab_embedded/lib/src/testing/` и тестам;
  - перенос экспортов `LlmScript`, слоя провайдеров сценария и `CwdTrackingStore`; импорты бинаря и `codelab_embedded/testing.dart`;
  - тесты бинаря и `codelab_embedded` остаются зелёными без правок ожиданий.

  Выполняется до или вместе с 2.2: `io.dart` не появляется, пока сценарий в основном бареле.

- [x] 2.10 `[agent]` Исправления по двойному ревью итерации 2 и решениям пользователя 2026-11-02, пары «тест → правка» (embedded-agent «Конфигурация и секреты встроенного агента», «Жизненный цикл встроенного агента», сценарий «Поздняя ошибка не запускает повторный отказ»; agent-runtime, сценарий «Паритет профилей»; D1, в; D2; D5; D6):
  - общая функция модели в `codelab_agent_core` (имя по стилю ядра, ориентир `createConfiguredStreamFunction`): модульный тест ядра (ключи через `SecretResolver`, `headerTemplates`, маршруты), затем перевод `AgentHost.build` и открывателя `codelab_embedded` на неё; тесты бинаря и `codelab_embedded` зелёные без правок ожиданий;
  - перенос теста паритета профилей из `codelab_embedded/test/profile_parity_test.dart` в `codelab_agent_core/test/host/profile_event_parity_test.dart`; общий журнал хоста `openHostSessions` в `codelab_agent_io`; поле `source` у `ConfigUsageException`; `testSecretStorePath` в `environment_layer.dart`;
  - открыватель: `logConfigWarnings` до броска `EmbeddedAgentConfigException` (тест: невалидный конфиг с предупреждением — предупреждение в логе);
  - открыватель: проверка профиля первым шагом, до загрузки конфига и создания ресурсов (тест: неверный профиль — HTTP-клиент не создан, конфиг не читался);
  - окружение MCP-серверов stdio — `hostEnvironment` из `environment` открывателя, как у `exec` (тест на allowlist переменных);
  - разбор `CODELAB_TEST_SECRET_STORE` и проверка define — в `codelab_agent_io` рядом с загрузчиком; открыватель только передаёт `testStorePath`; `testStorePath` — путь к `secrets.yaml`, причина `test store`;
  - события: `embedded.agent.dispose_failed {step, error_class}` `error`, `failed {error_class}` `error`, `late_error {error_class}` `warning` — snake_case, без текста; `serve_failed` и `errorType` удалены из кода и тестов;
  - тест `late_error`: вторая ошибка зоны после первой — одно `failed`, одно `late_error`, один `dispose`;
  - сторож: закрыть дыру `io.dart` → `testing.dart` — `codelab_embedded/lib/io.dart` и `lib/src/io/` не ссылаются ни на `package:codelab_agent_io/testing.dart`, ни на собственные `lib/testing.dart` и `lib/src/testing/` (в том числе относительным импортом), иначе сценарий модели транзитивно попадает в рабочую сборку клиентов (D8); негативный тест на временном пакете;
  - NIT ревью (комментарии, имена, тексты по-английски) — без изменения поведения.
- [x] 2.11 `[docs]` Правки артефактов change по двойному ревью итерации 2: D1 (в) — общая функция модели ядра, паритет как тест ядра, осознанный дубль MCP; D2 — `HostWiringException` у клиента, профиль первым шагом, предупреждения при невалидном конфиге, единый `environment`; D5 — `testStorePath` и место разбора переменной; D6 — шов `serve`, таблица событий в snake_case, `late_error`, устаревший результат `open` у резолвера; D10 и Risks; спека embedded-agent (секреты, общая функция модели, `late_error`, сценарий); задачи 2.4, 2.7, 2.8, 2.10, 3.3–3.4, 4.3–4.4.

## 3. CLI (итерация 3)

- [x] 3.1 `[client]` Тесты `codelab_client_core` и `codelab_client_io` (acp-client-kit «Профили и резолверы транспорта», сценарии «Встроенный профиль без резолвера встроенного агента», «Встроенный профиль не сохраняется в profiles.json»; D7). Красный: фабрики `ConnectionProfile.embedded` нет.
- [x] 3.2 `[client]` `ConnectionProfile.embedded` (`EmbeddedProfile`) и `build_runner` для freezed. Ветки исчерпывающих `switch`:
  - `ConfigTransportResolver` — `false`/`UnsupportedConnectionProfileException`;
  - `JsonFileProfileStore` — `ArgumentError` при `save`, `FormatException` при чтении;
  - `describeProfile`, `/profile`, `profiles` CLI, `ScenarioAgent` — заглушки до 3.6.
- [x] 3.3 `[client]` Тесты `apps/codelab_cli/test/profiles/profile_arg_test.dart`, `profiles_command_test.dart`, `test/embedded_resolver_test.dart` (codelab-cli «Профили подключения CLI», сценарии «Профиль default сильнее встроенного агента», «Встроенный агент явно», «embedded нельзя сохранить профилем», «Без профиля и без конфига»; «Встроенный агент в CLI», сценарий «Невалидный конфиг встроенного агента»; D6):
  - `embedded` и без `--agent` → `EmbeddedProfile(embedded-cli)` при отсутствии `default`;
  - битый `profiles.json` → `64`;
  - резолвер сериализует `open`: `await prev.dispose()` перед новым открывателем;
  - устаревший результат: если подключение отменено (новый `open` или `close()`), пока открыватель работает, агент, вернувшийся позже, получает `dispose()` и не становится текущим (`AGENTS.md` §12; D6, «Резолвер клиента»);
  - `close()` ждёт `dispose`.

  Существующие тесты «embedded is 64» меняются на новые ожидания. Красный: `UsageError` на `embedded`.
- [x] 3.4 `[client]` `resolveAgentProfile`: без `--agent` — профиль `default`, если он есть в `profiles.json`, иначе `EmbeddedProfile(embedded-cli)`; битый файл — код `64` (D13, п. 1). `EmbeddedTransportResolver` в `lib/src/embedded_transport_resolver.dart` (только основной барель `codelab_embedded`): сериализация `open` через `await prev.dispose()`, `dispose()` у агента, вернувшегося после отмены подключения — новым `open` или `close()` (D6). `composition_root.dart` только связывает резолвер с `localEmbeddedAgentOpener` из `io.dart`. Флаг `--debug-secrets`. `EmbeddedAgentConfigException` → код `64` в `run.dart`. Ожидание `close()` резолвера в `CliRuntime.dispose` и в обработке сигналов. Правила сторожа CLI для `codelab_embedded/io.dart` и `testing.dart`, `cliAllowlist` += `codelab_embedded` (workspace-architecture, сценарий «IO-барель встроенного агента вне composition root»; D3). Шов `runCodelab(…, {EmbeddedAgentOpener? embeddedOpener})` (`lib/src/run.dart`) для тестовой точки входа (D8).
- [x] 3.5 `[client]` Тест `apps/codelab_cli/test/scenario/test_scenario_command_test.dart` (cli-scenario-driver «Команда test-scenario», сценарии «Корпус против встроенного агента», «Фикстура с fake MCP-серверами»; D8):
  - корпус `--agent embedded` без `FAIL`;
  - пропуски с причинами;
  - временные каталоги удалены.

  Красный: `embedded` даёт `64`.
- [x] 3.6 `[client]` `ScenarioAgent` для `EmbeddedProfile`: `scriptedEmbeddedAgentOpener` с `setup.llm`, `setup.profile ?? 'agent-serve'`, `setup.mode`, временными `sessions` и `CODELAB_HOME`; `AgentConnection` с `dispose` агента. Скрипт `conformance:embedded` в корневом `pubspec.yaml` и в шагах `check`.
- [x] 3.7 `[client]` E2E `cli/*` для `CODELAB_E2E_AGENT=embedded` (testing-quality «Встроенный режим в e2e и conformance», сценарий «E2E CLI против встроенного агента»; codelab-cli «Встроенный агент в CLI», сценарии «Отказ по умолчанию в headless», «Журнал дописан при SIGTERM», «Отладка секретов»; «Профили подключения CLI», сценарий «Без профиля по умолчанию запускается встроенный агент»; критерий `cli/connect-profiles-stdio-ws-embedded`, вариант `embedded`):
  - тестовая точка входа `test/e2e/support/embedded_cli_main.dart`;
  - вариант `embedded` в `support/e2e_agent.dart`;
  - скрипт `test:e2e:cli:embedded` в `check`.

  Это приёмочные ворота (исключение (б) §9.0): пишутся до закрытия итерации, не до каждой задачи.
- [x] 3.8 `[docs]` `apps/codelab_cli/AGENTS.md`:
  - зависимость `codelab_embedded`;
  - импорт `io.dart` только из `composition_root.dart`, `testing.dart` — только из `scenario/`;
  - `--debug-secrets`;
  - выбор без `--agent`.

  `09-11-stage-6-cli-mvp.md`: таблица `--agent` и DoD — `default` из `profiles.json`, если есть, иначе `embedded` (D13, п. 1).
- [x] 3.9 `[client]` Исправления по двойному ревью итерации 3 и решениям пользователя 2026-11-02 (U1–U4), пары «тест → правка» (codelab-cli «Профили подключения CLI», сценарий «profiles.json неверной структуры»; «Встроенный агент в CLI», сценарии «Отладка секретов», «Без --debug-secrets лог агента молчит», «Журнал дописан при SIGTERM», «Второй сигнал при зависшем dispose»; cli-scenario-driver «Команда test-scenario», сценарии «Без --agent и без профиля default», «Без --agent при профиле default»; «Вывод и коды выхода test-scenario», сценарии «Все фикстуры пропущены», «Фильтр не выбрал фикстур»; D6, «Выход CLI»; D13, п. 7–10):
  - **U1**: `test-scenario` без `--agent` — `resolveAgentProfile` без `embeddedByDefault: false`; `noDefaultProfileMessage` и параметр удаляются, если больше не нужны; синопсис и справка `test-scenario` — `[--agent <profile>]`; тест «без `--agent` и без `default` — встроенный агент, ни одного процесса»;
  - **U3**: `--debug-secrets` / `CODELAB_DEBUG_SECRETS=1` — логгер встроенного агента пишет в stderr `secrets.lookup` без `--verbose`, остальные события — только с `--verbose`; тест логгера (`CliEmbeddedLogger`: фильтр по событию, `SecretRedactor`, очистка управляющих символов, только `error_class` у ошибки) и e2e без `--verbose`;
  - **U4**: `test-scenario` — код `1` и `codelab: no fixtures were played` в stderr, если не сыграна ни одна фикстура (все `SKIP` или пустой фильтр), для любого агента;
  - **сигналы и таймаут**: обработчики `SIGINT`/`SIGTERM` снимаются только после `dispose` агента; ожидание `close()` резолвера с таймаутом больше grace агента (5 s) и событием `embedded.close_timeout` уровня `warning`; второй сигнал во время `dispose` → сразу `130`/`143`; тест на подменных потоках сигналов и зависшем `dispose`;
  - **`try`/`finally`**: `dispose` рантайма CLI (и закрытие резолвера) в `finally` во всех режимах — REPL, `--ui tui`, `-p`; тест: ошибка режима не пропускает `dispose` агента;
  - **sanitize**: строки встроенного агента, которые CLI печатает в терминал (текст `EmbeddedAgentConfigException` и другие места по замечанию ревью), проходят `sanitizeTerminalText`: управляющие символы из конфига и путей не доходят до терминала;
  - **`profiles.json` неверной структуры**: `JsonFileProfileStore` переводит ошибки типа и формы (`TypeError`, отсутствующее поле, не объект) в `FormatException`, CLI — код `64` с причиной; тест `codelab_client_io` и тест `profile_arg_test.dart`;
  - **`/profile` и поздние события**: по замечанию ревью — смена профиля командой `/profile` не даёт событиям прежнего соединения (и прежнего встроенного агента) менять состояние нового (`AGENTS.md` §9); тест;
  - **сторож**: правила для `bin/` и бареля `lib/codelab_cli.dart` — `package:codelab_embedded/io.dart` и `testing.dart` из них запрещены, как во всём `lib/` вне `composition_root.dart` и `scenario/`; негативные тесты на временном пакете;
  - **e2e SIGTERM строже**: сигнал посылается после события начала хода (а не по таймеру), проверяются код `143`, `stopReason: aborted` в журнале и отсутствие процесса агента;
  - **`embedded_agent_test`** CLI запускается один раз, а не в трёх вариантах `CODELAB_E2E_AGENT`: тест сам задаёт встроенный режим (тег или проверка варианта в `support/e2e_agent.dart`);
  - **NIT** ревью — комментарии по-русски (почему/для чего/как), имена, тексты ошибок по-английски — без изменения поведения.
- [x] 3.10 `[docs]` Правки артефактов change по двойному ревью итерации 3 и решениям пользователя 2026-11-02 (U1–U4): D13, п. 7–10 и таблица соответствия; Risks «Молчаливый выбор встроенного агента», «Зависший `dispose` при выходе CLI»; D6 — поводы отмены `open` (новый `open`, `close()`), место резолвера CLI, решение L4 для app, «Выход CLI»; D1 (в) и D8 — сигнатура `scriptedEmbeddedAgentOpener` с `models`, `McpClientConnector` в сценарном открывателе, подтверждённое расхождение; шов `runCodelab(…, embeddedOpener:)` в D8 и testing-quality; спеки codelab-cli (выбор без `--agent` для всех режимов, молчаливый выбор, `profiles.json` неверной структуры, `--debug-secrets` без `--verbose`, выход с таймаутом и вторым сигналом, формат строки решения SJ-11, `stopReason: aborted`) и cli-scenario-driver (необязательный `--agent`, код `1` без сыгранных фикстур); proposal; `09-11-stage-6-cli-mvp.md`; `apps/codelab_cli/AGENTS.md`; задачи 3.3, 3.4, 3.9, 4.3, 4.4.

## 4. codelab-app (итерация 4)

- [x] 4.1 `[desktop]` Тесты `ConnectionCubit` (`test/features/workbench/application/connection_cubit_test.dart`) и widget-тест диалога подключения (agent-workbench-ui «Тип подключения «Встроенный агент»», сценарии «Выбор встроенного агента», «Нет конфигурации встроенного агента»; D9):
  - тип `embedded` строит `EmbeddedProfile(embedded-app-desktop)`;
  - метка и деталь;
  - `ConnectionFailed` с текстом проблем;
  - тип по умолчанию — `stdio`.

  Красный: значения `CodeLabTransportType.embedded` нет.
- [x] 4.2 `[desktop]` `CodeLabTransportType.embedded` и выбор типа в диалоге (`codelab_ui` — только отображение варианта, без логики).
- [x] 4.3 `[desktop]` Тест composition root (`test/app/app_scope_embedded_test.dart`) на `scriptedEmbeddedAgentOpener` через шов `createCodeLabRootScope(embeddedOpener:)` (agent-workbench-ui, сценарий «Одобрение во встроенном режиме»; embedded-agent «Жизненный цикл встроенного агента»; D6, D9):
  - подключение и ход;
  - отказ в карточке одобрения;
  - закрытие scope ждёт `dispose`;
  - сериализация `open` (`await prev.dispose()` перед новым) и `dispose()` у агента, вернувшегося после отмены подключения — повторным Connect (новый `open`) или закрытием root scope (`close()`) (`AGENTS.md` §12; D6, «Резолвер клиента», «Отмена подключения в app»);
  - лог агента в логгере приложения без значений секретов.

  Красный: резолвера нет.

  **Ограничение (ревью итерации 4):** шов `embeddedOpener` подменяет открыватель целиком, поэтому тест scope не исполняет проводку `localEmbeddedAgentOpener(logger: CodeLabEmbeddedLogger(…))`. Лог агента без значений секретов проверен модульным тестом адаптера `CodeLabEmbeddedLogger`, а проводка логгера в `app_scope.dart` — ревью (D9).
- [x] 4.4 `[desktop]` `EmbeddedTransportResolver` (сериализация `open`, `dispose()` устаревшего агента — D6; поводы отмены — новый `open` и `close()`, без нового API `TransportResolver` и `ClientWorkspace` — решение L4, D6, «Отмена подключения в app»; пользователь выбрал вариант без Disconnect 2026-11-02) и адаптер `Logger` в `lib/app/`; регистрация вторым резолвером `ClientWorkspace`; закрытие при закрытии root scope; зависимость `codelab_embedded` в `pubspec.yaml`. Правила сторожа desktop для `io.dart` (только `lib/app/`) и `testing.dart` (запрещён в `lib/`) — testing-quality, сценарий «Тестовый сценарий не попадает в app»; workspace-architecture, сценарий «IO-барель встроенного агента вне composition root»; D3.
- [x] 4.5 `[desktop]` Интеграционные тесты для `CODELAB_E2E_AGENT=embedded` (testing-quality «Встроенный режим в e2e и conformance»; D10; критерии таблицы этапа 4 для app):
  - вариант `embedded` в `integration_test/support/e2e_agent.dart`: выбор типа «Embedded agent», scope со `scriptedEmbeddedAgentOpener` и сценариями `integration_test/llm_scripts/`;
  - пропуск `fs_flow_test` и `terminal_flow_test` с причиной;
  - скрипт `test:e2e:app:embedded` в корневом `pubspec.yaml` вне `check`.

  В feature-ветке — только `fvm flutter analyze`; прогон на устройстве — в `release/<version>` (`AGENTS.md` §21; D13, п. 4). Причина пропуска `fs_flow_test` и `terminal_flow_test` видна в имени или описании теста: `skip` у `testWidgets` — `bool` (D10).

  **Ограничение:** ожидания варианта `embedded`, зависящие от агента, — `sessionLabel` и список моделей сценария — в feature-ветке проверены только анализом и подтверждаются прогоном в `release/<version>` (D10).
- [x] 4.6 `[docs]` `apps/codelab_desktop/AGENTS.md`:
  - встроенный профиль через `codelab_embedded` (вместо «ещё не существует»);
  - `io.dart` только в `lib/app/`;
  - путь `secrets.backend: file` для приложения, запущенного из Finder (D5).
- [x] 4.7 `[client]` Номер попытки в `DefaultClientWorkspace` (acp-client-kit «Явный автомат соединения», сценарии «Повторный Connect во время подключения», «Повторный Reconnect во время переподключения», «Поздний успех устаревшей попытки»; agent-workbench-ui, сценарий «Повторный Connect во время подключения встроенного агента»; D6, «Устаревшая попытка в `ClientWorkspace`»; `AGENTS.md` §9, §12). Решение пользователя 2026-11-02 по ревью итерации 4. Пара «тест → правка», красный тест коммитится до кода:
  - тест `packages/dart/codelab_client_core/test/workspace/client_workspace_test.dart` на резолвере с управляемым `open` (`Completer`): открыта сессия, первый `connect` ждёт `open`, второй `connect` стартует, затем `open` первой попытки бросает — в потоке `state` нет промежуточного `ConnectionFailed`, сессия первой попыткой не возобновлена и не загружена; то же для `reconnect` (`Reconnecting` без промежуточного `failed`); поздний успех первой попытки после старта второй не публикует `Connected` и возможности, не шлёт `session/list` и `session/load`. Красный: сейчас прерванная попытка публикует `ConnectionFailed` и вызывает `resume`;
  - реализация: внутренний номер попытки в `connect`/`reconnect`; после каждого `await` устаревшая попытка не публикует состояние, не трогает сессии (`resume`, `_reattachSessions`) и не выполняет шаги после подключения (`_listFirstPage`, `restoreAfterConnect`). Публичный API `ClientWorkspace` не меняется (L4); doc-комментарий по-русски со ссылкой на D6;
  - тесты существующих сценариев «Явный автомат соединения» и клиентов (CLI, desktop) остаются зелёными без правок ожиданий.
- [x] 4.8 `[desktop]` Таймаут закрытия встроенного агента в `CodeLabRootLifecycle.dispose` (agent-workbench-ui «Тип подключения «Встроенный агент»», сценарий «Зависшая остановка встроенного агента»; D6, таблица событий; D9, «Таймаут закрытия»). Решение пользователя 2026-11-02 по ревью итерации 4. Пара «тест → правка»:
  - тест в `apps/codelab_desktop/test/app/` с резолвером, чей `close()` не завершается (подменный открыватель с зависшим `dispose`), и подменным временем (`fake_async` или параметр таймаута): закрытие root scope завершается после 10 s, в логгере приложения — `embedded.close_timeout` уровня `warning` без текста ошибки, транспорт и `AcpClientApplication` освобождены. Красный: сейчас `dispose` ждёт `close()` без ограничения;
  - реализация: ожидание `close()` резолвера не дольше 10 s (как CLI), по истечении — `embedded.close_timeout` и продолжение освобождения; значение таймаута — параметр с умолчанием 10 s только ради теста, не настройка пользователя.

## 5. Замер 7.8 и разбор журнала в isolate (итерация 5)

- [x] 5.1 `[agent]` Разведка (исключение (д) §9.0, без пары, не дольше двух дней): `packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart` (embedded-agent «Нагрузка встроенного агента на UI-isolate», сценарий «Замер печатает метрики»; D11). Dev-зависимости `codelab_client_core`, `codelab_client_acp`. Прогон AOT на Mac Apple Silicon разработчика, три прогона, критерий — медиана p99 и максимум; Linux-раннер CI — справочно (D13, п. 3). Числа, машина, режим и вывод записываются в design.md, «Решение 7.8».
- [x] 5.2 `[agent]` Тест `codelab_agent_io/test/session/jsonl_replay_isolate_test.dart`: реплей журнала в 1000 записей совпадает до и после переноса (embedded-agent, сценарий «Реплей после переноса разбора»; D11). Тест зелёный до переноса и остаётся зелёным после: это характеризационный тест (исключение (а) §9.0).
- [x] 5.3 `[agent]` Разбор JSONL при `session/load` в `Isolate.run` в `JsonlSessionStore`.
- [x] 5.4 `[agent]` **Не требуется** (design.md, «Решение 7.8»: критерии D11 выполнены при реалистичном N ≈ 1; решение пользователя 2026-11-02 — остаётся `InProcessAcpLink`; follow-up — PERF-1, PERF-2 в `docs/backlog/perf-2026-11-02-stream-latency.md`). Исходная формулировка: только если 5.1 провалил критерии: новые задачи `IsolateAcpLink` по эскизу §9.12 добавляются сюда отдельной итерацией с парами тестов (порядок 1000 сообщений, `close` → `failed`, `DateTime` → `sendFailed`, `kill` после `grace`, падение isolate → `failed`). Решение пользователя по объёму — до начала.

## 6. Документы и Definition of Done (итерация 6)

- [x] 6.1 `[docs]` `README.md`: строка таблицы и узел `codelab_embedded` в графе, рёбра от `codelab_desktop` и `codelab_cli`, уточнение абзаца о сходимости веток (D3). Корневой `AGENTS.md` §5: пакет в дереве и в «Назначении пакетов», правило импорта `io.dart`/`testing.dart` клиентами. Таблица зон в `CLAUDE.md` и `.claude/agents/agent-core-engineer.md`: `codelab_embedded` — по согласованию с пользователем (D1; решение R6-1).
  Попутно в графе `README.md` сняты устаревшие пометки: `codelab_cli` больше не «план, этап 6», ребро `codelab_agent` → `codelab_agent_mcp` — сплошное (зависимость есть), список dev-зависимостей под графом сверен с `pubspec.yaml`.
- [x] 6.2 `[docs]` Тексты плана:
  - `09-12-stage-7-embedded.md` — итог 7.3–7.9, отметки DoD, решение 7.8;
  - `09-05-stage-0-foundation.md` — скрипт `test:e2e:app:embedded` без `CODELAB_ALLOW_SCRIPTED_LLM` (D8);
  - `agent-core/10-core-assembly-and-profiles.md` §10.12 — ссылка на тест паритета в `codelab_agent_core/test/host/` (D1, в);
  - `docs/architecture/concurrency.md` — ссылка на решение 7.8.
- [x] 6.3 `[docs]` Definition of Done этапа 7 по `09-12` (там же — тот же список с отметками). Результаты прогонов внесены по факту (2026-11-02):
  - `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded` (`melos run conformance:embedded`) — все `PASS` или `SKIP` с причиной, без `FAIL` (cli-scenario-driver «Вывод и коды выхода test-scenario»; D8) — **выполнено** 2026-11-02 на `develop` @ `8905dee`: код 0, `37 passed, 0 failed, 19 skipped`, у каждого `SKIP` причина;
  - `fvm dart run melos run guard` — правила D3, включая allowlist пакетов `codelab_*` app (задача 6.4) — **выполнено** 2026-11-02: код 0, 100 тестов;
  - интеграционные тесты app собираются: `fvm flutter analyze` в `apps/codelab_desktop` с `integration_test/` (testing-quality; D10, D13, п. 4) — **выполнено** 2026-11-02: `fvm flutter analyze integration_test` — код 0; прогон на устройстве `melos run test:e2e:app:embedded` отмечается в `release/<version>` (`AGENTS.md` §21);
  - замер выполнен, решение записано — **доказано**: D11, «Решение 7.8» (задача 5.1; R5-1);
  - конфиг через загрузчик 8.5 и ключ через `SecretResolver` 8.9 — **доказано** тестами задач 2.1 и 2.3: `packages/dart/codelab_embedded/test/io/local_opener_test.dart`, `packages/dart/codelab_agent_io/test/secrets/host_secrets_test.dart`, `packages/dart/codelab_embedded/test/io/test_secret_store_process_test.dart`;
  - Should (`codelab_setup` для мастера, D-05, мастер) — в будущий change `add-provider-setup-ui` (записан в `docs/architecture/proposals/delivery-roadmap.md` и `09-12`; этим change не создаётся).

  Change готов к архивированию по просьбе пользователя.
- [x] 6.4 `[desktop]` Allowlist зависимостей app в стороже (workspace-architecture «Автоматический сторож границ пакетов», сценарий «Пакет агента в зависимостях app»; D3). Решение пользователя 2026-11-02 по ревью итерации 4: отдельной задачей в итерации 6. Сторож пишет исполнитель зоны ограничиваемого кода (правило выше, как 1.7 `[agent]`, 3.4 `[client]`, 4.4 `[desktop]`):
  - красный тест в `packages/dart/codelab_architecture_tests/test/pubspec_allowlist_test.dart`: `desktopAllowlist` по пакетам `codelab_*` — `{codelab_client_acp, codelab_client_core, codelab_client_io, codelab_acp_protocol, codelab_acp_transports, codelab_embedded, codelab_ui}`; негативный случай — `codelab_agent_core` в `dependencies` временного `pubspec.yaml` даёт падение с именем пакета; `codelab_embedded` нарушением не считается; сторонние зависимости app не проверяются;
  - если текущий `apps/codelab_desktop/pubspec.yaml` проходит без правок, тест закрывает критерий (характеризационный, исключение (а) §9.0) и это фиксируется в PR;
  - doc-комментарий константы по-русски (почему/для чего/как) со ссылкой на D3;
  - `codelab_setup` в `desktopAllowlist` не входит: его добавит change `add-provider-setup-ui` вместе с потребителем (решение R6-2).
