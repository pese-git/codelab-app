Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_mcp` (сторона агента, design.md D1, «Исполнители»), `codelab_embedded`, `apps/codelab_agent`, мост `codelab_setup`;
- `[protocol]` — `codelab_agent_acp`, фикстуры `codelab_acp_testing`;
- `[client]` — `apps/codelab_cli`;
- `[docs]` — документы `docs/architecture/**` и вложенные `AGENTS.md`.

Задач `[desktop]` нет: `apps/codelab_desktop` и `codelab_ui` не меняются, встроенный агент app получает перезагрузку через `codelab_embedded` (D13). Страницы настроек — change `add-provider-setup-ui`.

Итерации (design.md, D16) — каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: документы;
- итерация 1 — группа 1: L-25;
- итерация 2 — группа 2: реестр настроек и типы правок, E-15;
- итерация 3 — группа 3: `ConfigWriter`;
- итерация 4 — группа 4: подкоманды записи, мост, `codelab`;
- итерация 5 — группа 5: живая перезагрузка;
- итерация 6 — группа 6: переподключение MCP, E-04;
- итерация 7 — группа 7: `/config` и `/mcp`;
- итерация 8 — группа 8: матрица, сверка документов, DoD.

Зависимости: 3 ← 2; 4 ← 3; 6 ← 5; 7 ← 5, 6. Итерация 1 независима.

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` пакета;
- `fvm dart test` пакета;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке ядра.

Полный `melos run check` — в CI pull request. Тесты с файлами работают во временных `CODELAB_HOME` и `cwd` и не читают настоящий `~/.codelab`. Время — `FakeClock`, синхронизация — completer-ы, без `Future.delayed`. Процессные тесты — с `Timeout(Duration(seconds: 60))` и пределами «не позже N с». `test:e2e:app:*` не запускаются (`AGENTS.md` §21).

## 0. Документы (итерация 0)

- [x] 0.1 `[docs]` `agent-core/17-5-agent-setup.md` — отступления design.md:
  - §17.5.2: `ConfigSource` без `cwd`, `changes` вместо `changedRoots` (D7, D8); `buildAgentCore(modelsFor:)`; `ConfigApplyReport` без MCP-полей, с `outcome`; без `applyConfig` (этап 10); `McpSupervisor` — расширение `McpSessionTools` (D11); `SecretResolver.invalidate` с поколениями (D8);
  - §17.5.3: тексты ошибок английские; запрет сочетания `--provider-type` с `--provider` (D3);
  - §17.5.5: без fsync каталога, права через `SecretProcessRunner`, повтор CLI при конфликте, правило литеральных секретов `UpsertMcpServer` (D5, D6);
  - §17.5.6: снимок на корень запуска (D8); таблица ключей сборки 1.0, `logging.level` — перезапуск (D14, OQ5); `mcp.servers` — после хода (D10); файлы проекта — новые сессии (D9);
  - §17.5.7: `applyConfigServers` → `replaceServers`, пробуждение `failed` при перезагрузке (D10, OQ8);
  - §17.5.8: дескрипторы разделов после MVP (D4);
  - §17.5.9: события D14;
  - §17.5.13: имена тестов D15.
- [x] 0.2 `[docs]` `agent-core/10-core-assembly-and-profiles.md` §10.3 (`AgentCoreServices.config`, `modelsFor`, `HostWiringException`); `13-acp-adapter.md` §13.4 (встроенные `config`, `mcp` первыми, D12) и §13.6; `15-configuration.md` §15.4 (`config.watch`, `config.poll_interval` применяются), §15.6 (`CODELAB_PROVIDER_*`, флаги); `12-observability-and-errors.md` §12.3 (события D14).
- [x] 0.3 `[docs]` `09-13-stage-8-mcp-config.md`, пункт 10: change, итерации, OQ; `09-11-stage-6-cli-mvp.md` — подкоманды `config|provider|mcp` (D6); `12-4-first-run-and-settings.md` §12.4.2 — состав `io.dart` после 8.10, мастер и `AgentConfigStore` — `add-provider-setup-ui`.

- [x] 0.4 `[docs]` `agent-core/07-permissions.md` §7.6.1 и PERM-11 — пути конфигурации агента от хоста (`AgentConfigPaths`), канонизация по самому глубокому существующему предку, перепроверка на каждой проверке, защита каталогов-предков, шаблоны `exec` (OQ2, D8; повторное ревью итерации 0).

**Критерий итерации 0.** Документы не расходятся с design.md; каждый изменённый абзац ссылается на D-решение.

## 1. Предконфигурация провайдера из окружения (итерация 1; D3; L-25)

- [ ] 1.1 `[agent]` Тесты `codelab_agent_io/test/config/provider_preconfig_env_test.dart` (agent-configuration «Предконфигурация провайдера из окружения», все сценарии; `core/provider-preconfig-from-env`):
  - `TYPE` + `CONFIG` без файлов;
  - `_BASE64` — тот же `CoreConfig`;
  - файл проигрывает окружению, `CODELAB_MODEL` выигрывает у предконфигурации;
  - обе переменные сразу, одна из пары, не base64, битый JSON, неизвестное поле, `api_key` → `inlineSecret`;
  - литеральный секретный заголовок `headers` → `inlineSecret` (сценарий «Литеральный токен в заголовке предконфигурации»; D3, D5);
  - ни одна проблема и запись `RecordingLogger` не содержит подстроки значения (CFG-12).

  Красный.
- [ ] 1.2 `[agent]` `environment_layer.dart`: `envPreconfigLayer` по §17.5.3; источник `env:CODELAB_PROVIDER_CONFIG`; doc-комментарии по `AGENTS.md` §15. 1.1 зелёный.
- [ ] 1.3 `[agent]` Тесты `apps/codelab_agent/test/serve_flags_test.dart` и `provider_preconfig_process_test.dart` (agent-binary «Флаги предконфигурации провайдера»; agent-configuration, сценарий «Флаги и модель»): флаги затеняют переменные, `config.preconfig.shadowed`; `--model` побеждает предконфигурацию флагов, `CODELAB_MODEL` ей проигрывает; справка рекомендует `@путь`; один флаг — `64`; сочетание с `--provider` — `64`; `@путь` не читается — `64`; значение не попадает в stderr и лог; `codelab-agent config check` видит предконфигурацию. Красный.
- [ ] 1.4 `[agent]` `apps/codelab_agent`: флаги в `serve_args.dart`, слой флагов в `ConfigLoader`. 1.3 зелёный.

## 2. Реестр настроек и типы правок (итерация 2; D4, D5; E-15)

- [ ] 2.1 `[agent]` Тесты `codelab_agent_core/test/config/settings_registry_complete_test.dart` (agent-configuration «Реестр настроек», сценарии «Ключ схемы без дескриптора», «Расхождение умолчаний», «Более конкретный дескриптор», «Разбор значения CLI»; `core/settings-registry-complete`, CFG-19): алгоритм §17.5.8, п. 1–7; список ключей перезапуска — константа теста со ссылкой на D8: `sessions.*`, `logging.*`, `profile.*`, `secrets.backend`, `permissions.*`, `trusted_projects` (R0-1), **без** `config.*` — раздел `config` в этой итерации непрозрачен и покрыт одним дескриптором `map`/`fileOnly` (D4, «Порядок итераций»). Красный.
- [ ] 2.2 `[agent]` `config/settings_registry.dart`: дескрипторы ключей схемы этой сборки и разделов после MVP (D4), `lookup`, `parseCliValue` с исключением ядра `ConfigValueException`; экспорт из бареля. 2.1 зелёный, `web-compile` зелёный.
- [ ] 2.3 `[agent]` Тесты `codelab_agent_core/test/config/config_edit_test.dart`: `ConfigTarget`, `ConfigSnapshot.get` с `mcp.servers[<name>]` и сегментом в кавычках, равенство правок. Красный.
- [ ] 2.4 `[agent]` `config/config_edit.dart` (`ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` и подклассы, `ConfigConflictException`); экспорт. 2.3 зелёный.

**Критерий итерации 2.** E-15 зелёный; новый ключ схемы без дескриптора роняет тест.

## 3. Запись конфига (итерация 3; D2, D5)

- [ ] 3.1 `[agent]` Тесты `codelab_agent_io/test/config/config_writer_test.dart` (agent-configuration «Запись конфига ConfigWriter», сценарии «Сохранение формата», «Ключ модели с точкой», «Удаление таблицы провайдера», «Сервер MCP по имени», «Конфликт с ручной правкой», «Невалидный итог не пишется», «Недоверенный проект», «Литеральный токен MCP»; CFG-13). Дополнительно:
  - строки `off`, `yes`, `${VAR}` пишутся в кавычках и читаются обратно строками;
  - отказ `YamlEditor` → `edit the file manually`;
  - незаданная `${VAR}` — предупреждение;
  - занятый lock → конфликт, lock старше 10 с — `config.write.stale_lock`; гонка снятия устаревшего lock двумя писателями — свежий lock возвращается на место, второй писатель получает конфликт (D5);
  - литеральный секрет по итоговому поддереву: `config set mcp.servers '…'` с `X-Api-Key`, `SetValue("providers.p.headers", {"Cookie": …})`, `env` с `GITHUB_TOKEN` — `ConfigInlineSecretException` без значения в тексте; имя с `-`/`_` и в другом регистре нормализуется; значение со ссылкой `${…}` проходит (сценарий «Литеральный токен через config set»).

  Красный.
- [ ] 3.2 `[agent]` Тесты `config_writer_atomic_test.dart` (сценарии «Сбой между tmp и переименованием», «Символическая ссылка и права»): тестовый шов между записью tmp и `rename`; права `0600` выставляются фейковым `SecretProcessRunner` на пустой tmp **до** записи содержимого (порядок вызовов фиксирует фейк); сбой `chmod` → `ConfigException`, tmp удалён, `rename` не было, содержимое не писалось (сценарий «Сбой смены прав»); ветка Windows — подменённой платформой. Красный.
- [ ] 3.3 `[agent]` `codelab_agent_io/pubspec.yaml`: `yaml_edit: ^2.2.4` с комментарием (D2); `fvm dart run melos bootstrap`; `guard` зелёный (allowlist не меняется).
- [ ] 3.4 `[agent]` `ConfigLoader.validateCandidate` и `config/config_writer.dart` (D5; конструктор с `SecretProcessRunner`, `Clock`, `Random`); doc-комментарий `SecretProcessRunner` называет второго потребителя. 3.1, 3.2 зелёные.

## 4. Подкоманды записи и чтения (итерация 4; D6)

- [ ] 4.1 `[agent]` Тесты `codelab_agent_io/test/cli/cli_config_commands_test.dart` (agent-configuration «Подкоманды записи и чтения конфига», все сценарии):
  - `config path|get|set|unset`, в том числе `get` без раскрытия `${VAR}`;
  - `provider add|list|remove`, `--api-key-stdin` на фейковом `SecretInput` и `MemorySecretStore` или `file` во временном `CODELAB_HOME`;
  - `mcp add|list|remove`;
  - повтор при конфликте;
  - коды `0`/`1`/`64`, `ConfigValueException` → `64`; значения секретов не в выводе;
  - `--api-key-stdin` при существующем секрете — `warning: replaced the existing secret codelab/<id>`.

  Отдельно `cli/config_output_test.dart` (R0-2, сценарий «get маскирует секреты»), по тесту на ветку: ключ из `inlineSecretKeys`; секретный заголовок; секретная переменная `env`; ссылка `${secret:…}` и `${VAR}` печатается как есть; значение слоя `env:*` и предконфигурации → `<from env:…>`; секретное имя листа вне `headers`/`env`; непрозрачные `providers.*.auth` и `key_rotation` → `<opaque: edit the file>` (сценарий «Непрозрачные поддеревья»); userinfo URL в `config get` и `provider list`; `--layer merged`; отображение и список поэлементно.

  Красный.
- [ ] 4.2 `[agent]` `cli/config_commands.dart` (`path`, `get`, `set`, `unset`), `cli/provider_commands.dart`, `cli/mcp_server_commands.dart`, `cli/config_output.dart` (маскирование R0-2, D6); экспорт из бареля `codelab_agent_io`. 4.1 зелёный.
- [ ] 4.3 `[agent]` Тесты `apps/codelab_agent/test/config_write_command_process_test.dart` (agent-binary «Подкоманда config бинаря», все сценарии) и `codelab_setup/test/config_write_exports_test.dart` (реэкспорт новых подкоманд из `io.dart`). Красный.
- [ ] 4.4 `[agent]` `apps/codelab_agent`: регистрация `config path|get|set|unset`, `provider`, `mcp`, справка `serveUsage`; `codelab_setup/lib/io.dart` — реэкспорт `ProviderCommands`, `McpServerCommands` и опций; `codelab_setup/AGENTS.md` §1, §3. 4.3 зелёный.
- [ ] 4.5 `[client]` Тесты `apps/codelab_cli/test/config_command_test.dart`, `provider_mcp_command_test.dart` и e2e `test/e2e/config_write_command_test.dart` (codelab-cli «Подкоманда codelab config», «Подкоманды codelab provider и codelab mcp», все сценарии, включая совпадение байтов с `codelab-agent`). Красный.
- [ ] 4.6 `[client]` `cli_args.dart` (подкоманды, флаги подключения → `64`), `run.dart` (вызов через `codelab_setup/io.dart`), справка `--help`; `apps/codelab_cli/AGENTS.md`. 4.5 зелёный.

**Критерий итерации 4.** `codelab config set` и `codelab-agent config set` дают одинаковые байты файла; комментарии сохранены.

## 5. Живая перезагрузка (итерация 5; D7, D8, D13, D14; E-04, часть конфига)

- [ ] 5.1 `[agent]` Тесты `codelab_agent_core/test/secrets/secret_resolver_test.dart` (agent-secrets «Резолвер секретов», сценарии «Сброс кэша», «Чтение во время сброса»). Красный.
- [ ] 5.2 `[agent]` `SecretResolver.invalidate()` с поколениями кэша. 5.1 зелёный.
- [ ] 5.3 `[agent]` Тесты `codelab_agent_core/test/runtime/config_reload_test.dart` на фейковом `ConfigSource`, `FakeClock` и fake-моделях (agent-runtime «Живая перезагрузка конфигурации», все сценарии; CFG-15, CFG-16):
  - `permissions.deny` — со следующего вызова;
  - `agent.default_model` — только новым сессиям;
  - ключ перезапуска;
  - невалидная правка;
  - смена списка моделей → `ModelOptionsChanged`;
  - коалесценция;
  - `dispose` во время загрузки;
  - сессия, создаваемая во время замены, получает снимок начала;
  - удалённая модель сессии работает на прежней функции;
  - ошибка `load()` по сигналу — `config.reload.failed` с `error_class`, а не исключение в зоне;
  - R0-1: `permissions.mode`, `permissions.deny`, `permissions.tools`, `trusted_projects`, stdio-элементы без прежнего `sameConnection` (новый, включённый из `enabled: false`, смена `http` → `stdio`, изменённые `command`/`args`/`env`, в том числе ссылка `${secret:…}` в `env`) — в `pendingRestartKeys`, правила разрешений прежние; HTTP-сервер без секретов и удаление применяются (сценарии «Права не меняются на лету», «Новый stdio-сервер ждёт перезапуска», «Смена типа на stdio»);
  - доверие на фейковом `ConfigSource` с закреплённым `initial`: проект добавлен в `trusted_projects` — его провайдеры и HTTP-серверы не в снимке, `Restart required: trusted_projects`; доверие снято — проектные слои прежние (сценарии «Проект добавлен в trusted_projects», «Доверие снято»);
  - R0-4: смена `base_url`, `headers`, `auth_header`, `kind`, `api_key_*` у провайдера с ключом, новый провайдер с ключом и `agent.default_model` на него, HTTP-сервер со ссылкой `${secret:…}` — отложены; новые модели того же провайдера применены (сценарий «Секрет на новый адрес»);
  - R0-4 по значению: новый HTTP-сервер с `X-Gw: ${secret:…}`, новый HTTP-сервер с `Authorization: Bearer ${GITHUB_TOKEN}`, смена `base_url` у провайдера с `auth_header` на `${VAR}` — отложены (сценарий «Подстановка по значению»);
  - новый провайдер с ключом и `agent.default_model` на его модель вместе с другой правкой — итог `applied`, ссылка отложена (сценарий «Новый провайдер с ключом и ссылки на его модели»);
  - атомарность группы полей провайдера: `base_url` + `models` → модели новые, адрес, заголовки и ключ прежние; только `headers` → всё прежнее (сценарий «Атомарность группы полей провайдера»);
  - включение stdio-сервера из `enabled: false` отложено (сценарий «Включение stdio-сервера из enabled: false»);
  - `${…}` в `base_url` делает провайдера «с ключом» (сценарий «Подстановка в base_url»); `checkConfig()` — по закреплённому доверию, новое `trusted_projects` в `Restart required`;
  - доверие в ядре: новая сессия не читает `prompts`/`agents` проекта, добавленного в `trusted_projects` перезагрузкой; `CoreConfig.trustedProjects` и `withoutProject.trustedProjects` прежние;
  - `CoreConfig.withDeferred` (только `CoreConfig` и `withoutProject`; `CatalogProvider` из прежних `config`, `key`, `headerTemplates` и новых `models`, прежняя запись `providerProblems`) и `validateSnapshot`; прежние `HostSettings` и `values` подставляет рантайм; ошибка повторной проверки — итог `failed`;
  - `config.reload.model_orphaned {session_id, model}` один раз на сессию и модель;
  - `ConfigLoadResult.values` и прежние `HostSettings` после перезагрузки с изменённым `logging.file`;
  - `services.config` без `modelsFor` — `HostWiringException`;
  - без `services.config` `modelsFor` не требуется и не вызывается; при сборке `modelsFor` не вызывается, начальный ход идёт на `streamFunction`, а после каждой применённой перезагрузки (в том числе `unchanged`) — на функции из `modelsFor` (D8, «`modelsFor` и `streamFunction` при сборке»).

  В итерации 5 тест проверяет снимок, `restartRequiredKeys` и `pendingRestartKeys`; применение серверов к живым сессиям — в 6.3.

  Красный.
- [ ] 5.4 `[agent]` Ядро:
  - `config/config_source.dart`, `AgentCoreServices.config`, `AgentCoreServices.agentConfigPaths`, `buildAgentCore(modelsFor:, configCommand:)`;
  - `ConfigLoadResult.values` в `CoreConfig.fromLayers` (D8); рантайм хранит `values` и `HostSettings` применённого снимка;
  - правила R0-1 и R0-4 в шаге 5 (до задачи 6.2, где появляется `McpServerConfig.enabled`, условие «включение из `enabled: false`» проверяется через отсутствие элемента в применённом снимке и `values`: выключенный сервер в них не попадает), `CoreConfig.withDeferred`, `CoreConfig.validateSnapshot`, `ConfigSource.initial` (D8, «Пересборка снимка с отложенными ключами»);
  - параметр `CoreConfig.fromLayers(..., pinnedTrustedProjects:)` в `resolveConfig`/`_trustedRoots` (`resolve.dart`): по закреплённому списку — проектные слои и `CoreConfig.trustedProjects` с `withoutProject`; константа ключей перезапуска теста 2.1 дополнена `config.*`;
  - `AgentRuntime.reloadConfig`/`checkConfig`/`configStatus`;
  - атомарная запись снимка, подписка на `changes` с отменой в `dispose`;
  - ветка `AgentEvent` `ModelOptionsChanged`;
  - строки схемы `config.watch`, `config.poll_interval` вместо `afterMvpSections`, доверие проектного слоя для `config` (agent-configuration «Ключи config.watch и config.poll_interval»); дескрипторы реестра обновлены.

  5.3 зелёный, 2.1 зелёный, `web-compile` зелёный.
- [ ] 5.5 `[agent]` Тесты `codelab_agent_io/test/config/config_watcher_test.dart` и `file_config_source_test.dart` (agent-configuration «Наблюдение за файлами конфига», все сценарии; «Ключи config.watch и config.poll_interval»): debounce на `FakeClock`, `rename`, новый файл, те же байты, режим опроса, `secrets.yaml` при `file`, `config.watch: false`, `close()` без поздних сигналов, переход на опрос при ошибке потока. Unit-тесты подают события через шов-фабрику потока (D7), без настоящей ФС; один интеграционный тест настоящего `watch` во временном каталоге — сигнал не позже 5 с, `Timeout(Duration(seconds: 60))`. `config.*` в `config.local.yaml` недоверенного проекта — `config.project.untrusted_key`. Красный.
- [ ] 5.6 `[agent]` `config/config_watcher.dart`, `config/file_config_source.dart` (с `initial` и закреплённым доверием), `ConfigLoader.load(pinnedTrustedProjects:)` — только передаёт список в `CoreConfig.fromLayers` (D8); `codelab_agent_io/AGENTS.md` §1. 5.5 зелёный; в 5.5 добавлен тест `file_config_source_test.dart` «доверие закреплено на `initial`».
- [ ] 5.7 `[protocol]` Тесты `codelab_agent_acp/test/config_reload_notifications_test.dart` (agent-acp-server «Уведомления после перезагрузки конфигурации», сценарии «Список моделей изменился», «Неудачная перезагрузка», «Модель сессии удалена»; ACP-8). Красный.
- [ ] 5.8 `[protocol]` `event_projection.dart`: `ModelOptionsChanged` → `config_option_update`, исчерпывающий `switch`; опция `model` с текущей моделью вне каталога. 5.7 зелёный.
- [ ] 5.9 `[agent]` (OQ2 (а)) Тесты `codelab_agent_core/test/permissions/agent_config_paths_test.dart` (agent-permissions «Критические пути правок конфигурации агента», все сценарии) и `codelab_agent_io/test/config/agent_config_paths_test.dart`:
  - `agentConfigPathsFor` даёт те же файлы, что наблюдает `ConfigWatcher`, плюс `$CODELAB_HOME/agents` и `prompts`; пути канонические (`~` раскрыт, symlink раскрыт);
  - `write`/`edit` с целью из `agentConfigPaths` — критические в `bypass`, `accept-edits`, без `allow_always`; в `autopilot` и без gate — отказ;
  - symlink dotfiles (`$CODELAB_HOME/config.yaml` → `~/dotfiles/…`); проектный конфиг корня запуска из сессии с другим `cwd`; файл `--config`;
  - `exec`: `>`/`>>`, `tee`, `cp`, `mv`, `rename`, `ln -sf`, `install`, `dd of=`, `sed -i`, `cd ~/.codelab && …`; пути `~/…`, `$HOME/…`, `${HOME}/…`, `$CODELAB_HOME/…`, `${CODELAB_HOME}/…`, `../../.codelab/…` — значения из `AgentConfigPaths.expansions`; другой регистр при `caseInsensitive`;
  - жёсткая ссылка: `ln` без `-s` и `cp -l`/`cp --link` с защищаемым путём в любой позиции (сценарий «Жёсткая ссылка»);
  - `.codelab` подменён ссылкой после старта: перепроверка защищаемых путей асинхронно в `beforeToolCall` через `ExecutionEnv`;
  - каталоги-предки: `ln -s sub .codelab`, `mv .codelab x`, `rm -rf ~/.codelab`, `mkdir .codelab` — критические; после одобренного `ln -s sub .codelab` вызов `write sub/config.yaml` критический (сценарий «Подмена каталога ссылкой»); канонизация по самому глубокому существующему предку;
  - чтение не ограничено.

  Красный.
- [ ] 5.10 `[agent]` (OQ2 (а)) `AgentCoreServices.agentConfigPaths: AgentConfigPaths {paths, expansions, caseInsensitive}`; политика сравнивает цель после канонизации `BoundedEnv`, пересчитывает каноническую форму защищаемых путей на каждой проверке и расширяет шаблон `write to agent configuration`, в том числе для каталогов-предков (PERM-11, §7.6.1 — обновлён в итерации 0, задача 0.4; D8); `codelab_agent_io` — `config/agent_config_paths.dart` (`agentConfigPathsFor`); `AgentHost` и открыватель `codelab_embedded` передают значение. 5.9 зелёный.
- [ ] 5.11 `[agent]` Тесты `apps/codelab_agent/test/config_reload_process_test.dart` и `agent_host_config_test.dart` (agent-binary «Перезагрузка конфига в serve», все сценарии): правка → `config_option_update` не позже 5 с; битая правка → ни одного кадра; `--llm-script` без источника; источник закрыт после остановки; начальные `streamFunction` и `services.models` из одного вызова `modelsFor`. Плюс `agent_host_ws_commands_test.dart` (agent-binary, сценарий «WebSocket без /config»; R0-3): у `--ws` нет `config` и `mcp` в списке команд, `/config check` уходит модели. Красный.
- [ ] 5.12 `[agent]` `AgentHost`: `FileConfigSource`, `modelsFor`, `agentConfigPaths`, `configCommand: false` для `--ws`, закрытие после `runtime.dispose()`; `apps/codelab_agent/AGENTS.md`. 5.11 зелёный.
- [ ] 5.13 `[agent]` Тесты `codelab_embedded/test/embedded_config_reload_test.dart` (embedded-agent «Перезагрузка конфига встроенного агента», все сценарии): правка из другого процесса, `dispose` закрывает наблюдатель, новый ключ провайдера, срыв открытия после создания источника. Красный.
- [ ] 5.14 `[agent]` `codelab_embedded`: источник в открывателе, `agentConfigPaths`, начальные функция модели и каталог из `modelsFor`, шаг `config_source` в `dispose`; `codelab_embedded/AGENTS.md`. 5.13 зелёный.

**Критерий итерации 5.** Работающий `serve --stdio` и встроенный агент подхватывают правку `config.yaml` и замену ключа в `secrets.yaml` без перезапуска; невалидная правка не меняет поведение агента.

## 6. Переподключение MCP (итерация 6; D10, D11; E-04)

- [ ] 6.1 `[agent]` Тесты `codelab_agent_mcp/test/supervisor/mcp_reconnect_test.dart` и `mcp_supervisor_state_test.dart` на `FakeMcpServer`, `FakeClock`, `Random(0)` (agent-mcp-client «Переподключение и состояние серверов сессии», все сценарии; `core/mcp-reconnect-after-crash`, CFG-17):
  - задержки 1, 2, 4, 8, 16, 30, 30 с;
  - сброс после 10 с;
  - вызов в полёте и во время простоя;
  - новый набор на границе шага;
  - закрытие во время ожидания и после подключения;
  - сводка состояния;
  - повторное раскрытие `${secret:…}` перед каждой попыткой; неудачное раскрытие → `failed` с `lastError` без значения (сценарий «Секрет не задан при повторе»);
  - сервер с `enabled: false` в `disabled` без процесса; `setEnabled(true)` для выключенного конфигом и для выключенного коллизией (сценарий «Выключенный конфигом сервер»);
  - логи на 1-м и 10-м сбое.

  Красный.
- [ ] 6.2 `[agent]` `mcp/mcp_connector.dart` ядра: поля `McpServerSummary` с умолчаниями, `reconnect`, `setEnabled`, функция раскрытия секретов в `McpConnectRequest`; `McpServerConfig.enabled` и передача выключенных серверов из `resolve.dart` (сейчас выбрасываются, строки 872–882) с сохранением `mcp.server.skipped` (D10); `McpClientConnector`: автомат, задержки, поколения, `Random` и `Clock` от хоста, `_ConnectedSession`; реализации интерфейса в тестах — `codelab_agent_core/test/mcp/fake_mcp_connector.dart`, `codelab_agent_acp/test/support/server_harness.dart` (D11); `codelab_agent_mcp/AGENTS.md`. 6.1 зелёный, `web-compile` зелёный.
- [ ] 6.3 `[agent]` Тесты `codelab_agent_core/test/runtime/mcp_apply_config_test.dart` на fake-коннекторе (agent-runtime «Серверы конфигурации при перезагрузке», все сценарии): изменён один сервер; удаление во время хода; сервер клиента не тронут; последний побеждает. Неизменённый `failed` будится сразу; общая очередь с `setMcpServers`; новый и изменённый stdio-сервер (без прежнего `sameConnection`, в том числе `http` → `stdio`) и HTTP-сервер с подстановкой `${…}` (`X-Gw: ${secret:…}`, `Authorization: Bearer ${GITHUB_TOKEN}`) в желаемый список не попадают (R0-1, R0-4), HTTP-сервер без подстановок — попадает; включение stdio-сервера из `enabled: false` отложено; `enabled: true → false` закрывает сервер. Красный.
- [ ] 6.4 `[agent]` Рантайм: шаг 7a перезагрузки через `replaceServers` и очередь сессии. Хосты (`AgentHost`, `codelab_embedded`) передают `Random` коннектору. 6.3 зелёный.
- [ ] 6.5 `[agent]` Процессный тест `apps/codelab_agent/test/mcp_reconnect_process_test.dart`: stdio fake-сервер (`fake_mcp_stdio_server.dart`) завершается после первого вызова; следующий вызов после переподключения — `completed`; после закрытия сессии процессов нет. Красный → зелёный без изменения кода или с правкой хоста.

**Критерий итерации 6.** E-04 зелёный (`core/mcp-reconnect-after-crash`, `mcp_apply_config_test.dart`).

## 7. Команды `/config` и `/mcp` (итерация 7; D12; OQ1 (а))

- [ ] 7.1 `[agent]` Тесты `codelab_agent_core/test/commands/builtin_commands_test.dart` (agent-slash-commands «Встроенные команды config и mcp», все сценарии; «Список команд сессии», сценарии «Встроенные команды идут первыми», «Перезагрузка не меняет список»):
  - тексты побайтово, таблица `/mcp list`;
  - без модели и без журнала;
  - `Usage`, неизвестный `<id>`;
  - `/mcp disable` только в сессии;
  - `/mcp enable` отложенного нового сервера — `Unknown MCP server`, отложенного изменённого — прежний вариант (сценарий «enable отложенного сервера»);
  - `session/cancel` → `cancelled`, слот освобождён;
  - без `ConfigSource` и при `configCommand: false` — текст модели (сценарий «WebSocket без /config»);
  - первая строка `/config check` — `Config: valid` / `Config: invalid (issues: <n>)`, строки проблем — `ConfigIssue.toString()`;
  - параллельный `prompt` во время `/mcp reload` отклонён, в том числе без моста ACP; `/mcp reload` после отложенной замены (сценарии «Параллельный промпт во время /mcp reload», «/mcp reload после отложенной замены»).

  Красный.
- [ ] 7.2 `[agent]` `commands/builtin_commands.dart`, `SlashCommandSource.builtin`, перехват в `AgentSession.prompt` до шаблонов под тем же слотом хода, объявление по `services.config`, `configCommand` и capability `mcp`, лог `command.builtin`. 7.1 зелёный.
- [ ] 7.3 `[protocol]` Фикстура `packages/dart/codelab_acp_testing/fixtures/acp/slash-mcp-list.json` и фабрика агентского прогона (`setup.config.mcp.servers`; acp-golden-fixtures «Фикстуры файлов проекта этапа 8», сценарий «Таблица /mcp list»). Обновлённые `acp/available-commands-no-tools.json` и `acp/prompt-template-command.json` (список `mcp`, `review`; оба кадра `available_commands_update` второй фикстуры). Тесты `codelab_agent_acp/test/conformance_test.dart` и `session_new_test.dart` (agent-acp-server «session/new», сценарии «Режимы и опции новой сессии», «Команды шаблонов после session/new»; «Уведомления после перезагрузки конфигурации», сценарий «Ответ встроенной команды»). Красный.
- [ ] 7.4 `[protocol]` `codelab_agent_acp`: `available_commands_update` со встроенными командами, кадры ответа команды; прочие фикстуры, сверяющие список команд побайтово, обновлены. Клиентский прогон фикстур (`melos run` клиентского драйвера) зелёный без изменений клиента. 7.3 зелёный.

**Критерий итерации 7.** `acp/slash-mcp-list` зелёная; в палитре codelab-app и в `/agent:` CLI видны `mcp` и, при источнике конфига, `config`.

## 8. Матрица, документы, DoD (итерация 8)

- [ ] 8.1 `[docs]` `agent-parity-goals.md`:
  - L-25 — `provider_preconfig_env_test.dart`;
  - E-15 — `settings_registry_complete_test.dart`;
  - E-04 — `mcp_reconnect_test.dart`, `config_reload_test.dart`, `mcp_apply_config_test.dart`;
  - E-13 — агентская часть `acp/slash-mcp-list`, страница app — `add-provider-setup-ui`.

  Колонки «Критерий приёмки» с путями тестов.
- [ ] 8.2 `[docs]` `09-13-stage-8-mcp-config.md`: «Итог 8.10» по образцу 8.9 и DoD 8.10 с путями тестов; отступления (D8–D11, OQ5). Вложенные `AGENTS.md` — `codelab_agent_io`, `codelab_agent_mcp`, `codelab_setup`, `codelab_embedded`, `apps/codelab_agent`, `apps/codelab_cli` — сверены с кодом. Нумерация слоёв: в `agent-core/15-configuration.md` §15.2 окружение — слой 5, `--config` — 4а, а в спецификации agent-configuration «Слои конфигурации и их порядок» и в D3 — слои 6 и 5; привести §15.2, §15.3, §15.6 и §17.5.3 к нумерации спецификации (итерация 0 не перенумеровывала).
- [ ] 8.3 `[docs]` Purpose `openspec/specs/agent-slash-commands/spec.md` при архивировании: встроенные `config` и `mcp` теперь в этой спецификации (D12).
- [ ] 8.4 `[agent]` Definition of Done: тесты строк L-25, E-04, E-15 и `acp/slash-mcp-list` зелёные; `melos run guard` и `web-compile` зелёные; `openspec validate add-config-writer-and-reload --strict` — код `0`.
