## Why

Задача 8.11 (`09-13-stage-8-mcp-config.md`, п. 11) объединяла редакцию секретов (P-10) и распознавание литеральных секретов в конфиге (пункты 2–3 CFG-9, P-12). После двойного ревью пользователь 2026-11-04 изменил объём (design.md, «Open Questions»):
- **R8-1.** До 1.0 агент работает «как Claude Code»: модель, журнал, запрос к провайдеру и кадры ACP видят всё как есть, P-10 переносится после 1.0 (D1).
- **R8-4.** Литеральный секрет в файле конфига — не ошибка загрузки, а предупреждение с подсказкой переноса (D4). Это заменяет OQ2 и R8-2.
- **R8-5.** Запись литерала через argv CLI по-прежнему отклоняется (D5), а взамен появляется ввод значения из stdin (D11).
- **R8-3.** Кнопка переноса в codelab-app (D8).
- **R8-6…R8-11.** Уточнения по ходу итераций: правило источников ключа, предупреждение о 1.0, ссылка в `api_key`, граница `args`, итог слияния и самопочинка `secret migrate` (design.md, «Open Questions»).

Секрет, лежащий в файле конфига, остаётся риском 1.0:
- проектный слой лежит в git, пользовательский — в dotfiles;
- файл читает модель;
- `config get` показывает значения.

Человек должен это видеть и иметь одну команду для исправления. Прошлые change оставили 8.11 и долги: пункты 2–3 CFG-9, R1-1 (смешанное значение заголовка), R4-6 (`mcp.servers[*].args`).

## What Changes

- **Предупреждение о секрете в файле** (D3, D4). Находки CFG-9 пп. 1–3 в файловых слоях дают `config.secret.in_file`: `<key>: a secret is stored in the config file; move it to the secret store: codelab secret migrate[ --project| --local]`. Это касается:
  - литерального `api_key`, `token`, `secret`, `password`;
  - литеральных частей `headers`/`env` по шаблонам §12.4, в том числе смешанного `Bearer sk-… ${X}` (R1-1) и DSN, разрезанного подстановкой (L5);
  - ключа вместо имени в `api_key_env`, `api_key_secret`, `${secret:…}`.

  У файла `CODELAB_CONFIG`/`--config`, который `migrate` не пишет, подсказка — `codelab secret set <name>`. Загрузка не прерывается; `config check` печатает предупреждение. Для ключей недоверенного проекта, которые доверие и так отбрасывает, этого предупреждения нет.
- **Литеральный `providers.<id>.api_key` работает как ключ провайдера.** Это ослабление CFG-2 и P-12.
  - Вместе с `api_key_env` или `api_key_secret` после слияния слоёв — проблема «источники ключа взаимоисключающие» (R8-6).
  - `api_key: ${VAR}` и `api_key: ${secret:x}` — ссылка, а не литерал: без предупреждения, `migrate` её не трогает (R8-8).
  - Прочие ключи-секреты (`token`, `secret`, `password`, `apiKey`) не применяются.
  - Ссылки п. 3, похожие на значение, вместо проблемы формата имени дают предупреждение и маркер `UnusableKeyRef`: ход получает ошибку без значения.
  - Дескриптор реестра `providers.*.api_key` — `fileOnly`, `secret`; `provider add --api-key-*` удаляет литерал.
- **Живая перезагрузка (D12).** Литерал приравнивается к подстановке в правиле R0-4: `api_key` в атомарной группе провайдера; провайдер или сервер с находкой — «с ключом», его правки адреса и новые элементы с литералом — после перезапуска.
- **Предупреждение о 1.0 (R8-7, D13).** Строка `Note: before 1.0, tool output, prompts and session logs are not redacted…` в справке `secret` и `serve` обоих бинарей; раздел «Известные ограничения» в release notes создаётся в `release/*`.
- **Публичные функции ядра** `literalSecretTag` и `findInlineSecrets` — один источник находок для загрузки, писателя, маскирования и переноса.
- **Запись** (D5, R8-5, OQ3). `config set`, `mcp add`, `provider add` по-прежнему отклоняют литерал, в том числе по шаблону в `headers`, `env`, `mcp.servers[*].args`. `config get` маскирует элементы `args`, в том числе после секретного флага; писатель такую пару не отклоняет (R8-9).
- **`mcp add --header-stdin <Name> [--header-scheme <Scheme>]` и `--env-stdin <NAME>`** (D11). Значение читается из stdin и сохраняется в хранилище под `codelab/mcp/<server>/<key>`, а в файл пишется `${secret:…}`. Один такой флаг на вызов.
- **`secret set|delete`** с именем, похожим на значение, — ошибка использования.
- **`secret migrate`** у `codelab` и `codelab-agent` (D7) переносит находки в хранилище и заменяет их ссылками с сохранением комментариев. Флаги: `--project`, `--local`, `--all`, `--cwd`, `--dry-run`, `--force`. Доверие, конфликты и итог слияния всех выбранных слоёв (R8-10) проверяются до любой записи; конфликт источников ключа R8-6 в загруженном конфиге не мешает, если перенос его снимает (R8-11); значения недоверенных проектов в хранилище не попадают; `--force` затирает безвозвратно.
- **codelab-app** (R8-3, D8). Встроенный агент с секретами в файле стартует, а над транскриптом появляется предупреждение с кнопкой `Migrate secrets`. Дальше — диалог с планом без значений, перенос тем же движком через `codelab_embedded/io.dart` и кнопка `Restart agent`. Для бэкенда `env` — понятное сообщение.
- **Документы.** §12.4–§12.4.3 документа ядра помечаются «после 1.0»; P-10 в матрице — этап «после 1.0» с причиной.

## Не входит (после 1.0, R8-1)

- редакция вывода инструментов, промпта, запроса к провайдеру, журнала и кадров ACP;
- `Redactor`, `RedactingLogger`;
- `AgentTool.redactResult` и `readPathOf`;
- прогресс `exec` по строкам;
- применение `redact.*` (остаются `not_applied`; решение OQ1 сохранено);
- `/redact`, P-14, P-18, P-19;
- фильтр окружения подпроцессов по `KEY|SECRET|TOKEN`, как в Codex.

Решения и находки ревью для этой части сохранены в design.md, раздел «Перенесено после 1.0».

Также не входит:
- распознавание паролей в `url`/`base_url` (`config get` уже убирает userinfo, R4-5);
- изменение предконфигурации из окружения: `api_key` там по-прежнему проблема, в том числе в файле флага `--provider-config @путь` — это значение флага, а не слой конфига;
- изменения ACP.

## Capabilities

### New Capabilities
Нет.

### Modified Capabilities
- `agent-configuration`:
  - секрет в файле — предупреждение, литеральный `api_key`, правило источников ключа;
  - ссылки п. 3;
  - запись и маскирование `args`;
  - `mcp add --header-stdin|--env-stdin`;
  - ключи `redact.*` не применяются до change редакции после 1.0.
- `agent-runtime`: литералы в правиле R0-4 живой перезагрузки (D12).
- `agent-secrets`:
  - ключ провайдера из литерального `api_key`;
  - `secret migrate`;
  - имя секрета, похожее на значение;
  - список подкоманд `secret`;
  - ссылка п. 3 у MCP-сервера — `failed`.
- `codelab-cli`: `codelab secret migrate`, флаги stdin `codelab mcp add`, строка о 1.0 в справке `secret` и `codelab --help`.
- `agent-binary`: `codelab-agent secret migrate`, флаги stdin `codelab-agent mcp add`, строка о 1.0 в справке `serve` и `secret`.
- `embedded-agent`: `EmbeddedAgent.secretsInConfig`, мигратор в `codelab_embedded/io.dart`.
- `agent-workbench-ui`: предупреждение и перенос секретов встроенного агента.

## Impact

- **Код:**
  - `codelab_agent_core`: `config/inline_secrets.dart`, `config/resolve.dart`, ключ провайдера в `llm/`;
  - `codelab_agent_io`: `literal_secret_rule.dart`, `config_output.dart`, `config_warnings.dart`, `mcp_server_commands.dart`, `secret_migrator.dart`, `secret_commands.dart`;
  - `codelab_setup`: реэкспорт `SecretMigrator` и опций `mcp add` для CLI, `before1Note` в основном бареле;
  - `codelab_embedded`: `secretsInConfig` и реэкспорт `SecretMigrator` в `io.dart` для app;
  - `apps/codelab_agent`, `apps/codelab_cli`: argv;
  - `apps/codelab_desktop`: резолвер, порт, Cubit, предупреждение и диалог.
- **API.** Публичный барель ядра: `literalSecretTag`, `hasInlineSecret`, `findInlineSecrets`, `InlineSecretFinding`, `InlineSecretKind`; маркеры `UnusableKeyRef` и `UnusableSecretReference`, флаг `ProviderConfig.literalApiKey`, константа `before1Note` (D9, D13). `codelab_embedded`: `EmbeddedAgent.secretsInConfig`, в `io.dart` — мигратор и `secretMigrationOptionsFor`. Используемые сигнатуры не ломаются.
- **Зависимости:** новых нет. Правил сторожа, правок allowlist и рёбер графа нет: app берёт мигратор из `codelab_embedded/io.dart`, на который уже опирается, а `codelab_embedded` уже зависит от `codelab_agent_io`.
- **Поведение.** BREAKING нет: конфиги с литералами, которые раньше не стартовали (литеральный `api_key`, с 8.9), теперь стартуют с предупреждением. Новые флаги и подкоманда, новый элемент UI app.
- **Имя change.** Переименован из `add-agent-core-secret-redaction` (одобрено пользователем 2026-11-04): редакции секретов в объёме нет. Будущий change редакции после 1.0 упоминается без имени — «change редакции секретов после 1.0».
