Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_mcp`, `apps/codelab_agent`, новый мост `codelab_setup` (реэкспорт `codelab_agent_io`), сторож агентских пакетов и документы ядра;
- `[client]` — `apps/codelab_cli` и документы клиентов (`09-11-stage-6-cli-mvp.md`, §12.4).

Задач `[protocol]` и `[desktop]` нет. ACP не меняется: фикстуры и драйвер `codelab_acp_testing` не трогаются, а E-02 и E-03 со стороны конфига проверяются тестами хоста (design.md, D17).

Итерации — тонкие сквозные срезы, каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: правки документов и матрицы, без кода (включая решение пользователя 2026-10-29 о `codelab.toml`);
- итерация 1 — группы 1–6: ядро в памяти — `ConfigTree` → `CoreConfig` со схемой, доверием, слиянием, `${ENV}`, секретами, MCP-серверами, `redact`; маршрут провайдеров; таймаут сервера; сессия вне корня;
- итерация 2 — группы 7–9: YAML-загрузчик, `config.legacy_found`, бинарь `serve` на конфиге, MCP-серверы конфига в процессе (E-02, E-03 — часть конфигурации), DoD `config_loader_test.dart`;
- итерация 3 — группа 10: только `config check` — `ConfigCommands` и `codelab-agent config check`;
- итерация 4 — группа 11: мост `codelab_setup` и `codelab config check` (OQ2 (а));
- итерация 5 — группа 12: матрица, сверка документов, Definition of Done.

Проверки каждой задачи — по `AGENTS.md` §21 только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` пакета;
- `fvm dart test` пакета и `fvm flutter test` того же пакета: `melos run test` гоняет все пакеты через `flutter test`;
- `fvm dart run melos run guard` при правке `pubspec.yaml`, импортов или `rules.dart`;
- `fvm dart run melos run web-compile` при правке ядра.

Полный `melos run check` — в CI pull request.

Тесты с реальными процессами и файлами:
- идут на Dart VM, во временных каталогах (`CODELAB_HOME`, `cwd`);
- у каждого — `timeout` (`Timeout(Duration(seconds: 60))`) и пределы «не позже N с»;
- `dart` дочернего процесса — через `dartExecutable()` из `apps/codelab_agent/test/support/agent_process.dart` (работает и под `flutter test`);
- kernel бинаря компилируется один раз на файл теста.

`test:e2e:app:*` не запускаются (`AGENTS.md` §21).

## 0. Документы и матрица (без кода)

- [x] 0.1 `[agent]` Точечные правки `agent-core/15-configuration.md`:
  - §15.1 — `ConfigTree.kind` (`ConfigLayerKind`), `ConfigIssue.kind`, `HostSettings` (D3); без `package:toml` и `yaml_edit` в 8.5 (D2);
  - §15.2 — абзац о `codelab.toml` заменяется ссылкой на §15.7: файл не читается (D12);
  - §15.4:
    - `mcp.servers` — строка `call_timeout` (`duration`, `10m`, `1s..24h`; D10);
    - строка «другой `type` — ошибка» (D10);
  - §15.5 — `config.key.not_applied` для ключей без потребителя и разделов после MVP (D6); `config.yml` — `config.file.ignored` (D4); шаг 2 — `config.legacy_found` вместо `legacyLayers`; сообщения об ошибках на английском (`AGENTS.md` §15), примеры приведены к ним;
  - §15.6 — `--max-steps` у `codelab-agent`, `--llm-script` не читает слои 2–4, `--config x.toml` — ошибка без подсказки `migrate` (D4);
  - §15.7 переписывается в раздел «Перенос настроек Python-агента» (решение пользователя 2026-10-29): таблица соответствия ключей `codelab.toml` → `config.yaml` для ручного переноса (включая разделы Python-рантайма, которые не переносятся, провайдера `mock`, модель с префиксом провайдера), места поиска, текст `config.legacy_found`; алгоритм `legacyLayers`, «Только чтение», команда `config migrate` и «Срок поддержки» удаляются;
  - §15.10 — CFG-20 переписывается: агент и клиенты читают и пишут только YAML, `codelab.toml` не читается и даёт `config.legacy_found`;
  - §15.11 — абзац «Устаревший файл — только чтение» заменяется обоснованием решения 2026-10-29;
  - §15.12 — тесты `codelab.toml` и `migrate` заменяются на `config_legacy_found_test.dart` (D17).
- [x] 0.2 `[agent]` Точечные правки:
  - `agent-core/17-5-agent-setup.md` §17.5.2 — `ConfigIssue.kind`, без поля `ConfigLoadResult.legacy` и `ConfigLegacyReadOnlyException`; `suggestedSecretName` добавляет change 8.9 (D3, D8); §17.5.5 — без `config migrate`, `writeMigrated` и отказа записи при активном `codelab.toml`;
  - `agent-core/01-layers-and-packages.md` §1.2 — allowlist `codelab_agent_io` без `toml`; §1.3 — состав `config/` ядра и `config/`, `cli/` пакета `_io` (D1);
  - `agent-core/10-core-assembly-and-profiles.md` §10.3 — `CoreConfig.projectRoot`/`withoutProject` до снимков по корням 8.10 (D9);
  - `agent-core/12-observability-and-errors.md` §12.2 — новые события D16, удаление `config.legacy_*` кроме `config.legacy_found`;
  - `agent-core/02-llm-contract.md` §2.10 — `createRoutedStreamFunction` (D11);
  - `agent-core/16-non-mvp-and-open-questions.md` — строки об удалении читателя `codelab.toml` и о формате конфига;
  - ADR-0001, п. 11 — примечание о решении 2026-10-29 со ссылкой на этот change (текст решения ADR не переписывается).
- [x] 0.3 `[agent]` План:
  - `09-13-stage-8-mcp-config.md`, задача 8.5 — без чтения `codelab.toml`, `ConfigLegacyReadOnlyException`, `config migrate`, `toml`; с `config.legacy_found`; ссылка на этот change; DoD — `config_loader_test.dart`, строки R-16, E-02, E-03; абзац «OpenSpec change» — scope `add-agent-configuration` без `toml`;
  - `09-14-stage-9-switch-default.md` — задача 9.7: пользовательская документация описывает ручной перенос настроек по таблице §15.7 вместо `codelab config migrate`, `technology-stack.md` без `toml`; задача 9.10 удаляется (читателя нет).
- [x] 0.4 `[agent]` `agent-parity-goals.md` (решение пользователя 2026-10-29, Must-строка меняется явно):
  - R-16 — новый текст: «`codelab.toml` не читается; если `config.yaml` нет, одно предупреждение `config.legacy_found` с путём и ссылкой на таблицу ручного переноса §15.7; при `config.yaml` — без предупреждения»; критерий — `core/config-legacy-found-warning` (`config_legacy_found_test.dart`); пометка «изменено решением пользователя 2026-10-29, change `add-agent-configuration`»; сценарий R-16 таблицы сценариев переписывается так же;
  - DF-12 — TOML-определения убраны, критерий — `core/config-rejects-yaml-agent-definitions` (ключ `agents.definitions` в YAML);
  - DF-15 — «неизвестный вид провайдера в `config.yaml` — ошибка конфигурации», критерий `core/config-unknown-provider-error`;
  - §6 «Критерий вывода Python-агента», п. 5 — пользовательская документация говорит, что настройки Python-агента переносятся вручную по таблице §15.7 (вместо миграции командой).
- [x] 0.5 `[client]` `09-11-stage-6-cli-mvp.md` — `codelab config check` через `codelab_setup/io.dart` в составе 8.5, `--cwd`; строка `config migrate` и упоминания `codelab.toml` удаляются (D14); `12-4-first-run-and-settings.md` — минимальный состав `codelab_setup` в 8.5 (§12.4.2), действие «Migrate to config.yaml» и `ConfigLegacyReadOnly` удаляются.

## 1. Сторож ядра (D1)

- [x] 1.1 `[agent]` Тест `import_guard_test.dart` (workspace-architecture «Автоматический сторож границ пакетов», сценарий «Ядро импортирует разборщик конфигурации»): временный пакет с правилом ядра и `import 'package:yaml/yaml.dart'` даёт одно нарушение. Красный: правило ядра `package:yaml/` не запрещает.
- [x] 1.2 `[agent]` `rules.dart` — к запретам ядра добавить `package:yaml/`, `package:yaml_edit/`, `package:toml/` с комментарием CFG-5. 1.1 зелёный, `melos run guard` зелёный.

## 2. Типы и схема ядра (D3, D6)

- [x] 2.1 `[agent]` Тесты `codelab_agent_core/test/config/config_schema_test.dart` (agent-configuration «Схема и строгая проверка»; CFG-1, CFG-4) — табличные, на `ConfigTree` в коде:
  - неизвестный ключ с подсказкой (`reserve_token` → `reserve_tokens`);
  - ключ с точкой → вложенная форма;
  - неверный тип с ожидаемым типом;
  - `yes`/`on`/`off` в `bool` → `use true or false`, но `off` в `profile.*` — строка;
  - `null` у ключа схемы;
  - `int` не принимает `2.0`, `float` принимает `2`;
  - `30s` == `"30s"`;
  - `permissions.mode: autopilot` в слое `user`;
  - `agent.default_model: required`;
  - `exec.secrets` строкой;
  - `providers.foo.kind: mock` → проблема со списком видов (`core/config-unknown-provider-error`, DF-15);
  - `agents.definitions.reviewer` → проблема с подсказкой `.codelab/agents/reviewer.md` (`core/config-rejects-yaml-agent-definitions`, DF-12).

  Красный.
- [x] 2.2 `[agent]` Тест `config_validator_positions_test.dart` (сценарий «Слой без позиций»): слой с позициями → `ConfigIssue` со строкой и столбцом; `app-storage` без позиций → источник и путь без строки. Красный.
- [x] 2.3 `[agent]` Тест `config_not_applied_test.dart` (сценарий «Ключ без потребителя»; D6, OQ4 (а)): `loop.empty_response_retries`, `skills.max_skills`, `redact.enabled` → по одному `config.key.not_applied`; ключ по умолчанию — без предупреждения; `foo.bar` → `unknownKey`. Красный.
- [x] 2.4 `[agent]` Реализация `lib/src/config/`:
  - `config_tree.dart`, `config_issue.dart` (`ConfigIssueKind`, `ConfigLoadResult`, `ConfigException`, `ConfigInlineSecretException`), `schema.dart` (таблица MVP-ключей §15.4 и разделы после MVP), `resolve.dart` (шаги 1 и 6–7 D3), Левенштейн ≤ 2;
  - переезд `CoreConfig`, `PermissionsConfig`, `CompactionOverrides` в `config/core_config.dart` без изменения экспорта;
  - doc-комментарии по §15 `AGENTS.md`.

  2.1–2.3 зелёные, существующие тесты ядра зелёные без правок (характеризация: `const CoreConfig(defaultModel: …)` компилируется).

## 3. Слияние, доверие, подстановка, секреты, redact (D4, D7, D8)

- [x] 3.1 `[agent]` Тест `config_merge_test.dart` (сценарии «Проектный слой перекрывает глобальный», «Флаг сильнее переменной и файлов», «Серверы сливаются по имени»): списки заменяются, `mcp.servers` по `name`, `enabled: false` выключает, `tools.disabled` объединяется, `sources` по порядку. Красный.
- [x] 3.2 `[agent]` Тест `config_trust_test.dart` (agent-configuration «Доверие к проектному конфигу», все сценарии; CFG-3):
  - `mcp.servers`, `providers`, `permissions.tools: allow` без доверия → `config.project.untrusted_key`, с доверием — есть;
  - `narrow` режима;
  - `budget` только уменьшение;
  - `sessions.*`/`logging.*` из проекта отброшены и с доверием;
  - `trusted_projects` вне `user` — проблема;
  - `config.local.yaml` и `extra` без ограничений.

  Красный.
- [x] 3.3 `[agent]` Тест `config_interpolation_test.dart` (agent-configuration «Подстановка переменных окружения»): `${VAR}`, `$${`, `$VAR`, вне разрешённых ключей — литерал, незаданная — проблема с ключом и переменной, без повторного раскрытия. Значения не встречаются в `message`. Красный.
- [x] 3.4 `[agent]` Тест `config_secrets_test.dart` (agent-configuration «Секреты только ссылками»; CFG-2, `core/config-rejects-inline-api-key`):
  - `api_key`, `token`, `password` в `providers.*` и `mcp.servers[*]` → `inlineSecret`, текст без значения;
  - `api_key_env` + `api_key_secret` → проблема;
  - незаданная `api_key_env` → `config.provider.key_missing` и `providerProblems`;
  - `api_key_secret` и `${secret:…}` → `config.secret.unavailable`, сервер пропущен (D8).

  Красный.
- [x] 3.5 `[agent]` Тест `config_redact_test.dart` (agent-configuration «Ключи редакции секретов»): неизвестный слой, неизвестная запись `builtin`, некомпилируемое выражение с путём `redact.allowlist.patterns[0]`, правила доверия §12.4.3 (удаление слоёв и новые `patterns` из недоверенного проекта отброшены). Красный.
- [x] 3.6 `[agent]` Реализация шагов 2–5 `fromLayers`, `RedactSettings`, `HostSettings` (`sessions.dir`, `fsync`, `logging.level`, `logging.file`, `profile.*`), провайдеры → `List<CatalogProvider>` с `LlmTimeouts`/`RetryPolicy`. 3.1–3.5 зелёные.

## 4. MCP-серверы конфигурации и таймаут вызова (D10)

- [x] 4.1 `[agent]` Тест `config_mcp_servers_test.dart` ядра (agent-configuration «MCP-серверы конфигурации», сценарий «Неподдерживаемый тип в конфиге»):
  - `stdio` и `http` → `McpServerConfig(origin: config)` с `connectTimeout` и `callTimeout`;
  - порядок заголовков;
  - `type: sse` и `url` без схемы — проблемы;
  - `call_timeout: 0s` и `25h` — проблемы;
  - `enabled: false` → нет в списке и `mcp.server.skipped {reason: "disabled in config"}`;
  - `toString` не раскрывает `env`/`headers`.

  Красный.
- [x] 4.2 `[agent]` Тест `codelab_agent_mcp/test/connector_test.dart`, группа «call timeout per server» (agent-mcp-client «Вызов инструмента, отмена и таймаут», сценарий «Таймаут сервера сильнее общего»): на `FakeClock` сервер с `callTimeout: 2 s` получает сигнал отмены и текст `within 2 s.`, сервер с `null` ждёт `options.callTimeout`. Красный.
- [x] 4.3 `[agent]` Реализация: поле `Duration? callTimeout` в `McpServerConfig` и ветвях (не входит в `sameConnection`), передача в клиента в `McpClientConnector`, отображение элементов `mcp.servers` в `resolve.dart`. Обновить doc-комментарий `McpClientOptions` (ключ теперь есть). 4.1–4.2 зелёные; тесты `codelab_agent_mcp` и `codelab_agent_acp` зелёные.

## 5. Несколько провайдеров (D11)

- [x] 5.1 `[agent]` Тест `codelab_agent_core/test/llm/routed_stream_function_test.dart` (agent-llm «Фабрика и закрытые адаптеры», сценарии «Маршрут по провайдеру», «Провайдер без ключа»): два провайдера на `MockClient` — запрос только к нужному, цепочка второго не создана; провайдер из `unavailable` — ошибка `auth` с текстом, ноль HTTP-запросов; неизвестный провайдер — `badRequest`. Красный.
- [x] 5.2 `[agent]` `createRoutedStreamFunction` в `llm/provider_factory.dart`, экспорт из бареля (PKG-5 соблюдён). 5.1 зелёный.

## 6. Сессия вне корня запуска (D9)

- [x] 6.1 `[agent]` Тест `codelab_agent_core/test/runtime/config_outside_root_test.dart` (agent-runtime «Конфигурация сессии вне корня запуска», все сценарии): `projectRoot: /A`, сессии `/A`, `/B`, `/A/sub` — серверы, режим, правила и модель из нужного снимка, один `config.session.outside_root` на `cwd`; `loadSession` — то же правило. Красный.
- [x] 6.2 `[agent]` `CoreConfig.projectRoot`/`withoutProject`, выбор снимка в `AgentRuntimeImpl` для `createSession` и `loadSession`. 6.1 зелёный, `melos run web-compile` зелёный.
- [x] 6.3 `[agent]` Исправления по ревью итерации 1 (решения пользователя 2026-10-30; design.md D3, D6–D9, D16; agent-configuration «Доверие к проектному конфигу», «Секреты только ссылками», «Схема и строгая проверка»; agent-permissions «Дополнительно запрещённые уровни из конфигурации»). Каждый пункт — сначала красный тест:
  - `ask` + `plan` в любом порядке → режим `ask` и поле дополнительно запрещённых уровней `PermissionsConfig` (`extraDeniedTiers = {write, exec}`); политика запрещает `mode.deniedTiers ∪ extra`; `session/set_mode` запрет не снимает;
  - `config.local.yaml` подчиняется правилам доверия, пока проект не в `trusted_projects`;
  - `permissions.deny` недоверенного проекта объединяется с нижними слоями; `permissions.tools.<t>` — только если не мягче (`deny` > `ask` > `allow`, равное применяется), иначе `config.project.untrusted_key`;
  - `secrets` отбрасывается из обоих проектных слоёв всегда (`ignored: secrets is read only from the global config`);
  - `prompts.*` и разделы `hooks`, `plugins`, `a2a`, `lsp` из недоверенного проекта отбрасываются с `config.project.untrusted_key`;
  - формат имён `api_key_env`/`api_key_secret`, значение не попадает в сообщение;
  - проектные слои без `projectRoot` — `ArgumentError`;
  - `trusted_projects`: только абсолютные пути; глобальный слой — `user` или `appStorage`; в проектном слое — `config.project.untrusted_key`;
  - ошибки LLM-транспорта без HTTP-статуса не содержат URL провайдера (`stream_state.dart`): адрес может нести учётные данные в userinfo или query и имя внутреннего хоста; тест — сетевой сбой на `MockClient` для URL с `user:pass@` и `?key=`, текст ошибки хода и лог без URL; Текст сетевого сбоя — `connection failed: <runtimeType>`, в прочих текстах любой `http(s)://…` заменяется на `<url>`; тест `test/llm/error_text_no_url_test.dart`.
  - сверка с принятыми отклонениями (D3, D6, D7, D8, D9, D16): `ConfigIssue.event/fields/level` у предупреждений и `ConfigLoadResult.orThrow()`; `HostSettings.fsync` строкой; `untrusted_key` для смягчения `permissions.mode`; ключи проблем `profile.<name>.<capability>`, `redact.layers[i]`, `providers.<id>.api_key_secret`; текст inlineSecret MCP `use ${NAME} in env or headers`; `not_applied` по листьям; `profile.<name>` — только встроенные профили, неизвестная capability — `unknownKey`, capability после MVP — `not_applied`; `default_model` в `providers.<p>.models`; `withoutProject` — второй проход `fromLayers` с `fallbackModel` и отказом при его проблемах; `config.session.outside_root` — логгером сессии, один раз на нормализованный `cwd`.

  Тесты групп 2–6 зелёные, `melos run guard` и `melos run web-compile` зелёные. **Конец итерации 1.**

## 7. Разведка и строгий профиль YAML (D2, D5)

- [x] 7.1 `[agent]` Разведка `package:yaml` 3.1.x (исключение (д) правила TDD, не дольше одного дня, без кода в `lib/`):
  - `span` узла с якорем и тегом;
  - идентичность узла алиаса;
  - `yes`/`on`/`0o17`/`~`;
  - `Duplicate mapping key` и его `span`;
  - BOM, CRLF.

  Итог — абзац в design.md D5 (подтверждение лексической проверки или переход на запасной путь).
- [x] 7.2 `[agent]` Сначала тест: `pubspec_allowlist_test.dart` — `ioAllowlist` без `toml`, проверка на временном `pubspec.yaml` с `toml` называет его (workspace-architecture, сценарий «Зависимость вне allowlist»); затем `ioAllowlist` правится, `pubspec.yaml` `codelab_agent_io` получает `yaml: ^3.1.3` с комментарием-ссылкой на D2; `melos bootstrap`; `melos run guard` зелёный.
- [x] 7.3 `[agent]` Тест `codelab_agent_io/test/config/config_yaml_profile_test.dart` (agent-configuration «Строгий профиль YAML», оба сценария; CFG-21) — все пункты §15.12 для профиля: якорь, ссылка, `<<: *base`, `!!str`, второй документ, ключ `1:`, составной ключ, повтор с обеими позициями, пустой файл, комментарии, flow-стиль, CRLF, BOM. Красный.
- [x] 7.4 `[agent]` `lib/src/config/yaml_reader.dart` — `readYamlTree(text, source:)` → `ConfigTree` с позициями или проблемы `profile`/`syntax`. 7.3 зелёный.

## 8. `ConfigLoader` (D4)

- [x] 8.1 `[agent]` Тест `codelab_agent_io/test/config/config_loader_test.dart` на временных каталогах (agent-configuration «Слои конфигурации и их порядок», все сценарии; DoD этапа):
  - **`invalid config reports key path and line`** — битый `.codelab/config.yaml` даёт `ConfigIssue` с файлом, строкой, столбцом и путём ключа, а не исключение;
  - порядок шести слоёв и `--config`;
  - `CODELAB_CONFIG=x.toml` → ошибка использования (`codelab.toml` не поддерживается);
  - `config.yml` → `config.file.ignored`;
  - со сценарием слои 2–4 не читаются, каталог не изменён;
  - слой окружения: `CODELAB_MODEL`, `CODELAB_MAX_STEPS`, `CODELAB_PERMISSION_MODE`, `CODELAB_LOG_*`;
  - `projectRoot` канонический (symlink на каталог).

  Красный.
- [x] 8.2 `[agent]` `config_loader.dart`, `environment_layer.dart`, экспорт `ConfigLoader` из бареля `codelab_agent_io`. 8.1 зелёный.
- [x] 8.3 `[agent]` Тест `codelab_agent_io/test/config/config_legacy_found_test.dart` — критерий `core/config-legacy-found-warning` (R-16 в редакции 2026-10-29; agent-configuration «Найденный codelab.toml не читается», сценарии «Только codelab.toml», «codelab.toml рядом с config.yaml»):
  - только `<cwd>/codelab.toml` с синтаксической ошибкой TOML и `$CODELAB_HOME/auth.toml` → загрузка без проблем из них, ровно одно `config.legacy_found` на два вызова `load` того же `cwd`, оба пути, ссылка на раздел 15.7, текст на английском, содержимого файлов в логе нет;
  - `$CODELAB_HOME/config.yaml` рядом с `<cwd>/codelab.toml` → предупреждения нет;
  - `--config x.yaml` при одном `codelab.toml` → предупреждения нет;
  - со сценарием (`--llm-script`) → не ищется;
  - `codelab.toml.example` → не ищется.

  Красный.
- [x] 8.4 `[agent]` `lib/src/config/legacy_notice.dart` (только проверка существования файлов, doc-комментарий со ссылкой на D12 и решение пользователя), подключение к `ConfigLoader`. 8.3 зелёный.

## 9. Бинарь `serve` на конфиге (D4, D10, D11, D16)

- [x] 9.1 `[agent]` Характеризационные тесты до правки `serve_args.dart` (исключение (а) правила TDD): существующие сценарии `serve_flags_test.dart` и `agent_host_test.dart` с `--provider`/`--model`/`--llm-script` без файлов конфига фиксируются и остаются зелёными после 9.3.
- [x] 9.2 `[agent]` Тесты (agent-binary «Конфиг бинаря из файлов, окружения и флагов», «Логи бинаря»):
  - `serve_flags_test.dart` — `--model anthropic/x` без `--provider` допустим, `--model gpt` без `--provider` — `64`, `--config a.toml` — `64`, `--max-steps`;
  - `agent_host_config_test.dart` — хост из `config.yaml` с провайдерами `openai` и `anthropic`: опция `model` содержит обе модели, запрос уходит на `base_url` нужного провайдера (`MockClient`); `profile.agent-serve.mcp: [http]` сужает профиль, `[stdio, http, sse]` — проблема конфига; `logging.file` из конфига и приоритет флага; HTTP MCP-сервер из конфига на `MockClient` над `FakeMcpServer` доступен модели (E-03, часть конфигурации);
  - процессный `config_invalid_process_test.dart` — битый конфиг → код `64` до чтения stdin, `config.yaml:<line>:` в stderr, `sk-test-secret` из `api_key` не встречается ни в stderr, ни в файле лога.

  Красные.
- [x] 9.3 `[agent]` Реализация в `apps/codelab_agent`:
  - `serve_args.dart` строит `ConfigTree` флагов, а не модели;
  - `AgentHost.build(ConfigLoadResult, …)` с `StaticModelCatalog` из `CoreConfig.providers`, `createRoutedStreamFunction`, `sessions.dir`/`fsync`, сужением профиля, тестовым шовом `http.Client`;
  - `run.dart` — проблемы конфига в stderr и `serve.config.invalid`, код `64`;
  - `host.config.loaded` и предупреждения D16;
  - doc-комментарий `ServeOptions` обновлён (флаги больше не «весь конфиг»).

  9.1–9.2 зелёные.
- [x] 9.4 `[agent]` Процессный тест `apps/codelab_agent/test/config_mcp_servers_test.dart` (agent-binary «MCP-серверы в бинаре», сценарий «Сервер из конфигурации»; agent-configuration, сценарий «Сервер конфига в сессии»; E-02, часть конфигурации): `serve --stdio --llm-script … --config <tmp>/c.yaml` с fake stdio-сервером в `mcp.servers`, `session/new` без `mcpServers` → `mcp__fake__echo` `completed` с `hi`; после EOF процесс сервера с записанным pid не жив не позже 10 с. Красный → зелёный без нового кода или с минимальной правкой. Если тест сразу зелёный, PR ссылается на критерий (`AGENTS.md` ядра §2).
- [x] 9.5 `[agent]` Тест сценария «WS-профиль не запускает MCP-серверы» (agent-binary): `serve --ws` с сервером в конфиге и сервером клиента — ни одного процесса, два `mcp.server.skipped` с причиной профиля. Красный → зелёный.
- [x] 9.6 Исправления по ревью итерации 2 (решения пользователя 2026-10-30; design.md D4, D5, D7, D9, D16). Каждая пара — красный тест, затем код:
  - `[agent]` явно названный, но отсутствующий файл `--config`/`CODELAB_CONFIG` — `ConfigIssue` `syntax` `cannot read the file` с источником `--config`/`CODELAB_CONFIG`, код `64`; отсутствие слоёв 2–4 — пропуск (agent-configuration «Слои конфигурации и их порядок», сценарий «Явно названный файл отсутствует»; agent-binary, тот же сценарий): `config_loader_test.dart`, `serve_flags_test.dart` или процессный тест → `config_loader.dart`;
  - `[agent]` относительный `CODELAB_CONFIG` — ошибка использования `64` с именем переменной; относительный `--config` — от текущего каталога процесса (agent-binary, сценарий «Относительный CODELAB_CONFIG»; D4) → `serve_args.dart`/`serve_config.dart`;
  - `[agent]` со сценарием `--llm-script` ключи `sessions.dir` и `sessions.fsync` из `--config` не применяются, по ключу — `config.key.not_applied` (agent-binary, сценарий «Журналы сценария не берутся из конфига»; D4) → `agent_host.dart`/`serve_config.dart`;
  - `[agent]` `--provider`: `api_key_env: CODELAB_API_KEY` только при заданной и непустой переменной; слой флагов заменяет `providers.cli` целиком (agent-binary, сценарии «Провайдер флагов без ключа», «Флаги заменяют providers.cli целиком»; D4) → `serve_args.dart`, слияние ядра `merge.dart` (тест ядра `codelab_agent_core/test/config/` на замену `providers.cli` слоем `flags`);
  - `[agent]` правила `--model` и `--max-steps`, `agent.default_model: required` — тесты на уже реализованное поведение (agent-binary, сценарии «Ошибки --model без --provider», «Нет модели по умолчанию»); если тест сразу зелёный, PR ссылается на критерий;
  - `[agent]` пределы разбора: файл больше 1 MiB — `syntax`; вложенность глубже 64 (в том числе глубокий flow-список) — `profile` без `StackOverflowError`; нестандартный тег — `profile` без имени тега в тексте; тег и якорь на корне (agent-configuration «Строгий профиль YAML», сценарий «Пределы и нестандартные теги»; D5) → `yaml_reader.dart`, `config_loader.dart`;
  - `[agent]` канонизация: элементы `trusted_projects` и корень проекта — в `ConfigLoader`; `cwd` сессии — через `PathResolver.realpath` перед `forSessionCwd` (agent-configuration «Доверие к проектному конфигу», сценарий «Доверие через symlink»; agent-runtime, сценарий «cwd через symlink на корень запуска»; D7, D9) → `config_loader.dart`, `agent_runtime.dart`;
  - `[agent]` наблюдаемость: `host.config.loaded` с `transport` и `models`, поле `message` у каждого события предупреждения загрузки и у `mcp.server.skipped` (agent-configuration «Наблюдаемость загрузки конфигурации»; D16) → `agent_host.dart`, `run.dart`.

  **Конец итерации 2.**

## 10. Подкоманда `codelab-agent config check` (D13)

- [x] 10.1 `[agent]` Тест `codelab_agent_io/test/cli/config_commands_test.dart` (agent-configuration «Подкоманда config check», все сценарии):
  - `Sources:`, строки проблем с файлом, строкой, столбцом и подсказкой, предупреждения (включая `config.legacy_found`), итоговая строка;
  - коды `0`/`1`;
  - `check` ничего не пишет;
  - `sk-test-secret` из `api_key` не встречается в выводе.

  Красный.
- [x] 10.2 `[agent]` `lib/src/cli/config_commands.dart` (`ConfigCommands`, `CheckOptions`, `ConfigCommandResult`), экспорт из бареля `codelab_agent_io`. 10.1 зелёный.
- [x] 10.3 `[agent]` Процессный тест `apps/codelab_agent/test/config_command_process_test.dart` (agent-binary «Подкоманда config бинаря», оба сценария): `config check` без сервера — `Config: valid`, код `0`, stdin не читается; `config set …` и `config migrate` → `64` и справка. Красный.
- [x] 10.4 `[agent]` Команда `config` с единственной подкомандой `check` в `run.dart`/`serve_args.dart` (`package:args`), вызов `ConfigCommands`. 10.3 зелёный. **Конец итерации 3.**
- [x] 10.5 `[agent]` Исправления по ревью итерации 3 (agent-configuration «Подкоманда config check» — сценарии «Предупреждения не делают конфиг невалидным», «Подсказка о codelab.toml», «CODELAB_CONFIG учитывается», «Несуществующий каталог», «Ошибка использования из окружения»; agent-binary «Подкоманда config бинаря» — сценарии «Ошибка разбора аргументов config», «Общая справка называет config check»): сначала красные тесты в `config_commands_test.dart` и `config_command_process_test.dart`, затем код — распознавание неизвестных `CODELAB_*` в `ConfigLoader` (`config.env.unknown`, D13), текст `config.legacy_found` без повтора пути из локации, `ConfigUsageException` → `64` с пустым stdout, ошибка разбора `config …` → `64` и справка `config`, `config check` в общей справке бинаря.

## 11. Мост `codelab_setup` и `codelab config check` (D14, OQ2 (а))

- [x] 11.1 `[agent]` Тесты сторожа (workspace-architecture, сценарий «Основной барель моста импортирует IO-пакет агента»): `import_guard_test.dart` на временном пакете с правилом `codelab_setup`; `pubspec_allowlist_test.dart` — `setupAllowlist = {codelab_agent_core, codelab_agent_io, meta}`, `codelab_setup` в `cliAllowlist`. Красные.
- [x] 11.2 `[agent]` Пакет `packages/dart/codelab_setup`:
  - `pubspec.yaml` с комментарием allowlist;
  - `lib/codelab_setup.dart` — реэкспорт `ConfigIssue`, `ConfigIssueKind`, `ConfigLoadResult`;
  - `lib/io.dart` — реэкспорт `ConfigCommands`, `CheckOptions`, `ConfigCommandResult`;
  - вложенный `AGENTS.md` (границы, «что придёт позже» по §12.4.2);
  - `workspace:` корневого `pubspec.yaml`;
  - правило в `rules.dart` вместо заготовки `// stage 7: codelab_setup`;
  - `README.md` — таблица и граф (D1);
  - `melos bootstrap`.

  11.1 зелёные, `package_naming_test.dart` зелёный.
- [x] 11.3 `[client]` Тест `apps/codelab_cli/test/config_command_test.dart` и e2e процесса `cli/config-check-reports-issues` (codelab-cli «Подкоманда codelab config», все сценарии): `check` на временных `CODELAB_HOME` и `--cwd` — проблема и код `1`, процесс агента не запускается; `config set` и `config migrate` → `64` `Unknown command`; вывод совпадает с `codelab-agent config check` для тех же каталогов (сценарий «Одинаковый вывод у двух бинарей»). Красные.
- [x] 11.4 `[client]` `apps/codelab_cli`: зависимость `codelab_setup` в `pubspec.yaml`; подкоманда `config check` в `cli_args.dart` и `run.dart` (`CliCommand.config`); вызов `package:codelab_setup/io.dart`; строка в `--help`; `dart:io` — только в точке входа и composition root (CLI `AGENTS.md` §2); вложенный `AGENTS.md` CLI — `codelab_setup` в списке зависимостей. 11.3 зелёные, `melos run guard` зелёный. **Конец итерации 4.**
- [x] 11.5 `[client]` Исправления по ревью итерации 4 (codelab-cli «Подкоманда codelab config» — сценарии «Неизвестная подкоманда config», «config без подкоманды», «--cwd подкоманды сильнее общего», «Без --cwd подкоманды берётся общий», «Относительный путь и `..` канонизирует загрузчик», «Флаги подключения с config — ошибка использования», «config check не меняет CODELAB_HOME»; workspace-architecture — `package:codelab_setup/io.dart` только из `run.dart`): сначала красные тесты в `config_command_test.dart`, e2e процесса и стороже (`rules.dart`), затем код `cli_args.dart`/`run.dart`. `melos run guard` зелёный.

## 12. Матрица, документы и Definition of Done

- [x] 12.1 `[agent]` `agent-parity-goals.md`:
  - E-02 и E-03 — серверы конфигурации подключаются (тесты 9.4 и 9.2), убрать «после change `add-agent-configuration`»;
  - R-16 (в редакции задачи 0.4) — критерий `core/config-legacy-found-warning` закрыт (8.3);
  - DF-12 (`core/config-rejects-yaml-agent-definitions`) и DF-15 (`core/config-unknown-provider-error`) закрыты (2.1).
- [x] 12.2 `[agent]` Сверка документов с кодом:
  - `agent-core/15-configuration.md`, §1.2–§1.3, §10.3, §12.2, §17.5.2 — то, что сделано, совпадает с D1–D17;
  - вложенные `AGENTS.md`: `codelab_agent_io` (`config/`, `cli/`, allowlist без `toml`), `apps/codelab_agent` (`config check`, файлы конфига, `--config`, `--max-steps`), `codelab_agent_core` (`config/`);
  - спецификации, которые изменились по ходу реализации, правятся в этом change, а не молча (`AGENTS.md` §17).
- [x] 12.3 `[client]` Сверка `09-11-stage-6-cli-mvp.md` и `apps/codelab_cli/AGENTS.md` с реализованной подкомандой.
- [x] 12.4 `[agent]` DoD этапа 8 для 8.5 в `09-13-stage-8-mcp-config.md`: отметка «Выполнено» у `config_loader_test.dart: invalid config reports key path and line`, строки R-16 (новая редакция), E-02 и E-03 (серверы конфигурации).
- [ ] 12.5 Полный melos run check зелёный в CI pull request. **Конец итерации 5.**
