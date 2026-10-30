## ADDED Requirements

### Requirement: Слои конфигурации и их порядок
Загрузчик `ConfigLoader` (`codelab_agent_io`) SHALL собирать конфигурацию агента из слоёв, от низшего приоритета к высшему (`agent-core-architecture` §15.2, §15.6):
1. встроенные умолчания;
2. `$CODELAB_HOME/config.yaml` (`CODELAB_HOME` по умолчанию `~/.codelab`);
3. `<cwd>/.codelab/config.yaml`;
4. `<cwd>/.codelab/config.local.yaml`;
5. файл `--config <path>` или `CODELAB_CONFIG` с расширением `.yaml` или `.yml`;
6. переменные `CODELAB_*`;
7. флаги командной строки.

Отсутствующий файл SHALL пропускаться. Отображения SHALL сливаться по ключам рекурсивно, скаляры и списки — заменяться целиком. Список `mcp.servers` SHALL сливаться по `name`: тот же `name` заменяет сервер, новый добавляется в конец, `enabled: false` в более приоритетном слое выключает сервер. `tools.disabled` слоёв 2–4 SHALL объединяться. `--config` с расширением `.toml` SHALL быть ошибкой использования: `codelab.toml` не поддерживается. Файл `config.yml` рядом с `config.yaml` или вместо него SHALL не читаться и давать предупреждение `config.file.ignored`. При запуске со сценарием `--llm-script` слои 2–4 SHALL не читаться.

#### Scenario: Проектный слой перекрывает глобальный
- **WHEN** `$CODELAB_HOME/config.yaml` задаёт `budget.max_steps: 50`, а `<cwd>/.codelab/config.yaml` — `budget.max_steps: 20`
- **THEN** итоговый `CoreConfig.budget.maxSteps` равен `20`

#### Scenario: Флаг сильнее переменной и файлов
- **WHEN** `config.local.yaml` задаёт `budget.max_steps: 30`, окружение — `CODELAB_MAX_STEPS=40`, а запуск — `--max-steps 10`
- **THEN** итоговое значение `10`, а `sources` результата перечисляет слои по порядку

#### Scenario: Серверы сливаются по имени
- **WHEN** глобальный слой объявляет серверы `github` и `files`, а локальный проектный — `github` с другим `url` и `files` с `enabled: false`
- **THEN** итог содержит один `github` с адресом локального слоя и не содержит `files`

#### Scenario: Сценарий не читает файлы пользователя
- **WHEN** загрузчик вызывается со сценарием `--llm-script` и `CODELAB_HOME=<tmp>`, где есть `config.yaml` с ошибкой
- **THEN** загрузка успешна, файл не прочитан, каталог `<tmp>` не изменён

### Requirement: Строгий профиль YAML
Файлы конфигурации SHALL разбираться `package:yaml` в `codelab_agent_io` в строгом профиле YAML 1.2 (§15.5, CFG-21). Каждое нарушение SHALL давать `ConfigIssue` с файлом, строкой и столбцом узла:
- второй документ — `multiple YAML documents are not supported`;
- якорь, алиас, ключ слияния `<<`, явный тег — `anchors, aliases, merge keys and tags are not supported`;
- ключ не строка (`1:`, `null`, `true`, составной) — ошибка;
- повторяющийся ключ — ошибка с позициями обоих ключей.

Пустой файл и файл только из комментариев SHALL давать пустой слой. Блочный и flow-стиль, переводы строк LF и CRLF и BOM SHALL читаться одинаково. Ядро НЕ SHALL импортировать `package:yaml`, `package:yaml_edit` и `package:toml` (CFG-5).

#### Scenario: Таблица нарушений профиля
- **WHEN** `config_yaml_profile_test.dart` разбирает файлы с якорем и ссылкой, `<<: *base`, тегом `!!str`, вторым документом, ключом `1:`, составным ключом и повторяющимся ключом
- **THEN** каждый даёт `ConfigIssue` вида `profile` со строкой и столбцом, а повторяющийся ключ называет позиции обоих

#### Scenario: Пустые файлы и стили
- **WHEN** разбираются пустой файл, файл из комментариев, файл во flow-стиле и тот же файл с CRLF и BOM
- **THEN** первые два дают пустой слой, а остальные — одинаковые деревья

### Requirement: Схема и строгая проверка
Ядро SHALL проверять каждый слой функцией `CoreConfig.fromLayers(layers, environment: …, projectRoot: …)` без файлов и без разборщиков (`codelab_agent_core/lib/src/config/`). Результат `ConfigLoadResult` SHALL содержать либо `CoreConfig`, либо непустой список `ConfigIssue {kind, key, source, line?, column?, message}`, а также предупреждения (тот же тип с заполненными `event`, `fields`, `level`) и список источников. `ConfigLoadResult.orThrow()` SHALL возвращать `CoreConfig` или бросать `ConfigException` (`ConfigInlineSecretException`, если есть проблема `inlineSecret`). Проектные слои без `projectRoot` — ошибка программиста хоста (`ArgumentError`), а не `ConfigIssue`.

- Неизвестный ключ SHALL давать проблему `unknownKey` с путём ключа и подсказкой ближайшего известного ключа (расстояние Левенштейна ≤ 2); ключ с точкой внутри — подсказку вложенной формы.
- Неверный тип SHALL давать проблему `type` с ожидаемым типом. Для `bool` строки `yes`, `no`, `on`, `off`, `y`, `n` — ошибка с подсказкой `use true or false`. `null` у ключа схемы — ошибка. `int` НЕ SHALL принимать `2.0`, `float` SHALL принимать `2`. `30s` и `"30s"` SHALL быть равны.
- `permissions.mode: autopilot` в любом файловом слое SHALL быть проблемой (CFG-4).
- Семантические проверки §15.5, шаг 8:
  - `agent.default_model` задан (`agent.default_model: required`), его провайдер объявлен, а модель есть в `providers.<p>.models`;
  - `openai-compatible` имеет `base_url`;
  - имена `mcp.servers` уникальны, `stdio` имеет `command`, `http` имеет `url`;
  - `reserve_tokens > 0`, `keep_recent_tokens > 0`, `max_steps ≥ 1`;
  - `idle_timeout_reasoning ≥ idle_timeout`.

  Нарушение SHALL давать проблему с путём ключа.

Строка и столбец SHALL браться из позиций слоя. У слоя без позиций (окружение, флаги, хранилище приложения) сообщение SHALL называть источник и путь ключа без строки.

Ключ схемы MVP без потребителя в этой сборке и ключ раздела после MVP SHALL приниматься с одним предупреждением `config.key.not_applied {key, source}` на каждый явно заданный лист; ключ вне схемы и вне списка разделов после MVP — проблема `unknownKey`. В `profile.<name>` допустимы только встроенные профили и известные capability (иначе `unknownKey`); capability после MVP даёт `config.key.not_applied`; расширение профиля — проблема с ключом `profile.<name>.<capability>`.

#### Scenario: Опечатка с подсказкой
- **WHEN** `config.yaml` содержит в строке 12, столбце 3 ключ `compaction.reserve_token`
- **THEN** проблема — `config.yaml:12:3: compaction.reserve_token: unknown key (did you mean reserve_tokens?)`, `CoreConfig` не построен

#### Scenario: Ключ с точкой
- **WHEN** внутри `tools:` записан ключ `output.max_lines: 2000`
- **THEN** проблема `unknownKey` предлагает вложенную форму `output:` → `max_lines:`

#### Scenario: Логическое значение yes
- **WHEN** `compaction.enabled: yes`, а в `profile.agent-serve.shell_exec` записано `off`
- **THEN** первое — проблема типа с подсказкой `use true or false`, второе — строка `off`

#### Scenario: Слой без позиций
- **WHEN** `fromLayers` получает слой `app-storage` без позиций с `budget.max_steps: "x"`
- **THEN** сообщение называет источник `app-storage` и ключ `budget.max_steps`, строки и столбца нет (`config_validator_positions_test.dart`)

#### Scenario: Ключ без потребителя
- **WHEN** глобальный конфиг задаёт `loop.empty_response_retries: 3` и `skills.max_skills: 100`
- **THEN** загрузка успешна, каждое значение даёт одно предупреждение `config.key.not_applied` с ключом и источником

#### Scenario: Предупреждения по листьям
- **WHEN** глобальный конфиг задаёт `loop: {misuse: {warn_after: 3, block_after: 6}}`
- **THEN** два предупреждения `config.key.not_applied` с ключами `loop.misuse.warn_after` и `loop.misuse.block_after`

#### Scenario: Сужение профиля
- **WHEN** глобальный конфиг задаёт `profile.my-profile.mcp: off`, `profile.agent-serve.shell: off`, `profile.agent-serve.network: off` и `profile.agent-serve.mcp: [stdio, http, sse]`
- **THEN** первые два — `unknownKey`, третье — `config.key.not_applied`, четвёртое — проблема с ключом `profile.agent-serve.mcp`

#### Scenario: Модель вне каталога провайдера
- **WHEN** `agent.default_model: openai/gpt-x`, а у провайдера `openai` в `models` только `gpt-4o`
- **THEN** проблема `agent.default_model`, `CoreConfig` не построен

#### Scenario: autopilot в файле
- **WHEN** `config.yaml` задаёт `permissions.mode: autopilot`
- **THEN** загрузка даёт проблему `permissions.mode`, а флаг `--permission-mode autopilot` того же запуска допустим

### Requirement: Доверие к проектному конфигу
Оба проектных слоя — `<cwd>/.codelab/config.yaml` и `<cwd>/.codelab/config.local.yaml` — SHALL подчиняться правилам доверия §15.3, пока проект не в `trusted_projects` (решение пользователя 2026-10-30). Проект доверенный, если его канонический корень есть в `trusted_projects` глобального слоя (`user` или `appStorage`). В `trusted_projects` SHALL допускаться только абсолютные пути (относительный — проблема). Относительный путь SHALL давать проблему `expected an absolute path` с ключом `trusted_projects[i]`; `~` SHALL раскрываться. `trusted_projects` в проектных слоях SHALL отбрасываться с предупреждением `config.project.untrusted_key` (`ignored: trusted_projects is read only from the global config`), а в слое `--config` — быть проблемой. Без доверия:
- `mcp.servers`, `providers.*`, `model_catalog.*`, `prompts.*` и разделы после MVP `hooks`, `plugins`, `a2a`, `lsp` SHALL отбрасываться с предупреждением `config.project.untrusted_key {key, source}`;
- раздел `secrets` SHALL отбрасываться из обоих проектных слоёв всегда, и с доверием тоже, с предупреждением `config.project.untrusted_key` (`ignored: secrets is read only from the global config`);
- `sessions.*`, `logging.*`, `exec.*` SHALL отбрасываться так же, а слоя `config.yaml` — и с доверием;
- `permissions.mode` проекта SHALL только ужесточать итоговый режим (`narrow`); смягчение SHALL отбрасываться с `config.project.untrusted_key`. Сочетание `ask` и `plan` в любом порядке SHALL давать режим `ask` с дополнительно запрещёнными уровнями `write` и `exec` (`PermissionsConfig` — поле дополнительно запрещённых уровней);
- `permissions.deny` проекта SHALL объединяться со списком нижних слоёв, а не заменять его;
- `permissions.tools.<t>` проекта SHALL применяться, только если не мягче значения нижних слоёв (`deny` > `ask` > `allow`; нет значения — как `allow`; равное применяется), иначе отбрасываться с `config.project.untrusted_key`;
- `budget.*` SHALL только уменьшаться;
- ключи `redact.*` SHALL подчиняться правилам §12.4.3.

Сравнение идёт с результатом слияния нижних слоёв. Отброшенный ключ НЕ SHALL быть ошибкой загрузки (CFG-3). Слои `--config`, окружение и флаги правилам доверия НЕ SHALL подчиняться.

#### Scenario: MCP-сервер и allow из недоверенного проекта
- **WHEN** `<cwd>/.codelab/config.yaml` объявляет `mcp.servers` и `permissions.tools.exec: allow`, а `trusted_projects` не содержит `<cwd>`
- **THEN** итог не содержит ни сервера, ни правила `allow`, а лог содержит два `config.project.untrusted_key`

#### Scenario: Локальный проектный слой без доверия
- **WHEN** `<cwd>/.codelab/config.local.yaml` объявляет `mcp.servers` и `prompts.system_text`, а проект не в `trusted_projects`
- **THEN** сервера и промпта в итоге нет, оба ключа — `config.project.untrusted_key`

#### Scenario: Тот же проект с доверием
- **WHEN** глобальный конфиг добавляет `<cwd>` в `trusted_projects`
- **THEN** сервер и правило `allow` из проектного слоя есть в итоге

#### Scenario: Ужесточение режима
- **WHEN** глобальный слой задаёт `permissions.mode: bypass`, а недоверенный проект — `ask`
- **THEN** итоговый режим — `ask`; если проект задаёт `bypass` поверх глобального `ask`, итог — `ask` и предупреждение `config.project.untrusted_key` для `permissions.mode`

#### Scenario: ask и plan
- **WHEN** глобальный слой задаёт `permissions.mode: ask`, а недоверенный проект — `plan`; во втором варианте глобальный — `plan`, проект — `ask`
- **THEN** в обоих вариантах режим — `ask`, дополнительно запрещённые уровни — `write` и `exec`: вызов `read` спрашивает, вызов `write` отклонён без вопроса

#### Scenario: Проект не снимает глобальные запреты
- **WHEN** глобальный слой задаёт `permissions.deny: ["exec:git push --force"]` и `permissions.tools.exec: deny`, а недоверенный проект — `permissions.deny: ["write:.env"]` и `permissions.tools.exec: allow`, `permissions.tools.read: ask`, а глобальный `permissions.tools.write: ask` проект повторяет как `ask`
- **THEN** итоговый `deny` содержит оба шаблона, `exec` — `deny` с предупреждением `config.project.untrusted_key` для `permissions.tools.exec`, `read` — `ask`, `write` — `ask` без предупреждения (равное значение применяется)

#### Scenario: trusted_projects не из глобального слоя
- **WHEN** проектный слой задаёт `trusted_projects: [<cwd>]`, а глобальный — `trusted_projects: [relative/path]`
- **THEN** проектный ключ отброшен с `config.project.untrusted_key` (`ignored: trusted_projects is read only from the global config`), проект не доверенный, а относительный путь глобального слоя — проблема `trusted_projects[0]: expected an absolute path`; `~/work/demo` раскрывается и проблемы не даёт

#### Scenario: secrets только из глобального конфига
- **WHEN** доверенный проект задаёт `secrets.backend: file` в `config.local.yaml`
- **THEN** ключ отброшен с `config.project.untrusted_key` и текстом `ignored: secrets is read only from the global config`

#### Scenario: Проект не увеличивает бюджет
- **WHEN** глобальный слой задаёт `budget.max_steps: 30`, а проект — `budget.max_steps: 100`
- **THEN** итог — `30` и одно предупреждение `config.project.untrusted_key` для `budget.max_steps`

### Requirement: Подстановка переменных окружения
Форма `${NAME}` (`NAME` — `[A-Za-z_][A-Za-z0-9_]*`) SHALL раскрываться только в `providers.*.base_url`, `providers.*.headers.*`, `mcp.servers[*].args[*]`, `mcp.servers[*].env.*`, `mcp.servers[*].url` и `mcp.servers[*].headers.*` (§15.5). В остальных ключах `${` SHALL быть литералом. `$${` SHALL давать литерал `${`, форма `$NAME` без скобок — литерал. Результат подстановки НЕ SHALL раскрываться повторно. Незаданная переменная SHALL быть проблемой с путём ключа и именем переменной, а не пустой строкой. Значение переменной НЕ SHALL попадать в сообщения и логи.

#### Scenario: Подстановка и литералы
- **WHEN** `mcp.servers[github].headers.Authorization` — `"Bearer ${GITHUB_TOKEN}"`, `args` содержит `"$${HOME}"` и `"$HOME"`, а `agent.default_model` — `"${X}/m"`
- **THEN** заголовок получает значение переменной, аргументы — литералы `${HOME}` и `$HOME`, а `${X}` в `agent.default_model` не раскрывается

#### Scenario: Незаданная переменная
- **WHEN** `GITHUB_TOKEN` не задана
- **THEN** проблема — `mcp.servers[github].headers.Authorization: variable GITHUB_TOKEN is not set`, сервер не построен

### Requirement: Секреты только ссылками
Конфигурация НЕ SHALL хранить ключи API значением (CFG-2). Ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` SHALL давать проблему `inlineSecret`; хост SHALL отказывать в старте исключением `ConfigInlineSecretException` с путём ключа. Текст проблемы НЕ SHALL содержать значение; у элемента `mcp.servers` текст SHALL подсказывать `use ${NAME} in env or headers`. `api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`); `api_key_secret` и имя в `${secret:<name>}` — непустым именем секрета до 128 символов без пробелов и управляющих символов (иначе `expected a secret name (no spaces or control characters)`; точный pattern — change `add-agent-secret-store`). Неверный формат — проблема с путём ключа без значения в тексте.

- `api_key_env` SHALL разрешаться из окружения при загрузке. Незаданная переменная SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса.
- До хранилища секретов (change `add-agent-secret-store`) `api_key_secret` и `${secret:<name>}` SHALL приниматься синтаксически:
  - провайдер с `api_key_secret` при выборе модели SHALL давать ошибку хода `API key secret <name> cannot be read: the secret store is not available yet` без HTTP-запроса;
  - MCP-сервер с `${secret:…}` SHALL пропускаться с предупреждением `config.secret.unavailable {key}`.

#### Scenario: Ключ значением
- **WHEN** `config.yaml` задаёт `providers.openai.api_key: sk-test-secret`
- **THEN** запуск отклонён с проблемой `providers.openai.api_key`, а stderr, лог и вывод `config check` не содержат `sk-test-secret`

#### Scenario: Ключ вместо имени переменной
- **WHEN** провайдер задаёт `api_key_env: sk-test-secret-123`
- **THEN** проблема `providers.<id>.api_key_env` о формате имени, текст и лог не содержат `sk-test-secret-123`

#### Scenario: Переменная ключа не задана
- **WHEN** провайдер `openai` задаёт `api_key_env: OPENAI_API_KEY`, переменная не задана, а сессия выбирает модель `openai/gpt-4o`
- **THEN** загрузка успешна с предупреждением `config.provider.key_missing`, а ход завершается ошибкой `API key variable OPENAI_API_KEY is not set` без запроса к провайдеру

#### Scenario: Секрет до хранилища секретов
- **WHEN** провайдер задаёт `api_key_secret: codelab/anthropic`, а сервер `gh` — заголовок `${secret:codelab/mcp/gh/authorization}`
- **THEN** выбор модели провайдера даёт ошибку о недоступном хранилище секретов, сервер `gh` пропущен с `config.secret.unavailable`, остальная конфигурация работает

### Requirement: MCP-серверы конфигурации
Элементы `mcp.servers` SHALL отображаться в `CoreConfig.mcpServers` с `origin: config`:
- `type: stdio` → `McpStdioServerConfig {command, args, env}`;
- `type: http` → `McpHttpServerConfig {url, headers}` с порядком заголовков файла.

Другой `type` SHALL быть проблемой `only stdio and http are supported`. `url` без схемы `http`/`https` SHALL быть проблемой. `connect_timeout` (по умолчанию `10s`) SHALL задавать `connectTimeout`. Новый ключ `call_timeout` (тип `duration`, по умолчанию `10m`, допустимо `1s..24h`) SHALL задавать `McpServerConfig.callTimeout`. Сервер с `enabled: false` НЕ SHALL попадать в `CoreConfig.mcpServers` и SHALL давать лог `mcp.server.skipped {server, reason: "disabled in config"}`. Значения `env` и `headers` НЕ SHALL попадать в логи, журнал сессии и строковое представление.

#### Scenario: Сервер конфига в сессии
- **WHEN** глобальный `config.yaml` объявляет stdio-сервер `fake`, а клиент создаёт сессию без `mcpServers`
- **THEN** модель видит `mcp__fake__echo` с первого хода, а после закрытия сессии процесс сервера завершён

#### Scenario: Сервер клиента вытесняет сервер конфига
- **WHEN** конфиг объявляет `github` (http), а `session/new.mcpServers` — `github` (stdio)
- **THEN** подключается только сервер клиента, сервер конфига пропущен с `mcp.server.skipped` и причиной `replaced by a server of the client with the same name`

#### Scenario: Таймаут вызова из конфига
- **WHEN** сервер конфига задаёт `call_timeout: 2s`, а его инструмент не отвечает
- **THEN** через 2 с серверу уходит сигнал отмены, а результат вызова — ошибка `MCP server <id> did not answer tools/call within 2 s.`

#### Scenario: Неподдерживаемый тип в конфиге
- **WHEN** элемент `mcp.servers` задаёт `type: sse`
- **THEN** загрузка даёт проблему `mcp.servers[<name>].type: only stdio and http are supported`

### Requirement: Ключи редакции секретов
Ключи `redact.enabled`, `redact.layers`, `redact.allowlist.builtin`, `redact.allowlist.patterns` и `redact.exempt_tools` SHALL читаться и проверяться (§12.4.3):
- имя слоя вне `exact`, `credential_files`, `formats`, `pem`, `connection_strings`, `key_values`, `entropy` — проблема;
- запись `builtin` вне `git_sha`, `uuid` — проблема;
- некомпилируемое регулярное выражение в `allowlist.patterns` — проблема с путём ключа.

Проверенные значения SHALL попадать в `CoreConfig.redact`. Правила доверия проектного слоя SHALL соблюдаться: без доверия проект может только включить редакцию, добавить слои и убрать записи `allowlist`. До редактора задачи 8.11 явно заданный ключ `redact.*` SHALL давать `config.key.not_applied`.

#### Scenario: Невалидное выражение
- **WHEN** `redact.allowlist.patterns` содержит `"[a-"`
- **THEN** проблема называет ключ `redact.allowlist.patterns[0]`, `CoreConfig` не построен

#### Scenario: Проект выключает редакцию без доверия
- **WHEN** недоверенный проект задаёт `redact.enabled: false` и новый `allowlist.patterns`
- **THEN** оба ключа отброшены с `config.project.untrusted_key`, `CoreConfig.redact.enabled` — `true`

### Requirement: Найденный codelab.toml не читается
Агент НЕ SHALL читать, разбирать и переводить `codelab.toml` Python-агента (решение пользователя 2026-10-29; design.md, D12). Если нет ни одного YAML-файла слоёв 2–4 и не задан `--config`, а хотя бы один из файлов `$CODELAB_HOME/codelab.toml`, `$CODELAB_HOME/auth.toml`, `<cwd>/codelab.toml`, `<cwd>/codelab.local.toml` существует, загрузчик SHALL выдать ровно одно предупреждение `config.legacy_found {files}` на процесс и `cwd`. Текст — на английском: файл не используется Dart-агентом, настройки переносятся в `config.yaml` вручную, таблица соответствия ключей — `docs/architecture/proposals/agent-core/15-configuration.md`, раздел 15.7. Проверяется только существование файлов; содержимое и размер НЕ SHALL попадать в лог. При любом YAML-файле слоёв 2–4 или при `--config` предупреждения НЕ SHALL быть. `codelab.toml.example` не ищется.

Ключ `agents.definitions` в YAML SHALL быть проблемой с подсказкой перенести определение в `.codelab/agents/<name>.md` (DF-12). Неизвестное значение `providers.<id>.kind` SHALL быть проблемой со списком известных видов, без подмены mock-провайдером (DF-15).

#### Scenario: Только codelab.toml
- **WHEN** в `<cwd>` есть `codelab.toml` с синтаксической ошибкой TOML, а `config.yaml` нет ни в одном слое
- **THEN** загрузка не даёт проблем из этого файла, лог содержит ровно одно `config.legacy_found` с путём `<cwd>/codelab.toml` и ссылкой на раздел 15.7, без содержимого файла (`config_legacy_found_test.dart`)

#### Scenario: codelab.toml рядом с config.yaml
- **WHEN** есть `$CODELAB_HOME/config.yaml` и `<cwd>/codelab.toml`
- **THEN** действует только YAML, предупреждения `config.legacy_found` нет

#### Scenario: Определения агентов в YAML
- **WHEN** `config.yaml` содержит `agents.definitions.reviewer`
- **THEN** проблема называет ключ и подсказывает `.codelab/agents/reviewer.md` (`core/config-rejects-yaml-agent-definitions`)

#### Scenario: Неизвестный вид провайдера
- **WHEN** `config.yaml` задаёт `providers.foo.kind: mock`
- **THEN** проблема `providers.foo.kind` перечисляет `openai-compatible`, `anthropic`, `gemini`; агент не стартует (`core/config-unknown-provider-error`)

### Requirement: Подкоманда config check
`codelab-agent config check [--cwd <dir>]` и `codelab config check [--cwd <dir>]` SHALL выполнять полную загрузку для `cwd` без запуска агента и печатать в stdout:
- строку `Sources:` со слоями по порядку;
- каждую проблему в форме `<source>:<line>:<column>: <key>: <message>` (без строки и столбца, если их нет);
- каждое предупреждение, включая `config.legacy_found`;
- последней строкой — `Config: valid` или `Config: invalid (issues: <n>)`.

Код выхода SHALL быть `0` при валидном конфиге, `1` при проблемах, `64` при ошибке использования. Подкоманда НЕ SHALL писать файлы и печатать значения секретов. Обе подкоманды SHALL использовать одну реализацию `ConfigCommands` из `codelab_agent_io`.

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, содержит одну опечатку ключа, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку проблемы с файлом, строкой, столбцом и подсказкой, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: Одинаковый вывод у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются с одним `CODELAB_HOME` и `cwd`
- **THEN** их stdout и коды выхода совпадают

### Requirement: Наблюдаемость загрузки конфигурации
Успешная загрузка SHALL писать `host.config.loaded {sources, warnings, project_root}`. Каждое предупреждение загрузки SHALL писаться отдельным событием своего имени (`config.env.unknown`, `config.project.untrusted_key`, `config.key.not_applied`, `config.provider.key_missing`, `config.secret.unavailable`, `config.file.ignored`, `config.legacy_found`). Значения ключей конфигурации, переменных и секретов НЕ SHALL попадать в эти события и в текст проблем: только пути ключей, имена переменных и секретов, источники.

#### Scenario: Ни одного значения в логе
- **WHEN** конфиг содержит `headers.Authorization: "Bearer ${TOKEN}"` с `TOKEN=tok-test-secret` и ключ без потребителя, а агент стартует с `--log-level trace`
- **THEN** лог содержит `host.config.loaded` и `config.key.not_applied`, но не содержит `tok-test-secret`
