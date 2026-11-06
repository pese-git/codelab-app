Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование или сценарий спеки этого change и решение design.md. Красные тесты коммитятся отдельно до кода. Коммит — только по просьбе пользователя: оркестратор спрашивает, а не коммитит сам.

Метки исполнителей (зоны — D11): `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent` и мост `codelab_setup` (`lib/src/provider/provider_readiness.dart`, D12); `[desktop]` — только тесты app: `apps/codelab_desktop/test/app/provider_setup_probe_test.dart` (ожидание изменено по D3/D12) и проверка баннера в `integration_test/embedded_provider_settings_flow_test.dart` (задача 8.7); код app не меняется. Задач `[protocol]` и `[client]` нет: ACP-проекция не меняется (D11), `codelab_client_*` и `apps/codelab_cli` кода не меняют — только прогон тестов (раздел 5). Итерация 3 `add-provider-setup-ui` вливается в `develop` раньше (D12, п. 5): правки её текстов, тестов и `checkProviderReadiness` делает этот change в разделе 7 после обновления от `develop`.

Тесты — на Dart VM, во временных `CODELAB_HOME` и `cwd`, окружение передаётся явно. Тестовые ключи — `sk-test-leak-…`.

## 0. Документы (сделано в этом change)

- [x] 0.1 `[agent]` `docs/architecture/proposals/agent-core/15-configuration.md`:
  - §15.4, таблица `agent` — `default_model` необязателен, ссылка на правило выбора;
  - §15.5, шаг 8 — правило «нет ни одной модели» и событие `config.model.none`;
  - §15.7 — текст про старт без конфига.
- [x] 0.2 `[agent]` `docs/architecture/proposals/agent-core/17-5-agent-setup.md` — абзац R3-1 о `provider add` без `--default` и `required`.
- [x] 0.3 `[agent]` `docs/architecture/proposals/agent-core/13-acp-adapter.md` — `session/new` не передаёт модель, источник `currentValue` опции `model`.

## 1. Ядро: схема и модель уровня конфига

- [x] 1.1 `[agent]` Красные тесты `packages/dart/codelab_agent_core/test/config/config_schema_test.dart` и соседние:
  - заменить тест `agent.default_model is required` на «провайдер без ключа модели → `gw/m`, `firstProvider`» (agent-configuration «Схема и строгая проверка», сценарий «Провайдер без agent.default_model»);
  - сценарии требования «Модель по умолчанию без agent.default_model»:
    - «Первая модель первого провайдера»;
    - «Первый провайдер без ключа»;
    - «Ссылка на секрет не читается при выборе» — фейковый `SecretStore` со счётчиком вызовов;
    - «Нет доступных провайдеров»;
    - «Нет ни одного провайдера» — `key`, `kind`, `event`, текст, провайдер без моделей;
    - «Явная модель на несуществующую модель»;
    - «CODELAB_MODEL — явная модель» (через слой окружения в тесте `codelab_agent_io`);
  - снимок без проекта: модель и источник полного снимка (D1).
- [x] 1.2 `[agent]` Реализация в `codelab_agent_core/lib/src/config/`:
  - `DefaultModelSource` (enum с проводными именами `config`, `last-used`, `first-provider`);
  - `CoreConfig.defaultModelSource` (в конструкторе, `_copyWith`, `withDeferred`, сборке в `resolve.dart`);
  - `_defaultModel` по D1–D4, событие `config.model.none` — константа рядом с `validationIncompleteEvent`;
  - экспорт из публичного бареля, doc-комментарии на русском (почему, для чего, как; ссылки D1–D4; источник идеи — OpenCode, D-контекст).
- [x] 1.3 `[agent]` Красные тесты перезагрузки `codelab_agent_core/test/runtime/config_reload_test.dart` и `test/config/config_reload_plan_test.dart` — сценарий «Отложенный новый провайдер не становится моделью» (D10); удаление явного ключа — переход на `firstProvider` для новых сессий.
- [x] 1.4 `[agent]` Реализация D10 в `CoreConfig.withDeferred` (пересчёт неявной модели по итоговым провайдерам). Правка `config_reload_plan.dart` не понадобилась: у неявной модели нет ключа `agent.default_model` в `diff`, поэтому `deferred.defaultModel` для неё и так не выставляется (D10).

## 2. Ядро: выбор модели сессии и порт последней модели

- [x] 2.1 `[agent]` Красные тесты `codelab_agent_core/test/runtime/` (новый `session_model_selection_test.dart`) с фейком `LastModelStore`:
  - agent-runtime «Модель новой сессии»:
    - «Явная модель конфига побеждает последнюю»;
    - «Последняя модель побеждает первого провайдера» — `model_change`, `configOptions` через `AgentRuntime.models`;
    - «Последней модели нет в каталоге»;
    - «Сбой чтения последней модели»;
    - событие `session.model.selected` с `source`;
  - «Последняя выбранная модель»:
    - «Автоматический выбор не пишет файл» — фейк без вызова `write`;
    - `setModel` вызывает `write` после `model_change`;
    - `createSession(spec.model)` и `loadSession(model:)` вызывают `write`;
    - восстановление из журнала и смена агента не вызывают;
    - «Сбой записи не ломает смену модели»;
  - `loadSession` без модели журнала по-прежнему берёт `CoreConfig.defaultModel` без шага 2 (D5).
- [x] 2.2 `[agent]` Реализация:
  - порт `LastModelStore` (`codelab_agent_core/lib/src/host/` или `session/`, рядом с портами сервисов) и `AgentCoreServices.lastModel`;
  - чистая функция `selectSessionModel` (D5);
  - `AgentRuntimeImpl.createSession`/`loadSession`/`_Session.setModel` по D5–D6, события `session.model.selected`, `model.last_used.ignored`, `model.last_used.write_failed`;
  - doc-комментарии на русском.
- [x] 2.3 `[agent]` ACP-проекция без правки кода: прогнать `codelab_agent_acp` тесты `config_options`/`set_config_option` и добавить красный, затем зелёный тест «`session/new` без ключа модели → `currentValue` неявной модели; `set_config_option model` → `write`» на фейке порта (D11).

## 3. `codelab_agent_io`: файл состояния, PERM-11, подкоманды

- [x] 3.1 `[agent]` Красные тесты `packages/dart/codelab_agent_io/test/state/last_model_file_test.dart`:
  - запись и чтение `{"v":1,"model":"b/y"}`;
  - создание `state/`;
  - уникальный tmp и `rename` — нет `*.tmp-*` после записи;
  - очередь внутри процесса;
  - «Повреждённый файл состояния» (не строка, обрезанный JSON, `v: 9`, больше 4 KiB) — `null`, событие `model.last_used.ignored` с категорией без содержимого, файл не изменён;
  - нет файла — `null` без события;
  - «Секретов нет в файле и логе».
- [x] 3.2 `[agent]` Реализация `FileLastModelStore` (`lib/src/state/last_model_file.dart`, экспорт из бареля; D7) и обновление `packages/dart/codelab_agent_io/AGENTS.md` §1.
- [x] 3.3 `[agent]` Красный тест `test/config/agent_config_paths_test.dart`: путь `last-model.json` в `agentConfigPathsFor` и его нет в `watchedConfigFiles` (сценарий «Файл под защитой PERM-11»). Затем реализация в `agent_config_paths.dart`.
- [x] 3.4 `[agent]` Красные тесты `test/cli/cli_config_commands_test.dart` и `test/cli/provider_commands_test.dart`:
  - тест «без --default в пустом CODELAB_HOME: warning о прежней проблеме, код 0» → нет строк `warning:` (сценарий «provider add в пустом CODELAB_HOME без --default»);
  - строка 184 (`config set` → `warning: agent.default_model: required`) → новый текст («config set и get»);
  - `config check`: «Модель первого провайдера в config check», «Источник модели в config check»;
  - «provider remove единственного провайдера без ключа модели» — нет `change the model first`;
  - «provider remove провайдера последней модели»;
  - `config_writer_test.dart`: «Первая запись в пустой конфиг» (событие), «Первый провайдер без модели по умолчанию».
- [x] 3.5 `[agent]` Реализация:
  - `ConfigCommands.check` — строка `Default model:` через `selectSessionModel` и `FileLastModelStore.read()`, строка `warning:` о нечитаемом файле (D9);
  - `ProviderCommands.remove` — подсказка по `issue.event` (D9);
  - doc-комментарии.

## 4. Хосты

- [x] 4.1 `[agent]` Красные тесты:
  - `apps/codelab_agent/test/config_invalid_process_test.dart` — «no model anywhere» ожидает новый текст и `agent.default_model` (agent-binary «Нет ни одной модели»);
  - новый процессный тест «Провайдер без модели по умолчанию» (`session/new` → `currentValue gw/m`);
  - сценарий agent-runtime «Пустой CODELAB_HOME и provider add» — процессный, `provider add` затем `serve --stdio`;
  - комментарий в `serve_flags_test.dart:267` — текст проблемы;
  - `--llm-script` не создаёт `state/` (D8).
- [x] 4.2 `[agent]` Реализация в `apps/codelab_agent/lib/src/host/agent_host.dart` — `FileLastModelStore` без `--llm-script` (D8).
- [x] 4.3 `[agent]` Красные тесты `packages/dart/codelab_embedded/test/`: `localEmbeddedAgentOpener` передаёт файловую память над `CODELAB_HOME`; сценарный открыватель — без неё, `state/` не создаётся. Затем реализация в `lib/src/io/local_opener.dart` (D8).

## 5. Совместимость клиентов (только проверка, без правки кода)

- [x] 5.1 `[agent]` Прогнать тесты, которые видят новый вывод:
  - `apps/codelab_cli/test/provider_mcp_command_test.dart`;
  - `apps/codelab_cli/test/e2e/config_write_command_test.dart`;
  - `apps/codelab_agent/test/config_write_command_process_test.dart`.

  `config check` у CLI и бинаря совпадает по построению. Если тест сверяет stdout `config check` целиком, поправить его в паре «тест → код» задачи 3.4.
- [x] 5.2 `[agent]` Прогнать тесты `packages/dart/codelab_setup` (`startProblems`, `provider_remove_test.dart`, `file_agent_config_store_test.dart`) и `apps/codelab_desktop/test/features/settings/application/provider_settings_cubit_test.dart`. Ожидание — зелёные без правки (D4, D12), кроме тестов, изменённых в разделе 7: `provider_setup_needed_test.dart`, `provider_readiness_test.dart` и `apps/codelab_desktop/test/app/provider_setup_probe_test.dart` (ожидание «провайдер без ключа модели → мастер не нужен» изменено по D3/D12). Иное падение — стоп и вопрос пользователю.
- [x] 5.3 `[agent]` Golden-фикстуры `codelab_acp_testing` задают `default_model` сценарием — изменений нет; прогон `conformance:agent`.

## 7. После слияния итерации 3 `add-provider-setup-ui` (D12, п. 5)

- [x] 7.1 `[agent]` Обновить ветку от `develop` (через `sync_with_base_branch`), найти в коде, тестах и спеках итерации 3 опору на `agent.default_model: required` и лист `agent.default_model` (`provider_readiness.dart`, `provider_setup_needed_test.dart`, `checkProviderReadiness`, спеки `client-agent-setup`/`agent-workbench-ui`, D26), показать пользователю список до правок.
- [x] 7.2 Красные тесты: `providerSetupNeeded` на настоящем загрузчике — пустой `CODELAB_HOME` → `true` с новым текстом; «провайдеры есть, ключа модели нет» → `false`; `checkProviderReadiness` берёт модель `CoreConfig.defaultModel` (явная или первый провайдер), а не `NoProviderConfigured` (D12, п. 3–4). Файлы:
  - `[agent]` `packages/dart/codelab_setup/test/provider_setup_needed_test.dart`, `provider_readiness_test.dart`;
  - `[desktop]` `apps/codelab_desktop/test/app/provider_setup_probe_test.dart` — «a provider without a default model» ожидает `false` вместо `true` (D3, D12, п. 2).
- [x] 7.3a `[agent]` Формулировки спек и design.md change `add-provider-setup-ui` (client-agent-setup «Готовность провайдера», agent-workbench-ui «Встроенный агент без провайдера», D16, D26) поправлены прямо в его каталоге этим change — по согласованию с его сессией 2026-11-06: тот change не архивирован, текст и поведение меняются в одном PR.
- [x] 7.3 `[agent]` Реализация в `codelab_setup/lib/src/provider/provider_readiness.dart`: `providerSetupNeeded` — все проблемы `value` ключа `agent.default_model` и (есть `event == config.model.none` или нет листов `providers.*`), ветка «нет листа» удалена; `checkProviderReadiness` — модель как у ядра (`CoreConfig.defaultModel`), а не из листа.

## 8. Исправления ревью (2026-11-06)

Пары «тест → реализация»; красные тесты коммитятся отдельно до кода (по просьбе пользователя).

- [x] 8.1 `[agent]` Файл последней модели — чтение и запись (D7; agent-runtime «Последняя выбранная модель», сценарий «Повреждённый файл состояния»):
  - красные тесты `packages/dart/codelab_agent_io/test/state/last_model_file_test.dart`: каталог и FIFO на месте `last-model.json` → `null`, `reason: not a file`, файл не открывается (FIFO — без зависания, только POSIX); файл 4097+ байт → `null`, `reason: too large` без чтения содержимого; файл ровно 4096 байт с валидным JSON читается; отсутствующий `$CODELAB_HOME` создаётся при записи с правами `0700` (кроме Windows);
  - реализация в `codelab_agent_io/lib/src/state/last_model_file.dart`: `stat` перед чтением, проверка типа и размера, чтение ограничено 4097 байтами, `0700` для созданного `$CODELAB_HOME` по образцу `ConfigWriter`.
- [x] 8.2 `[agent]` PERM-11 — пути (D7; сценарий «Файл под защитой PERM-11»):
  - красные тесты `packages/dart/codelab_agent_io/test/config/agent_config_paths_test.dart`: в `agentConfigPathsFor` есть лексический `$CODELAB_HOME/state/last-model.json`, его канонический путь, если файл — ссылка, и каталог `$CODELAB_HOME/state` префиксом (путь `state/other.json` защищён), как `agents`/`prompts`; в `watchedConfigFiles` их нет;
  - реализация в `agent_config_paths.dart`.
- [x] 8.3 `[agent]` PERM-11 — уровень политики (сценарий «Файл под защитой PERM-11»): красный тест в `packages/dart/codelab_agent_core/test/permissions/agent_config_paths_test.dart` (рядом с прочими сценариями PERM-11): инструмент записи с путём `$CODELAB_HOME/state/last-model.json` и с путём внутри `$CODELAB_HOME/state/` при путях хоста из `agentConfigPathsFor` → решение `critical`, как для `config.yaml`. Реализация — только если тест красный (политика PERM-11 уже читает пути хоста).
- [x] 8.4 `[agent]` Событие `not in catalog` (D5; agent-runtime «Модель новой сессии», сценарий «Последней модели нет в каталоге»): красный тест в `codelab_agent_core/test/runtime/session_model_selection_test.dart` — событие `model.last_used.ignored {session_id, reason: not in catalog}` уровня `info`, без идентификатора модели из памяти; реализация в `AgentRuntimeImpl.createSession`.
- [x] 8.5 `[agent]` «Ссылка на секрет не читается при выборе» (agent-configuration, одноимённый сценарий): проверка `store.reads` убрана из `codelab_agent_core/test/config/config_default_model_test.dart` (фейк туда не подключался). `ConfigLoader` хранилища не принимает — гарантия «загрузка и выбор не читают секрет» структурная (CFG-10), описана в комментарии теста. Поведенческая проверка — `packages/dart/codelab_agent_io/test/cli/config_commands_test.dart`: `config check` с провайдером `api_key_secret: codelab/gw` без `agent.default_model` делает столько же чтений хранилища, сколько с явной моделью (чтения — только прежняя проверка состояния секретов), т. е. выбор модели чтений не добавляет.
- [x] 8.6 `[agent]` Снимок без проекта (D1; agent-configuration «Модель по умолчанию без agent.default_model», сценарии «Снимок без проекта при явной модели», «Провайдеры пользователя и проекта», «Доступен только провайдер проекта», «Снимок без проекта без своих моделей»): тесты в `codelab_agent_core/test/config/config_default_model_test.dart` на `CoreConfig.fromLayers` с `projectRoot` и доверенным проектным слоем — модель и источник полного снимка и снимка без проекта. Реализация уже соответствует (`_defaultModel` в `resolve.dart`); тест обязан сначала упасть на подмене правила — иначе он ничего не проверяет.
- [x] 8.7 `[desktop]` `apps/codelab_desktop/integration_test/embedded_provider_settings_flow_test.dart` (сценарий баннера «Новая установка», agent-workbench-ui change `add-provider-setup-ui`): проверка «сырых проблем нет» ищет `no model is configured` вместо `agent.default_model: required` (`findsNothing`), проверка `codelab config check` остаётся. Прогон — только в `release/*` (AGENTS.md §21); в `feature/*` — `fvm flutter analyze` пакета.

## 6. Проверки (AGENTS.md §21, только затронутое)

- [x] 6.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_embedded`, `codelab_setup`, `apps/codelab_agent`, `apps/codelab_cli`. Публичный API ядра изменён, поэтому нужны и зависимые пакеты.
- [x] 6.2 `[agent]` `fvm dart run melos run guard`, `fvm dart run melos run web-compile` (ядро и web-барели), `fvm dart run melos run conformance:agent`, `fvm dart run melos run test:e2e:cli:dart-agent`.
- [x] 6.3 `[agent]` `openspec validate optional-default-model --strict`.
- [x] 6.4 `[agent]` Smoke в изолированном `CODELAB_HOME` (временный каталог, `secrets.backend: file`):
  - `printf 'sk-test-leak-0123456789\n' | codelab-agent provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-stdin` — код `0`, нет `warning: agent.default_model`;
  - `codelab-agent config check` — `Default model: gw/m (first-provider)`, `Config: valid`;
  - `codelab -a embedded` стартует;
  - `grep -r sk-test-leak` по выводу, `config.yaml`, `state/` и логам пуст.
