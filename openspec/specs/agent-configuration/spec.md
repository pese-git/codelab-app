# agent-configuration Specification

## Purpose
Конфигурация Dart-агента: ядро `codelab_agent_core` собирает `CoreConfig` из слоёв без IO и возвращает проблемы как `ConfigIssue` с файлом, строкой, столбцом и путём ключа, а `codelab_agent_io` читает YAML строгого профиля и окружение `CODELAB_*`. Слои по возрастанию приоритета: умолчания < `~/.codelab/config.yaml` < `<cwd>/.codelab/config.yaml` < `config.local.yaml` < `--config`/`CODELAB_CONFIG` < `CODELAB_*` < флаги. Недоверенный проект может только ужесточать правила (CFG-3), секреты указываются только ссылками (CFG-2), `codelab.toml` не читается — о нём одно предупреждение `config.legacy_found`. Подкоманда `config check` в `codelab-agent` и `codelab` (через мост `codelab_setup`) печатает одинаковый результат проверки. Решения и обоснования — `design.md` архивного change `add-agent-configuration` (D1–D17) и `agent-core-architecture` §15.
## Requirements
### Requirement: Слои конфигурации и их порядок
Загрузчик `ConfigLoader` (`codelab_agent_io`) SHALL собирать конфигурацию агента из слоёв, от низшего приоритета к высшему (`agent-core-architecture` §15.2, §15.6):
1. встроенные умолчания;
2. `$CODELAB_HOME/config.yaml` (`CODELAB_HOME` по умолчанию `~/.codelab`);
3. `<cwd>/.codelab/config.yaml`;
4. `<cwd>/.codelab/config.local.yaml`;
5. файл `--config <path>` или `CODELAB_CONFIG` с расширением `.yaml` или `.yml`;
6. переменные `CODELAB_*`;
7. флаги командной строки.

Отсутствующий файл слоёв 2–4 SHALL пропускаться. Файл слоя 5, явно названный через `--config` или `CODELAB_CONFIG`, но отсутствующий или нечитаемый, SHALL давать проблему `ConfigIssue` вида `syntax` с ключом `""`, текстом, начинающимся с `cannot read the file`, и источником `--config` или `CODELAB_CONFIG` (решение пользователя 2026-10-30): опечатка в явно названном пути не должна молча запускать агента без этого файла. `CODELAB_CONFIG` SHALL быть абсолютным путём; относительный путь хост SHALL отклонять ошибкой использования до загрузки (требование agent-binary): относительный путь считался бы от корня проекта, а слой 5 правилам доверия не подчиняется, и склонированный репозиторий обошёл бы CFG-3. `--config` МОЖЕТ быть относительным и разрешается от текущего каталога процесса. Отображения SHALL сливаться по ключам рекурсивно, скаляры и списки — заменяться целиком. Список `mcp.servers` SHALL сливаться по `name`: тот же `name` заменяет сервер, новый добавляется в конец, `enabled: false` в более приоритетном слое выключает сервер. `tools.disabled` слоёв 2–4 SHALL объединяться. `--config` с расширением `.toml` SHALL быть ошибкой использования: `codelab.toml` не поддерживается. Файл `config.yml` рядом с `config.yaml` или вместо него SHALL не читаться и давать предупреждение `config.file.ignored`. При запуске со сценарием `--llm-script` слои 2–4 SHALL не читаться.

#### Scenario: Проектный слой перекрывает глобальный
- **WHEN** `$CODELAB_HOME/config.yaml` задаёт `budget.max_steps: 50`, а `<cwd>/.codelab/config.yaml` — `budget.max_steps: 20`
- **THEN** итоговый `CoreConfig.budget.maxSteps` равен `20`

#### Scenario: Флаг сильнее переменной и файлов
- **WHEN** `config.local.yaml` задаёт `budget.max_steps: 30`, окружение — `CODELAB_MAX_STEPS=40`, а запуск — `--max-steps 10`
- **THEN** итоговое значение `10`, а `sources` результата перечисляет слои по порядку

#### Scenario: Серверы сливаются по имени
- **WHEN** глобальный слой объявляет серверы `github` и `files`, а локальный проектный — `github` с другим `url` и `files` с `enabled: false`
- **THEN** итог содержит один `github` с адресом локального слоя и не содержит `files`

#### Scenario: Явно названный файл отсутствует
- **WHEN** загрузчик вызывается с `--config <tmp>/missing.yaml`, а файла нет; во втором варианте — с `CODELAB_CONFIG=<tmp>/missing.yaml`
- **THEN** результат содержит проблему вида `syntax` с текстом `cannot read the file…` и источником `--config` (во втором варианте — `CODELAB_CONFIG`), `CoreConfig` не построен; отсутствие `$CODELAB_HOME/config.yaml` и `<cwd>/.codelab/*` проблем не даёт

#### Scenario: Сценарий не читает файлы пользователя
- **WHEN** загрузчик вызывается со сценарием `--llm-script` и `CODELAB_HOME=<tmp>`, где есть `config.yaml` с ошибкой
- **THEN** загрузка успешна, файл не прочитан, каталог `<tmp>` не изменён

### Requirement: Строгий профиль YAML
Файлы конфигурации SHALL разбираться `package:yaml` в `codelab_agent_io` в строгом профиле YAML 1.2 (§15.5, CFG-21). Каждое нарушение SHALL давать `ConfigIssue` с файлом, строкой и столбцом узла:
- второй документ — `multiple YAML documents are not supported`;
- якорь, алиас, ключ слияния `<<`, явный тег — `anchors, aliases, merge keys and tags are not supported`;
- ключ не строка (`1:`, `null`, `true`, составной) — ошибка;
- повторяющийся ключ — ошибка с позициями обоих ключей;
- нестандартный тег (`!foo`, `!e!x` с необъявленным префиксом) — та же проблема профиля, а не синтаксическая ошибка разборщика; текст НЕ SHALL содержать имя тега;
- якорь или тег на корневом узле документа — та же проблема профиля, а не пропуск проверки.

Пределы разбора (ревью безопасности итерации 2, 2026-10-30) SHALL проверяться до построения дерева и не приводить к исключению или переполнению стека:
- файл больше 1 MiB (1 048 576 байт) SHALL давать `ConfigIssue` вида `syntax` с ключом `""`, текст называет предел; файл не разбирается;
- вложенность отображений и списков глубже 64 уровней SHALL давать `ConfigIssue` вида `profile` с позицией узла, на котором предел превышен; `StackOverflowError` НЕ SHALL возникать.

Пустой файл и файл только из комментариев SHALL давать пустой слой. Блочный и flow-стиль, переводы строк LF и CRLF и BOM SHALL читаться одинаково. Ядро НЕ SHALL импортировать `package:yaml`, `package:yaml_edit` и `package:toml` (CFG-5).

#### Scenario: Таблица нарушений профиля
- **WHEN** `config_yaml_profile_test.dart` разбирает файлы с якорем и ссылкой, `<<: *base`, тегом `!!str`, вторым документом, ключом `1:`, составным ключом и повторяющимся ключом
- **THEN** каждый даёт `ConfigIssue` вида `profile` со строкой и столбцом, а повторяющийся ключ называет позиции обоих

#### Scenario: Пределы и нестандартные теги
- **WHEN** разбираются файл размером 1 MiB + 1 байт, файл с вложенностью 65 уровней (и с 10 000 уровней flow-списков `[[[…]]]`), файл со значением `!secret-tag x` и файл, корень которого — `&root` или `!!map`
- **THEN** первый — проблема `syntax` без разбора, второй — проблема `profile` без исключения и без `StackOverflowError`, третий — проблема `profile`, текст которой не содержит `secret-tag`, четвёртый — проблема `profile` с позицией корня

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
Оба проектных слоя — `<cwd>/.codelab/config.yaml` и `<cwd>/.codelab/config.local.yaml` — SHALL подчиняться правилам доверия §15.3, пока проект не в `trusted_projects` (решение пользователя 2026-10-30). Проект доверенный, если его канонический корень есть в `trusted_projects` глобального слоя (`user` или `appStorage`). Загрузчик (`codelab_agent_io`) SHALL канонизировать корень проекта и каждый элемент `trusted_projects` (раскрыть `~`, `.`/`..` и symlink; несуществующий путь — нормализация без раскрытия symlink) до сравнения: иначе `trusted_projects: [/work/link]` для проекта `/work/real` (или наоборот) давал бы разный ответ в зависимости от записи пути. В `trusted_projects` SHALL допускаться только абсолютные пути (относительный — проблема). Относительный путь SHALL давать проблему `expected an absolute path` с ключом `trusted_projects[i]`; `~` SHALL раскрываться. `trusted_projects` в проектных слоях SHALL отбрасываться с предупреждением `config.project.untrusted_key` (`ignored: trusted_projects is read only from the global config`), а в слое `--config` — быть проблемой. Без доверия:
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

#### Scenario: Доверие через symlink
- **WHEN** `/tmp/link` — symlink на каталог проекта `/tmp/real`, глобальный слой задаёт `trusted_projects: [/tmp/link]`, а загрузка идёт для `cwd: /tmp/real` (во втором варианте — `trusted_projects: [/tmp/real]` и `cwd: /tmp/link`)
- **THEN** в обоих вариантах проект доверенный, `project_root` результата — `/tmp/real`

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
Конфигурация НЕ SHALL хранить ключи API значением (CFG-2). Ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` SHALL давать проблему `inlineSecret`; хост SHALL отказывать в старте исключением `ConfigInlineSecretException` с путём ключа и `suggestedSecretName` — именем `SecretNames.suggestFor(путь)` (capability `agent-secrets`, «Имена секретов»). Текст проблемы НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>`:
- у провайдера — и ссылку `api_key_secret: <suggestedSecretName>`;
- у элемента `mcp.servers` — и подстановку `${secret:<suggestedSecretName>}` в `env` или `headers`.

`api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`). Значение `api_key_secret` и имя в `${secret:<name>}` SHALL проходить правило `SecretNames` (иначе `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`). Неверный формат — проблема `value` с путём ключа без значения в тексте. Проверка литералов по шаблонам §12.4 (пункты 2–3 CFG-9) — change `add-agent-core-secret-redaction`.

- `api_key_env` незаданной переменной SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса. Значение переменной SHALL читаться при запросе через `SecretResolver.env`.
- `api_key_secret` и `${secret:<name>}` в `providers.*.headers.*`, `mcp.servers[*].env.*` и `mcp.servers[*].headers.*` SHALL разрешаться через `SecretResolver`: у провайдера — при запросе, у MCP-сервера — при подключении к сессии (capability `agent-secrets`, требования «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»). Загрузка НЕ SHALL читать хранилище секретов и НЕ SHALL пропускать MCP-сервер из-за ссылки на секрет.
- `${secret:…}` вне значений `env` и `headers` — в `mcp.servers[*].args[*]`, `mcp.servers[*].url` и `providers.*.base_url`, где `${ENV}` допустим, — SHALL давать проблему `value` с путём ключа и текстом `secret references ${secret:…} are allowed only in env and headers values`; конфиг невалиден. Ссылка там НЕ SHALL раскрываться и НЕ SHALL оставаться литералом: argv виден через `ps`, а URL попадает в логи и тексты ошибок (fail closed; design.md, D4).
- Ключ `secrets.backend` SHALL принимать `auto`, `keychain`, `env`, `file` (capability `agent-secrets`, «Выбор бэкенда secrets.backend»); он больше не даёт `config.key.not_applied`. `keychain` и незнакомое значение SHALL давать проблему `value` ядра. `file` на Windows SHALL давать проблему `value` от `ConfigLoader` (ядро платформу не знает) с источником и позицией слоя, где задан ключ, и текстом общей проверки `secretsBackendProblem`: `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`. Загрузка со `scripted` (`--llm-script`) эту проверку не выполняет: сценарий всегда использует `env` (design.md, D7, D11, D14).

#### Scenario: file на Windows при загрузке
- **WHEN** `ConfigLoader.load` с подменённой платформой `windows` читает пользовательский `config.yaml` с `secrets.backend: file`
- **THEN** результат без `config` и `host`, проблема `value` с ключом `secrets.backend`, источником этого файла и строкой ключа `backend`, `toString()` содержит `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; `auto` и `env` на Windows проблем не дают

#### Scenario: Ключ значением
- **WHEN** `config.yaml` задаёт `providers.openai.api_key: sk-test-secret`
- **THEN** запуск отклонён с проблемой `providers.openai.api_key`, текст содержит `codelab secret set codelab/openai` и `api_key_secret: codelab/openai`, у исключения `suggestedSecretName == "codelab/openai"`, а stderr, лог и вывод `config check` не содержат `sk-test-secret` (`core/config-rejects-inline-api-key`)

#### Scenario: Токен значением у MCP-сервера
- **WHEN** элемент `mcp.servers` с `name: github` задаёт `token: ghp-test-secret`
- **THEN** проблема `mcp.servers[github].token`, текст содержит `codelab secret set codelab/mcp/github/token` и `${secret:codelab/mcp/github/token}` и не содержит `ghp-test-secret`

#### Scenario: Ключ вместо имени переменной
- **WHEN** провайдер задаёт `api_key_env: sk-test-secret-123`
- **THEN** проблема `providers.<id>.api_key_env` о формате имени, текст и лог не содержат `sk-test-secret-123`

#### Scenario: Ключ вместо имени секрета
- **WHEN** провайдер задаёт `api_key_secret: "sk-Test Secret"`
- **THEN** проблема `providers.<id>.api_key_secret` с текстом правила имени, текст и лог не содержат значения

#### Scenario: Ссылка на секрет в args MCP-сервера
- **WHEN** stdio-сервер `gh` задаёт `args: ["--token", "${secret:codelab/mcp/gh/token}"]`
- **THEN** проблема `value` `mcp.servers[gh].args[1]: secret references ${secret:…} are allowed only in env and headers values`, конфиг невалиден, хранилище не вызывалось

#### Scenario: Ссылка на секрет в base_url провайдера
- **WHEN** провайдер `gw` задаёт `base_url: "https://llm.internal/${secret:codelab/gw}/v1"`
- **THEN** проблема `value` `providers.gw.base_url: secret references ${secret:…} are allowed only in env and headers values`, конфиг невалиден, хранилище не вызывалось

#### Scenario: Переменная ключа не задана
- **WHEN** провайдер `openai` задаёт `api_key_env: OPENAI_API_KEY`, переменная не задана, а сессия выбирает модель `openai/gpt-4o`
- **THEN** загрузка успешна с предупреждением `config.provider.key_missing`, а ход завершается ошибкой `API key variable OPENAI_API_KEY is not set` без запроса к провайдеру

#### Scenario: Ссылки на секреты не читаются при загрузке
- **WHEN** провайдер задаёт `api_key_secret: codelab/anthropic`, а сервер `gh` — заголовок `${secret:codelab/mcp/gh/authorization}`; загрузка идёт с хранилищем, которое считает вызовы
- **THEN** загрузка успешна без предупреждений о секретах, хранилище не вызывалось, `CoreConfig.mcpServers` содержит `gh`, `providerProblems` не содержит `anthropic`

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
`codelab-agent config check [--cwd <dir>]` и `codelab config check [--cwd <dir>]` SHALL выполнять полную загрузку для `cwd` (по умолчанию — текущий каталог процесса) без запуска агента. Загрузка SHALL учитывать окружение процесса целиком, включая `CODELAB_CONFIG` и прочие `CODELAB_*`; флагов `serve` (`--config`, `--provider`, `--model` и других) у подкоманды нет: проверяется то, что увидит `serve` без флагов. Вывод в stdout по строкам:
- первая строка — `Sources: <источники через ", ">`, где источники — `ConfigLoadResult.sources` как есть, по порядку слоёв: `defaults`, затем канонические абсолютные пути прочитанных файлов, затем `env`, если есть переменные-ключи (например `Sources: defaults, /home/u/.codelab/config.yaml, /work/demo/.codelab/config.yaml`);
- каждая проблема — строка `ConfigIssue.toString()`: `<location>: <key>: <message>`, без `<key>: `, если ключ пустой; `<location>` — `<source>:<line>:<column>` или `<source>`, если позиции нет; подсказка (`did you mean max_steps?`) — часть `<message>`;
- каждое предупреждение — строка `warning: <location>: [<key>: ]<message>` в той же форме, включая `config.legacy_found` и `config.env.unknown`. Текст `config.legacy_found` НЕ SHALL повторять путь, уже стоящий в `<location>`. Неизвестные `CODELAB_*` SHALL распознаваться в `ConfigLoader` (`codelab_agent_io`), а не в каждом бинаре: правило одно для `serve` и обеих подкоманд. `CODELAB_TEST_SECRET_STORE` SHALL считаться известной только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`; в обычной сборке она SHALL давать `config.env.unknown`, как любая неизвестная `CODELAB_*`, и НЕ SHALL читаться (agent-core §15.6);
- последняя строка — `Config: valid` или `Config: invalid (issues: <n>)`, где `<n>` — число проблем; предупреждения проблемами не считаются.

Код выхода SHALL быть `0` при валидном конфиге (с предупреждениями тоже), `1` при проблемах, `64` при ошибке использования. Ошибка использования — несуществующий каталог `--cwd` и `ConfigUsageException` загрузчика (`CODELAB_CONFIG` с расширением `.toml` или относительный): текст ошибки идёт в stderr, stdout SHALL быть пустым. Подкоманда НЕ SHALL писать файлы и печатать значения секретов. Обе подкоманды SHALL использовать одну реализацию `ConfigCommands` из `codelab_agent_io`.

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, содержит одну опечатку ключа, а `config check` запускается в этом `cwd`
- **THEN** первая строка stdout начинается с `Sources: defaults, ` и называет канонический абсолютный путь `config.yaml`, строка проблемы содержит файл, строку, столбец, путь ключа и подсказку `did you mean …?`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: Предупреждения не делают конфиг невалидным
- **WHEN** `config.yaml` валиден, окружение содержит неизвестную переменную `CODELAB_UNKNOWN_X=1`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_UNKNOWN_X`, но не её значение; последняя строка `Config: valid`, код `0`

#### Scenario: Подсказка о codelab.toml
- **WHEN** `CODELAB_HOME` пуст, в `cwd` есть только `codelab.toml`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: <cwd>/codelab.toml: codelab.toml is not used by the Dart agent…`, в тексте после локации путь `<cwd>/codelab.toml` не повторяется; единственная проблема — `agent.default_model: required`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: CODELAB_CONFIG учитывается
- **WHEN** `CODELAB_CONFIG=<tmp>/extra.yaml` (абсолютный путь), файл содержит неизвестный ключ, а `config check` запускается без флагов
- **THEN** строка `Sources:` содержит `<tmp>/extra.yaml`, stdout содержит проблему этого файла, код `1`

#### Scenario: Несуществующий каталог
- **WHEN** запускается `config check --cwd <tmp>/missing`, а каталога нет
- **THEN** код `64`, stderr называет каталог, stdout пуст

#### Scenario: Ошибка использования из окружения
- **WHEN** `CODELAB_CONFIG` равна `<tmp>/c.toml` или относительному пути `.codelab/extra.yaml`
- **THEN** код `64`, stderr содержит текст `ConfigUsageException` с именем `CODELAB_CONFIG`, stdout пуст, файл не читается

#### Scenario: Одинаковый вывод у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются с одним окружением и `cwd`
- **THEN** их stdout и коды выхода совпадают

#### Scenario: Тестовое хранилище в обычной сборке
- **WHEN** агент собран без `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`, `config.yaml` валиден, окружение содержит `CODELAB_TEST_SECRET_STORE=<tmp>/test-secrets`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_TEST_SECRET_STORE`, но не её значение; каталог `<tmp>/test-secrets` не читается и не создаётся; последняя строка `Config: valid`, код `0`

### Requirement: Наблюдаемость загрузки конфигурации
Успешная загрузка SHALL писать `host.config.loaded {sources, warnings, project_root, transport, models}` (`transport` — `stdio` или `ws`, `models` — id моделей каталога). Каждое предупреждение загрузки SHALL писаться отдельным событием своего имени (`config.env.unknown`, `config.project.untrusted_key`, `config.key.not_applied`, `config.provider.key_missing`, `config.file.ignored`, `config.legacy_found`, `mcp.server.skipped`) и SHALL нести поле `message` — английский текст `ConfigIssue.message` без значений. Событие `config.secret.unavailable` НЕ SHALL писаться: ссылки на секреты разрешаются при запросе и подключении (requirement «Секреты только ссылками»). Значения ключей конфигурации, переменных и секретов НЕ SHALL попадать в эти события и в текст проблем: только пути ключей, имена переменных и секретов, источники.

#### Scenario: Ни одного значения в логе
- **WHEN** конфиг содержит `headers.Authorization: "Bearer ${TOKEN}"` с `TOKEN=tok-test-secret` и ключ без потребителя, а агент стартует с `--log-level trace`
- **THEN** лог содержит `host.config.loaded` с полями `transport` и `models` и `config.key.not_applied` с полями `key`, `source`, `message`, но не содержит `tok-test-secret`

#### Scenario: Нет предупреждения о недоступном хранилище
- **WHEN** конфиг содержит `api_key_secret` и `${secret:…}` в MCP-сервере
- **THEN** лог загрузки не содержит `config.secret.unavailable`

### Requirement: Корень состояния CODELAB_HOME
Корень глобального состояния агента — `CODELAB_HOME`, по умолчанию `~/.codelab` (`agent-core-architecture` §15.6). Его SHALL вычислять одна функция `codelabHomeOf` (`codelab_agent_io`) для всех потребителей: слоя 2 (`$CODELAB_HOME/config.yaml`), поиска `codelab.toml`, пользовательской области файлов проекта (`prompts/`, `agents/`) и журналов сессий хоста (design.md change `add-agent-project-files`, D17; решение пользователя 2026-10-30). Значение `CODELAB_HOME`, равное `~` или начинающееся с `~/`, SHALL раскрываться: `~` заменяется домашним каталогом — `HOME`, а если он не задан или пуст, `USERPROFILE`. Почему: тильду раскрывает оболочка, а в unit launchd/systemd, в `env` профиля и внутри кавычек она приходит буквально, и `~/x` молча указывал бы на каталог `./~/x` относительно текущего каталога процесса. Раскрытие SHALL совпадать с раскрытием `~` в `trusted_projects` (требование «Доверие к проектному конфигу»). Любое другое значение, начинающееся с `~` (`~user/…`, а также `~\…` на Windows — его, как и `trusted_projects`, агент не раскрывает), SHALL быть ошибкой использования (`ConfigUsageException`) с текстом `CODELAB_HOME: ~user is not supported, use an absolute path`. Значение `~` или `~/…` при неизвестном домашнем каталоге (`HOME` и `USERPROFILE` не заданы или пусты) SHALL быть ошибкой использования с текстом `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`. Ошибка возникает до чтения файлов: `serve` и `config check` печатают текст в stderr и завершаются с кодом `64`; относительный каталог `./~…` не создаётся и не читается. Пустой `CODELAB_HOME` SHALL считаться незаданным; умолчание без `CODELAB_HOME` не меняется. При запуске со сценарием `--llm-script` `$CODELAB_HOME` не читается (требование agent-binary «Конфиг бинаря…»; D16), поэтому `CODELAB_HOME` в этом режиме НЕ SHALL раскрываться и проверяться: неверное значение не даёт кода `64`.

#### Scenario: Тильда раскрывается в HOME
- **WHEN** загрузчик вызывается с `CODELAB_HOME='~/cl'` (буквально, без раскрытия оболочкой) и `HOME=<tmp>`, а `<tmp>/cl/config.yaml` задаёт `budget.max_steps: 50`
- **THEN** слой 2 прочитан из `<tmp>/cl/config.yaml` (источник в `config check` — этот путь), итоговое значение `50`; каталог `<cwd>/~` не создаётся и не читается

#### Scenario: Пользовательская область файлов проекта
- **WHEN** `serve --stdio` или `config check` запускается с `CODELAB_HOME='~/cl'`, `HOME=<tmp>`, а в `<tmp>/cl/prompts/` лежит шаблон `review.md`
- **THEN** шаблон загружен из `<tmp>/cl/prompts/review.md` (команда `/review` опубликована, `config check` не печатает `project files could not be read`)

#### Scenario: Windows и USERPROFILE
- **WHEN** `CODELAB_HOME='~/cl'`, `HOME` не задан, `USERPROFILE=<dir>`
- **THEN** корень состояния — `<dir>/cl`

#### Scenario: ~user — ошибка использования
- **WHEN** `codelab-agent serve --stdio` или `codelab-agent config check` запускается с `CODELAB_HOME='~bob/cl'` и `HOME=<tmp>`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: ~user is not supported, use an absolute path`; каталог `<cwd>/~bob` не создаётся

#### Scenario: Тильда без домашнего каталога
- **WHEN** `codelab-agent config check` запускается с `CODELAB_HOME='~/cl'`, а `HOME` и `USERPROFILE` не заданы или пусты
- **THEN** код `64`, stderr содержит `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`

#### Scenario: Сценарий --llm-script не проверяет CODELAB_HOME
- **WHEN** `codelab-agent serve --stdio --llm-script <file.json>` запускается с `CODELAB_HOME='~bob/cl'` (или `CODELAB_HOME='~/cl'` без `HOME` и `USERPROFILE`)
- **THEN** бинарь запускается и проводит ход сценария, ошибки использования и кода `64` нет; каталог `~bob` не создаётся и не читается

#### Scenario: Абсолютное значение не меняется
- **WHEN** `CODELAB_HOME=/srv/cl`
- **THEN** корень состояния — `/srv/cl`

### Requirement: Ключ tools.project_context.max_bytes
Ключ `tools.project_context.max_bytes` SHALL применяться: целое `0..262144`, по умолчанию `32768`; `0` выключает чтение контекста проекта (design.md change `add-agent-project-files`, D5). Значение вне диапазона SHALL быть проблемой конфига с путём ключа. В проектных слоях недоверенного проекта значение SHALL приниматься только на уменьшение относительно результата слияния нижних слоёв; увеличение SHALL отбрасываться с предупреждением `config.project.untrusted_key`. Ключ НЕ SHALL давать `config.key.not_applied`.

#### Scenario: Увеличение из недоверенного проекта
- **WHEN** глобальный конфиг не задаёт ключ, а `.codelab/config.yaml` недоверенного проекта задаёт `tools.project_context.max_bytes: 200000`
- **THEN** итоговое значение `32768`, предупреждение `config.project.untrusted_key` с ключом `tools.project_context.max_bytes`

#### Scenario: Уменьшение из проекта
- **WHEN** недоверенный проект задаёт `tools.project_context.max_bytes: 4096`
- **THEN** итоговое значение `4096`, предупреждения нет

### Requirement: Доверенные проекты в CoreConfig
`CoreConfig` SHALL содержать `trustedProjects` — канонические абсолютные корни из `trusted_projects` глобального слоя (после раскрытия `~` и symlink в `ConfigLoader`); снимок `withoutProject` SHALL содержать тот же список. Проектные слои список не меняют (CFG-3).

#### Scenario: Список доступен сессии вне корня
- **WHEN** глобальный конфиг доверяет `/work/a` и `/work/b`, а проектные слои прочитаны для `/work/a`
- **THEN** `config.trustedProjects` и `config.withoutProject.trustedProjects` равны `[/work/a, /work/b]`

### Requirement: config check показывает диагностику файлов проекта
`ConfigCommands.check` SHALL после валидной загрузки конфига загружать файлы проекта для канонического `--cwd` (та же форма, что у runtime: `LocalExecutionEnv.realpath`) тем же `ProjectFilesLoader` с доверием и каталогом моделей загруженного конфига и печатать перед последней строкой (design.md, D13):
- каждую диагностику уровня `error` или `warning` — строкой `warning: <path>[:<line>[:<column>]]: <message>`;
- диагностику `untrusted_project` — строкой `note: <каталог>: the project is not trusted; add it to trusted_projects`, по строке на каталог (`.codelab/prompts`, `.codelab/agents`).

Прочие диагностики уровня `info` НЕ SHALL печататься. Сообщения SHALL быть фиксированными текстами кодов (D3, D10); имя ключа или фрагмент файла в сообщение НЕ SHALL попадать. Непредвиденное исключение загрузчика SHALL давать одну строку `warning: <cwd>: project files could not be read: <runtimeType>`; загрузка дольше 5 с (D6) SHALL прерываться строкой `warning: <cwd>: project files were not read within 5 s`. Диагностики, заметки, сбой и таймаут НЕ SHALL считаться проблемами: последняя строка и код выхода определяются только конфигом. При невалидном конфиге файлы проекта НЕ SHALL проверяться. Вывод SHALL совпадать у `codelab-agent config check` и `codelab config check`.

#### Scenario: Битое определение агента
- **WHEN** конфиг валиден, проект доверенный, а `.codelab/agents/reviewer.md` содержит неизвестный ключ `color` в строке 4
- **THEN** stdout содержит строку с префиксом `warning: <cwd>/.codelab/agents/reviewer.md:4:1: unknown frontmatter key`, без `color`; последняя строка `Config: valid`, код `0`

#### Scenario: Одинаково у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются в том же `cwd` с битым шаблоном `$CODELAB_HOME/prompts/Review.md`
- **THEN** у обоих есть строка `warning:` с путём шаблона и `not a valid command name`, коды выхода совпадают

#### Scenario: Недоверенный проект
- **WHEN** конфиг валиден, `cwd` нет в `trusted_projects`, а в нём есть `.codelab/prompts/` и `.codelab/agents/`
- **THEN** stdout содержит ровно две строки `note: <каталог>: the project is not trusted; add it to trusted_projects` — для `<cwd>/.codelab/prompts` и `<cwd>/.codelab/agents`; других строк от диагностик `info` нет; последняя строка и код выхода — как без этих каталогов

#### Scenario: Сбой загрузчика
- **WHEN** конфиг валиден, а загрузчик бросает непредвиденное исключение (в тестах — подменённый бросающий источник файлов проекта: через `CODELAB_HOME` сбой больше не вызвать, тильда даёт ошибку использования заранее)
- **THEN** у обоих бинарей stdout содержит одну строку `warning: <cwd>: project files could not be read: <runtimeType>`, последняя строка и код выхода — как без файлов проекта

#### Scenario: Таймаут загрузки
- **WHEN** конфиг валиден, а загрузка файлов проекта не завершается за 5 с
- **THEN** stdout содержит строку `warning: <cwd>: project files were not read within 5 s`, последняя строка и код выхода — как без файлов проекта

### Requirement: config check показывает состояние секретов
Если загрузка валидна, а конфиг ссылается на секреты (`api_key_secret`, `${secret:…}` у провайдеров и MCP-серверов), `config check` SHALL проверять каждое имя (без повторов) резолвером без режима отладки, с тем же хранилищем, что у подкоманд `secret`. Перед последней строкой `Config: …` SHALL печататься:
- `note: secrets backend: <id>` (или `note: secrets backend: env (<reason>)`);
- на каждый ненайденный секрет — `warning: <location>: <key>: secret <name> is not set; run: codelab secret set <name>`; при бэкенде `env` (в том числе `auto`) текст SHALL вместо этого подсказывать `set <envOverride(name)> or add 'secrets.backend: file' and run: codelab secret set <name>` (на Windows — только переменную);
- при недоступном хранилище — одна строка `warning: secrets: <backend> is unavailable (<reason>)`.

`<location>` — `файл:строка:столбец` слоя, который последним задал ключ ссылки (слой без позиций — имя источника).

При `secrets.backend: file` SHALL всегда, даже без ссылок на секреты, печататься `warning: secrets: file backend stores secrets unencrypted in <path>`. Отказ бэкенда `file` SHALL давать ровно одну строку: при правах шире `0600` — `warning: secrets: <path> has permissions <mode>; run: chmod 600 <path>`, при любой другой причине — `warning: secrets: file is unavailable (<reason>)`. При отказе бэкенда строки по отдельным именам НЕ SHALL печататься.

Найденный секрет строки НЕ SHALL давать. Значения секретов НЕ SHALL печататься и логироваться. Без ссылок на секреты хранилище НЕ SHALL вызываться, и вывод НЕ SHALL меняться, кроме строк бэкенда `file`. Строки секретов НЕ SHALL влиять на код выхода. Обе подкоманды `config check` SHALL печатать одно и то же.

#### Scenario: Секрет не задан при auto
- **WHEN** валидный конфиг на macOS или Linux задаёт `providers.openai.api_key_secret: codelab/openai` без `secrets.backend`, переменной `CODELAB_SECRET_CODELAB_OPENAI` нет
- **THEN** stdout содержит `note: secrets backend: env (…)` и `warning: …: providers.openai.api_key_secret: secret codelab/openai is not set; set CODELAB_SECRET_CODELAB_OPENAI or add 'secrets.backend: file' and run: codelab secret set codelab/openai`, последняя строка `Config: valid`, код `0`

#### Scenario: Секрет не задан в file
- **WHEN** тот же конфиг с `secrets.backend: file`, `secrets.yaml` с правами `0600` без `codelab/openai`
- **THEN** строка `warning: …: secret codelab/openai is not set; run: codelab secret set codelab/openai`, код `0`

#### Scenario: Секрет задан переменной
- **WHEN** тот же конфиг, а `CODELAB_SECRET_CODELAB_OPENAI=sk-test-0123456789abcdef`
- **THEN** строки `warning:` про `codelab/openai` нет, stdout не содержит `sk-test-0123456789abcdef`

#### Scenario: Предупреждение об открытом тексте
- **WHEN** валидный глобальный конфиг задаёт `secrets.backend: file` и не ссылается на секреты, `secrets.yaml` имеет права `0644`
- **THEN** stdout содержит `warning: secrets: file backend stores secrets unencrypted in <path>` и строку о правах с `chmod 600`, последняя строка `Config: valid`, код `0`

#### Scenario: Отказ file без строк по именам
- **WHEN** валидный конфиг с `secrets.backend: file` ссылается на `codelab/openai` и `codelab/mcp/github/authorization`, `secrets.yaml` имеет права `0644`
- **THEN** stdout содержит `warning: secrets: <path> has permissions 0644; run: chmod 600 <path>` ровно один раз и не содержит строк `is not set` и `is unavailable`, последняя строка `Config: valid`, код `0`

#### Scenario: Отказ file по другой причине
- **WHEN** валидный конфиг с `secrets.backend: file` ссылается на `codelab/openai`, а `secrets.yaml` — символическая ссылка
- **THEN** stdout содержит одну строку `warning: secrets: file is unavailable (…)` и не содержит строки `is not set`, код `0`

#### Scenario: Без ссылок вывод прежний
- **WHEN** конфиг использует только `api_key_env`
- **THEN** строк `note: secrets` и `warning: secrets` нет, хранилище не вызывалось

