Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование или сценарий спеки этого change и решение design.md. Красные тесты коммитятся отдельно до кода. Коммит — только по просьбе пользователя: оркестратор спрашивает, а не коммитит сам.

Метка исполнителя — `[agent]` (`codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`; ACP-проекция не меняется, D11). Задач `[protocol]`, `[client]`, `[desktop]` нет: клиенты и мост `codelab_setup` кода не меняют (D11, D12). Итерация 3 `add-provider-setup-ui` вливается в `develop` раньше (D12, п. 4): правки её текстов, тестов и `checkProviderReadiness` делает этот change в разделе 7 после обновления от `develop`; исполнитель раздела 7 — по путям (`codelab_setup` — `[agent]`, клиентские пакеты — `[client]`, app — `[desktop]`).

Тесты — на Dart VM, во временных `CODELAB_HOME` и `cwd`, окружение передаётся явно. Тестовые ключи — `sk-test-leak-…`.

## 0. Документы (сделано в этом change)

- [x] 0.1 `[agent]` `docs/architecture/proposals/agent-core/15-configuration.md`:
  - §15.4, таблица `agent` — `default_model` необязателен, ссылка на правило выбора;
  - §15.5, шаг 8 — правило «нет ни одной модели» и событие `config.model.none`;
  - §15.7 — текст про старт без конфига.
- [x] 0.2 `[agent]` `docs/architecture/proposals/agent-core/17-5-agent-setup.md` — абзац R3-1 о `provider add` без `--default` и `required`.
- [x] 0.3 `[agent]` `docs/architecture/proposals/agent-core/13-acp-adapter.md` — `session/new` не передаёт модель, источник `currentValue` опции `model`.

## 1. Ядро: схема и модель уровня конфига

- [ ] 1.1 `[agent]` Красные тесты `packages/dart/codelab_agent_core/test/config/config_schema_test.dart` и соседние:
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
- [ ] 1.2 `[agent]` Реализация в `codelab_agent_core/lib/src/config/`:
  - `DefaultModelSource` (enum с проводными именами `config`, `last-used`, `first-provider`);
  - `CoreConfig.defaultModelSource` (в конструкторе, `_copyWith`, `withDeferred`, сборке в `resolve.dart`);
  - `_defaultModel` по D1–D4, событие `config.model.none` — константа рядом с `validationIncompleteEvent`;
  - экспорт из публичного бареля, doc-комментарии на русском (почему, для чего, как; ссылки D1–D4; источник идеи — OpenCode, D-контекст).
- [ ] 1.3 `[agent]` Красные тесты перезагрузки `codelab_agent_core/test/runtime/config_reload_test.dart` и `test/config/config_reload_plan_test.dart` — сценарий «Отложенный новый провайдер не становится моделью» (D10); удаление явного ключа — переход на `firstProvider` для новых сессий.
- [ ] 1.4 `[agent]` Реализация D10 в `CoreConfig.withDeferred` (пересчёт неявной модели по итоговым провайдерам) и `config_reload_plan.dart` (неявная модель не выставляет `deferred.defaultModel`).

## 2. Ядро: выбор модели сессии и порт последней модели

- [ ] 2.1 `[agent]` Красные тесты `codelab_agent_core/test/runtime/` (новый `session_model_selection_test.dart`) с фейком `LastModelStore`:
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
- [ ] 2.2 `[agent]` Реализация:
  - порт `LastModelStore` (`codelab_agent_core/lib/src/host/` или `session/`, рядом с портами сервисов) и `AgentCoreServices.lastModel`;
  - чистая функция `selectSessionModel` (D5);
  - `AgentRuntimeImpl.createSession`/`loadSession`/`_Session.setModel` по D5–D6, события `session.model.selected`, `model.last_used.ignored`, `model.last_used.write_failed`;
  - doc-комментарии на русском.
- [ ] 2.3 `[agent]` ACP-проекция без правки кода: прогнать `codelab_agent_acp` тесты `config_options`/`set_config_option` и добавить красный, затем зелёный тест «`session/new` без ключа модели → `currentValue` неявной модели; `set_config_option model` → `write`» на фейке порта (D11).

## 3. `codelab_agent_io`: файл состояния, PERM-11, подкоманды

- [ ] 3.1 `[agent]` Красные тесты `packages/dart/codelab_agent_io/test/state/last_model_file_test.dart`:
  - запись и чтение `{"v":1,"model":"b/y"}`;
  - создание `state/`;
  - уникальный tmp и `rename` — нет `*.tmp-*` после записи;
  - очередь внутри процесса;
  - «Повреждённый файл состояния» (не строка, обрезанный JSON, `v: 9`, больше 4 KiB) — `null`, событие `model.last_used.ignored` с категорией без содержимого, файл не изменён;
  - нет файла — `null` без события;
  - «Секретов нет в файле и логе».
- [ ] 3.2 `[agent]` Реализация `FileLastModelStore` (`lib/src/state/last_model_file.dart`, экспорт из бареля; D7) и обновление `packages/dart/codelab_agent_io/AGENTS.md` §1.
- [ ] 3.3 `[agent]` Красный тест `test/config/agent_config_paths_test.dart`: путь `last-model.json` в `agentConfigPathsFor` и его нет в `watchedConfigFiles` (сценарий «Файл под защитой PERM-11»). Затем реализация в `agent_config_paths.dart`.
- [ ] 3.4 `[agent]` Красные тесты `test/cli/cli_config_commands_test.dart` и `test/cli/provider_commands_test.dart`:
  - тест «без --default в пустом CODELAB_HOME: warning о прежней проблеме, код 0» → нет строк `warning:` (сценарий «provider add в пустом CODELAB_HOME без --default»);
  - строка 184 (`config set` → `warning: agent.default_model: required`) → новый текст («config set и get»);
  - `config check`: «Модель первого провайдера в config check», «Источник модели в config check»;
  - «provider remove единственного провайдера без ключа модели» — нет `change the model first`;
  - «provider remove провайдера последней модели»;
  - `config_writer_test.dart`: «Первая запись в пустой конфиг» (событие), «Первый провайдер без модели по умолчанию».
- [ ] 3.5 `[agent]` Реализация:
  - `ConfigCommands.check` — строка `Default model:` через `selectSessionModel` и `FileLastModelStore.read()`, строка `warning:` о нечитаемом файле (D9);
  - `ProviderCommands.remove` — подсказка по `issue.event` (D9);
  - doc-комментарии.

## 4. Хосты

- [ ] 4.1 `[agent]` Красные тесты:
  - `apps/codelab_agent/test/config_invalid_process_test.dart` — «no model anywhere» ожидает новый текст и `agent.default_model` (agent-binary «Нет ни одной модели»);
  - новый процессный тест «Провайдер без модели по умолчанию» (`session/new` → `currentValue gw/m`);
  - сценарий agent-runtime «Пустой CODELAB_HOME и provider add» — процессный, `provider add` затем `serve --stdio`;
  - комментарий в `serve_flags_test.dart:267` — текст проблемы;
  - `--llm-script` не создаёт `state/` (D8).
- [ ] 4.2 `[agent]` Реализация в `apps/codelab_agent/lib/src/host/agent_host.dart` — `FileLastModelStore` без `--llm-script` (D8).
- [ ] 4.3 `[agent]` Красные тесты `packages/dart/codelab_embedded/test/`: `localEmbeddedAgentOpener` передаёт файловую память над `CODELAB_HOME`; сценарный открыватель — без неё, `state/` не создаётся. Затем реализация в `lib/src/io/local_opener.dart` (D8).

## 5. Совместимость клиентов (только проверка, без правки кода)

- [ ] 5.1 `[agent]` Прогнать тесты, которые видят новый вывод:
  - `apps/codelab_cli/test/provider_mcp_command_test.dart`;
  - `apps/codelab_cli/test/e2e/config_write_command_test.dart`;
  - `apps/codelab_agent/test/config_write_command_process_test.dart`.

  `config check` у CLI и бинаря совпадает по построению. Если тест сверяет stdout `config check` целиком, поправить его в паре «тест → код» задачи 3.4.
- [ ] 5.2 `[agent]` Прогнать тесты `packages/dart/codelab_setup` (`startProblems`, `provider_remove_test.dart`, `file_agent_config_store_test.dart`) и `apps/codelab_desktop/test/features/settings/application/provider_settings_cubit_test.dart`. Ожидание — зелёные без правки (D4, D12); падение — стоп и вопрос пользователю.
- [ ] 5.3 `[agent]` Golden-фикстуры `codelab_acp_testing` задают `default_model` сценарием — изменений нет; прогон `conformance:agent`.

## 7. После слияния итерации 3 `add-provider-setup-ui` (D12, п. 4)

- [ ] 7.1 Обновить ветку от `develop` (через `sync_with_base_branch`), найти в коде, тестах и спеках итерации 3 опору на `agent.default_model: required` и лист `agent.default_model` (`provider_readiness.dart`, `provider_setup_needed_test.dart`, `checkProviderReadiness`, спеки `client-agent-setup`/`agent-workbench-ui`, D26), показать пользователю список до правок.
- [ ] 7.2 Красные тесты: `providerSetupNeeded` на настоящем загрузчике — пустой `CODELAB_HOME` → `true` с новым текстом; «провайдеры есть, ключа модели нет» → `false`; `checkProviderReadiness` берёт модель `CoreConfig.defaultModel` (явная или первый провайдер), а не `NoProviderConfigured`.
- [ ] 7.3 Реализация и правки текстов; delta спек итерации 3 — в этом change (MODIFIED), если её спеки к этому моменту архивированы, иначе согласовать с её сессией.

## 6. Проверки (AGENTS.md §21, только затронутое)

- [ ] 6.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_embedded`, `codelab_setup`, `apps/codelab_agent`, `apps/codelab_cli`. Публичный API ядра изменён, поэтому нужны и зависимые пакеты.
- [ ] 6.2 `[agent]` `fvm dart run melos run guard`, `fvm dart run melos run web-compile` (ядро и web-барели), `fvm dart run melos run conformance:agent`, `fvm dart run melos run test:e2e:cli:dart-agent`.
- [ ] 6.3 `[agent]` `openspec validate optional-default-model --strict`.
- [ ] 6.4 `[agent]` Smoke в изолированном `CODELAB_HOME` (временный каталог, `secrets.backend: file`):
  - `printf 'sk-test-leak-0123456789\n' | codelab-agent provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-stdin` — код `0`, нет `warning: agent.default_model`;
  - `codelab-agent config check` — `Default model: gw/m (first-provider)`, `Config: valid`;
  - `codelab -a embedded` стартует;
  - `grep -r sk-test-leak` по выводу, `config.yaml`, `state/` и логам пуст.
