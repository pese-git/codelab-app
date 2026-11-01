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

Итерации 3 и 4 независимы друг от друга после итерации 2. Открытых вопросов нет: решения пользователя 2026-11-02 — design.md, D13.

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

- [ ] 1.1 `[agent]` Тест `codelab_agent_core/test/host/host_profile_test.dart` и golden `test/host/profiles/embedded-app-desktop.golden.json` (agent-runtime «Профили хостов и сужение», сценарий «Профиль встроенного агента приложения»; D4). Красный: `HostProfile.of('embedded-app-desktop')` бросает `ArgumentError`.
- [ ] 1.2 `[agent]` Профиль `embedded-app-desktop` в `host_profile.dart` с причинами по §10.4.
- [ ] 1.3 `[protocol]` Тесты `codelab_agent_acp/test/` (agent-acp-server «Локальное окружение сессии от хоста», все три сценария; D4):
  - клиент объявил `fs`/`terminal`, сервер с `localEnv` не шлёт `fs/*`/`terminal/*`;
  - `write` в `standard` по-прежнему спрашивает клиента;
  - без `localEnv` — прежние кадры;
  - `fileListing` при `localEnv` без листинга — `HostWiringException`.

  Красный: поля `localEnv` нет.
- [ ] 1.4 `[protocol]` `AcpServerConfig.localEnv` и ветка в `_wire` (`agent_server.dart`). Doc-комментарии по-русски со ссылкой на D4 и §13.1.
- [ ] 1.5 `[agent]` Тест `codelab_agent_io/test/scripted/llm_script_test.dart` — случаи `apps/codelab_agent/test` про разбор `--llm-script` и слой провайдеров сценария переносятся на новый API (embedded-agent «Сценарий модели для тестов», сценарий «Сценарий бинаря и встроенного агента разбирается одинаково»; D8). Красный: API нет в `codelab_agent_io`.
- [ ] 1.6 `[agent]` Перенести `LlmScript` и `_withScriptedProviders` в `codelab_agent_io/lib/src/scripted/` (`LlmScriptException` вместо `UsageError`); `apps/codelab_agent` переводит исключение в код `64`. Тесты бинаря (`llm_scripts_load_test.dart`, `agent_host_*_test.dart`, процессные) остаются зелёными без правок ожиданий.
- [ ] 1.7 `[agent]` Сторож до кода пакета (workspace-architecture «Автоматический сторож границ пакетов», сценарии «Основной барель встроенного агента импортирует IO-пакет», «Встроенный агент собирает ядро вручную», «Зависимость моста встроенного агента вне allowlist»; D3):
  - два правила `packages/dart/codelab_embedded` в `rules.dart` вместо комментария `stage 7`;
  - `embeddedAllowlist` и тест в `pubspec_allowlist_test.dart`;
  - сканирование `packages/dart/codelab_embedded/lib` в `host_assembly_guard_test.dart`;
  - негативные тесты на временном пакете.

  Красный: пакета нет, тест allowlist не находит `pubspec.yaml`.
- [ ] 1.8 `[agent]` Тесты `packages/dart/codelab_embedded/test/embedded_agent_test.dart` на `scriptedEmbeddedAgentOpener` и `MemorySessionStore`/временном каталоге (embedded-agent:
  - «Сборка встроенного агента», сценарий «Ход через встроенного агента»;
  - «Локальное исполнение и containment», оба сценария;
  - «Разрешения во встроенном режиме», оба сценария;
  - D2, D4).

  Красный: пакета нет.
- [ ] 1.9 `[agent]` Пакет `packages/dart/codelab_embedded`:
  - `pubspec.yaml` по `embeddedAllowlist`, запись в `workspace:` корневого `pubspec.yaml`;
  - основной барель (`createEmbeddedAgent`, `EmbeddedAgent`, `EmbeddedAgentConfig`, `EmbeddedHostServices`, `EmbeddedAgentOpener`, `EmbeddedAgentConfigException`, реэкспорт `Logger`/`LogLevel`);
  - `lib/testing.dart` (`scriptedEmbeddedAgentOpener`);
  - вложенный `AGENTS.md` (назначение, границы, TDD, готовность итерации — §9.0, правило 7).

  Сборка — только `buildAgentCore`, сервер на `InProcessAcpLink` с `agentInfo` бинаря и `detachGrace: zero` (D2, D4).
- [ ] 1.10 `[agent]` Web-smoke `packages/dart/codelab_embedded/test/web_smoke/main.dart` и строка в скрипте `web-compile` корневого `pubspec.yaml` (workspace-architecture «Границы пакетов monorepo», сценарий «Основной барель встроенного агента собирается для web»; embedded-agent «Пакет codelab_embedded и его точки входа», сценарий «Основной барель собирается для web»; D3). Красный: файла нет, `web-compile` падает на отсутствующей точке входа после правки скрипта.

## 2. Настоящий хост: конфиг, секреты, журнал, жизненный цикл (итерация 2)

- [ ] 2.1 `[agent]` Тесты `codelab_embedded/test/io/local_opener_test.dart` с временным `CODELAB_HOME`, `MockClient` и окружением теста (embedded-agent «Конфигурация и секреты встроенного агента», сценарии «Ключ провайдера из secrets.yaml», «Невалидный конфиг», «Нет конфигурации»; D5):
  - ключ через `openHostSecrets` и `secrets.backend: file`;
  - ключ из `CODELAB_SECRET_*`;
  - `EmbeddedAgentConfigException` без значений, HTTP-клиент не создан;
  - журнал JSONL в `$CODELAB_HOME/sessions`;
  - сужение `profile.embedded-cli.*`.

  Красный: `io.dart` нет.
- [ ] 2.2 `[agent]` `lib/io.dart` и `lib/src/io/`: `localEmbeddedAgentOpener`:
  - `ConfigLoader` и `codelabHomeOf`, затем `openHostSecrets`;
  - `createRoutedStreamFunction` и `StaticModelCatalog`;
  - `JsonlSessionStore`, `LocalExecutionEnv`, `ProjectFilesLoader`;
  - `McpClientConnector` (stdio и streamable HTTP);
  - `createEmbeddedAgent`.

  Ресурсы создаются после успешной загрузки конфига.
- [ ] 2.3 `[agent]` Тест `codelab_agent_io/test/secrets/host_secrets_test.dart`: `openHostSecrets(testStorePath:)` даёт `FileSecretStore` по пути с `backend.id == "file"`. Процессный тест `codelab_embedded/test/io/test_secret_store_process_test.dart` запускает `fvm dart run -DCODELAB_ALLOW_TEST_SECRETS=true` и проверяет обратный случай без define (embedded-agent, сценарий «Тестовое хранилище только в тестовой сборке»; D5). Красный: параметра нет.
- [ ] 2.4 `[agent]` Параметр `testStorePath` у `openHostSecrets`; чтение `CODELAB_TEST_SECRET_STORE` в открывателе только при `const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')`. Снять `skip` в `config_loader_test.dart`, где он ссылается на задачу 7.7, если тест теперь покрыт процессным.
- [ ] 2.5 `[agent]` Тесты `codelab_embedded/test/lifecycle_test.dart` (embedded-agent «Жизненный цикл встроенного агента», все три сценария; D6):
  - `dispose` при ожидающем разрешении — отказ, `cancelled`, итог хода в журнале;
  - повторный `dispose`;
  - закрытие клиентом — `closed`, MCP-процесс fake-сервера остановлен;
  - асинхронная ошибка в зоне — клиентский `failed`/`disconnected`, `embedded.agent.failed` без текста, внешняя зона ничего не получает.

  Красный: `dispose` не ждёт `shutdown`, зоны нет.
- [ ] 2.6 `[agent]` Охраняемая зона `serve`, подписка на закрытие агентского конца, порядок `dispose` по D6, `closed`.
- [ ] 2.7 `[agent]` Тест паритета профилей `codelab_embedded/test/profile_parity_test.dart` (agent-runtime, сценарий «Паритет профилей»; §10.12). Красный до 2.2, если ядро и сервер расходятся; иначе тест закрывает критерий и фиксируется ссылкой в PR.
- [ ] 2.8 `[agent]` Рефакторинг по итогам итерации: общая часть сборки `apps/codelab_agent` и `codelab_embedded` сверена. Различия — только профиль, транспорт и сценарий (D1, в); дублирование логики устранено переносом в существующие пакеты, если оно появилось.

## 3. CLI (итерация 3)

- [ ] 3.1 `[client]` Тесты `codelab_client_core` и `codelab_client_io` (acp-client-kit «Профили и резолверы транспорта», сценарии «Встроенный профиль без резолвера встроенного агента», «Встроенный профиль не сохраняется в profiles.json»; D7). Красный: фабрики `ConnectionProfile.embedded` нет.
- [ ] 3.2 `[client]` `ConnectionProfile.embedded` (`EmbeddedProfile`) и `build_runner` для freezed. Ветки исчерпывающих `switch`:
  - `ConfigTransportResolver` — `false`/`UnsupportedConnectionProfileException`;
  - `JsonFileProfileStore` — `ArgumentError` при `save`, `FormatException` при чтении;
  - `describeProfile`, `/profile`, `profiles` CLI, `ScenarioAgent` — заглушки до 3.6.
- [ ] 3.3 `[client]` Тесты `apps/codelab_cli/test/profiles/profile_arg_test.dart`, `profiles_command_test.dart`, `test/embedded_resolver_test.dart` (codelab-cli «Профили подключения CLI», сценарии «Профиль default сильнее встроенного агента», «Встроенный агент явно», «embedded нельзя сохранить профилем», «Без профиля и без конфига»; «Встроенный агент в CLI», сценарий «Невалидный конфиг встроенного агента»; D6):
  - `embedded` и без `--agent` → `EmbeddedProfile(embedded-cli)` при отсутствии `default`;
  - битый `profiles.json` → `64`;
  - резолвер сериализует `open` и ждёт `dispose` прежнего агента;
  - `close()` ждёт `dispose`.

  Существующие тесты «embedded is 64» меняются на новые ожидания. Красный: `UsageError` на `embedded`.
- [ ] 3.4 `[client]` `resolveAgentProfile`: без `--agent` — профиль `default`, если он есть в `profiles.json`, иначе `EmbeddedProfile(embedded-cli)`; битый файл — код `64` (D13, п. 1). `EmbeddedTransportResolver` и `localEmbeddedAgentOpener` в `composition_root.dart`. Флаг `--debug-secrets`. `EmbeddedAgentConfigException` → код `64` в `run.dart`. Ожидание `close()` резолвера в `CliRuntime.dispose` и в обработке сигналов. Правила сторожа CLI для `codelab_embedded/io.dart` и `testing.dart`, `cliAllowlist` += `codelab_embedded` (workspace-architecture, сценарий «IO-барель встроенного агента вне composition root»; D3). Шов `run(…, {EmbeddedAgentOpener? embeddedOpener})` для тестовой точки входа (D8).
- [ ] 3.5 `[client]` Тест `apps/codelab_cli/test/scenario/test_scenario_command_test.dart` (cli-scenario-driver «Команда test-scenario», сценарии «Корпус против встроенного агента», «Фикстура с fake MCP-серверами»; D8):
  - корпус `--agent embedded` без `FAIL`;
  - пропуски с причинами;
  - временные каталоги удалены.

  Красный: `embedded` даёт `64`.
- [ ] 3.6 `[client]` `ScenarioAgent` для `EmbeddedProfile`: `scriptedEmbeddedAgentOpener` с `setup.llm`, `setup.profile ?? 'agent-serve'`, `setup.mode`, временными `sessions` и `CODELAB_HOME`; `AgentConnection` с `dispose` агента. Скрипт `conformance:embedded` в корневом `pubspec.yaml` и в шагах `check`.
- [ ] 3.7 `[client]` E2E `cli/*` для `CODELAB_E2E_AGENT=embedded` (testing-quality «Встроенный режим в e2e и conformance», сценарий «E2E CLI против встроенного агента»; codelab-cli «Встроенный агент в CLI», сценарии «Отказ по умолчанию в headless», «Журнал дописан при SIGTERM», «Отладка секретов»; «Профили подключения CLI», сценарий «Без профиля по умолчанию запускается встроенный агент»; критерий `cli/connect-profiles-stdio-ws-embedded`, вариант `embedded`):
  - тестовая точка входа `test/e2e/support/embedded_cli_main.dart`;
  - вариант `embedded` в `support/e2e_agent.dart`;
  - скрипт `test:e2e:cli:embedded` в `check`.

  Это приёмочные ворота (исключение (б) §9.0): пишутся до закрытия итерации, не до каждой задачи.
- [ ] 3.8 `[docs]` `apps/codelab_cli/AGENTS.md`:
  - зависимость `codelab_embedded`;
  - импорт `io.dart` только из `composition_root.dart`, `testing.dart` — только из `scenario/`;
  - `--debug-secrets`;
  - выбор без `--agent`.

  `09-11-stage-6-cli-mvp.md`: таблица `--agent` и DoD — `default` из `profiles.json`, если есть, иначе `embedded` (D13, п. 1).

## 4. codelab-app (итерация 4)

- [ ] 4.1 `[desktop]` Тесты `ConnectionCubit` (`test/features/workbench/application/connection_cubit_test.dart`) и widget-тест диалога подключения (agent-workbench-ui «Тип подключения «Встроенный агент»», сценарии «Выбор встроенного агента», «Нет конфигурации встроенного агента»; D9):
  - тип `embedded` строит `EmbeddedProfile(embedded-app-desktop)`;
  - метка и деталь;
  - `ConnectionFailed` с текстом проблем;
  - тип по умолчанию — `stdio`.

  Красный: значения `CodeLabTransportType.embedded` нет.
- [ ] 4.2 `[desktop]` `CodeLabTransportType.embedded` и выбор типа в диалоге (`codelab_ui` — только отображение варианта, без логики).
- [ ] 4.3 `[desktop]` Тест composition root (`test/app/app_scope_embedded_test.dart`) на `scriptedEmbeddedAgentOpener` через шов `createCodeLabRootScope(embeddedOpener:)` (agent-workbench-ui, сценарий «Одобрение во встроенном режиме»; embedded-agent «Жизненный цикл встроенного агента»; D6, D9):
  - подключение и ход;
  - отказ в карточке одобрения;
  - закрытие scope ждёт `dispose`;
  - лог агента в логгере приложения без значений секретов.

  Красный: резолвера нет.
- [ ] 4.4 `[desktop]` `EmbeddedTransportResolver` и адаптер `Logger` в `lib/app/`; регистрация вторым резолвером `ClientWorkspace`; закрытие при закрытии root scope; зависимость `codelab_embedded` в `pubspec.yaml`. Правила сторожа desktop для `io.dart` (только `lib/app/`) и `testing.dart` (запрещён в `lib/`) — testing-quality, сценарий «Тестовый сценарий не попадает в app»; workspace-architecture, сценарий «IO-барель встроенного агента вне composition root»; D3.
- [ ] 4.5 `[desktop]` Интеграционные тесты для `CODELAB_E2E_AGENT=embedded` (testing-quality «Встроенный режим в e2e и conformance»; D10; критерии таблицы этапа 4 для app):
  - вариант `embedded` в `integration_test/support/e2e_agent.dart`: выбор типа «Embedded agent», scope со `scriptedEmbeddedAgentOpener` и сценариями `integration_test/llm_scripts/`;
  - пропуск `fs_flow_test` и `terminal_flow_test` с причиной;
  - скрипт `test:e2e:app:embedded` в корневом `pubspec.yaml` вне `check`.

  В feature-ветке — только `fvm flutter analyze`; прогон на устройстве — в `release/<version>` (`AGENTS.md` §21; D13, п. 4).
- [ ] 4.6 `[docs]` `apps/codelab_desktop/AGENTS.md`:
  - встроенный профиль через `codelab_embedded` (вместо «ещё не существует»);
  - `io.dart` только в `lib/app/`;
  - путь `secrets.backend: file` для приложения, запущенного из Finder (D5).

## 5. Замер 7.8 и разбор журнала в isolate (итерация 5)

- [ ] 5.1 `[agent]` Разведка (исключение (д) §9.0, без пары, не дольше двух дней): `packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart` (embedded-agent «Нагрузка встроенного агента на UI-isolate», сценарий «Замер печатает метрики»; D11). Dev-зависимости `codelab_client_core`, `codelab_client_acp`. Прогон AOT на Mac Apple Silicon разработчика, три прогона, критерий — медиана p99 и максимум; Linux-раннер CI — справочно (D13, п. 3). Числа, машина, режим и вывод записываются в design.md, «Решение 7.8».
- [ ] 5.2 `[agent]` Тест `codelab_agent_io/test/session/jsonl_replay_isolate_test.dart`: реплей журнала в 1000 записей совпадает до и после переноса (embedded-agent, сценарий «Реплей после переноса разбора»; D11). Тест зелёный до переноса и остаётся зелёным после: это характеризационный тест (исключение (а) §9.0).
- [ ] 5.3 `[agent]` Разбор JSONL при `session/load` в `Isolate.run` в `JsonlSessionStore`.
- [ ] 5.4 `[agent]` Только если 5.1 провалил критерии: новые задачи `IsolateAcpLink` по эскизу §9.12 добавляются сюда отдельной итерацией с парами тестов (порядок 1000 сообщений, `close` → `failed`, `DateTime` → `sendFailed`, `kill` после `grace`, падение isolate → `failed`). Решение пользователя по объёму — до начала.

## 6. Документы и Definition of Done (итерация 6)

- [ ] 6.1 `[docs]` `README.md`: строка таблицы и узел `codelab_embedded` в графе, рёбра от `codelab_desktop` и `codelab_cli`, уточнение абзаца о сходимости веток (D3). Корневой `AGENTS.md` §5: пакет в дереве и в «Назначении пакетов», правило импорта `io.dart`/`testing.dart` клиентами. Таблица зон в `CLAUDE.md` и `.claude/agents/agent-core-engineer.md`: `codelab_embedded` — по согласованию с пользователем (D1).
- [ ] 6.2 `[docs]` Тексты плана:
  - `09-12-stage-7-embedded.md` — итог 7.3–7.9, отметки DoD, решение 7.8;
  - `09-05-stage-0-foundation.md` — скрипт `test:e2e:app:embedded` без `CODELAB_ALLOW_SCRIPTED_LLM` (D8);
  - `agent-core/10-core-assembly-and-profiles.md` §10.12 — ссылка на тест паритета;
  - `docs/architecture/concurrency.md` — ссылка на решение 7.8.
- [ ] 6.3 `[docs]` Definition of Done этапа 7 по `09-12`:
  - `codelab test-scenario … --agent embedded` — все `PASS` или `SKIP` с причиной;
  - `melos run guard` — правила D3;
  - интеграционные тесты app собираются (`fvm flutter analyze`); прогон на устройстве отмечается в `release/<version>`;
  - замер выполнен, решение записано;
  - конфиг через загрузчик 8.5 и ключ через `SecretResolver` 8.9 доказаны тестами 2.1 и 2.3;
  - Should (`codelab_setup`, D-05, мастер) — в change `add-provider-setup-ui`.

  Change готов к архивированию по просьбе пользователя.
