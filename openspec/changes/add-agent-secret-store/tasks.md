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

- [ ] 5.1 `[agent]` Тесты `codelab_agent_io/test/secrets/env_secret_store_test.dart` (agent-secrets «Бэкенды env и file», сценарий «env только для чтения»). Красный.
- [ ] 5.2 `[agent]` Тесты `codelab_agent_io/test/secrets/file_secret_store_test.dart` во временном `CODELAB_HOME` на macOS и Linux (agent-secrets «Бэкенд file», все сценарии):
  - права `0644` → отказ чтения, записи и `names()` с текстом `chmod 600`, одно `secrets.file.refused`;
  - символическая ссылка → отказ;
  - отсутствующий файл: `read`/`delete`/`names()` файл не создают;
  - запись создаёт файл с правами `0600`; права выставлены до записи значения (фейковый `SecretProcessRunner` для `/bin/chmod` проверяет, что в момент вызова файл пуст; в argv только путь);
  - сбой между временным файлом и переименованием оставляет прежний файл, следующий `write` удаляет tmp;
  - значения с `"`, `\` и не-ASCII читаются обратно; значение с переводом строки отклонено;
  - битая структура → исключение без строк файла;
  - подменённая платформа `windows` → отказ.

  Красный.
- [ ] 5.3 `[agent]` `SecretProcessRunner`, `IoSecretProcessRunner`, `EnvSecretStore`, `FileSecretStore` с явным путём (D14: переиспользование тестовым хранилищем этапа 7); экспорт из бареля `codelab_agent_io`. 5.1, 5.2 зелёные; `pubspec.yaml` не меняется.
- [ ] 5.4 `[agent]` Тесты `codelab_agent_io/test/secrets/open_secret_store_test.dart` (agent-secrets «Выбор бэкенда secrets.backend», сценарии «auto — env на всех ОС», «auto не выбирает file»): `auto` = `env` на macOS/Linux/Windows без процессов и с причиной, называющей `secrets.backend: file`; `env`; `file`; `secrets.backend.selected` один раз. Тест `config_loader_test.dart`: `file` на подменённой платформе Windows — проблема конфигурации (agent-secrets «Бэкенд file», сценарий «file на Windows»). Красные.
- [ ] 5.5 `[agent]` `openSecretStore`; проблема `file` на Windows в `ConfigLoader`. 5.4 зелёные.

## 6. `SecretAdmin` и `openHostSecrets` (итерация 2; D15)

- [ ] 6.1 `[agent]` Тесты `codelab_agent_io/test/secrets/secret_admin_test.dart` (agent-secrets «Программная запись секретов», все сценарии): типизированные результаты `Stored`/`Updated`/`InvalidName`/`InvalidValue`/`Collision`/`ReadOnly`/`Failed`; `ReadOnly` у `env` с подсказкой `secrets.backend: file`; значение ни в argv, ни в stdin дочерних процессов; `toString` результатов без значения. Красный.
- [ ] 6.2 `[agent]` `SecretAdmin` и результаты; экспорт из бареля. 6.1 зелёный; задача 8.2 строит `SecretCommands` поверх него.
- [ ] 6.3 `[agent]` Тесты `codelab_agent_io/test/secrets/host_secrets_test.dart` (agent-secrets «Секреты настольных хостов и встроенных профилей», все сценарии): `openHostSecrets` внутри `Isolate.run` из сериализуемых данных — наружу только `found`/`source`, лог без значения; общий секрет через `SecretAdmin` и резолвер на бэкенде `file`; замена прочитанного секрета видна только новому резолверу. Красный.
- [ ] 6.4 `[agent]` `openHostSecrets` в `lib/src/secrets/host_secrets.dart`; экспорт из бареля. 6.3 зелёный. **Конец итерации 2.**

## 7. Бинарь: хранилище и отладка (итерация 3; D11)

- [ ] 7.1 `[agent]` Процессные тесты `apps/codelab_agent/test/` (agent-binary «Хранилище секретов в бинаре», все сценарии):
  - ключ из `CODELAB_SECRET_*` к локальному HTTP-серверу теста;
  - ошибка хода `API key secret … is not set` при `secrets.backend: env`;
  - `--debug-secrets` и `CODELAB_DEBUG_SECRETS=1` → `secrets.lookup` без значения;
  - `--llm-script` с `secrets.backend: file` в `--config` — бэкенд `env`, `secrets.yaml` не открывается;
  - `secrets.backend: file` → `secrets.backend.plaintext` при старте, файл не создан;
  - `secrets.backend: keychain` → код `64` до старта транспорта, текст `not supported yet`;
  - stdout, stderr и лог не содержат значения.

  Красный.
- [ ] 7.2 `[agent]` `AgentHost.build` через `openHostSecrets` (задача 6.4); флаг `--debug-secrets` в `serve_args.dart`; справка `serve`. 7.1 зелёный.

## 8. `codelab-agent secret` и `config check` (итерация 3; D8, D9)

- [ ] 8.1 `[agent]` Тесты `codelab_agent_io/test/cli/secret_commands_test.dart` на фейковом `SecretInput` и фейковом хранилище (agent-secrets «Подкоманды secret», все сценарии):
  - `set` с TTY и без, `\n`/`\r\n`, пустое значение, перевод строки внутри;
  - значение аргументом → `64` без печати аргумента;
  - коллизия `envOverride`; бэкенд `env` (и `auto`) → `1` с подсказкой `secrets.backend: file` и переменной, на Windows — только переменной;
  - `Stored`/`Updated`;
  - `delete` существующего и отсутствующего;
  - `list` с бэкендом, причиной и строкой `Environment overrides`;
  - невалидный конфиг с `api_key` не блокирует;
  - бэкенд `file`: строка `warning: secrets are stored unencrypted` в stderr каждой подкоманды, отказ по правам → код `1`;
  - синтаксическая ошибка YAML → `1`;
  - ни в одной строке нет значения и длины.

  Красный.
- [ ] 8.2 `[agent]` `lib/src/cli/secret_commands.dart`, `secret_input.dart` (`SecretInput`, `StdinSecretInput` с восстановлением эха в `finally` и по `SIGINT`); экспорт из бареля. 8.1 зелёный.
- [ ] 8.3 `[agent]` Тесты `codelab_agent_io/test/cli/config_commands_test.dart` (agent-configuration «config check показывает состояние секретов», все сценарии): строки `note:`/`warning:` перед `Config: …`; при `env` подсказка `secrets.backend: file`; код не меняется; без ссылок хранилище не вызывается и вывод прежний; `secrets.backend: file` — строка об открытом тексте всегда и строка о правах при `0644`. Красный.
- [ ] 8.4 `[agent]` `ConfigCommands.check` — проверка ссылок резолвером. 8.3 зелёный.
- [ ] 8.5 `[agent]` Процессные тесты `apps/codelab_agent/test/secret_command_process_test.dart` (agent-binary «Подкоманда secret бинаря», все сценарии; agent-secrets, сценарии «Значение аргументом», «Только чтение при auto», «Сохранение в file»): неизвестная подкоманда, `list` с `env`, справка бинаря называет `secret`. Красный.
- [ ] 8.6 `[agent]` `apps/codelab_agent/lib/src/cli/secret_cli.dart`, регистрация в `run.dart`, общая справка; вложенный `AGENTS.md` приложения (§1, §2: команды `secret`, `--debug-secrets`). 8.5 зелёный. **Конец итерации 3.**

## 9. Мост и `codelab secret` (итерация 4; D1, D8)

- [ ] 9.1 `[agent]` `codelab_setup/lib/io.dart` — реэкспорт `SecretCommands`, `SecretCommandResult`, `SecretSetOptions`, `SecretDeleteOptions`, `SecretListOptions`, `SecretInput`, `StdinSecretInput`, `SecretAdmin` с результатами и `openSecretStore` (D15); основной барель не меняется; тест компиляции реэкспортов; вложенный `AGENTS.md` моста (§1, §3). `melos run guard` зелёный, `setupAllowlist` не меняется.
- [ ] 9.2 `[client]` Тесты `apps/codelab_cli/test/secret_command_test.dart` и e2e процесса (codelab-cli «Подкоманда codelab secret», все сценарии; agent-secrets, сценарий «Одинаковый вывод двух бинарей»):
  - совпадение вывода с `codelab-agent secret` на ошибках использования и `list`;
  - флаги подключения → `64`;
  - без подкоманды и с неизвестной;
  - `CODELAB_HOME` не изменён;
  - справка `--help`.

  Красный.
- [ ] 9.2a `[desktop]` Создать новый вложенный `apps/codelab_desktop/AGENTS.md` (сейчас его нет) — минимальный, только правило секретов: секреты — только через общие бэкенды `codelab_agent_io` (через `codelab_setup/io.dart` и `codelab_embedded`), `flutter_secure_storage` на desktop не используется (D15, D16). Кода нет. Корневые `AGENTS.md` и `CLAUDE.md` говорят о вложенных `AGENTS.md` в общем виде, их правка не нужна.
- [ ] 9.2b `[client]` `09-12-stage-7-embedded.md`: `desktopHostServices` и `_agentMain` вызывают `openHostSecrets`; `DesktopServicesSpec` с `codelabHome`, `secretsBackend`, `debugSecrets`; в 1.0 встроенный профиль использует `env` и `file`; известное ограничение кэша; `CODELAB_TEST_SECRET_STORE` — бэкенд `file` с явным путём (D14, D15). **Сделано при подготовке change (2026-10-31)**, сверить в 10.2.
- [ ] 9.3 `[client]` `CliCommand.secret` в `cli_args.dart`, вызов в `run.dart` через `package:codelab_setup/io.dart`; строка в `--help`; вложенный `AGENTS.md` CLI (§1). 9.2 зелёный, `melos run guard` зелёный. **Конец итерации 4.**

## 10. Матрица, документы и Definition of Done (итерация 5)

- [ ] 10.1 `[agent]` Матрица этапа 8 в `09-13-stage-8-mcp-config.md` и `agent-parity-goals.md`:
  - P-12 — «частично: `env` и `file`, пункт 1 CFG-9; хранилище ОС — после 1.0 (`add-agent-os-secret-backends`), пункты 2–3 CFG-9 — 8.11» с файлами тестов;
  - P-17 — `debug_secrets_test.dart`;
  - итог 8.9 абзацем, как у 8.6–8.8.
- [ ] 10.2 `[agent]` Сверка документов с кодом (`codelab_agent_core/AGENTS.md` §3, критерий (е)):
  - §17.5.2, §17.5.4, §17.5.9, §17.5.13, §10.3, §15.4–§15.6, §12.2–§12.4;
  - вложенные `AGENTS.md` `codelab_agent_io` (§1: хранилища секретов `env` и `file` вместо «ещё не созданы»), `codelab_setup`, `apps/codelab_agent`, `apps/codelab_cli`;
  - doc-комментарии новых сущностей на русском (`AGENTS.md` §15).
- [ ] 10.3 `[agent]` Definition of Done change:
  - все сценарии спецификаций этого change покрыты тестами задач 1–9;
  - `melos run guard`, `web-compile` зелёные;
  - сторож и allowlist не менялись (D1);
  - `openspec validate add-agent-os-secret-backends --strict` зелёный (черновик после 1.0 не устарел относительно D-решений 8.9);
  - `openspec validate add-agent-secret-store --strict` зелёный;
  - полный `melos run check` — в CI pull request последней итерации.
