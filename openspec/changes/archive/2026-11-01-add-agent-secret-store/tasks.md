Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent`, мост `codelab_setup` (реэкспорт `codelab_agent_io`, как в change `add-agent-configuration`) и документы ядра;
- `[client]` — `apps/codelab_cli` и клиентские документы (`09-11-stage-6-cli-mvp.md`, `12-4-first-run-and-settings.md`, `09-12-stage-7-embedded.md`);
- `[desktop]` — только правило во вложенном `AGENTS.md` `apps/codelab_desktop` (D15: общие бэкенды с CLI); страница настроек и встроенный профиль — этап 7/§12.4, не этот change.

Задач `[protocol]` нет; код `codelab_client_*` и `apps/codelab_desktop` не меняется (proposal, «Impact»; design.md, D12, D15).

Итерации — тонкие сквозные срезы, каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: документы;
- итерация 1 — группы 1–4: ядро — имена, резолвер, ссылки в конфиге, ленивое разрешение у провайдеров и MCP; после неё работают переменные `CODELAB_SECRET_*`;
- итерация 2 — группы 5–6: бэкенды `env` и `file`, выбор бэкенда (`auto` = `env`, `keychain` — «not supported yet»), `SecretAdmin`, `openHostSecrets`;
- итерация 3 — группы 7–8: бинарь — `AgentHost`, `--debug-secrets`, `codelab-agent secret`, `config check` с секретами;
- итерация 4 — группа 9: мост `codelab_setup` и `codelab secret`;
- итерация 5 — группа 10: матрица, сверка документов, Definition of Done.

Бэкенды хранилищ ОС, индекс имён, разведка утилит, `ffi` и тест `os-keychain` — в черновике `openspec/changes/add-agent-os-secret-backends/` (после 1.0; решение пользователя 2026-10-31). Сторож и allowlist в этом change не меняются (D1).

Итерация 2 зависит от порта итерации 1; итерация 3 — от итераций 1 и 2; итерация 4 — от `SecretCommands` итерации 3.

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` пакета;
- `fvm dart test` пакета;
- `fvm dart run melos run guard` при правке импортов (`pubspec.yaml` не меняется);
- `fvm dart run melos run web-compile` при правке ядра.

Полный `melos run check` — в CI pull request. Тесты с файлами идут во временных `CODELAB_HOME` и `cwd` и не читают настоящий `~/.codelab`. Хранилищ ОС в этом change нет; процессные тесты — с бэкендом `env` или `file` во временном `CODELAB_HOME`, `chmod` — на фейковом `SecretProcessRunner` или настоящем `/bin/chmod` во временном каталоге. Процессные тесты — с `timeout` (`Timeout(Duration(seconds: 60))`). `test:e2e:app:*` не запускаются (`AGENTS.md` §21).

## 0. Документы (итерация 0)

- [x] 0.1 `[agent]` Документы ядра — отступления и уточнения design.md:
  - `agent-core/17-5-agent-setup.md`:
    - §17.5.2 — `SecretLookup` вместо `String?`, без `redactor` и `invalidate` в 8.9 (D3);
    - §17.5.4 — таблица бэкендов (в 1.0 — `env` и `file`, бэкенды ОС — после 1.0), выбор (`auto` = `env`, `keychain` — «not supported yet»), подсказки `secrets.backend: file`, правила `file` и Windows: **сделано при подготовке change (2026-10-31)**; остаётся — ссылки клиента ACP — литерал (D4);
    - §17.5.9 — флаг `--debug-secrets`, события `secrets.backend.selected`, `secrets.file.refused`;
    - §17.5.13 — имена тестов D12;
  - `agent-core/10-core-assembly-and-profiles.md` §10.3 — `AgentCoreServices.secrets` типа `SecretResolver?`, без `debugSecrets` (D3); реализации в 1.0 — `env` и `file`;
  - `agent-core/15-configuration.md`:
    - §15.4 — `secrets.backend` с этапа 8.9 (`auto | keychain | env | file`; `keychain` — после 1.0);
    - §15.5, п. 7 — шаблон вместо строки, раскрытие при запросе и подключении (D4);
    - §15.6 — `--debug-secrets` и `CODELAB_SECRET_*` с этапа 8.9;
  - `agent-core/12-observability-and-errors.md` §12.2 — примеры ошибок (секрет не задан — `auth`, `keychain` — проблема конфигурации; D4, D7); §12.3 — события D10, `config.secret.unavailable` убрано; §12.4 — абзац «до 8.11» (D10, п. 3);
  - `09-13-stage-8-mcp-config.md`, пункт 9; `agent-parity-goals.md` P-12 — «частично»: **сделано при подготовке change (2026-10-31)**.
- [x] 0.2 `[client]` `09-11-stage-6-cli-mvp.md` (абзац о подкомандах): `secret set|delete|list` — через `codelab_setup/io.dart` в составе 8.9, бэкенд из `secrets.backend` пользовательского конфига и `CODELAB_CONFIG`; в 1.0 запись — только с `secrets.backend: file` (D7, D8). `12-4-first-run-and-settings.md` §12.4.2: в `io.dart` моста с 8.9 — `SecretCommands`, `SecretAdmin`; реэкспорт типов секретов в основном бареле — вместе со страницей настроек (D1, D15); статус ключа и мастер в 1.0 предлагают `file` или переменную, а не хранилище ОС.

- [x] 0.3 `[agent]` Тестовое хранилище в обычной сборке (D14; agent-configuration «Подкоманда config check», сценарий «Тестовое хранилище в обычной сборке»; agent-core §15.6; решение пользователя 2026-10-31). Не зависит от итерации 1, делается отдельной веткой и отдельным PR:
  - тест в `codelab_agent_io/test/config/config_loader_test.dart` (рядом с проверками `config.env.unknown`): обычный прогон `fvm dart test` (без `-D`) с `CODELAB_TEST_SECRET_STORE=<tmp>/test-secrets` даёт предупреждение `config.env.unknown`, текст называет переменную и не содержит значения, каталог не создан; тот же сценарий — на уровне `ConfigCommands` в `codelab_agent_io/test/cli/config_commands_test.dart` (строка `warning:` в stdout, `Config: valid`, код `0`). Красный;
  - `codelab_agent_io/lib/src/config/environment_layer.dart`: `CODELAB_TEST_SECRET_STORE` в `_knownVariables` только при `const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')` (collection-if в константном множестве); doc-комментарий со ссылкой на §15.6 и D14. Тест зелёный. Вариант сборки с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true` проверяет задача 7.7 этапа 7 вместе с чтением переменной.

**Критерий итерации 0.** Документы не расходятся с design.md; в каждом изменённом абзаце есть ссылка на D-решение.

## 1. Имена секретов (итерация 1; D2)

- [x] 1.1 `[agent]` Тесты `codelab_agent_core/test/secrets/secret_names_test.dart` (agent-secrets «Имена секретов», все сценарии): правило, `envOverride`, `suggestFor` для провайдера, MCP `env`/`headers` и бэкенда поиска, `forMcp`; результат всегда проходит правило; текст ошибки не содержит проверяемой строки. Красный.
- [x] 1.2 `[agent]` `lib/src/secrets/secret_names.dart`, экспорт из бареля; doc-комментарии по `AGENTS.md` §15. 1.1 зелёный.

## 2. Порт и резолвер (итерация 1; D3, D10)

- [x] 2.1 `[agent]` Тесты `codelab_agent_core/test/secrets/secret_resolver_test.dart` на `MemorySecretStore` и фейковом `DescribedSecretStore` (agent-secrets «Резолвер секретов», все сценарии):
  - переменная побеждает хранилище;
  - кэш найденного, ненайденное не кэшируется;
  - single-flight;
  - недоступность — одно предупреждение на причину;
  - `env()`;
  - `SecretFound.toString()` без значения.

  Красный.
- [x] 2.2 `[agent]` Тесты `codelab_agent_core/test/secrets/debug_secrets_test.dart` (agent-secrets «Диагностика обращений к секретам», `core/debug-secrets-never-logs-value`, CFG-10): две функции `createRoutedStreamFunction` над одним резолвером (провайдеры `openai` и `org`) дают записи `secrets.lookup` `memory`, `memory`, `cache`, `cache`; повторный ход первой функции записей не добавляет; в сырых `LogRecord` нет значения, его подстрок длиной 4+, длины в полях записи и SHA-256 значения; без режима записей нет. Красный.
- [x] 2.3 `[agent]` `lib/src/secrets/`: `SecretStore`, `DescribedSecretStore`, `SecretBackendInfo`, `SecretStoreUnavailableException`, `SecretLookup` и ветки, `SecretResolver`, `MemorySecretStore` (в `lib/src/testing/` или рядом — по образцу существующих тестовых реализаций ядра); экспорт из бареля. 2.1, 2.2 зелёные, `web-compile` зелёный.

## 3. Ссылки в конфиге (итерация 1; D2, D4, D7)

- [x] 3.1 `[agent]` Тесты `codelab_agent_core/test/config/` (agent-configuration «Секреты только ссылками», все сценарии; `config_inline_secret_test.dart` — `core/config-rejects-inline-api-key` в части пункта 1 CFG-9):
  - строгое имя у `api_key_secret` и `${secret:…}`;
  - `${secret:…}` в `mcp.servers.*.args`, `mcp.servers.*.url` и `providers.*.base_url` — проблема `value` `secret references ${secret:…} are allowed only in env and headers values`;
  - `suggestedSecretName` и текст подсказки у провайдера и MCP;
  - `CatalogProvider.key` (`EnvKeyRef`, `SecretKeyRef`);
  - шаблоны заголовков и `secretValues` MCP, включая литерал `$${secret:x}`;
  - нет `config.secret.unavailable` и записей `providerProblems` о секретах, MCP-сервер со ссылкой не пропущен;
  - `secrets.backend`: `auto`/`env`/`file` приняты без `config.key.not_applied`; `keychain` — проблема `not supported yet`; другое значение — `expected one of: auto, keychain, env, file` (agent-secrets «Выбор бэкенда secrets.backend», сценарии «keychain ещё не поддерживается», «Неизвестный бэкенд»);
  - `secrets` из проектного слоя по-прежнему отброшен;
  - недоверенный проект с `${secret:…}` не даёт ссылок (agent-secrets, сценарий «Недоверенный проект не читает секреты»).

  Красный.
- [x] 3.2 `[agent]` `config/resolve.dart`, `schema.dart`, `config_issue.dart` (`suggestedSecretName`), `host_settings.dart` (`secretsBackend`), `interpolate.dart` (шаблон), `model_catalog.dart` (`CatalogProvider.key`, `headerTemplates`), `mcp/mcp_server_config.dart` (`secretValues`); `_validSecretName` заменяется `SecretNames`. 3.1 зелёный; существующие тесты конфига обновлены только там, где сценарий спецификации изменён этим change.

## 4. Ленивое разрешение у провайдеров и MCP (итерация 1; D4)

- [x] 4.1 `[agent]` Тесты `codelab_agent_core/test/llm/routed_stream_function_secrets_test.dart` на фейковом `http.Client` и `MemorySecretStore` (agent-secrets «Ключ провайдера при запросе», все сценарии):
  - ключ из хранилища, одно чтение на два хода;
  - не задан → `auth` без HTTP и успех после записи без перезапуска;
  - недоступно → текст с бэкендом и переменной;
  - заголовок с `${secret:…}`;
  - `api_key_env` через `env()`;
  - отмена во время ожидания — `aborted` (`LlmErrorClass.aborted`, `StopReason.aborted`) не позже 1 с;
  - без резолвера `api_key_env` и `api_key_secret` → `… cannot be read: the host has no secret resolver`, HTTP-запроса нет;
  - тело `401`, содержащее только сырое значение секрета заголовка, — значения нет в тексте ошибки;
  - два одновременных первых запроса — одно чтение;
  - значения нет в тексте ошибки.

  Красный.
- [x] 4.2 `[agent]` `createRoutedStreamFunction(…, secrets:)` в `llm/provider_factory.dart`; doc-комментарий обновлён (больше не «ключ уже разрешён при загрузке»). 4.1 зелёный.
- [x] 4.3 `[agent]` Тесты `codelab_agent_core/test/runtime/mcp_secret_values_test.dart` на фейковом `McpConnector` (agent-secrets «Секреты MCP-серверов конфигурации», все сценарии):
  - заголовок из хранилища;
  - ненайденный секрет → `mcp.server.failed`, остальные серверы подключены;
  - ссылка клиента ACP — литерал;
  - без `services.secrets` → причина `no secret store`;
  - `dispose()` и `close()` во время раскрытия → результат отброшен, `connect` не вызван, `mcp.server.failed` нет;
  - раскрытие при `loadSession` и `setMcpServers`;
  - заголовки после раскрытия в порядке файла конфига;
  - лог и журнал без значения.

  Красный.
- [x] 4.4 `[agent]` `AgentCoreServices.secrets` (`host/services.dart`), раскрытие в `AgentRuntimeImpl` перед `connect` (`runtime/agent_runtime.dart`). 4.3 зелёный.
- [x] 4.5 `[agent]` `apps/codelab_agent`: `AgentHost` временно передаёт резолвер над бэкендом `env` (D3, Migration Plan, итерация 1); характеризационный тест `serve` с `api_key_env` проходит без изменений. **Конец итерации 1.**

## 5. Бэкенды `env` и `file`, выбор бэкенда (итерация 2; D5–D7, D14)

- [x] 5.1 `[agent]` Тесты `codelab_agent_io/test/secrets/env_secret_store_test.dart` (agent-secrets «Бэкенды env и file», сценарий «env только для чтения»). Красный.
- [x] 5.2 `[agent]` Тесты `codelab_agent_io/test/secrets/file_secret_store_test.dart` во временном `CODELAB_HOME` на macOS и Linux (agent-secrets «Бэкенд file», все сценарии):
  - права `0644` → отказ чтения, записи и `names()` с текстом `chmod 600`, одно `secrets.file.refused`;
  - символическая ссылка → отказ;
  - отсутствующий файл: `read`/`delete`/`names()` файл не создают;
  - запись создаёт файл с правами `0600`; права выставлены до записи значения (фейковый `SecretProcessRunner` для `/bin/chmod` проверяет, что в момент вызова файл пуст; в argv только путь);
  - сбой между временным файлом и переименованием оставляет прежний файл, следующий `write` удаляет брошенный tmp старше 10 минут; свежие, чужие tmp и ссылки не удаляются; tmp — в приватном `.secrets-tmp` (`0700`), очередь записей на путь общая для экземпляров;
  - `$CODELAB_HOME` — ссылка или с записью для группы/остальных → отказ без изменения каталога; созданный бэкендом каталог — `0700`;
  - размер файла ≤ 1 МиБ (и при записи), значение ≤ 64 КиБ, непарный суррогат отклонён; `secrets.file.refused` один раз на процесс и путь;
  - значения с `"`, `\` и не-ASCII читаются обратно; значение с переводом строки отклонено;
  - битая структура → исключение без строк файла;
  - подменённая платформа `windows` → отказ.

  Красный.
- [x] 5.3 `[agent]` `SecretProcessRunner`, `IoSecretProcessRunner`, `EnvSecretStore`, `FileSecretStore` с явным путём (D14: переиспользование тестовым хранилищем этапа 7); экспорт из бареля `codelab_agent_io`. 5.1, 5.2 зелёные; `pubspec.yaml` не меняется.
- [x] 5.4 `[agent]` Тесты `codelab_agent_io/test/secrets/open_secret_store_test.dart` (agent-secrets «Выбор бэкенда secrets.backend», сценарии «auto — env на всех ОС», «auto не выбирает file»): `auto` = `env` на macOS/Linux/Windows без процессов и с причиной, называющей `secrets.backend: file` (на Windows — только `CODELAB_SECRET_*`); недопустимое значение — `SecretStoreUnavailableException` с текстом `secretsBackendProblem`; `env`; `file`; `secrets.backend.selected` один раз. Тест `config_loader_test.dart`: `file` на подменённой платформе Windows — проблема конфигурации (agent-secrets «Бэкенд file», сценарий «file на Windows»). Красные.
- [x] 5.5 `[agent]` `openSecretStore`; проблема `file` на Windows в `ConfigLoader`. 5.4 зелёные.

## 6. `SecretAdmin` и `openHostSecrets` (итерация 2; D15)

- [x] 6.1 `[agent]` Тесты `codelab_agent_io/test/secrets/secret_admin_test.dart` (agent-secrets «Программная запись секретов», все сценарии): типизированные результаты `SecretStored`/`SecretUpdated`/`SecretInvalidName`/`SecretInvalidValue`/`SecretCollision`/`SecretReadOnly`/`SecretFailed`, `SecretDeleted`/`SecretNotSet`, `SecretListing`/`SecretListFailed`; `SecretReadOnly` у `env` с данными подсказки (`variable`, `fileBackendOffered`); `checkStore` без значения; значение ни в argv, ни в stdin дочерних процессов; `toString` результатов без значения. Красный.
- [x] 6.2 `[agent]` `SecretAdmin` и результаты; экспорт из бареля. 6.1 зелёный; задача 8.2 строит `SecretCommands` поверх него.
- [x] 6.3 `[agent]` Тесты `codelab_agent_io/test/secrets/host_secrets_test.dart` (agent-secrets «Секреты настольных хостов и встроенных профилей», все сценарии): `openHostSecrets` внутри `Isolate.run` из сериализуемых данных — наружу только `found`/`source`, лог без значения; общий секрет через `SecretAdmin` и резолвер на бэкенде `file`; замена прочитанного секрета видна только новому резолверу. Красный.
- [x] 6.4 `[agent]` `openHostSecrets` в `lib/src/secrets/host_secrets.dart`; экспорт из бареля. 6.3 зелёный. **Конец итерации 2.**

## 7. Бинарь: хранилище и отладка (итерация 3; D11)

- [x] 7.1 `[agent]` Процессные тесты `apps/codelab_agent/test/` (agent-binary «Хранилище секретов в бинаре», все сценарии):
  - ключ из `CODELAB_SECRET_*` к локальному HTTP-серверу теста;
  - ошибка хода `API key secret … is not set` при `secrets.backend: env`;
  - `--debug-secrets` и `CODELAB_DEBUG_SECRETS=1` → `secrets.lookup` без значения;
  - `--llm-script` с `secrets.backend: file` в `--config` — бэкенд `env`, `secrets.yaml` не открывается, `secrets.backend.selected {backend: env, reason: forced by --llm-script}`;
  - `secrets.backend: file` → `secrets.backend.plaintext` при старте, файл не создан;
  - `secrets.backend: keychain` → код `64` до старта транспорта, текст `not supported yet`;
  - stdout, stderr и лог не содержат значения.

  Красный.
- [x] 7.2 `[agent]` `AgentHost.build` через `openHostSecrets` (задача 6.4) с `selectionReason` для `--llm-script` (D11, D15); флаг `--debug-secrets` в `serve_args.dart`; справка `serve`. 7.1 зелёный.

## 8. `codelab-agent secret` и `config check` (итерация 3; D8, D9)

- [x] 8.1 `[agent]` Тесты `codelab_agent_io/test/cli/secret_commands_test.dart` на фейковом `SecretInput` и фейковом хранилище (agent-secrets «Подкоманды secret», все сценарии):
  - `set` с TTY и без, `\n`/`\r\n`, пустое значение, перевод строки внутри, недопустимый UTF-8 (`secret value must be valid UTF-8`);
  - значение аргументом и неверное имя → `64` с `showUsage`, без печати аргумента (`hasValueArgument`); ошибки значения и коллизия → `64` без `showUsage`;
  - недопустимый `CODELAB_CONFIG` (относительный, расширение не `.yaml`/`.yml` без учёта регистра) → `warning: CODELAB_CONFIG ignored: <reason>`, бэкенд из `$CODELAB_HOME/config.yaml`, код не меняется;
  - коллизия `envOverride`; бэкенд `env` (и `auto`) → `1` с подсказкой `secrets.backend: file` и переменной, на Windows — только переменной;
  - `Stored secret …`/`Updated secret …` (по `SecretStored`/`SecretUpdated`); подсказка `SecretReadOnly` с настоящим путём `$CODELAB_HOME`; порядок D8 через `SecretAdmin.checkStore`;
  - `delete` существующего и отсутствующего;
  - `list` с бэкендом, причиной и строкой `Environment overrides`;
  - невалидный конфиг с `api_key` не блокирует;
  - бэкенд `file`: строка `warning: secrets are stored unencrypted` в stderr каждой подкоманды, отказ по правам → код `1`;
  - синтаксическая ошибка YAML → `1`;
  - ни в одной строке нет значения и длины.

  Красный.
- [x] 8.2 `[agent]` `lib/src/cli/secret_commands.dart` (`SecretSetOptions.hasValueArgument`, `SecretCommandResult.showUsage`, параметр `platform`), `secret_input.dart` (`SecretInput`, `StdinSecretInput`: неканонический режим без эха, ручные Backspace и Ctrl+D, отказ многострочной вставки с вычиткой остатка, восстановление режимов в `finally` и по `SIGINT` с кодом `130`; D8); экспорт из бареля. 8.1 зелёный.
- [x] 8.3 `[agent]` Тесты `codelab_agent_io/test/cli/config_commands_test.dart` (agent-configuration «config check показывает состояние секретов», все сценарии): строки `note:`/`warning:` перед `Config: …`; при `env` подсказка `secrets.backend: file`; код не меняется; без ссылок хранилище не вызывается и вывод прежний; `secrets.backend: file` — строка об открытом тексте всегда; отказ — одна строка (права `0644` → `has permissions 0644; run: chmod 600`, иначе `file is unavailable (<reason>)`) без строк по именам; `<location>` из `ConfigLoader.loadWithLayers`. Красный.
- [x] 8.4 `[agent]` `ConfigCommands.check` — проверка ссылок резолвером. 8.3 зелёный.
- [x] 8.5 `[agent]` Процессные тесты `apps/codelab_agent/test/secret_command_process_test.dart` (agent-binary «Подкоманда secret бинаря», все сценарии; agent-secrets, сценарии «Значение аргументом», «Ошибка разбора argv не цитирует слово», «Недопустимый CODELAB_CONFIG», «Только чтение при auto», «Сохранение в file»): неизвестная подкоманда, ошибка argv → `codelab-agent: invalid arguments for secret` без присланного слова, справка только при ошибках использования, `list` с `env`, справка бинаря называет `secret`. Красный.
- [x] 8.6 `[agent]` `apps/codelab_agent/lib/src/cli/secret_cli.dart`, регистрация в `run.dart`, общая справка; вложенный `AGENTS.md` приложения (§1, §2: команды `secret`, `--debug-secrets`). 8.5 зелёный.
- [x] 8.7 `[agent]` Ручная проверка скрытого ввода в настоящем pty (macOS и Linux; автотест не владеет терминалом, D8): обычный ввод сохраняет значение без эха; вставка нескольких строк → код `64` `secret value must be a single line`, ничего не записано, вставленные строки не выполнились оболочкой; Ctrl+C во время ввода → код `130`, эхо и построчный режим терминала восстановлены. Результат — запись в описании pull request. **Конец итерации 3.** Проверено 2026-11-01 на macOS (`script`): обычный ввод — 0, две строки одним куском и через 20 мс — 64, Ctrl+C — 130, 2000 символов — 0, Backspace — 0; во всех случаях эхо восстановлено. На Linux не проверялось.

## 9. Мост и `codelab secret` (итерация 4; D1, D8)

- [x] 9.1 `[agent]` `codelab_setup/lib/io.dart` — реэкспорт `SecretCommands`, `SecretCommandResult`, `SecretSetOptions`, `SecretDeleteOptions`, `SecretListOptions`, `SecretInput`, `StdinSecretInput`, `SecretAdmin` с результатами и `openSecretStore` (D15); основной барель не меняется; тест компиляции реэкспортов; вложенный `AGENTS.md` моста (§1, §3). `melos run guard` зелёный, `setupAllowlist` не меняется.
- [x] 9.2 `[client]` Тесты `apps/codelab_cli/test/secret_command_test.dart` и e2e процесса (codelab-cli «Подкоманда codelab secret», все сценарии; agent-secrets, сценарий «Одинаковый вывод двух бинарей»):
  - совпадение вывода с `codelab-agent secret` на ошибках использования и `list`;
  - флаги подключения → `64`;
  - без подкоманды и с неизвестной;
  - `CODELAB_HOME` не изменён;
  - справка `--help`.

  Красный.
- [x] 9.2a `[desktop]` Создать новый вложенный `apps/codelab_desktop/AGENTS.md` (сейчас его нет) — минимальный, только правило секретов: секреты — только через общие бэкенды `codelab_agent_io` (через `codelab_setup/io.dart` и `codelab_embedded`), `flutter_secure_storage` на desktop не используется (D15, D16). Кода нет. Корневые `AGENTS.md` и `CLAUDE.md` говорят о вложенных `AGENTS.md` в общем виде, их правка не нужна.
- [x] 9.2b `[client]` `09-12-stage-7-embedded.md`: `desktopHostServices` и `_agentMain` вызывают `openHostSecrets`; `DesktopServicesSpec` с `codelabHome`, `secretsBackend`, `debugSecrets`; в 1.0 встроенный профиль использует `env` и `file`; известное ограничение кэша; `CODELAB_TEST_SECRET_STORE` — бэкенд `file` с явным путём (D14, D15). **Сделано при подготовке change (2026-10-31)**, сверить в 10.2.
- [x] 9.3 `[client]` `CliCommand.secret` в `cli_args.dart`, вызов в `run.dart` через `package:codelab_setup/io.dart`; строка в `--help`; вложенный `AGENTS.md` CLI (§1). 9.2 зелёный, `melos run guard` зелёный. **Конец итерации 4.**

- [x] 9.4 `[agent]` Тесты `codelab_agent_io/test/cli/secret_commands_test.dart` и `codelab_setup/test/secret_exports_test.dart` (agent-secrets «Подкоманды secret», сценарий «Нет домашнего каталога»; «SecretAdmin», реэкспорт `DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger`): пустые `CODELAB_HOME`, `HOME`, `USERPROFILE` → `64`, stdin не читается, `./.codelab` не создан; `serve` не затронут. Красный.
- [x] 9.5 `[agent]` Проверка домашнего каталога в `SecretCommands` (D8, «Нет домашнего каталога»); реэкспорт трёх типов в `codelab_setup/lib/io.dart` (D15). 9.4 зелёный.
- [x] 9.6 `[client]` Тесты `apps/codelab_cli/test/secret_command_test.dart` и `cli_args_test.dart` (codelab-cli «Подкоманда codelab secret»; agent-secrets, сценарий «Ошибка флага верхнего уровня перед secret»): `-C`/`--cwd` с `secret` → `codelab: --cwd does not apply to secret`; любая ошибка разбора при `secret` в argv — только `codelab: invalid arguments for secret` и справка, без текста `package:args`. Красный.
- [x] 9.7 `[client]` Правка `cli_args.dart`/`run.dart` по 9.6 (D8). 9.6 зелёный, `melos run guard` зелёный.

## 10. Матрица, документы и Definition of Done (итерация 5)

- [x] 10.1 `[agent]` Матрица этапа 8 в `09-13-stage-8-mcp-config.md` и `agent-parity-goals.md`:
  - P-12 — «частично: `env` и `file`, пункт 1 CFG-9; хранилище ОС — после 1.0 (`add-agent-os-secret-backends`), пункты 2–3 CFG-9 — 8.11» с файлами тестов;
  - P-17 — `debug_secrets_test.dart`;
  - итог 8.9 абзацем, как у 8.6–8.8.
- [x] 10.2 `[agent]` Сверка документов с кодом (`codelab_agent_core/AGENTS.md` §3, критерий (е)):
  - §17.5.2, §17.5.4, §17.5.9, §17.5.13, §10.3, §15.4–§15.6, §12.2–§12.4;
  - вложенные `AGENTS.md` `codelab_agent_io` (§1: хранилища секретов `env` и `file` вместо «ещё не созданы»), `codelab_setup`, `apps/codelab_agent`, `apps/codelab_cli`;
  - doc-комментарии новых сущностей на русском (`AGENTS.md` §15).
- [x] 10.3 `[agent]` Definition of Done change:
  - все сценарии спецификаций этого change покрыты тестами задач 1–9;
  - `melos run guard`, `web-compile` зелёные;
  - сторож и allowlist не менялись (D1);
  - `openspec validate add-agent-os-secret-backends --strict` зелёный (черновик после 1.0 не устарел относительно D-решений 8.9);
  - `openspec validate add-agent-secret-store --strict` зелёный;
  - полный `melos run check` — зелёный в CI PR #205 (последняя итерация, все проверки `ci` успешны).

  Сверка 10.1–10.2 (2026-11-01). 10.1: P-12 — «частично: `env` и `file`, пункт 1 CFG-9; хранилище ОС — после 1.0, пункты 2–3 CFG-9 — 8.11» с файлами тестов, P-17 — «выполнено» (`debug_secrets_test.dart`) в `agent-parity-goals.md`; итог 8.9, таблица DoD 8.9 и scope change в `09-13-stage-8-mcp-config.md` (тест `secret_store_backends_test.dart` относится к черновику `add-agent-os-secret-backends`). 10.2: документы сверены с кодом — §17.5.2 (`SecretNames.maxLength`, правило `suggestFor`, `SecretTemplate`/`MemorySecretStore`, `suggestedSecretName` с 8.9), §17.5.4 (объём CFG-9 в 8.9, английский текст `inlineSecret`, `SecretResolver.env` читает окружение резолвера, правило «нет домашнего каталога» у `secret`), §17.5.10 (пример ошибки и исправления в 1.0), §17.5.13 (фактические файлы и состав тестов), §15.3–§15.5 (`secrets.*` с 8.9 из пользовательского конфига и `--config`, `${secret:…}` в `headers`/`env` с 8.9, текст `inlineSecret`, шаг 3 загрузки); §10.3, §15.6, §12.2–§12.4 расхождений не имеют. Вложенные `AGENTS.md`: `codelab_agent_io` (§1 `lib/src/secrets/`, §3 тесты секретов), `codelab_setup` (§4), `apps/codelab_agent` (§2: `selectionReason`, `plaintext`, классы ошибок `secret`), `apps/codelab_cli` (§2: флаги и ошибки разбора с `secret`). Найдено расхождение кода со спецификацией: `FileSecretStore` при файле больше 1 МиБ отказывал без `secrets.file.refused`; исправлено в итерации 5 (дефект 1 ниже), причина `too_large` добавлена в §12.3, design.md (D10, D14) и agent-secrets «Бэкенд file».

  Сверка DoD 2026-11-01 (итерация 5). Сторож и allowlist (D1): `git log 647a0d5^..HEAD` и `git diff 647a0d5^..HEAD` по `packages/dart/codelab_architecture_tests` и по `pubspec.yaml` всех пакетов и приложений пусты, незакоммиченных правок там нет. Прогоны 2026-11-01: `fvm exec melos run guard` (68 тестов) и `fvm exec melos run web-compile` — exit 0; `openspec validate add-agent-secret-store --strict` и `openspec validate add-agent-os-secret-backends --strict` — valid. Черновик `add-agent-os-secret-backends` сверен с D-решениями 8.9 (порт `SecretProcessRunner`/`SecretProcessResult`, `secretsBackendProblem`, синхронные `openSecretStore`/`openHostSecrets` с `selectionReason`, механизм записи `FileSecretStore`, `SecretAdmin`): `design.md` («Сверка с итогом 8.9», D2, D3, D5, OQ3, OQ4) и `proposal.md` («Impact») обновлены. Полный `melos run check` подтверждается CI pull request.

  Дефекты, найденные при сверке DoD и исправленные в итерации 5 (тест, затем код):
  1. `FileSecretStore` при `secrets.yaml` больше 1 МиБ отказывал при чтении без `secrets.file.refused`; теперь — `secrets.file.refused {path, reason: too_large}` один раз на процесс и путь (`io/secrets/file_secret_store_test.dart`, «a file over 1 MiB on read is refused with secrets.file.refused {reason: too_large}, once per process and path»).
  2. `codelab-agent --<слово> secret list` печатал текст `package:args` с присланным словом (возможно, значением секрета) и справку `serve`; теперь `apps/codelab_agent/lib/src/run.dart` при `secret` в argv печатает только `codelab-agent: invalid arguments for secret` и справку `secret` (`agent/secret_command_process_test.dart`, «a top-level flag error before secret (…): 64, fixed text, the secret usage, no echo»).

  Сценарий спецификации → тест (пути от корня; `core` = `packages/dart/codelab_agent_core/test`, `io` = `packages/dart/codelab_agent_io/test`, `agent` = `apps/codelab_agent/test`, `cli` = `apps/codelab_cli/test`):

  | Спецификация, сценарий | Тест | Покрытие |
  |---|---|---|
  | agent-secrets «Переменная переопределения» | `core/secrets/secret_names_test.dart` («uppercases and maps every character outside [A-Z0-9] to _») | да |
  | agent-secrets «Предлагаемое имя MCP» | там же («an MCP env or header suggests codelab/mcp/<server>/<key>», «the result always passes the rule») | да |
  | agent-secrets «Предлагаемое имя ключа элемента MCP и запасной вариант» | `core/secrets/secret_names_test.dart` («a path without a rule falls back to the codelab/ prefix»: `mcp.servers[GitHub].token` → `codelab/mcp/github/token`, `tools.exec.Api Token` → `codelab/tools.exec.api-token`) | да |
  | agent-secrets «Неверные имена» | там же («rejects other names with the rule text, never with the name») | да |
  | agent-secrets «Переменная побеждает хранилище» | `core/secrets/secret_resolver_test.dart` («a variable wins over the store and the store is not read») | да |
  | agent-secrets «Кэш и отсутствие» | там же («a found value is cached, a missing one is not») | да |
  | agent-secrets «Одно обращение на имя» | там же («concurrent requests of one name make one read») | да |
  | agent-secrets «Хранилище недоступно» | там же («two names give two SecretUnavailable and one warning») | да |
  | agent-secrets «Ключ из хранилища» | `core/llm/routed_stream_function_secrets_test.dart` («the key comes from the store; two turns make one read») | да |
  | agent-secrets «Секрет не задан» | там же («not set: auth without HTTP, then success after a write without a restart») | да |
  | agent-secrets «Отмена во время ожидания хранилища» | там же («cancellation ends the stream as aborted within 1 s, no HTTP») | да |
  | agent-secrets «Хост без резолвера» | там же (группы `api_key_env` и `api_key_secret`: «without a resolver …») | да (переменная процесса в тесте не задаётся: без резолвера ядро окружение не читает вовсе) |
  | agent-secrets «Сырое значение в теле ошибки» | там же («the bare value in a 401 body reaches neither the error nor the log») | да |
  | agent-secrets «Заголовок из хранилища» | `core/runtime/mcp_secret_values_test.dart` («a header value comes from the store; log and journal stay clean») | да |
  | agent-secrets «Порядок заголовков сохраняется» | `core/config/config_secret_refs_test.dart` («withSecrets keeps the header order of the config file …»); там же в рантайме — `X-Plain`, `Authorization` | да |
  | agent-secrets «Закрытие во время раскрытия» | `core/runtime/mcp_secret_values_test.dart` (группа `dispose`: «during expansion the result is discarded and connect is not called» — `connect` не вызван, `mcp.server.failed` нет; `setMcpServers`: «close() during expansion ends quietly …») | да |
  | agent-secrets «Ненайденный секрет MCP» | там же («a missing secret fails only its server») | да |
  | agent-secrets «Ссылка от клиента ACP — литерал» | там же («a client server keeps a literal ${secret:…}; the store is not read») | да |
  | agent-secrets «Недоверенный проект не читает секреты» | `core/config/config_secret_refs_test.dart` (группа `untrusted project`) | да |
  | agent-secrets «env только для чтения» | `io/secrets/env_secret_store_test.dart` («reads CODELAB_SECRET_* and refuses write and delete») | да |
  | agent-secrets «Права шире 0600» | `io/secrets/file_secret_store_test.dart` («0644 refuses read, write, delete and names with chmod hint»); `SecretUnavailable` — `secret_resolver_test.dart` | да |
  | agent-secrets «Символическая ссылка» | там же («a symbolic link is refused even if its target is 0600») | да |
  | agent-secrets «Файл создаёт только запись» | там же («read, delete and names of a missing file do not create it», «write creates the file with 0600 and read returns the value») | да |
  | agent-secrets «Атомарная запись» | там же («a tmp file with wider permissions never receives the value», «tmp directory widened after createSync: refused, no value on disk» — сбой после создания tmp; «a failure before the rename keeps the old file and the next write removes the leftover tmp» — брошенный tmp старше 10 минут) | да (сочетанием) |
  | agent-secrets «Свежие и чужие временные файлы не удаляются» | там же («removes only abandoned files; fresh foreign tmp and links survive») | да |
  | agent-secrets «Каталог секретов доступен на запись другим» | там же (группа `directory safety`) | да |
  | agent-secrets «Чужой каталог секретов» | там же («a failing no-op chmod of home (foreign owner) refuses the write before any tmp file exists») | да |
  | agent-secrets «Широкие права после переименования» | там же (группа `wide permissions after rename`) | да |
  | agent-secrets «Каталог секретов создаёт запись» | там же («a newly created CODELAB_HOME is made private independent of umask»; `0600` — «write creates the file with 0600 …») | да |
  | agent-secrets «Записи разных экземпляров не теряются» | там же («two instances over one path lose no update; file stays 0600») | да |
  | agent-secrets «file на Windows» | `io/config/config_loader_test.dart` (группа `secrets.backend: file on Windows`); `file_secret_store_test.dart` («the substituted platform refuses every operation») | да |
  | agent-secrets «auto — env на всех ОС» | `io/secrets/open_secret_store_test.dart` (группа `auto is env on every OS`, «no backend of this version starts a process») | да |
  | agent-secrets «Недопустимое значение у openSecretStore» | там же («file on Windows is a typed failure …», «keychain and unknown choices are typed failures with spec texts») | да |
  | agent-secrets «auto не выбирает file» | там же («auto never selects file even if secrets.yaml exists») | да |
  | agent-secrets «keychain ещё не поддерживается» | `core/config/config_secret_refs_test.dart` («keychain is a problem: not supported yet»); `agent/secret_store_process_test.dart` («secrets.backend: keychain exits 64 before the transport starts»); `io/cli/config_commands_test.dart` («secrets.backend: keychain: проблема конфигурации, код 1»); `agent/config_command_process_test.dart` («config check: secrets.backend: keychain gives code 1 and the problem, no transport») | да |
  | agent-secrets «Неизвестный бэкенд» | `core/config/config_secret_refs_test.dart` («another value is a problem with the list of values») | да |
  | agent-secrets «Значение аргументом» | `io/cli/secret_commands_test.dart` («значение аргументом: код 64, хранилище не открывается …»); `agent/secret_command_process_test.dart` («a value argument …»); `cli/secret_command_test.dart` («a value passed as an argument: 64, never printed») | да |
  | agent-secrets «Значение из stdin без TTY» | `io/cli/secret_commands_test.dart` («без TTY: весь поток без одного завершающего \n») | да |
  | agent-secrets «Перезапись существующего секрета» | там же («перезапись: Updated secret, без вопроса и флага») | да |
  | agent-secrets «Конфиг с ключом значением не мешает set» | там же («невалидный конфиг с api_key значением не блокирует») | да |
  | agent-secrets «Коллизия переменной» | там же («коллизия envOverride: код 64, называет оба имени и переменную …») | да |
  | agent-secrets «Только чтение при auto» | там же («бэкенд env (auto): код 1, stdin не читается …»); `agent/secret_command_process_test.dart` («auto: set is read-only, code 1, stdin is not read») | да |
  | agent-secrets «Сохранение в file» | `io/cli/secret_commands_test.dart` («file: secrets.yaml создан с правами 0600 …»); `agent/secret_command_process_test.dart` («file: set stores from stdin, then list and delete work») | да |
  | agent-secrets «Одинаковый вывод двух бинарей» | `cli/e2e/secret_command_test.dart` («env backend: list is identical in both binaries …») | да |
  | agent-secrets «Ошибка значения без справки» | `io/cli/secret_commands_test.dart` («пустое значение …: код 64», `showUsage == false`) | да |
  | agent-secrets «Недопустимый UTF-8» | там же («недопустимый UTF-8 без TTY: код 64, ничего не сохранено», `showUsage == false`); `io/cli/secret_input_test.dart` | да |
  | agent-secrets «Ошибка разбора argv не цитирует слово» | `agent/secret_command_process_test.dart` («the value as …: code 64, the secret usage, no part of the value in the output») | да |
  | agent-secrets «Вставка нескольких строк в TTY» | `io/cli/secret_commands_test.dart` («многострочная вставка с TTY …»); `io/cli/secret_input_test.dart` (байты после перевода строки) | да |
  | agent-secrets «Слова secret после другой команды» | `agent/secret_command_process_test.dart` («serve --stdio with trailing secret tokens: 64, rest tokens are never quoted»; тот же тест для `config check`) | да |
  | agent-secrets «Недопустимый CODELAB_CONFIG» | `io/cli/secret_commands_test.dart` («CODELAB_CONFIG с относительным путём игнорируется с предупреждением, код выхода прежний» — `set`; «CODELAB_CONFIG с чужим расширением …» — `list`, `Backend: env`, код `0`) | да (сочетанием) |
  | agent-secrets «Нет домашнего каталога» | `io/cli/secret_commands_test.dart` (группа `без домашнего каталога`: «set с secrets.backend: file в CODELAB_CONFIG: код 64, stdin не читался, ничего не создано», «delete и list: код 64 и тот же текст»); `agent/secret_command_process_test.dart` («no home folder at all: secret list exits 64 and creates nothing in cwd», «no home folder at all: set with secrets.backend: file in CODELAB_CONFIG exits 64 and creates nothing in cwd») | да |
  | agent-secrets «Ошибка флага верхнего уровня перед secret» | `cli/secret_command_test.dart` («a bad top-level flag before secret: 64, fixed phrase, flag not echoed»); `agent/secret_command_process_test.dart` («a top-level flag error before secret (…): 64, fixed text, the secret usage, no echo») | да |
  | agent-secrets «Значение не попадает в лог» | `core/secrets/debug_secrets_test.dart` (группа `provider path`: «two turns: lookups are memory, then cache …») | да |
  | agent-secrets «Без режима» | там же («without the mode there are no secrets.lookup records») | да |
  | agent-secrets «Резолвер внутри isolate» | `io/secrets/host_secrets_test.dart` («openHostSecrets works inside an isolate from serializable data …») | да |
  | agent-secrets «Общий секрет CLI и встроенного агента» | там же («a secret saved by SecretAdmin is found by the resolver on the file backend») | да |
  | agent-secrets «Замена прочитанного секрета требует перезапуска» | там же («a replaced secret is seen only by a new resolver») | да |
  | agent-secrets «Запись из приложения и список в CLI» | `cli/secret_command_test.dart` («SecretAdmin.store from the app, then codelab secret list shows the name and never the value»); значение не в argv и stdin дочерних процессов — `io/secrets/secret_admin_test.dart` («no child process receives the value in argv or stdin») | да |
  | agent-secrets «Отказ без исключения» | `io/secrets/secret_admin_test.dart` («invalid name and invalid value are results, the store is not called») | да |
  | agent-secrets «Предварительная проверка без значения» | там же (группа `checkStore`) | да |
  | agent-secrets «Бэкенд только для чтения на Windows» | там же («env is read-only: structured data, file backend offered», «on Windows the file backend is not offered, only the variable») | да |
  | agent-configuration «file на Windows при загрузке» | `io/config/config_loader_test.dart` (группа `secrets.backend: file on Windows`) | да |
  | agent-configuration «Ключ значением» | `core/config/config_inline_secret_test.dart` (группа `providers.*`); `agent/config_invalid_process_test.dart` («a key written as a value: the secret is in neither stderr nor the log file»); `io/cli/config_commands_test.dart` («an inline secret never reaches the output») | да |
  | agent-configuration «Токен значением у MCP-сервера» | `core/config/config_inline_secret_test.dart` («a token value names the command and the ${secret:…} form») | да |
  | agent-configuration «Ключ вместо имени переменной» | `core/config/config_secrets_test.dart` («api_key_env that is not a variable name is a problem without the value anywhere») | да |
  | agent-configuration «Ключ вместо имени секрета» | `core/config/config_secret_refs_test.dart` («api_key_secret follows the strict rule, the name is not echoed») | да |
  | agent-configuration «Ссылка на секрет в args MCP-сервера» | там же («a reference outside env and headers is a problem») | да |
  | agent-configuration «Ссылка на секрет в base_url провайдера» | там же («providers.*.base_url with a reference is a value problem») | да |
  | agent-configuration «Переменная ключа не задана» | `core/config/config_secrets_test.dart` («an unset variable is a warning and a provider problem …»); `core/llm/routed_stream_function_secrets_test.dart` («an unset variable is an auth failure without HTTP») | да |
  | agent-configuration «Ссылки на секреты не читаются при загрузке» | `core/config/config_secret_refs_test.dart` («references are not read at load …») | да (загрузка ядра хранилища не получает вовсе) |
  | agent-configuration «Битый конфиг», «Предупреждения не делают конфиг невалидным», «Подсказка о codelab.toml», «Несуществующий каталог», «Ошибка использования из окружения» (прежние) | `io/cli/config_commands_test.dart` («a typo …», «an unknown CODELAB_* variable is a warning line …», «codelab.toml alone …», «a missing cwd is a usage error: code 64», «a bad CODELAB_CONFIG file name is a usage error …»); `agent/config_command_process_test.dart` | да (DoD change `add-agent-configuration`) |
  | agent-configuration «CODELAB_CONFIG учитывается» (прежний) | `io/cli/config_commands_test.dart` («CODELAB_CONFIG is honoured: absolute extra.yaml with an unknown key appears in Sources: and its problem gives code 1 (agent-configuration, CODELAB_CONFIG учитывается)»); слои — `io/config/config_loader_test.dart` | да |
  | agent-configuration «Одинаковый вывод у двух бинарей» (прежний) | `cli/config_command_test.dart` | да (DoD change `add-agent-configuration`) |
  | agent-configuration «Тестовое хранилище в обычной сборке» | `io/cli/config_commands_test.dart` («CODELAB_TEST_SECRET_STORE in a regular build …»); `io/config/config_loader_test.dart` (группа `config.env.unknown`) | да |
  | agent-configuration «Ни одного значения в логе» (прежний) | `agent/agent_host_config_test.dart` (`TOKEN=tok-test-secret`) | да |
  | agent-configuration «Нет предупреждения о недоступном хранилище» | `core/config/config_secret_refs_test.dart` (`config.secret.unavailable` нет в `warnings`, которые хост пишет в лог) | да |
  | agent-configuration «Секрет не задан при auto» | `io/cli/config_commands_test.dart` (группа `secrets`: «auto: note с причиной и warning с подсказкой env/file …», «Windows: подсказка только с переменной») | да |
  | agent-configuration «Секрет не задан в file» | там же («file без секрета: подсказка set …») | да |
  | agent-configuration «Секрет задан переменной» | там же («секрет задан переменной: строки warning нет …») | да |
  | agent-configuration «Предупреждение об открытом тексте» | там же («file без ссылок: строка об открытом тексте всегда …», «file с правами 0644: строка о правах с chmod 600, код 0») | да |
  | agent-configuration «Отказ file без строк по именам» | `io/cli/config_commands_test.dart` («file с правами 0644 и ссылками: секреты недоступны, отдельных warning на каждое имя нет» — ссылки `codelab/openai` и заголовка MCP, одна строка о правах) | да |
  | agent-configuration «Отказ file по другой причине» | там же («file: secrets.yaml — символьная ссылка …») | да |
  | agent-configuration «Без ссылок вывод прежний» | там же («без ссылок на секреты хранилище не вызывается, вывод прежний», «только api_key_env …») | да |
  | agent-binary «Ключ провайдера из переменной переопределения» | `agent/secret_store_process_test.dart` («the provider key comes from CODELAB_SECRET_*; the value is in no output»); `agent/agent_host_secrets_test.dart` (`--stdio`, `--ws`) | да |
  | agent-binary «Секрет не задан — ошибка хода» | `agent/secret_store_process_test.dart` («a missing secret with secrets.backend: env is a turn error and the process keeps running») | да |
  | agent-binary «Режим отладки секретов» | там же (`--debug-secrets` и `CODELAB_DEBUG_SECRETS=1`: «secrets.lookup without the value») | да |
  | agent-binary «Бэкенд file при старте» | там же («secrets.backend: file logs secrets.backend.plaintext at start and does not create the file») | да |
  | agent-binary «Сценарий не читает secrets.yaml» | там же («--llm-script ignores secrets.backend: file; secrets.yaml is not opened») | да |
  | agent-binary «Неизвестная подкоманда» | `agent/secret_command_process_test.dart` («an unknown subcommand: code 64, the secret usage, stdout is empty» — текст `secret needs a subcommand`, без `codelab/openai`) | да |
  | agent-binary «list с бэкендом env» | там же («list with secrets.backend: env: the first line is Backend: env, code 0») | да |
  | codelab-cli «Совпадение с бинарём агента» | `cli/e2e/secret_command_test.dart` («set with a value argument: both binaries give 64 and the same output …») | да |
  | codelab-cli «Флаги подключения с secret» | `cli/e2e/secret_command_test.dart` («-p hi secret list: 64, stdout empty, no agent started»); `cli/secret_command_test.dart` | да |
  | codelab-cli «--cwd с secret» | `cli/secret_command_test.dart` («--cwd <dir> / -C <dir> secret list: 64, exact message, secret usage, store untouched»; «connection flags with secret are usage errors») | да |
  | codelab-cli «Ошибка верхнего парсера с secret» | `cli/secret_command_test.dart` («a bad top-level flag before secret: 64, fixed phrase, flag not echoed»: `--no-such-flag`, без `Could not find an option`) | да |
  | codelab-cli «Подкоманда не меняет CODELAB_HOME» | `cli/secret_command_test.dart` («list with the env backend: 0, Backend line, home unchanged»); `cli/e2e/secret_command_test.dart` («CODELAB_HOME is not modified by list and by usage errors») | да; вариант с `CODELAB_CONFIG` — `list with env backend from CODELAB_CONFIG: empty home unchanged` (`apps/codelab_cli/test/secret_command_test.dart`) |
  | agent-runtime «Секрет сервера конфига не найден» | `core/runtime/mcp_secret_values_test.dart` («a missing secret fails only its server») | да |
  | agent-runtime «Хранилище недоступно при загрузке сессии» | `core/runtime/mcp_secret_values_test.dart` (группа `loadSession`: «an unavailable store skips only its server and logs the reason, no value») | да |
  | agent-runtime «Закрытие во время раскрытия секретов» | там же (группы `dispose` и `setMcpServers`) | да |
  | agent-runtime «Закрытие во время замены», «Замена во время хода», «Сервер конфига не тронут» (прежние) | `core/runtime/set_mcp_servers_test.dart` («close during a connection of a new server …», группа `a session with a turn`, «servers of the config stay in the list …») | да (DoD change `add-agent-mcp-client`) |
  | agent-runtime «Сервер клиента побеждает сервер конфига», «Сессии не видят чужих инструментов», «Процессы закрываются вместе с сессией», «Сбой после подключения закрывает серверы», «Коннектор бросил», «Коннектор отдал инструмент без префикса», «Capability выключена» (прежние) | `core/runtime/session_mcp_test.dart` (группы `list of servers`, `registration and isolation`, `close`, `robustness`, `capability filter`) | да (DoD change `add-agent-mcp-client`) |
  | agent-runtime «Коллизия двух серверов», «Коллизия внутри одного сервера» (прежние) | `packages/dart/codelab_agent_mcp/test/connector_test.dart` (группа `name collisions disable the later server (E-05, HOST-5)`) | да (DoD change `add-agent-mcp-client`) |

  Итог: все сценарии спецификаций этого change покрыты тестами (сценарии, перенесённые без изменений из прежних changes, — их тестами и тестами итерации 5); 10.3 отмечен. Полный `melos run check` подтверждается CI pull request.
