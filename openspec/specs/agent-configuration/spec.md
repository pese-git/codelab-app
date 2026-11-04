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
Запись конфигурации (`ConfigWriter`, подкоманды CLI, страницы настроек клиентов) НЕ SHALL сохранять секрет значением (CFG-2; design.md change `add-config-literal-secrets-and-migrate`, D5). Литеральный секрет в **файле** конфига SHALL давать предупреждение, а не проблему (решение пользователя 2026-11-04 R8-4; требование «Литеральные секреты в файле конфига»): ключи `api_key`, `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах `mcp.servers` файловых слоёв SHALL давать предупреждение `config.secret.in_file` с путём ключа и текстом по шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>` требования «Литеральные секреты в файле конфига». Литеральный `providers.<id>.api_key` SHALL использоваться как ключ провайдера; значение `api_key` из одной подстановки `${VAR}` или `${secret:x}` SHALL быть ссылкой, а не литералом (R8-8): раскрывается как в заголовках, предупреждения не даёт, `secret migrate` его не трогает. Литерал `api_key` с управляющими или не-ASCII символами SHALL быть проблемой загрузки `value` с текстом `api_key must be printable ASCII`, литерал секретно названного заголовка провайдера — `<Header> must be printable ASCII`, смесь литерала и `${secret:…}` в `api_key` — `api_key may use ${secret:…} only as the whole value`; значение в тексты НЕ SHALL попадать; остальные из этих ключей НЕ SHALL применяться. **R8-6:** `api_key` вместе с `api_key_env` или `api_key_secret` у одного провайдера после слияния слоёв SHALL быть проблемой загрузки `value` с ключом `providers.<id>.api_key` и текстом `api_key, api_key_env and api_key_secret are mutually exclusive` — это конфликт источников, а не «секрет в файле». Проблема `inlineSecret` и `ConfigInlineSecretException` SHALL оставаться у писателя и у предконфигурации из окружения (требование «Предконфигурация провайдера из окружения»), включая файл флага `--provider-config @путь`: это значение флага, а не слой конфига. Текст проблемы `inlineSecret` НЕ SHALL содержать значение и SHALL называть команду `codelab secret set <suggestedSecretName>` (`SecretNames.suggestFor(путь)`, capability `agent-secrets`, «Имена секретов»):
- у провайдера — и ссылку `api_key_secret: <suggestedSecretName>`;
- у элемента `mcp.servers` — и подстановку `${secret:<suggestedSecretName>}` в `env` или `headers`;

`api_key_env` и `api_key_secret` вместе SHALL быть проблемой с ключом `providers.<id>.api_key_secret`. Значение `api_key_env` SHALL быть именем переменной (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`). Значение `api_key_secret` и имя в `${secret:<name>}` SHALL проходить правило `SecretNames` (иначе `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`). Неверный формат — проблема `value` с путём ключа без значения в тексте. Литералы по шаблонам §12.4 (пункты 2–3 CFG-9) SHALL распознаваться по требованию «Литеральные секреты в файле конфига»; распознавание идёт до проверки формата имени.

- `api_key_env` незаданной переменной SHALL давать предупреждение `config.provider.key_missing {provider, variable}` при загрузке и ошибку хода `API key variable <VAR> is not set` при выборе модели этого провайдера без HTTP-запроса. Значение переменной SHALL читаться при запросе через `SecretResolver.env`.
- `api_key_secret` и `${secret:<name>}` в `providers.*.headers.*`, `mcp.servers[*].env.*` и `mcp.servers[*].headers.*` SHALL разрешаться через `SecretResolver`: у провайдера — при запросе, у MCP-сервера — при подключении к сессии (capability `agent-secrets`, требования «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»). Загрузка НЕ SHALL читать хранилище секретов и НЕ SHALL пропускать MCP-сервер из-за ссылки на секрет.
- `${secret:…}` вне значений `env` и `headers` — в `mcp.servers[*].args[*]`, `mcp.servers[*].url` и `providers.*.base_url`, где `${ENV}` допустим, — SHALL давать проблему `value` с путём ключа и текстом `secret references ${secret:…} are allowed only in env and headers values`; конфиг невалиден. Ссылка там НЕ SHALL раскрываться и НЕ SHALL оставаться литералом: argv виден через `ps`, а URL попадает в логи и тексты ошибок (fail closed; design.md, D4).
- Ключ `secrets.backend` SHALL принимать `auto`, `keychain`, `env`, `file` (capability `agent-secrets`, «Выбор бэкенда secrets.backend»); он больше не даёт `config.key.not_applied`. `keychain` и незнакомое значение SHALL давать проблему `value` ядра. `file` на Windows SHALL давать проблему `value` от `ConfigLoader` (ядро платформу не знает) с источником и позицией слоя, где задан ключ, и текстом общей проверки `secretsBackendProblem`: `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`. Загрузка со `scripted` (`--llm-script`) эту проверку не выполняет: сценарий всегда использует `env` (design.md, D7, D11, D14).

#### Scenario: file на Windows при загрузке
- **WHEN** `ConfigLoader.load` с подменённой платформой `windows` читает пользовательский `config.yaml` с `secrets.backend: file`
- **THEN** результат без `config` и `host`, проблема `value` с ключом `secrets.backend`, источником этого файла и строкой ключа `backend`, `toString()` содержит `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; `auto` и `env` на Windows проблем не дают

#### Scenario: Ключ значением
- **WHEN** пользовательский `config.yaml` задаёт `providers.openai.api_key: sk-test-secret`, а сессия делает ход с моделью `openai`
- **THEN** загрузка успешна с предупреждением `config.secret.in_file` с текстом `providers.openai.api_key: a secret is stored in the config file; move it to the secret store: codelab secret migrate`, без `sk-test-secret`; запрос к провайдеру идёт с этим ключом; stderr, лог и вывод `config check` не содержат `sk-test-secret` (`core/config-warns-inline-api-key`, заменяет `core/config-rejects-inline-api-key`)

#### Scenario: Два источника ключа
- **WHEN** пользовательский слой задаёт `providers.openai.api_key: sk-x…`, а проектный (доверенный) — `providers.openai.api_key_secret: codelab/openai`
- **THEN** проблема `value` с ключом `providers.openai.api_key`, текст `api_key, api_key_env and api_key_secret are mutually exclusive` без значения; агент не стартует

#### Scenario: Токен значением у MCP-сервера
- **WHEN** элемент `mcp.servers` с `name: github` задаёт `token: ghp-test-secret`
- **THEN** загрузка успешна с предупреждением `mcp.servers[github].token: a secret is stored in the config file; move it to the secret store: codelab secret migrate` без `ghp-test-secret`; поле `token` не применяется

#### Scenario: Ключ вместо имени переменной
- **WHEN** провайдер `a` задаёт `api_key_env: sk-test-secret-123` (не совпадает с шаблоном `sk-…`: после префикса меньше 20 символов), а провайдер `b` — `api_key_env: sk-proj-AbCdEfGhIjKlMnOpQrStUvWx` (совпадает)
- **THEN** у `a` — проблема `providers.a.api_key_env` о формате имени без значения в тексте; у `b` — проблемы формата нет, есть предупреждение `config.secret.in_file` для `providers.b.api_key_env`, а ход с моделью `b` завершается ошибкой `API key reference providers.b.api_key_env looks like a secret value, not a name; run: codelab secret migrate`; текст и лог не содержат ни одного из значений

#### Scenario: Ключ вместо имени секрета
- **WHEN** провайдер `a` задаёт `api_key_secret: "sk-Test Secret"` (не совпадает с шаблоном), а провайдер `b` — `api_key_secret: ghp_abcdefghijklmnopqrstuvwxyz0123456789` (совпадает с шаблоном GitHub и при этом проходит правило `SecretNames`)
- **THEN** у `a` — проблема `providers.a.api_key_secret` с текстом правила имени; у `b` — предупреждение `config.secret.in_file`, ссылка не разрешается, хранилище не вызывается; текст и лог не содержат значений

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

Проверенные значения SHALL попадать в `CoreConfig.redact`. Правила доверия проектного слоя SHALL соблюдаться: без доверия проект может только включить редакцию, добавить слои и убрать записи `allowlist`. До change редакции секретов (P-10, после 1.0; решение пользователя 2026-11-04 R8-1, design.md change `add-config-literal-secrets-and-migrate`, D2) явно заданный ключ `redact.*` SHALL давать `config.key.not_applied`.

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

### Requirement: Предконфигурация провайдера из окружения
Слой переменных `CODELAB_*` загрузчика `ConfigLoader` SHALL принимать предконфигурацию провайдера (`agent-core-architecture` §17.5.3; design.md, D3):
- `CODELAB_PROVIDER_TYPE` — `openai-compatible` или `anthropic`;
- `CODELAB_PROVIDER_CONFIG` — JSON-объект, или вместо него `CODELAB_PROVIDER_CONFIG_BASE64` — тот же JSON в base64 (стандартный или URL-safe алфавит, `=` необязательны).

**Поля JSON:**
- `id` — `[a-z0-9_-]+`, по умолчанию `env`;
- `base_url` — обязателен для `openai-compatible`;
- `model` и `context_window` — обязательны;
- необязательные: `max_output_tokens`, `name`, `image`, `reasoning`, ровно одно из `api_key_env` и `api_key_secret` (или ни одного), `auth_header`, `headers`, `connect_timeout`, `idle_timeout`.

Результат — таблица `providers.<id>` с `kind` и моделью `<model>`, а также `agent.default_model = "<id>/<model>"`. Внутри слоя 6 предконфигурация SHALL применяться первой, `CODELAB_MODEL` — после неё. Внутри слоя 7 (флаги) предконфигурация флагов SHALL применяться первой, `--model` — после неё; поэтому `CODELAB_MODEL` проигрывает предконфигурации флагов, а `--model` её побеждает. Таблица сливается с файловыми слоями по ключам, поля окружения побеждают. Правила доверия §15.3 к слою НЕ SHALL применяться. Источник в `ConfigLoadResult.sources` — `env:CODELAB_PROVIDER_CONFIG` (или `env:CODELAB_PROVIDER_CONFIG_BASE64`).

**Ошибки** — `ConfigIssue` без строки и столбца, источник — имя переменной. Текст SHALL называть переменную и поле и НЕ SHALL цитировать значение переменной, фрагмент JSON или текст исключения парсера:
- обе переменные `CONFIG` и `CONFIG_BASE64` сразу;
- только одна из пары `TYPE`/`CONFIG`;
- неизвестный тип провайдера — со списком допустимых;
- не base64;
- неверный JSON — со смещением;
- корень не объект;
- неизвестное поле — с подсказкой ближайшего;
- неверный тип поля — с ожидаемым типом;
- поле `api_key`, `apiKey`, `key`, `token`, `secret` или `password` — проблема `inlineSecret` с `suggestedSecretName` `codelab/<id>` (CFG-9);
- значение секретного заголовка `headers` (нормализованное правило требования «Запись конфига ConfigWriter») без `${secret:…}` и `${VAR}` — проблема `inlineSecret`.

Если хост передал флаги предконфигурации (capability `agent-binary`), переменные `CODELAB_PROVIDER_*` НЕ SHALL читаться, а лог SHALL содержать `config.preconfig.shadowed {by: "flags"}`.

#### Scenario: Провайдер без файла конфига
- **WHEN** `CODELAB_HOME` пуст, окружение содержит `CODELAB_PROVIDER_TYPE=openai-compatible` и `CODELAB_PROVIDER_CONFIG={"id":"gw","base_url":"https://llm.internal/v1","model":"qwen3-coder","context_window":131072,"api_key_env":"GW_KEY"}`
- **THEN** загрузка успешна, каталог содержит `gw/qwen3-coder`, `agent.default_model` равен `gw/qwen3-coder`, `sources` содержит `env:CODELAB_PROVIDER_CONFIG` (`core/provider-preconfig-from-env`, L-25)

#### Scenario: base64 даёт тот же конфиг
- **WHEN** тот же JSON передан в `CODELAB_PROVIDER_CONFIG_BASE64` без `=` в конце
- **THEN** `CoreConfig` совпадает с конфигом из `CODELAB_PROVIDER_CONFIG`

#### Scenario: Окружение сильнее файла, CODELAB_MODEL сильнее предконфигурации
- **WHEN** `config.yaml` задаёт `agent.default_model: openai/gpt-4o` и провайдера `openai`, предконфигурация — провайдера `gw` с моделью `m1`, а `CODELAB_MODEL=openai/gpt-4o`
- **THEN** каталог содержит обе модели, `agent.default_model` — `openai/gpt-4o`; без `CODELAB_MODEL` — `gw/m1`

#### Scenario: Битый JSON не цитируется
- **WHEN** `CODELAB_PROVIDER_CONFIG={"id":"gw","headers":{"Authorization":"Bearer sk-live-123"` (JSON обрезан)
- **THEN** загрузка даёт проблему с источником `env:CODELAB_PROVIDER_CONFIG` и смещением; ни проблема, ни одна запись лога не содержат `sk-live-123`

#### Scenario: Ключ значением
- **WHEN** JSON предконфигурации содержит поле `api_key`
- **THEN** проблема `inlineSecret` называет `codelab secret set codelab/<id>` и не содержит значения поля

#### Scenario: Флаги и модель
- **WHEN** `config.yaml` объявляет модель `m2` провайдера `a`, окружение задаёт `CODELAB_MODEL=openai/gpt-4o`, а флаги — предконфигурацию провайдера `a` с моделью `m1` (таблица `providers.a` сливается с файлом, каталог содержит `a/m1` и `a/m2`); второй запуск добавляет `--model a/m2`
- **THEN** в первом запуске `agent.default_model` — `a/m1`, во втором — `a/m2`

#### Scenario: Литеральный токен в заголовке предконфигурации
- **WHEN** JSON предконфигурации содержит `"headers":{"Authorization":"Bearer sk-live-1"}`
- **THEN** проблема `inlineSecret` для `headers.Authorization`, текст не содержит `sk-live-1`

#### Scenario: Опечатка в поле
- **WHEN** JSON содержит `contex_window` вместо `context_window`
- **THEN** проблема называет `CODELAB_PROVIDER_CONFIG.contex_window` и подсказывает `context_window`

### Requirement: Реестр настроек
Ядро SHALL предоставлять `SettingsRegistry` (`codelab_agent_core/lib/src/config/settings_registry.dart`, чистый Dart) со списком `SettingDescriptor {key, type, defaultValue, scope, fileOnlyReason, section, label, description, secret, restartRequired, enumValues, min, max, layers}` в порядке показа (`agent-core-architecture` §17.5.2, §17.5.8; design.md, D4).

`SettingsRegistry.lookup(key)` SHALL находить дескриптор с учётом `*` и покрытия поддерева ключами типа `map`/`mapList`. Более конкретный дескриптор побеждает `*` и «прочие».

**Тест полноты** `settings_registry_complete_test.dart` SHALL проверять:
1. каждый листовой путь схемы валидатора (имена — `*`) покрыт ровно одним дескриптором;
2. путь каждого дескриптора есть в схеме, его `type` и `enumValues` совпадают со схемой; `min`/`max` каждого `int` совпадают с поведением валидатора (граница принимается, значение за ней отклоняется); `defaultValue` ключа, который ядро применяет, совпадает с разрешённым `CoreConfig` пустой конфигурации, а умолчания остальных ключей перечислены явной константой теста «только по §15.4» (в узлах схемы умолчаний и диапазонов нет, design.md, D4);
3. `scope == fileOnly` тогда и только тогда, когда `fileOnlyReason` не пуст; `label` и `description` не пусты;
4. каждый ключ верхнего уровня схемы покрыт;
5. `restartRequired` истинен ровно для ключей «только после перезапуска» (capability `agent-runtime`, «Живая перезагрузка конфигурации»);
6. `layers` — подмножество слоёв, которые правила доверия §15.3 разрешают ключу;
7. дескриптор со `scope: shared` покрывает только узлы схемы с `applied: true`.

Разделы схемы после MVP (непрозрачные узлы) SHALL иметь по одному дескриптору `map` со `scope: fileOnly`; непрозрачный узел внутри раздела хоста (`logging.llm_snapshot`) SHALL наследовать `restartRequired` и слои своего раздела. Ключ, чей узел схемы не применяется (`applied: false`: `agent.fallback`, `agent.summary_model`, `permissions.timeout`, `tools.disabled` и др.), SHALL иметь `scope: fileOnly` с причиной `not applied in this version`. Типы дескрипторов SHALL совпадать с узлами схемы этой сборки (`tools.untrusted_paths` — `stringList`; `tools.project_context.max_bytes`, `loop.empty_response_retries` — `int`). Ключ схемы без дескриптора SHALL ронять тест с сообщением `config key <path> has no SettingDescriptor: declare it shared or fileOnly with a reason` (CFG-19, E-15).

`SettingsRegistry.parseCliValue(descriptor, raw)` SHALL разбирать строку значения по типу дескриптора (списки и отображения — JSON). Ошибка разбора — исключение ядра `ConfigValueException {key, expected}` с ожидаемым форматом (design.md, D4); подкоманда переводит его в код `64`. Значение в текст ошибки НЕ SHALL попадать.

`restartRequired` SHALL быть истинным и для `permissions.*` и `trusted_projects` (R0-1). Пока раздел `config` непрозрачен (итерация 2), он покрыт одним дескриптором `map`/`fileOnly`.

#### Scenario: Ключ схемы без дескриптора
- **WHEN** тест добавляет в копию схемы лист `budget.max_widgets`
- **THEN** проверка полноты падает с сообщением `config key budget.max_widgets has no SettingDescriptor: declare it shared or fileOnly with a reason` (`core/settings-registry-complete`)

#### Scenario: Расхождение умолчаний
- **WHEN** дескриптор `budget.max_steps` объявляет умолчание, отличное от разрешённого `CoreConfig` пустой конфигурации
- **THEN** проверка полноты падает и называет ключ

#### Scenario: Ключ без потребителя не показывается в UI
- **WHEN** тест подставляет в копию таблицы дескриптор `tools.disabled` со `scope: shared`, а узел схемы `tools.disabled` — `applied: false`
- **THEN** проверка полноты падает и называет ключ; в настоящей таблице `tools.disabled` — `fileOnly` с причиной `not applied in this version`

#### Scenario: Более конкретный дескриптор
- **WHEN** вызывается `lookup("providers.openai.api_key_secret")`
- **THEN** возвращается дескриптор `providers.*.api_key_secret` с `secret: true`, а не дескриптор `providers`

#### Scenario: Разбор значения CLI
- **WHEN** `parseCliValue` получает `compaction.enabled` со значением `yes` и `permissions.deny` со значением `["exec:rm -rf *"]`
- **THEN** первое — `ConfigValueException` с подсказкой `true or false`, второе — список из одной строки

### Requirement: Запись конфига ConfigWriter
Программная запись конфигурации SHALL выполняться только `ConfigWriter` (`codelab_agent_io/lib/src/config/config_writer.dart`) над правками ядра `ConfigEdit` (`SetValue`, `UnsetValue`, `UpsertMcpServer`, `RemoveMcpServer`, `RemoveTable`) и целью `ConfigTarget` (`user`, `project`, `projectLocal`). Алгоритм — `agent-core-architecture` §17.5.5 с уточнениями design.md, D5. `ConfigWriter.apply(base, edits)` SHALL:
- **Реестр.** Отклонять `SetValue` и `UpsertMcpServer` с ключом вне `SettingsRegistry` и ключ, чей дескриптор не разрешает слой цели. `UnsetValue` SHALL принимать и ключ вне реестра, если он есть в файле.
- **Доверие.** Отклонять правку проектного слоя, которую правило доверия §15.3 проигнорировало бы. Текст SHALL подсказывать `--local` или `trusted_projects`. Доверие SHALL проверяться только при записи в проектный слой (`project`, `projectLocal`).
- **Секреты.** Отклонять `ConfigInlineSecretException` (с `suggestedSecretName`):
  - значение-секрет по правилу CFG-9, п. 1;
  - по итоговому поддереву документа после всех правок на любой глубине, независимо от типа правки (`SetValue`, `UpsertMcpServer`) и от того, записан лист или значение-отображение целиком: каждое изменённое значение в `providers.*.headers`, `mcp.servers[*].headers`, `mcp.servers[*].env`, `exec.env`, чьё имя после нормализации (нижний регистр, без `-` и `_`) содержит `token`, `secret`, `password`, `apikey`, `auth`, `cookie`, `key` или `privatetoken`, — если в значении нет ни `${secret:…}`, ни `${VAR}`;
  - в поддеревьях непрозрачных узлов схемы (`providers.*.auth`, `providers.*.key_rotation`, `tools.web`, `llm`, `hooks` и прочие разделы после MVP) — по тому же нормализованному правилу имён для любого листа;
  - лист с именем из `inlineSecretKeys` на любой глубине; имя SHALL сравниваться после той же нормализации (`API_KEY`, `Api-Key` — как `api_key`);
  - нестроковый скаляр (число, `bool`) под секретным именем SHALL считаться литералом;
  - изменённость элемента `mcp.servers` SHALL определяться по его номеру в списке, а не по `name`: при дублях `name` каждый элемент проверяется сам.
- **Блокировка и отпечаток.** Брать эксклюзивный `<path>.lock` с содержимым `<pid> <nonce>`. Lock старше порога устаревания (10 с) снимается через `rename` в уникальное имя с повторной проверкой возраста и содержимого и `config.write.stale_lock`; свежий lock другого писателя возвращается на место, а запись получает `ConfigConflictException`. Занятый lock или отпечаток sha256 файла, отличный от `base.fingerprint`, дают `ConfigConflictException`. Брошенные `<path>.tmp-*` SHALL удаляться только после взятия lock. Таймаут смены прав (`chmod`, 5 s) SHALL быть строго меньше порога устаревания lock (10 s). Непосредственно перед `rename` писатель SHALL перечитывать свой lock (в нём его nonce) и отпечаток цели (совпадает с прочитанным под lock); иначе — `ConfigConflictException`, tmp удаляется, цель и чужой lock не трогаются.
- **Правка.** Применять правки к байтам файла через `YamlEditor` (`package:yaml_edit`). Комментарии, пустые строки, порядок ключей, flow-стиль и перевод строк (LF/CRLF) вне изменённых узлов SHALL сохраняться побайтово. Новый ключ SHALL вставляться по правилу `YamlEditor` (R3-2): в отображение, ключи которого отсортированы по алфавиту, — на своё место по алфавиту, иначе — в конец отображения; новый элемент списка (`mcp.servers`) — в конец списка; недостающие предки — в блочном стиле с отступом файла. Известная граница: при вставке по алфавиту комментарий над следующим ключом оказывается над новым ключом; байты комментария сохраняются. Строку, которая содержит `${`, SHALL писать в одинарных кавычках без экранирования `/` (`'Bearer ${secret:codelab/mcp/gh/x}'`): в двойных `yaml_edit` экранирует `/` как `\/`, и файл становится нечитаемым (design.md change `add-config-literal-secrets-and-migrate`, D5). Прочую строку, которая по профилю §15.5 прочиталась бы не строкой (`off`, `yes`), SHALL писать в двойных кавычках. Строку с управляющим символом (в том числе `\n`) SHALL писать в двойных кавычках: одинарные его не выражают. Отказ `YamlEditor` SHALL давать `ConfigException` с `cannot edit <key> automatically; edit the file manually`.
- **Проверка.** Проверять итог `ConfigLoader.validateCandidate` по всем слоям с заменой целевого. Незаданная `${VAR}` — предупреждение результата, а не ошибка. Незаданную `${VAR}` писатель SHALL узнавать по структурному признаку проблемы ядра, а не по тексту сообщения. Итог кандидата и исходный текст слоя проверять тем же методом в режиме полной проверки без обрыва ступеней (R3-3); если полную проверку кандидата не удалось довести до конца (вырезан предок вместо точного пути или весь слой, нет прогресса, исчерпан лимит кругов; правило доверия SHALL вычисляться по исходным слоям до вырезания), проверка SHALL давать служебную проблему `config.validation.incomplete`, и запись SHALL отклоняться (fail-closed), даже если такая проблема была и в базе; неполнота одной базы запись НЕ SHALL блокировать: база сравнения SHALL содержать проблемы всех ступеней, включая каскадные, а не только ступени, на которой оборвалась бы обычная загрузка; сравнивать проблемы до и после правки по сигнатуре `kind|key|source`, без значений и без позиции `line:column` (R3-1); сравнение SHALL учитывать число проблем каждой сигнатуры, поэтому проблемы с пустым ключом НЕ SHALL схлопываться в одну: проблема, которой не было до правки, SHALL давать `ConfigException` с новыми проблемами без записи; проблема, которая была и до правки, SHALL возвращаться в `ConfigWriteResult.warnings`, а запись — выполняться. Литеральный секрет, вносимый правкой, ключ вне реестра, слой, не разрешённый дескриптором, и ключ, отброшенный правилом доверия, SHALL отклоняться всегда, независимо от сравнения. Правка SHALL блокироваться, только если в кандидате есть проблема, которой нет в полном наборе базы; поэтому проблема поздней ступени, открывшаяся после исправления ранней ошибки, НЕ SHALL считаться новой. Обычная загрузка (`config check`, `serve`, перезагрузка) по поведению НЕ SHALL меняться: она по-прежнему останавливается на первой провалившейся ступени.
- **Замена.** Эксклюзивно создавать пустой `<path>.tmp-<pid>-<rand>` в каталоге цели, выставлять на него права исходного файла (кроме Windows) через `SecretProcessRunner` **до** записи содержимого, затем писать, сбрасывать на диск и атомарно переименовывать поверх цели. Сбой смены прав SHALL давать `ConfigException`, удалять tmp и не выполнять `rename`. Символическую ссылку SHALL раскрывать: правится цель, ссылка остаётся. Для слоя `user` ссылка MAY вести куда угодно (dotfiles). Для слоёв `project` и `projectLocal` раскрытая цель (и каталог `.codelab`, если он ссылка) SHALL лежать внутри канонического `<cwd>/.codelab`; иначе — `ConfigException` до взятия lock и до создания каталогов. Больше 32 переходов по ссылкам — `ConfigException` `too many symbolic links`. Каталог `$CODELAB_HOME`, созданный писателем, SHALL получать права `0700` (кроме Windows).
- **Итог.** Писать лог `config.write {path, keys}` и возвращать `ConfigWriteResult {path, fingerprint, warnings, restartRequiredKeys}`.

При любой ошибке файл НЕ SHALL меняться, tmp и lock SHALL удаляться (CFG-13). Значения ключей НЕ SHALL попадать в лог и тексты ошибок. TOML писатель НЕ SHALL писать никогда.

#### Scenario: Сохранение формата
- **WHEN** файл содержит комментарий над `agent:`, хвостовой комментарий у `default_model`, flow-список `fallback: [a/b]` и переводы строк CRLF, и применяется `SetValue("agent.default_model", "anthropic/claude-sonnet-4")`
- **THEN** изменилась только строка `default_model`, её хвостовой комментарий на месте, остальные байты файла совпадают с исходными (`config_writer_test.dart`)

#### Scenario: Ключ модели с точкой
- **WHEN** применяется `SetValue` ключа `providers.local.models."qwen2.5-coder-32b".context_window`
- **THEN** в YAML появляется один ключ `qwen2.5-coder-32b`, а загрузка возвращает модель `local/qwen2.5-coder-32b` с этим окном

#### Scenario: Удаление таблицы провайдера
- **WHEN** применяется `RemoveTable("providers.local")`, а под ним есть модели и комментарии
- **THEN** поддерево и комментарии внутри удалены, комментарий над следующим ключом сохранён; `RemoveTable` несуществующего ключа — `ConfigException`

#### Scenario: Сервер MCP по имени
- **WHEN** применяется `UpsertMcpServer` с `name: github` при существующем элементе `github` и `UpsertMcpServer` с `name: docs` без него
- **THEN** элемент `github` изменён на месте, `docs` добавлен в конец списка `mcp.servers`

#### Scenario: Конфликт с ручной правкой
- **WHEN** файл изменён другим процессом между `read` и `apply`
- **THEN** `apply` бросает `ConfigConflictException`, содержимое файла — правка другого процесса

#### Scenario: Невалидный итог не пишется
- **WHEN** конфиг без проблем загрузки, и применяется `SetValue("budget.max_steps", 0)`
- **THEN** `ConfigException` с новой проблемой `budget.max_steps`, байты файла не изменены, tmp и lock отсутствуют

#### Scenario: Первая запись в пустой конфиг
- **WHEN** `$CODELAB_HOME` пуст, и применяется `SetValue("budget.max_steps", 40)` или правки `provider add` без `--default`
- **THEN** файл записан, `ConfigWriteResult.warnings` содержит проблему `agent.default_model` (`required`), исключения нет

#### Scenario: Правка не вносит новую ошибку
- **WHEN** `agent.default_model: gw/m`, провайдер `gw` — единственный, и применяется `RemoveTable("providers.gw")`
- **THEN** `ConfigException` с проблемой `agent.default_model`, файл не изменён; при этом прежняя проблема другого ключа, бывшая в файле до правки, отказа не вызывает и возвращается предупреждением

#### Scenario: Проблемы без ключа не схлопываются
- **WHEN** исходный текст слоя даёт одну проблему без ключа некоторого вида, а правка вносит ещё одну проблему того же вида без ключа в том же источнике
- **THEN** проблем с сигнатурой `kind||source` стало две вместо одной: лишняя считается новой, `ConfigException`, файл не изменён

#### Scenario: Прежняя ошибка ниже вставки — предупреждение
- **WHEN** в файле есть проблема ключа ниже места вставки (например, `budget.max_steps: 0`), и `SetValue` добавляет новый ключ выше неё, сдвигая её строку
- **THEN** сигнатура `kind|key|source` не изменилась: проблема возвращается в `ConfigWriteResult.warnings`, запись выполнена

#### Scenario: Ошибка ранней ступени
- **WHEN** файл содержит неизвестный ключ `bogus_key` и `budget.max_steps: 0`, и применяется `UnsetValue("bogus_key")`
- **THEN** запись выполнена, `bogus_key` удалён, проблема `budget.max_steps` возвращается в `ConfigWriteResult.warnings`: полная проверка исходного текста (R3-3) видит её в базе, хотя обычная загрузка исходного файла остановилась бы на `bogus_key`

#### Scenario: Ранняя ошибка скрывает поздние
- **GIVEN** `$CODELAB_HOME/config.yaml` с провайдером `lm`, в котором литеральный `api_key: sk-fake-1` и `base_url: "https://u:p@ss@host/v1"`, и `agent.default_model`, ссылающимся на модель `lm`; `codelab-agent config check` сообщает одну проблему (литеральный секрет `providers.lm.api_key`)
- **WHEN** выполняется `codelab-agent config unset providers.lm.api_key`
- **THEN** код выхода `0`, stdout — `Removed providers.lm.api_key from <home>/config.yaml`, затем строки `warning:` для `providers.lm.base_url` и для `agent.default_model` (модели нет в каталоге) как прежних проблем базы
- **AND** ключа `api_key` в файле больше нет, остальные строки и комментарии не изменены
- **AND** строка `sk-fake-1` не встречается ни в stdout, ни в stderr, ни в логе

#### Scenario: Новая ошибка поздней ступени при ранней
- **WHEN** файл содержит неизвестный ключ `bogus_key` и корректный `budget.max_steps: 40`, и применяется `SetValue("budget.max_steps", 0)` (`codelab-agent config set budget.max_steps 0`)
- **THEN** `ConfigException` с новой проблемой `budget.max_steps` (CLI — код `1`), байты файла не изменены, tmp и lock отсутствуют: проблемы `budget.max_steps` нет в полном наборе базы, а прежняя проблема `bogus_key` новой не считается

#### Scenario: Порча слоя не отключает правило доверия
- **WHEN** проектный слой недоверенного проекта содержит испорченные элементы `mcp.servers` (имя не строкой, ключ с кавычкой, больше восьми дубликатов имени), и в этот слой применяется `SetValue("permissions.mode", "bypass")`
- **THEN** запись отклоняется: либо проблемой правила доверия `trusted_projects`, либо служебной `config.validation.incomplete`; байты файла не изменены

#### Scenario: Неполная проверка базы не мешает удалить порчу
- **WHEN** полная проверка исходного слоя неполна, а правка удаляет испорченный элемент, и кандидат проверяется полностью
- **THEN** запись проходит

#### Scenario: Порядок нового ключа
- **WHEN** `SetValue` добавляет новый ключ в отображение с ключами `a`, `c` (по алфавиту) и в отображение с ключами `c`, `a`
- **THEN** в первом новый ключ `b` встаёт между `a` и `c`, во втором — в конец; комментарии и остальные строки не изменены
- **AND** если над `c` в первом отображении стоит комментарий `# про c`, он оказывается над новым ключом `b` (граница `YamlEditor`, design.md D5), а его байты не меняются

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, и применяется `UpsertMcpServer` к слою `project`
- **THEN** `ConfigException` с подсказкой `--local` или `trusted_projects`, файл не создан; `SetValue("trusted_projects", …)` в слой `project` — отказ по слоям ключа

#### Scenario: Литеральный токен MCP
- **WHEN** `UpsertMcpServer` задаёт заголовок `Authorization: "Bearer ghp_abc"` серверу `github`
- **THEN** `ConfigInlineSecretException` с `suggestedSecretName` `codelab/mcp/github/authorization`, текст не содержит `ghp_abc`, файл не изменён

#### Scenario: Литеральный токен через config set
- **WHEN** применяется `SetValue("mcp.servers", [{"name":"gh","type":"http","url":"https://h","headers":{"X-Api-Key":"k-1"}}])` или `SetValue("providers.p.headers", {"Cookie":"s=1"})`
- **THEN** `ConfigInlineSecretException`, текст не содержит `k-1` и `s=1`, файл не изменён

#### Scenario: Литеральный секрет во вложенном значении
- **WHEN** применяется `SetValue("exec", {"env":{"GITHUB_TOKEN":"ghp_x"}})` или `SetValue` значения-отображения с вложенным листом `token: "t-1"`
- **THEN** `ConfigInlineSecretException`, текст не содержит `ghp_x` и `t-1`, файл не изменён

#### Scenario: Литеральный секрет в непрозрачном поддереве
- **WHEN** правка записывает в `providers.p.auth` лист `client_secret: "cs-1"`, или лист `API_KEY: "k-2"` на любой глубине, или `token: 123456` (число)
- **THEN** каждая правка даёт `ConfigInlineSecretException`, текст не содержит значений, файл не изменён

#### Scenario: Дубли имени сервера MCP
- **WHEN** в `mcp.servers` уже есть элемент `name: gh` без заголовков, и правка добавляет второй элемент `name: gh` с заголовком `Authorization: "Bearer ghp_y"`
- **THEN** `ConfigInlineSecretException`: второй элемент сравнивается со своим прежним по номеру, а не с первым по `name`; файл не изменён

#### Scenario: Сбой смены прав
- **WHEN** фейковый `SecretProcessRunner` возвращает ненулевой код на `chmod` tmp
- **THEN** `ConfigException` с `cannot set permissions`, исходный файл не изменён, tmp удалён, содержимое в tmp не записывалось

#### Scenario: Сбой между tmp и переименованием
- **WHEN** запись прерывается после записи tmp и до `rename` (тестовый шов)
- **THEN** исходный файл цел, а следующая запись удаляет брошенный tmp (`config_writer_atomic_test.dart`)

#### Scenario: Символическая ссылка и права
- **WHEN** `$CODELAB_HOME/config.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** после записи ссылка осталась ссылкой, изменена цель, права цели — `0600`

#### Scenario: Ссылка проектного слоя наружу
- **WHEN** `<cwd>/.codelab/config.local.yaml` — ссылка на `$CODELAB_HOME/config.yaml` (или `<cwd>/.codelab` — ссылка на каталог вне `<cwd>`), и применяется правка слоя `projectLocal`
- **THEN** `ConfigException` с путём, цель ссылки не изменена, lock, tmp и новые каталоги не созданы

#### Scenario: Цепочка ссылок и новый CODELAB_HOME
- **WHEN** путь цели проходит больше 32 символических ссылок (в том числе цикл), а в другом случае `$CODELAB_HOME` не существует
- **THEN** в первом случае `ConfigException` `too many symbolic links`, ничего не создано; во втором писатель создаёт `$CODELAB_HOME` с правами `0700` (кроме Windows) и записывает файл

#### Scenario: Lock снят во время записи
- **WHEN** после записи tmp и до `rename` (тестовый шов) lock писателя удалён или заменён lock другого писателя, либо файл цели изменён в обход lock
- **THEN** `ConfigConflictException`, правки писателя в цели нет (байты — исходные или чужой правки), tmp удалён, чужой lock на месте

#### Scenario: Брошенный tmp и занятый lock
- **WHEN** рядом с целью лежит `<path>.tmp-*` старше 10 с, а lock занят другим живым писателем
- **THEN** запись получает `ConfigConflictException`, и брошенный tmp этой записью не удаляется: чистка идёт только под lock

#### Scenario: Ссылка на секрет в одинарных кавычках
- **WHEN** применяется `UpsertMcpServer` stdio-сервера `gh` с `env.GH_TOKEN` = `Bearer ${secret:codelab/mcp/gh/x}` и `env.DEBUG` = строкой `off`
- **THEN** файл содержит `GH_TOKEN: 'Bearer ${secret:codelab/mcp/gh/x}'` без `\/` и `DEBUG: "off"`; загрузка возвращает те же строки

### Requirement: Ссылки проектных слоёв при чтении
`ConfigLoader` (`codelab_agent_io`) SHALL перед чтением файла слоя `project` (`<cwd>/.codelab/config.yaml`) и `projectLocal` (`<cwd>/.codelab/config.local.yaml`) проверять, куда ведут его символические ссылки (design.md, D5, п. 5, «Чтение проектных слоёв»):
- **Существующий файл** SHALL проверяться и открываться по реальному пути, который даёт ОС (`realpath`, `resolveSymbolicLinksSync`), а не по лексическому пути и не по собственному разбору ссылок: проверенный и открытый пути совпадают. Посегментный обход с несуществующим хвостом — только у `ConfigWriter`, которому нужна будущая цель ещё не созданного файла.
- **Разделитель пути** SHALL быть `/` на POSIX, где `\` — обычный символ имени, и `/` или `\` на Windows.
- **Внутри.** Реальный путь SHALL лежать строго внутри канонического `<cwd>/.codelab` (канонический корень проекта плюс `.codelab`, без раскрытия ссылки `.codelab`); сравнение — по сегментам, `.codelab-evil` не внутри.
- Правило «внутри `<cwd>/.codelab`», текст проблемы и раскрытие ссылок SHALL быть одним кодом у писателя, загрузчика и наблюдателя, без копий (design.md, D5, «Где»).

Если реальный путь существующего файла вне канонического `<cwd>/.codelab`, или ссылки файла раскрыть нельзя, загрузчик SHALL:
- не открывать и не читать цель;
- добавлять в результат загрузки проблему `ConfigIssue` вида `syntax` с ключом `""` и источником — путём файла слоя (`<канонический cwd>/.codelab/config.yaml` или `config.local.yaml`). Текст — `the config file resolves outside <canonical cwd>/.codelab/; symbolic links of a project config must stay inside .codelab` (общий с `ConfigWriter`). Цель ссылки и содержимое файла в тексте НЕ SHALL называться: путь чужого дерева для исправления не нужен. Отдельного события лога нет — это обычная проблема загрузки;
- не включать слой в итог: конфигурация с такой проблемой невалидна, как при нечитаемом файле слоя (`config check` её печатает, `serve` и встроенный агент не стартуют, перезагрузка даёт исход `failed` и сохраняет прежний снимок).

Ошибка раскрытия ссылок SHALL всегда быть такой же проблемой загрузки — и у существующего файла, и у висячей ссылки:
- цикл или больше 32 переходов — текст `too many symbolic links: <path>`;
- `..` в несуществующем хвосте пути — текст `invalid path: <path>`.

**Без проблемы** SHALL обрабатываться ровно один случай — висячая ссылка, цель которой вне `<cwd>/.codelab`: слой отсутствует, снаружи ничего не открывается. Проект, у которого `.codelab` указывает на общий каталог без файлов конфига, не должен переставать запускаться; писатель такую ссылку по-прежнему отклоняет. Висячая ссылка внутри `<cwd>/.codelab` — тоже отсутствующий слой, как отсутствующий файл.

Ссылка внутри `<cwd>/.codelab` SHALL читаться как обычный файл. Слой `user` (`$CODELAB_HOME/config.yaml`, раскладки dotfiles) и файл `--config`/`CODELAB_CONFIG` ограничению НЕ SHALL подчиняться: их выбрал тот, кто запускает агента. Почему: каталог проекта приходит из чужого репозитория, и ссылка `.codelab/config.yaml -> ../../other/.codelab/config.yaml` иначе подставляла бы в проект чужой файл, а диагностика загрузки называла бы ключи и позиции файла вне проекта (ревью безопасности итерации 3, L2; решение пользователя 2026-11-02).

**Наблюдатель.** Для файла проектного слоя, чья цель вне `<cwd>/.codelab`, `ConfigWatcher` (требование «Наблюдение за файлами конфига»):
- НЕ SHALL читать содержимое цели, хэшировать её и замерять цель для отпечатка (`stat` по цели); `lstat`/`readlink` звеньев цепочки ссылок допустимы — они нужны, чтобы узнать, куда ведёт ссылка;
- НЕ SHALL подписываться на каталог цели; если сам `<cwd>/.codelab` — ссылка наружу, наблюдатель НЕ SHALL подписываться и на него;
- SHALL давать файлу отпечаток «заблокирован», отличный от отсутствия и от любого содержимого, в том числе в режиме опроса. Поэтому перенаправление ссылки наружу или обратно внутрь даёт сигнал.

Известная граница: висячая ссылка наружу, цель которой появилась позже, сигнала не даёт — цель снаружи не замеряется. Слой учитывается при следующей перезагрузке по другой причине.

#### Scenario: Ссылка проектного файла в другой проект
- **WHEN** `<cwd>/.codelab/config.yaml` — относительная ссылка `../../other/.codelab/config.yaml`, проект в `trusted_projects`, а файл `other` задаёт `budget.max_steps: 7` и `mcp.servers`
- **THEN** результат загрузки содержит проблему с источником `<канонический cwd>/.codelab/config.yaml` и текстом `the config file resolves outside <canonical cwd>/.codelab/; symbolic links of a project config must stay inside .codelab`, `CoreConfig` не построен, ни значения, ни ключи файла `other` в проблемах не встречаются (`config_loader_link_containment_test.dart`)

#### Scenario: Абсолютная ссылка наружу
- **WHEN** `<cwd>/.codelab/config.local.yaml` — абсолютная ссылка на `$CODELAB_HOME/config.yaml`
- **THEN** та же проблема с источником `config.local.yaml`, цель не открывается, путь цели в тексте не назван

#### Scenario: Висячая ссылка наружу
- **WHEN** `<cwd>/.codelab/config.yaml` — ссылка на несуществующий файл вне `<cwd>/.codelab`
- **THEN** слой отсутствует, проблемы нет, загрузка успешна; `ConfigWriter` для того же слоя отклоняет правку `ConfigException`

#### Scenario: Цикл ссылок — всегда проблема
- **WHEN** `<cwd>/.codelab/config.yaml` — ссылка на `loop.yaml`, а `loop.yaml` — ссылка на `config.yaml` (цель не существует ни как файл, ни снаружи)
- **THEN** проблема загрузки с источником `config.yaml` и текстом `too many symbolic links: <path>`, а не отсутствующий слой

#### Scenario: Каталог .codelab — ссылка наружу
- **WHEN** `<cwd>/.codelab` — ссылка на каталог вне `<cwd>`, в котором лежат `config.yaml` и `config.local.yaml`
- **THEN** оба проектных слоя дают по проблеме со своим источником, ни один файл не прочитан; наблюдатель не подписан ни на `<cwd>/.codelab`, ни на каталог его цели

#### Scenario: Обратная косая черта в имени на POSIX
- **WHEN** на macOS или Linux `cwd` содержит `\` в имени каталога, `<cwd>/.codelab/config.yaml` — ссылка на `a\b`, а рядом есть каталог `a/b` с файлом вне `<cwd>/.codelab`, на который реально ведёт цепочка
- **THEN** проверка идёт по реальному пути ОС: `\` считается символом имени, а не разделителем; файл вне `<cwd>/.codelab` даёт проблему выхода за `.codelab` и не читается, проверка не обходится

#### Scenario: Ссылки, которые читаются
- **WHEN** `<cwd>/.codelab/config.local.yaml` — ссылка на `<cwd>/.codelab/shared.yaml`, а `$CODELAB_HOME/config.yaml` — ссылка на `~/dotfiles/codelab/config.yaml` (вне любого проекта)
- **THEN** оба слоя прочитаны, проблем о ссылках нет: слой `user` не ограничивается

#### Scenario: Наблюдатель не следит за целью снаружи
- **WHEN** работающий агент наблюдает `<cwd>/.codelab/config.yaml`, который становится ссылкой наружу `<cwd>/.codelab`, а затем меняется файл цели
- **THEN** перенаправление ссылки даёт один сигнал, перезагрузка — исход `failed` с проблемой выхода за `.codelab`; содержимое цели не читается и цель не замеряется, каталог цели не наблюдается, и правка файла цели второго сигнала не даёт; возврат ссылки внутрь `.codelab` даёт сигнал, и перезагрузка применяет слой; в режиме опроса заблокированный файл отличим от отсутствующего

### Requirement: Подкоманды записи и чтения конфига
Общая реализация `codelab_agent_io/lib/src/cli/` SHALL предоставлять подкоманды (design.md, D6):
- `ConfigCommands`: `path`, `get`, `set`, `unset` (а также существующий `check`);
- `ProviderCommands`: `add`, `list`, `remove`;
- `McpServerCommands`: `add`, `list`, `remove`.

Результат каждой подкоманды — `{exitCode, stdout, stderr}`. Набор флагов и действия — таблица §17.5.5. Аргументы разбирает каждое приложение. Вывод и коды выхода SHALL быть общими для `codelab-agent` и `codelab`.

**Правила:**
- **Слой.** Подкоманды записи (`config set`, `config unset`, `provider add`, `provider remove`, `mcp add`, `mcp remove`) SHALL по умолчанию писать в слой `user`; `--project` и `--local` — слои 3 и 4 для `cwd`. `config get` без `--layer` SHALL читать `merged`.
- **`cwd`** — `--cwd` подкоманды (есть у `config path|get|set|unset|check`, `provider list`, `mcp list`), иначе каталог процесса; канонизирует его загрузчик.
- **`config get`** SHALL печатать сырое значение слоя-победителя (скаляр — одной строкой, отображение и список — JSON с отступом), затем строку `layer: <name>`, где `<name>` — `user`, `project`, `local`, `extra` (файл `CODELAB_CONFIG`/`--config`), `env` или `flags`. Победитель — старший слой, где ключ задан; его поддерево берётся целиком. Подстановки `${VAR}` и `${secret:…}` НЕ SHALL раскрываться ни при каком `--layer`, включая `merged`. Отсутствующий ключ — код `1`.
- **Удаление отсутствующей записи** (`config unset`, `provider remove`, `mcp remove`) SHALL завершаться кодом `0` без записи файла и печатать `<key> is not set in <path>`.
- **Наличие ключа** для `config get`, `config unset`, `provider remove` и `mcp remove` SHALL определяться по пути в документе слоя, а не по значению: ключ со значением `null` присутствует, и `config unset` SHALL его удалять.
- **`provider add <id>`** для существующего провайдера SHALL обновлять его (upsert): переданные флаги перезаписывают свои поля, остальные поля и модели сохраняются.
- **Источник ключа** (R4-4): `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL заменять источник ключа целиком — поля другого источника (`api_key_secret`, `api_key_env`, литеральный `api_key`) удаляются той же записью. Пары `api_key_env` + `api_key_secret` у провайдера после команды НЕ SHALL быть. Без флага ключа источник не меняется.
- **Недостающие обязательные флаги** `provider add` (`--kind`, `--model`, `--context-window`) SHALL перечисляться все одной строкой stderr.
- **`provider remove`** при ссылке из `agent.*` SHALL завершаться кодом `1`, stderr SHALL содержать `change the model first: config set agent.default_model <provider>/<model>`.
- **`mcp add` и `mcp remove`** SHALL отклонять имя сервера с пробелом, `[`, `]` или `"` кодом `64`.
- **`mcp remove <name>`** SHALL искать сервер только по `name`, никогда по номеру элемента списка.
- **Ошибка разбора аргументов** `config set`, `config unset`, `provider` и `mcp` SHALL печатать фиксированную фразу (`invalid arguments for config set`, `invalid arguments for config unset`, `invalid arguments for provider`, `invalid arguments for mcp`) и справку, не цитируя слова argv.
- **Маскирование** (R0-2; design.md, D6) — в `config get` и `provider list`:
  - значение любого листа без дескриптора реестра и элемента отображения с произвольными ключами (`headers`, `env`), чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному правилу требования «Запись конфига ConfigWriter» (на любой глубине дерева), без `${secret:…}` и `${VAR}` SHALL печататься как `<redacted>`; значение со ссылкой — как есть; скалярный лист, описанный реестром (`api_key_secret`, `api_key_env`, `auth_header`), SHALL печататься как есть, **кроме** листа с находкой `literalSecretTag` (литеральный `api_key`, ссылка-значение п. 3 в `api_key_env`/`api_key_secret`) — он SHALL печататься `<redacted>` (design.md change `add-config-literal-secrets-and-migrate`, D5); значения с `${…}` тоже SHALL проходить `literalSecretTag` по литеральным частям;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP и другие узлы без схемы листьев) SHALL печататься как `<opaque: edit the file>` без содержимого;
  - значение из слоя окружения SHALL заменяться именем источника: `<from env:CODELAB_PROVIDER_CONFIG>`, `<from env:CODELAB_MODEL>`;
  - URL (`base_url`, `url`) SHALL разбираться как URI и печататься без userinfo (R4-5); неразбираемый URL и URL с `@` без авторитета (`user:pass@host`) SHALL печататься как `<redacted>`; значение query-параметра или пары `имя=значение` во фрагменте с секретным именем (то же нормализованное правило имён) без ссылки `${…}` SHALL печататься как `<redacted>`, значение-ссылка — как есть;
  - отображения и списки маскируются поэлементно.
- **`config set`** SHALL разбирать значение через `SettingsRegistry.parseCliValue`.
- **`config path`** без флага слоя SHALL печатать строки `user: <path> (exists|missing)`, `project: …`, `local: …` и при заданной `CODELAB_CONFIG` — `CODELAB_CONFIG: …`; с `--project`/`--local` — только путь.
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по строке на провайдера итогового конфига `<id>  kind: …  base_url: …  models: a, b  key: <source>` (без `base_url` — `(default)`); источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`, `literal in config file`; у `api_key: ${VAR}` — `env <VAR>: set|not set`, у `api_key: ${secret:x}` — `secret x: found|not set|unavailable`; у ссылки-значения п. 3 — `unusable reference (looks like a secret value)` без поиска в хранилище).
- **`mcp list`** SHALL печатать серверы файлов по слоям строками `<name>  type: …  layer: …  enabled: true|false` без подключения к ним.
- **`provider add --api-key-stdin`**:
  1. проверить кандидат конфига без записи;
  2. проверить хранилище `SecretAdmin.checkStore("codelab/<id>")`;
  3. прочитать ключ через `SecretInput`;
  4. сохранить ключ `SecretAdmin.store`;
  5. записать `api_key_secret: codelab/<id>`.

  В конфиг SHALL попадать только имя секрета. Ошибка записи конфига после сохранения ключа SHALL называть сохранённый секрет в stderr. Если секрет `codelab/<id>` уже был, stdout SHALL содержать `warning: replaced the existing secret codelab/<id>`.
- **Конфликт.** При `ConfigConflictException` подкоманда SHALL один раз перечитать файл и повторить правки; второй конфликт — код `1` с текстом `config file changed during the edit; run the command again`.
- **Коды выхода:**
  - `0` — успех;
  - `1` — новая ошибка загрузки итога (R3-1), отказ доверия, `inlineSecret`, конфликт, хранилище секретов только для чтения или недоступно;
  - `64` — ошибка использования: неизвестный ключ `set`, неверное значение, недостающий обязательный флаг `provider add` (`--kind`, `--model`, `--context-window`), несовместимые флаги, лишние аргументы, недопустимое имя MCP-сервера.
- **Вывод успешной записи** SHALL содержать строку `Updated <key> in <path>` (`Updated providers.<id> in <path>`, `Updated mcp.servers[<name>] in <path>`) или `Removed <key> from <path>`, строки `warning:` предупреждений писателя и `note: restart the agent to apply: <keys>` для ключей `restartRequired`.

Значения секретов и раскрытые подстановки НЕ SHALL попадать в stdout, stderr и лог.

#### Scenario: config set и get
- **WHEN** в пустом `$CODELAB_HOME` вызывается `config set budget.max_steps 40`, затем `config get budget.max_steps`
- **THEN** первый — код `0`, `Updated budget.max_steps in <home>/config.yaml` и строка `warning: agent.default_model: required` (прежняя проблема конфига, R3-1), второй — `40` и слой `user`

#### Scenario: get не раскрывает переменную
- **WHEN** `providers.gw.headers.X-Token` в файле равен `"${GW_TOKEN}"`, окружение содержит `GW_TOKEN=t-123`, и вызывается `config get providers.gw.headers --layer merged`
- **THEN** stdout содержит `${GW_TOKEN}` и не содержит `t-123`

#### Scenario: get маскирует секреты
- **WHEN** файл содержит `providers.p.api_key: sk-1`, `providers.p.base_url: https://u:pw@h/v1`, `mcp.servers[gh].headers.Authorization: "Bearer lit"` и `mcp.servers[gh].env.GITHUB_TOKEN: "${GH}"`, а окружение — `CODELAB_MODEL=p/m`; вызываются `config get providers.p`, `config get mcp.servers --layer merged`, `config get agent.default_model`
- **THEN** вывод содержит `<redacted>` вместо `sk-1` и `Bearer lit`, `https://h/v1` без `u:pw`, `${GH}` как есть и `<from env:CODELAB_MODEL>`; ни `sk-1`, ни `pw`, ни `lit` в выводе нет (`config_output_test.dart`)

#### Scenario: Маскирование URL
- **WHEN** файл содержит `providers.p.base_url: "https://u:p@ss@host/v1?api_key=X&v=2"`, и вызываются `config get providers.p.base_url` и `provider list`
- **THEN** вывод не содержит `p@ss` и `X`, содержит `host/v1` и `v=2`

#### Scenario: Неразбираемый URL
- **WHEN** `providers.p.base_url` содержит строку, которую нельзя разобрать как URI, и вызывается `config get providers.p.base_url`
- **THEN** stdout содержит `<redacted>` вместо значения, код `0`

#### Scenario: Непрозрачные поддеревья
- **WHEN** файл содержит `providers.p.auth: {client_secret: s-1}` и `providers.p.key_rotation: {keys: [k-1]}`, и вызывается `config get providers.p`
- **THEN** оба поддерева выведены как `<opaque: edit the file>`, вывод не содержит `s-1` и `k-1`

#### Scenario: unset удаляет запрещённый ключ
- **WHEN** файл содержит `providers.openai.api_key: sk-1` (конфиг невалиден), и вызывается `config unset providers.openai.api_key`
- **THEN** ключ удалён, итог валиден, код `0`; stdout и stderr не содержат `sk-1`

#### Scenario: provider add с ключом из stdin
- **WHEN** `secrets.backend: file`, вызывается `provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-stdin --default`, ключ подаётся в stdin
- **THEN** `secrets.yaml` содержит `codelab/gw`, `config.yaml` — `api_key_secret: codelab/gw` и `agent.default_model: gw/m`, а ни один файл конфига и ни один вывод не содержат значения ключа (`cli_config_commands_test.dart`)

#### Scenario: provider add при бэкенде env
- **WHEN** `secrets.backend` не задан (`auto` = `env`), вызывается `provider add … --api-key-stdin`
- **THEN** код `1`, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_CODELAB_GW`; ключ не запрашивается, `config.yaml` не изменён

#### Scenario: provider remove со ссылкой
- **WHEN** `agent.default_model: gw/m`, вызывается `provider remove gw`
- **THEN** код `1`, проблема `agent.default_model` и строка `change the model first: config set agent.default_model <provider>/<model>` в stderr, файл не изменён

#### Scenario: get без --layer читает итог
- **WHEN** `budget.max_steps: 10` в `config.yaml`, `budget.max_steps: 20` в `.codelab/config.yaml` проекта, и вызывается `config get budget.max_steps --cwd <project>`
- **THEN** код `0`, stdout — `20` и `layer: project`

#### Scenario: get отсутствующего ключа
- **WHEN** ключ `budget.max_steps` не задан ни в одном слое, и вызывается `config get budget.max_steps`
- **THEN** код `1`, stdout пуст

#### Scenario: config unset отсутствующего ключа
- **WHEN** `config.yaml` не содержит `budget.max_steps`, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `budget.max_steps is not set in <home>/config.yaml`, файл не изменён

#### Scenario: provider remove отсутствующего провайдера
- **WHEN** `config.yaml` не содержит `providers.gw`, и вызывается `provider remove gw`
- **THEN** код `0`, stdout — `providers.gw is not set in <home>/config.yaml`, файл не изменён

#### Scenario: mcp remove отсутствующего сервера
- **WHEN** `config.yaml` не содержит сервера `github`, и вызывается `mcp remove github`
- **THEN** код `0`, stdout — `mcp.servers[github] is not set in <home>/config.yaml`, файл не изменён

#### Scenario: unset ключа со значением null
- **WHEN** `config.yaml` содержит `budget:` с вложенным `max_steps:` без значения, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `Removed budget.max_steps from <home>/config.yaml`, строки `max_steps:` в файле нет

#### Scenario: Флаг ключа заменяет источник ключа
- **WHEN** `secrets.backend: file`, `config.yaml` содержит `providers.gw` с `api_key_env: GW_KEY`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с ключом в stdin
- **THEN** код `0`, `providers.gw` содержит `api_key_secret: codelab/gw` и не содержит `api_key_env`

#### Scenario: provider add без обязательных флагов
- **WHEN** вызывается `provider add gw` без `--kind`, `--model` и `--context-window`
- **THEN** код `64`, одна строка stderr называет `--kind`, `--model` и `--context-window`; файлы не изменены

#### Scenario: mcp remove не ищет по номеру
- **WHEN** `mcp.servers` содержит один сервер `github`, и вызывается `mcp remove 0`
- **THEN** код `0`, stdout — `mcp.servers[0] is not set in <home>/config.yaml`, сервер `github` на месте, файл не изменён

#### Scenario: Недопустимое имя в mcp remove
- **WHEN** вызывается `mcp remove "my server"`
- **THEN** код `64`, файл не изменён

#### Scenario: provider add обновляет провайдера
- **WHEN** `config.yaml` содержит `providers.gw` с `base_url: https://x/v1` и `api_key_secret: codelab/gw`, хранилище `file` уже содержит секрет `codelab/gw`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с новым ключом в stdin
- **THEN** код `0`, секрет `codelab/gw` заменён новым значением, `base_url` сохранён; stdout содержит `warning: replaced the existing secret codelab/gw` и `Updated providers.gw in <home>/config.yaml`, ни старого, ни нового значения ключа в выводе нет

#### Scenario: Недопустимое имя MCP-сервера
- **WHEN** вызывается `mcp add "my server" --type http --url https://h`
- **THEN** код `64`, файл не изменён

#### Scenario: Ошибка разбора аргументов не цитирует argv
- **WHEN** вызывается `provider add gw --api-key sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for provider` и справку, не содержит `sk-1`

#### Scenario: Ошибка разбора аргументов config set не цитирует argv
- **WHEN** вызывается `config set budget.max_steps --sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for config set` и справку, не содержит `sk-1`

#### Scenario: mcp add с литеральным токеном
- **WHEN** вызывается `mcp add github --type http --url https://h --header Authorization="Bearer ghp_x"`
- **THEN** код `1`, stderr подсказывает `${secret:codelab/mcp/github/authorization}` и `codelab secret set codelab/mcp/github/authorization`, не содержит `ghp_x`; файл не изменён

#### Scenario: Неизвестный ключ set
- **WHEN** вызывается `config set budget.max_stepz 10`
- **THEN** код `64`, stderr подсказывает `budget.max_steps`, файл не изменён

### Requirement: Ключи config.watch и config.poll_interval
Схема SHALL принимать и применять `config.watch` (`bool`, по умолчанию `true`) и `config.poll_interval` (`duration`, по умолчанию `2s`, допустимо `1s..60s`) в слоях `user`, `projectLocal` и `--config`/`CODELAB_CONFIG` (design.md, D7). В проектном слое 3 и в `config.local.yaml` недоверенного проекта раздел `config` SHALL отбрасываться с `config.project.untrusted_key`. Оба ключа SHALL быть `restartRequired`. Предупреждения `config.key.not_applied` они больше НЕ SHALL давать.

#### Scenario: Применяемые ключи
- **WHEN** глобальный конфиг задаёт `config.watch: false` и `config.poll_interval: 5s`
- **THEN** загрузка успешна без `config.key.not_applied`, `HostSettings` содержит оба значения

#### Scenario: Недопустимый интервал и проектный слой
- **WHEN** глобальный конфиг задаёт `config.poll_interval: 500ms`, а `<cwd>/.codelab/config.yaml` — `config.watch: false`
- **THEN** первое — проблема `config.poll_interval` с допустимым диапазоном, второе отброшено с `config.project.untrusted_key`

### Requirement: Наблюдение за файлами конфига
`ConfigWatcher` (`codelab_agent_io`) SHALL следить за файлами слоёв, которые загрузчик читает для корня запуска: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<root>/.codelab/config.yaml` и `config.local.yaml` (в том числе ещё не созданные), а при `secrets.backend: file` — `$CODELAB_HOME/secrets.yaml` (design.md, D7).

**Механизм:**
- события родительского каталога (`Directory.watch`), одна подписка на каталог;
- если каталога нет, фабрика событий бросила, поток вернул ошибку или завершился (`onDone`) — опрос раз в `config.poll_interval` по `(exists, mtime, size)` и sha256; отсутствующий каталог SHALL распознаваться до подписки (на macOS `watch` по нему молчит), а файл, переведённый на опрос, SHALL оставаться на опросе до `close()`;
- сигнал запускает только событие, у которого путь или цель `rename` имеет точное имя наблюдаемого файла;
- после события — debounce 300 мс на часах `Clock`, новые события перезапускают таймер;
- если sha256 всех файлов совпадает с базой, сигнала нет; отсутствующий файл и нечитаемый файл — два разных состояния, отличных от любого содержимого; файл больше лимита размера загрузчика (`maxConfigBytes`) SHALL сравниваться по `(size, mtime)` без чтения — загрузчик его всё равно отклонит;
- база SHALL обновляться при каждом сигнале и в `rebase()`, который `FileConfigSource.load()` вызывает перед чтением слоёв: собственное чтение НЕ SHALL давать повторного сигнала, правка во время чтения SHALL давать. Загрузка для проверки (`load(rebase: false)`, `/config check`) `rebase()` НЕ SHALL вызывать: иначе правка, ждущая debounce, совпала бы с базой и перезагрузка потерялась бы;
- для файла-ссылки SHALL наблюдаться и лексический путь, и каталог канонической цели ссылки; сигнал — по событию любого из них, содержимое сравнивается по лексическому пути (у файла проектного слоя — по реальному пути из требования «Ссылки проектных слоёв при чтении», как читает загрузчик), цель пересчитывается в `rebase()`. Исключение — файл проектного слоя, чья цель вне канонического `<cwd>/.codelab` (требование «Ссылки проектных слоёв при чтении»): ни каталог цели, ни `<cwd>/.codelab`, если он сам ссылка наружу, не наблюдаются; содержимое цели не читается и цель не замеряется (`lstat`/`readlink` звеньев допустимы); отпечаток файла — состояние «заблокирован», в том числе при опросе; такой файл SHALL опрашиваться раз в `config.poll_interval`, пока вердикт не изменится.

Поток событий каталога SHALL приходить через шов-фабрику `Stream<DirectoryChange> Function(Directory)` с узкой структурой `DirectoryChange {path, destination}` (`FileSystemEvent` запечатан и в тестах не строится), а замер для опроса — через шов `ConfigFileProbe`; по умолчанию — настоящие `Directory.watch` и `stat`. Unit-тесты подают события без настоящей файловой системы; настоящий `watch` проверяет один интеграционный тест с пределом времени. `FileConfigSource implements ConfigSource` SHALL выдавать сигнал `changes` после debounce. Хост SHALL создавать его до сборки ядра, с результатом стартовой загрузки (`initial`), и каждая `load()` SHALL вызывать `ConfigLoader.load` с `pinnedTrustedProjects` из `initial.config.trustedProjects`. Загрузчик SHALL лишь передавать список в `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`: доверие вычисляет ядро, и по закреплённому списку строятся проектные слои и `CoreConfig.trustedProjects`; новое значение `trusted_projects` попадает только в `values` (design.md, D8). `close()` SHALL останавливать наблюдение и таймеры; после `close()` сигналов нет. При `config.watch: false` наблюдатель НЕ SHALL создаваться. События по служебным файлам `ConfigWriter` (`config.yaml.lock`, `*.lock.stale-*`, `*.tmp-*`) в `$CODELAB_HOME` и `.codelab/` НЕ SHALL запускать перезагрузку; распознавать их SHALL предикат писателя (`config_write_lock.dart`), а не дублированные шаблоны. Ошибка потока событий SHALL переводить файлы каталога на опрос с `config.watch.fallback`; ошибка замера при опросе или чтения файла при сравнении — давать `config.watch.failed` без остановки опроса.

#### Scenario: Debounce
- **WHEN** файл записывается три раза за 200 мс
- **THEN** ровно один сигнал через 300 мс после последней записи (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Замена через rename и новый файл
- **WHEN** редактор заменяет `config.yaml` через `rename`, а позже создаётся отсутствовавший при старте `<root>/.codelab/config.local.yaml`
- **THEN** оба изменения дают по сигналу

#### Scenario: Запись ConfigWriter даёт один сигнал
- **WHEN** `ConfigWriter` записывает `$CODELAB_HOME/config.yaml` (создание и удаление `config.yaml.lock`, `config.yaml.tmp-*`) и отдельно в `.codelab/` появляется и исчезает `config.local.yaml.lock.stale-*`
- **THEN** запись даёт ровно один сигнал — по итоговому `rename`; события служебных файлов сами по себе сигнала не дают (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Те же байты
- **WHEN** файл перезаписывается теми же байтами
- **THEN** сигнала нет

#### Scenario: Режим опроса
- **WHEN** наблюдатель работает в режиме опроса с `poll_interval: 1s`, и файл меняется
- **THEN** сигнал приходит не позже интервала опроса плюс 300 мс

#### Scenario: Отсутствующий каталог уходит на опрос
- **WHEN** при старте нет каталога `<root>/.codelab/`, а позже он создаётся вместе с `config.yaml`
- **THEN** при старте пишется `config.watch.fallback` с путём файла, а создание файла даёт сигнал опросом, не позже `poll_interval` плюс 300 мс (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Собственное чтение не даёт сигнала
- **WHEN** `FileConfigSource.load()` читает слои после правки, уже давшей сигнал, а затем приходит запоздалое событие по тому же файлу без новых байтов
- **THEN** второго сигнала нет; правка, сделанная после `rebase()`, даёт сигнал (`file_config_source_test.dart`)

#### Scenario: /config check во время debounce не теряет перезагрузку
- **WHEN** наблюдаемый файл изменён, наблюдатель ждёт debounce, и в это время вызывается `checkConfig()` (`load(rebase: false)`)
- **THEN** проверка видит новое содержимое, база наблюдателя не сдвинута; по истечении debounce приходит сигнал, и перезагрузка применяет правку (`file_config_source_test.dart`, `FakeClock`)

#### Scenario: Поток каталога завершился
- **WHEN** поток событий каталога завершается без ошибки (`onDone`), а затем наблюдаемый файл меняется
- **THEN** файлы каталога переведены на опрос с `config.watch.fallback`, правка даёт сигнал не позже `poll_interval` плюс 300 мс

#### Scenario: Файл больше лимита загрузчика
- **WHEN** наблюдаемый файл больше `maxConfigBytes` и меняется его размер или `mtime`
- **THEN** наблюдатель сравнивает отпечаток `(size, mtime)` без чтения содержимого и даёт сигнал; загрузчик сообщает о превышении лимита

#### Scenario: Посторонний файл каталога
- **WHEN** в `$CODELAB_HOME` меняется файл с другим именем (`notes.txt`, `config.yaml.bak`)
- **THEN** сигнала нет

#### Scenario: Нечитаемый файл
- **WHEN** наблюдаемый файл становится нечитаемым, и по нему приходит событие каталога
- **THEN** пишется `config.watch.failed` с путём, а состояние «нечитаемый» отличается от прежнего содержимого — сигнал есть, причину называет загрузчик при `load()`

#### Scenario: Правка цели symlink даёт сигнал
- **WHEN** `$CODELAB_HOME/config.yaml` — ссылка на `~/dotfiles/codelab/config.yaml`, и меняется файл цели в `~/dotfiles/codelab/`
- **THEN** наблюдатель получает событие каталога цели и даёт ровно один сигнал после debounce; после `load()` (`rebase()`) перенаправленная ссылка наблюдается по новой цели

### Requirement: Литеральные секреты в файле конфига
Публичные функции ядра (`config/inline_secrets.dart`; design.md change `add-config-literal-secrets-and-migrate`, D3) SHALL быть одним источником находок для загрузки, писателя, маскирования и `secret migrate`:
- `literalSecretTag(value)` — тег первого совпадения шаблонов §12.4 (`sk-…`, GitHub, AWS, Google, Slack, JWT, Bearer, PEM, присваивание секрета, URL с паролем) в **литеральных частях** значения (между подстановками `${…}`), с учётом встроенного белого списка `git_sha`, `uuid`, или `null`;
- `findInlineSecrets(ConfigTree)` — список `InlineSecretFinding {keyPath, kind, tag, suggestedSecretName, spans}` для пунктов 1–3 CFG-9.

Ни тег, ни находка НЕ SHALL содержать значение или его часть. Выражения с `(?i)` SHALL компилироваться с `caseSensitive: false`; части имени шаблона «присваивание секрета» SHALL быть ограничены 64 символами. Значение с URL-авторитетом, чей пароль userinfo не состоит целиком из одной подстановки `${…}`, SHALL давать находку `connection-string`, в том числе если подстановка разрезает пароль (`postgres://u:lit${X}@h/db`).

Находка в файловом слое (`user`, `project`, `projectLocal`, `CODELAB_CONFIG`/`--config`) SHALL давать предупреждение `config.secret.in_file {key, source}` с файлом, строкой и столбцом и текстом по одному шаблону `<key>: a secret is stored in the config file; move it to the secret store: <command>`, где `<command>`:
- `codelab secret migrate` — для слоя `user`;
- `codelab secret migrate --project` / `--local` — для проектных слоёв;
- `codelab secret set <suggestedSecretName>` — для `CODELAB_CONFIG`/`--config`.

Загрузка НЕ SHALL прерываться (R8-4; D4). Находки SHALL считаться по слою независимо от `enabled` элемента. `config check` SHALL печатать его строкой `warning:` без изменения кода выхода. Что применяется:
- литеральные части `providers.*.headers.*`, `mcp.servers[*].headers.*`, `mcp.servers[*].env.*` (п. 2, R1-1) — применяются как есть;
- `api_key_env`, `api_key_secret` или имя в `${secret:<name>}`, совпавшие с шаблоном (п. 3), — проблемы формата имени НЕ SHALL быть; значение SHALL попадать в `CoreConfig` маркером, а не ссылкой: `UnusableKeyRef` у ключа провайдера, `UnusableSecretReference` в шаблоне заголовка или `env`. Токен вместо имени переменной в `${…}` (`${ghp_…}`) SHALL давать ту же находку (`referenceName`): переменная не читается, тексты проблемы и предупреждения имени не содержат. Шаблон `sk-…` к именам п. 3 SHALL применяться только в начале значения. Маркер НЕ SHALL участвовать в поиске в хранилище в `config check`, в `config.provider.key_missing`, `providerProblems` и `secrets.lookup`. Такая ссылка НЕ SHALL разрешаться: ход провайдера SHALL завершаться ошибкой `auth` без HTTP-запроса с текстом `API key reference providers.<id>.<key> looks like a secret value, not a name; run: codelab secret migrate`, а MCP-сервер — состоянием `failed` с тем же текстом для своего ключа; значение НЕ SHALL попадать ни в текст, ни в `secrets.lookup`.

Для ключей недоверенного проектного слоя, которые правило доверия §15.3 отбрасывает (`providers.*`, `mcp.servers`), предупреждения `config.secret.in_file` НЕ SHALL быть: остаётся `config.project.untrusted_key`. Предконфигурация из окружения этим требованием не меняется. `url` и `base_url` на пароль в userinfo НЕ SHALL проверяться (`config get` печатает их без userinfo, R4-5).

`ConfigWriter` SHALL применять `literalSecretTag` к изменённым значениям `headers` и `env` и к элементам `mcp.servers[*].args` (R4-6, OQ3) и отклонять запись `ConfigInlineSecretException` (R8-5); у элемента `args` подсказка SHALL называть `--env <NAME>='${secret:<suggestedSecretName>}'`. Прежний литерал файла SHALL переходить в предупреждения записи. Загрузка элементы `args` НЕ SHALL проверять.

Дескриптор `providers.*.api_key` реестра настроек SHALL быть `fileOnly` с признаком `secret: true` (тест полноты CFG-19). `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL удалять и литеральный `api_key` той же правкой (R4-4). `provider list` SHALL показывать источник ключа `key: literal in config file` без значения.

#### Scenario: Ссылка в api_key
- **WHEN** провайдер `p` задаёт `api_key: "${P_KEY}"` (переменная задана), а провайдер `q` — `api_key: "${secret:codelab/q}"`
- **THEN** предупреждений `config.secret.in_file` нет; `p` получает значение переменной, `q` — секрет через резолвер; `api_key: "${P_KEY}"` вместе с `api_key_env` — проблема R8-6

#### Scenario: Токен вместо имени переменной в подстановке
- **WHEN** заголовок сервера `gh` — `Authorization: "Bearer ${ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`, а заголовок провайдера `p` — `X-Api-Key: "${ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`
- **THEN** проблем загрузки нет, есть предупреждения `config.secret.in_file` для обоих ключей; в шаблонах — маркер `UnusableSecretReference`, окружение не читается; сервер `gh` — `failed`, ход провайдера `p` — ошибка `auth` без HTTP-запроса; ни текст, ни лог не содержат `ghp_`

#### Scenario: Смесь литерала и ссылки в api_key
- **WHEN** провайдер задаёт `api_key: "sk-lit ${secret:codelab/p}"`
- **THEN** проблема `value` с ключом `providers.<id>.api_key` и текстом `api_key may use ${secret:…} only as the whole value`, без значения

#### Scenario: Управляющий символ в заголовке провайдера
- **WHEN** литеральный `providers.p.headers.X-Api-Key` содержит символ табуляции
- **THEN** проблема `value` с текстом `X-Api-Key must be printable ASCII`, без значения; у MCP-сервера та же строка проблемы не даёт

#### Scenario: Токен в URL в выводе config get
- **WHEN** `providers.p.base_url: "https://h/v1/ghp_abcdefghijklmnopqrstuvwxyz0123456789?region=eu"`, выполняется `codelab config get providers.p.base_url`
- **THEN** выводится `<redacted>`, токена в выводе нет

#### Scenario: Имя секрета с sk- не в начале
- **WHEN** провайдер задаёт `api_key_secret: codelab/sk-test-provider-key-name`
- **THEN** находки нет, ссылка разрешается как обычное имя

#### Scenario: Управляющий символ в ключе
- **WHEN** `api_key` содержит символ табуляции
- **THEN** проблема `value` с ключом `providers.<id>.api_key`, текст без значения

#### Scenario: Литерал в файле CODELAB_CONFIG
- **WHEN** файл `CODELAB_CONFIG` задаёт `providers.p.api_key: sk-<30 символов>`
- **THEN** предупреждение с текстом `providers.p.api_key: a secret is stored in the config file; move it to the secret store: codelab secret set codelab/p`

#### Scenario: Выключенный сервер
- **WHEN** сервер `gh` с `enabled: false` содержит литеральный заголовок по шаблону
- **THEN** предупреждение `config.secret.in_file` есть

#### Scenario: config get не печатает литеральный ключ
- **WHEN** файл задаёт `providers.p.api_key: sk-<30 символов>` и `providers.q.api_key_env: ghp_<36 символов>`, выполняются `codelab config get providers` и `codelab provider list`
- **THEN** оба листа выведены как `<redacted>`, `provider list` показывает `key: literal in config file` у `p`; ни одно значение не напечатано

#### Scenario: Смешанное значение заголовка
- **WHEN** пользовательский `config.yaml` задаёт у MCP-сервера `gh` заголовок `Authorization: "Bearer ghp_<36 символов> ${X}"`
- **THEN** загрузка успешна с предупреждением `mcp.servers[gh].headers.Authorization: a secret is stored in the config file; move it to the secret store: codelab secret migrate` без `ghp_`; заголовок применяется

#### Scenario: Ссылка рядом с префиксом схемы
- **WHEN** заголовок `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`
- **THEN** предупреждений нет

#### Scenario: Токен вместо имени переменной
- **WHEN** провайдер `p` задаёт `api_key_env: ghp_<36 символов>`, и сессия делает ход с его моделью
- **THEN** загрузка успешна с предупреждением; ход завершается ошибкой `auth` `API key reference providers.p.api_key_env looks like a secret value, not a name; run: codelab secret migrate` без HTTP-запроса; ни текст, ни лог не содержат значения

#### Scenario: DSN, разрезанный подстановкой
- **WHEN** сервер `db` задаёт `env.DATABASE_URL: "postgres://app:pw-lit${SUFFIX}@localhost/db"`, а `db2` — `env.DATABASE_URL: "postgres://app:${PW}@localhost/db"`
- **THEN** предупреждение только у `mcp.servers[db].env.DATABASE_URL`, без `pw-lit` в тексте

#### Scenario: Недоверенный проект
- **WHEN** проект вне `trusted_projects` задаёт в `.codelab/config.yaml` `providers.p.api_key: sk-<30 символов>`
- **THEN** загрузка успешна, есть `config.project.untrusted_key` для `providers`, предупреждения `config.secret.in_file` нет

#### Scenario: Литеральный токен в args через mcp add
- **WHEN** `codelab-agent mcp add gh --type stdio --command gh-mcp --arg --token --arg ghp_<36 символов>`
- **THEN** код `1`, файл не тронут, stderr называет `--env` и `${secret:…}` и не содержит значения

### Requirement: Маскирование args MCP-серверов в выводе
Значения `url` и `base_url` в `config get` после удаления userinfo (R4-5) SHALL проверяться `hasInlineSecret`; находка (токен в пути или под несекретным именем query-параметра) SHALL давать `<redacted>`. Маскер `config get` и `provider list` SHALL прогонять через `literalSecretTag` все листья, включая листья, описанные реестром, и значения с `${…}`; лист с находкой SHALL печататься `<redacted>`, даже если это лист реестра (`api_key`, `api_key_env`, `api_key_secret`). `config get` SHALL маскировать элементы `mcp.servers[*].args` (R4-6; design.md change `add-config-literal-secrets-and-migrate`, D5):
- элемент с `literalSecretTag != null` → `<redacted>`;
- элемент после флага, чьё имя без ведущих `-` секретное по нормализованному правилу имён, → `<redacted>`;
- `--<секретное имя>=<значение>` → `--<имя>=<redacted>`;
- элемент, состоящий только из ссылок `${…}`, — как есть; литеральная часть рядом со ссылкой после секретного флага или в `--<секретное имя>=…` → `<redacted>` (fail closed);
- элемент-список или элемент-отображение (невалидный конфиг ручной правки) — маска целиком.

Маскирование SHALL действовать при любом `--layer`.

#### Scenario: Токены в args ручной правки
- **WHEN** файл задаёт `args: ["--token", "plain-value-1", "--api-key=plain-value-2", "--verbose", "ghp_<36 символов>", "${TOKEN}"]`, и выполняется `codelab config get mcp.servers`
- **THEN** вывод содержит `"--token"`, `"<redacted>"`, `"--api-key=<redacted>"`, `"--verbose"`, `"<redacted>"`, `"${TOKEN}"` и не содержит ни одного из трёх значений; код `0`; вывод `codelab-agent config get` совпадает байт в байт

### Requirement: Значение заголовка или переменной mcp add из stdin
`mcp add` (`McpServerCommands`, оба бинаря) SHALL принимать флаги `--header-stdin <Name>` с необязательным `--header-scheme <Scheme>` и `--env-stdin <NAME>` (R8-5; design.md change `add-config-literal-secrets-and-migrate`, D11):
- значение SHALL читаться из stdin через `SecretInput`, как у `secret set` и `provider add --api-key-stdin` (с TTY — скрытый ввод, без TTY — поток без одного завершающего перевода строки); пустое, многострочное или не UTF-8 значение — ошибка значения с кодом `64`;
- значение SHALL сохраняться в хранилище секретов под `SecretNames.forMcp(<server>, <Name|NAME>)` (`codelab/mcp/<server>/<key>`), а в файл SHALL записываться значение `${secret:<имя>}` в `headers.<Name>` (с `--header-scheme S` — `S ${secret:<имя>}`) или в `env.<NAME>`; строка со ссылкой SHALL записываться в YAML в одинарных кавычках без экранирования `/` (`'Bearer ${secret:codelab/mcp/gh/x}'`; design.md, D5);
- на вызов допускается ровно один флаг `--header-stdin` или `--env-stdin`; два и больше — код `64` с `only one of --header-stdin, --env-stdin can be used per call`;
- `--header-stdin` при `--type stdio` — код `64` с `mcp add: --header-stdin is for --type http`; `--env-stdin` при `--type http` — код `64` с `mcp add: --env-stdin is for --type stdio`;
- `--header-scheme` без `--header-stdin` — код `64` с `mcp add: --header-scheme requires --header-stdin`; схема SHALL быть token по RFC 9110 (непустая, только буквы, цифры и ``!#%&'*+.^_`|~-``; `$` и пробелы не допускаются), иначе код `64` с текстом ``mcp add: --header-scheme must be a token of letters, digits and !#%&'*+.^_`|~- (RFC 9110)``;
- флаг `-stdin` с именем, уже заданным в том же вызове, — код `64`: `mcp add: --header-stdin name is also set by --header` (имена заголовков сравниваются без учёта регистра), `mcp add: --env-stdin name is also set by --env` (имена переменных сравниваются с учётом регистра, как в POSIX);
- имя в `--header-stdin`/`--env-stdin` с `literalSecretTag(Name) != null` — код `64` с текстом `mcp add: <флаг> expects a header or variable name, not a secret value`; имя НЕ SHALL печататься;
- порядок: кандидат конфига без записи; проверка коллизии имени секрета (ниже); `SecretAdmin.checkStore`; чтение stdin; сохранение секрета; одна атомарная запись. Коллизия SHALL проверяться раньше хранилища. Бэкенд только для чтения — код `1`, stdin не читается, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_<…>`; существующий собственный секрет этого сервера заменяется со строкой `warning: replaced the existing secret <имя>`; сбой записи конфига после сохранения — код `1`, stderr `the secret <имя> was stored; the config was not changed: <причина>`;
- коллизия, до чтения stdin и до хранилища, кодом `1`: целевое имя секрета упомянуто в загруженном конфиге другим сервером или провайдером (`${secret:<имя>}` или `api_key_secret`), или `forMcp` другого сервера конфига даёт то же имя (`GH`/`gh`, `my server`/`my-server`). Текст: `secret <имя> is already used by <ключ>; store the value with codelab secret set <another name> and reference it with --header/--env`; `<ключ>` — путь ссылки (`mcp.servers[GH].headers.Authorization`), а при совпадении только по `forMcp` — элемент сервера (`mcp.servers[GH]`);
- значение НЕ SHALL попадать в stdout, stderr, лог и argv; `--header Name='${…}'` и `--env K='${…}'` SHALL работать как прежде.

#### Scenario: Токен заголовка из stdin
- **WHEN** `secrets.backend: file`, вызывается `codelab-agent mcp add gh --type http --url https://h --header-stdin Authorization --header-scheme Bearer`, в stdin — `ghp-test-value-1\n`
- **THEN** код `0`; хранилище содержит `codelab/mcp/gh/authorization` со значением `ghp-test-value-1`; файл содержит `Authorization: 'Bearer ${secret:codelab/mcp/gh/authorization}'`; ни stdout, ни stderr не содержат значения

#### Scenario: Два флага stdin
- **WHEN** вызывается `mcp add gh --type stdio --command x --env-stdin A --env-stdin B`
- **THEN** код `64`, stdin не читается, файл и хранилище не изменены

#### Scenario: Бэкенд env
- **WHEN** `secrets.backend` не задан, вызывается `mcp add gh --type stdio --command x --env-stdin GITHUB_TOKEN`
- **THEN** код `1`, подсказка `secrets.backend: file` или `CODELAB_SECRET_CODELAB_MCP_GH_GITHUB_TOKEN`; stdin не читается; файл не изменён

#### Scenario: Имя секрета занято другим сервером
- **WHEN** конфиг содержит сервер `GH` со ссылкой `${secret:codelab/mcp/gh/authorization}`, вызывается `mcp add gh --type http --url https://h --header-stdin Authorization`
- **THEN** код `1`, stdin не читается, stderr — `secret codelab/mcp/gh/authorization is already used by mcp.servers[GH].headers.Authorization; store the value with codelab secret set <another name> and reference it with --header/--env`; файл и хранилище не изменены

#### Scenario: Имя секрета совпало по forMcp
- **WHEN** конфиг содержит сервер `GH` без ссылок на секреты, `secrets.backend` не задан (`env`), вызывается `mcp add gh --type http --url https://h --header-stdin Authorization`
- **THEN** код `1`, stderr — `secret codelab/mcp/gh/authorization is already used by mcp.servers[GH]; …` без подсказки про `secrets.backend`; stdin не читается; файл не изменён

#### Scenario: Флаг stdin не для этого типа
- **WHEN** вызывается `mcp add gh --type stdio --command x --header-stdin Authorization` или `mcp add gh --type http --url https://h --env-stdin TOKEN`
- **THEN** код `64` с `mcp add: --header-stdin is for --type http` или `mcp add: --env-stdin is for --type stdio`; stdin не читается, файл и хранилище не изменены

#### Scenario: Имя stdin повторяет --header
- **WHEN** вызывается `mcp add gh --type http --url https://h --header 'authorization=${X}' --header-stdin Authorization`
- **THEN** код `64` с `mcp add: --header-stdin name is also set by --header`; stdin не читается

#### Scenario: Имя заголовка похоже на токен
- **WHEN** вызывается `mcp add gh --type http --url https://h --header-stdin ghp_<36 символов>`
- **THEN** код `64`, stderr содержит `expects a header or variable name, not a secret value` и не содержит `ghp_`; stdin не читается

