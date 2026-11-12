## ADDED Requirements

### Requirement: Порт файлов навыков
Ядро SHALL объявлять порт `SkillFilesSource` с методом `loadSkills(SkillFilesQuery)` и необязательное поле `AgentCoreServices.skillFiles` (design.md change `add-agent-skills`, D1). Запрос: канонический `cwd` сессии, `projectTrusted` (тот же расчёт, что у файлов проекта: без раскрытого `realpath` проект недоверенный), элементы `skills.extra_roots` в порядке конфига, токен отмены. Результат `SkillFiles` содержит для каждого найденного `SKILL.md` сырой frontmatter, результат его разбора с позициями (`ConfigTree`) или ошибку разбора, признак `repaired` (разбор удался после починки; диагностику `yaml_repaired` по нему даёт ядро), тело, канонический каталог навыка, область (`ExtensionScope`), номер корня в порядке приоритета, относительные пути сопутствующих файлов с признаком неполного списка, и список `ExtensionDiagnostic`.

Реализация SHALL жить в `codelab_agent_io` (`ProjectFilesLoader` реализует оба порта). Порт НЕ SHALL бросать исключений для ошибок файлов. Рантайм SHALL вызывать порт при открытии и загрузке сессии отдельной фазой, параллельно с фазой файлов проекта, со своим таймаутом 5 с и общей отменой:
- отмена (`close()` сессии, `dispose()` рантайма) — сессия НЕ SHALL создаваться, результат выбрасывается;
- таймаут или непредвиденное исключение — сессия SHALL создаваться без навыков, с инструкциями проекта и шаблонами, лог `project_files.diagnostic` с `code: timeout` или `unexpected`; поздний результат в сессию НЕ SHALL попадать.

Без порта (`null`) или при выключенной capability `skills` порт НЕ SHALL вызываться, и сессия SHALL быть без навыков.

#### Scenario: Медленный корень не отнимает инструкции проекта
- **WHEN** фейковый `SkillFilesSource` не отвечает дольше таймаута, а `ProjectFilesSource` отдаёт `AGENTS.md` сразу
- **THEN** сессия создана, системный промпт содержит секцию `project_context` и не содержит секции `skills/catalog`, лог содержит `project_files.diagnostic` с `code: timeout`

#### Scenario: Отмена во время загрузки навыков
- **WHEN** `AgentRuntime.dispose()` вызывается, пока фейковый `SkillFilesSource` ещё не завершил `loadSkills`
- **THEN** `createSession` завершается отменой, сессия не создаётся, поздний результат выброшен

### Requirement: Корни навыков, приоритет и согласие
Загрузчик SHALL искать навыки — подкаталоги первого уровня с файлом `SKILL.md` — в корнях трёх уровней (design.md change `add-agent-skills`, D3; решения пользователя Q13, Q21, Q22):
1. **`project`** — только если проект доверенный. Уровни каталогов от канонического `cwd` вверх до корня git-репозитория (поиск корня — как у инструкций проекта, capability `agent-project-context`, «Поиск инструкций проекта»; без репозитория — только `cwd`); на каждом уровне — `<уровень>/.codelab/skills`, затем `<уровень>/.agents/skills`. Ближний к `cwd` уровень SHALL перекрывать дальний. У недоверенного проекта каждый существующий корень даёт одну диагностику `info` `untrusted_project` и не читается.
2. **`user`** — `$CODELAB_HOME/skills`, затем `~/.agents/skills` (домашний каталог пользователя процесса агента).
3. **`extra`** — элементы `skills.extra_roots` по порядку; абсолютный путь — как есть, относительный — от `cwd` и только для доверенного проекта, иначе `warning` `untrusted_project`.

Диагностика `untrusted_project` SHALL иметь два уровня, и это осознанно: у корней проекта — `info` (ожидаемое состояние недоверенного репозитория; `config check` печатает его строкой `note:`), у относительного элемента `skills.extra_roots` — `warning` (пользователь явно задал корень, который в этом проекте не действует, — это ошибка настройки).

Каталоги конкретных агентов (`.claude/skills`, `~/.codex/skills` и подобные) загрузчик НЕ SHALL обходить, если пути нет в `skills.extra_roots`. Каталоги на `.`, файл `SKILL.md` прямо в корне и записи корня, не являющиеся каталогами, SHALL пропускаться без диагностики. Подкаталогов в одном корне читается не больше 1000 (лишние — `warning` `limit_exceeded`).

Порядок приоритета — порядок корней выше. Навык с именем, уже загруженным из корня выше, SHALL пропускаться с диагностикой `warning` `shadowed`, называющей оба пути, — и между уровнями, и внутри уровня; внутри одного корня побеждает первый каталог в байтовом порядке имён.

Граница чтения SHALL быть двухступенчатой (design.md change `add-agent-project-files`, D2): каталог корня раскрывается `realpath`; каталог навыка, чей `realpath` вне корня, пропускается с `outside_root`; `SKILL.md` и перечисление файлов идут через `BoundedEnv` с корнем в реальном пути каталога навыка. Чтение SHALL идти с файловой системы процесса агента, а не через env сессии ACP.

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, а `<cwd>/.codelab/skills/review/SKILL.md` и `<cwd>/.agents/skills/pdf/SKILL.md` существуют
- **THEN** навыков `review` и `pdf` нет; есть две диагностики `untrusted_project`

#### Scenario: .agents/skills без отдельного согласия
- **WHEN** проект доверенный, `<cwd>/.agents/skills/pdf/SKILL.md` и `~/.agents/skills/notes/SKILL.md` валидны, `skills.extra_roots` пуст
- **THEN** загружены `pdf` (область `project`) и `notes` (область `user`)

#### Scenario: .claude/skills только с согласия
- **WHEN** проект доверенный, `<cwd>/.claude/skills/lint/SKILL.md` существует; во втором варианте глобальный конфиг задаёт `skills.extra_roots: [".claude/skills"]`
- **THEN** в первом варианте навыка `lint` нет и файл не читался, во втором — `lint` загружен с областью `extra`; во втором варианте `<cwd>/.claude/skills/**` — путь конфигурации агента этой сессии (PERM-11, решение Q27): `write` туда критический

#### Scenario: Ближний уровень проекта перекрывает дальний
- **WHEN** `/repo` — корень git, проект `/repo/pkg` доверенный, навык `release` есть в `/repo/.codelab/skills` и в `/repo/pkg/.agents/skills`
- **THEN** загружен навык из `/repo/pkg/.agents/skills`, у `/repo/.codelab/skills/release` — `warning` `shadowed` с обоими путями

#### Scenario: Проект перекрывает пользователя с предупреждением
- **WHEN** навык `release-notes` есть в `<cwd>/.codelab/skills` доверенного проекта и в `$CODELAB_HOME/skills`
- **THEN** загружен проектный, у пользовательского — `warning` `shadowed`, строка видна в `config check`

#### Scenario: Symlink каталога навыка наружу
- **WHEN** `$CODELAB_HOME/skills/evil` — symlink на `/etc`
- **THEN** навыка `evil` нет, диагностика `outside_root` с путём

### Requirement: Формат SKILL.md и мягкая проверка
`SKILL.md` SHALL содержать YAML-frontmatter между строками `---` и тело. Проверка SHALL быть одинаково мягкой во всех корнях: навык загружается, если это возможно, а нарушения дают предупреждения (design.md change `add-agent-skills`, D4; решения пользователя Q11, Q14, Q20; руководство Agent Skills, «Lenient validation»).

**Разбор.** Frontmatter разбирается в строгом профиле CFG-21. Если разбор не удался, хост SHALL один раз переписать строки верхнего уровня `ключ: значение` со значением без кавычек, содержащим `: `, в строки в одинарных кавычках YAML с удвоением `'` внутри значения (одинарные кавычки не обрабатывают `\`, поэтому `C:\temp` и `"` сохраняются как есть) и разобрать снова: успех — `warning` `yaml_repaired`; неуспех — `error` (`syntax` или `profile`, со строкой и столбцом), навык пропущен.

**Пропуск навыка** — только в случаях:
- frontmatter нет или он не разобран и после починки;
- `description` отсутствует или пусто после схлопывания пробельных последовательностей и удаления `\r` (`error` `missing_description`);
- имя нельзя сделать командой: не соответствует `^[A-Za-z0-9][A-Za-z0-9_-]*$` или длиннее 128 символов (`error` `invalid_name`; текст называет допустимые символы — латинские буквы, цифры, `-`, `_`);
- тело больше 64 КиБ (`too_large`), файл `SKILL.md` больше 128 КиБ (не читается, `too_large`), файл не в UTF-8 (`not_utf8`).

**Предупреждения, навык загружается:**
- `name` не по правилу спецификации Agent Skills (`^[a-z0-9]+(-[a-z0-9]+)*$`, не длиннее 64) — `warning` `invalid_name`;
- `name` не совпадает с именем каталога — `warning` `name_mismatch`, навык загружается под именем из `name`;
- `name` нет — `warning` `missing_name`, имя — имя каталога;
- `description` длиннее 1024 символов — `warning`;
- `argument-hint` (1–80), `user-invocable`, `disable-model-invocation` (bool) неверного типа или длины — `warning`, поле по умолчанию (`user-invocable: true`, `disable-model-invocation: false`, без подсказки);
- `compatibility` длиннее 500 символов — `warning`, значение обрезается до 500; пустое (`""` или только пробелы) — `warning`, поле считается отсутствующим и атрибута в блоке нет;
- закреплённые строки K-06 SHALL читаться из `metadata.codelab-operative` (решение Q32): значение — строка, каждая непустая строка после обрезки пробелов — одно правило, не больше 16 правил по 1–512 символов; нестроковое значение или нарушение пределов — `warning`, правил нет; непустой список — `info` `not_applied`. Поле верхнего уровня `operative` — неизвестный ключ (`warning` `unknown_key`);
- неизвестный ключ — `warning` `unknown_key`;
- пустое тело — `warning` `empty_body`.

**Обрезка тела.** Тело SHALL быть текстом после закрывающей строки `---` frontmatter с удалёнными пробельными символами в начале и в конце; `\r\n` внутри SHALL нормализоваться в `\n`. От этой формы считаются `empty_body`, предел 64 КиБ, отпечаток SHA-256 и сравнение содержимого при повторе.

Известные поля спецификации `license`, `compatibility`, `metadata`, `allowed-tools` SHALL приниматься без диагностики. `allowed-tools` НЕ SHALL применяться и НЕ SHALL расширять права (Q14). Ошибка навыка НЕ SHALL прерывать создание сессии. Сообщения диагностик SHALL быть фиксированными текстами кодов без фрагментов файла.

#### Scenario: Двоеточие без кавычек
- **WHEN** frontmatter содержит `description: Use this skill when: the user asks about PDFs`
- **THEN** навык загружен с этим описанием, есть `warning` `yaml_repaired`

#### Scenario: Починка сохраняет обратную косую и кавычки
- **WHEN** frontmatter содержит `description: Use when: files are under C:\temp and named "it's"`
- **THEN** навык загружен с описанием `Use when: files are under C:\temp and named "it's"` — без изменений символов; есть `warning` `yaml_repaired`

#### Scenario: Совсем нечитаемый YAML
- **WHEN** frontmatter содержит незакрытую скобку потока `tags: [a, b`
- **THEN** навык пропущен, диагностика `error` со строкой и столбцом

#### Scenario: Свой корень, мягкая проверка
- **WHEN** `$CODELAB_HOME/skills/notes/SKILL.md` содержит ключ `color` в строке 4 и `name: notes-`
- **THEN** навык `notes-` загружен; есть `warning` `unknown_key` со строкой 4, `warning` `invalid_name` и `warning` `name_mismatch`

#### Scenario: Известные поля без диагностики
- **WHEN** навык задаёт `license`, `metadata` и `allowed-tools: Bash(git:*) Read`
- **THEN** навык загружен, диагностик по этим полям нет, политика разрешений не меняется

#### Scenario: Закреплённые строки в metadata
- **WHEN** frontmatter содержит `metadata:` с ключом `codelab-operative: |` и двумя непустыми строками `Never invent PR numbers.` и `Write in English.` между ними — пустая строка
- **THEN** навык загружен, `SkillDefinition.operative` — два правила в порядке строк, есть `info` `not_applied`; системный промпт этих строк не содержит

#### Scenario: Без описания
- **WHEN** у навыка нет `description`
- **THEN** навык пропущен, диагностика `error` `missing_description`

#### Scenario: Нелатинское имя
- **WHEN** `name: отчёт`
- **THEN** навык пропущен, диагностика `error` `invalid_name` называет допустимые символы

#### Scenario: Длинное описание
- **WHEN** у навыка описание из 1500 символов
- **THEN** навык загружен, есть `warning` о длине описания; в секции каталога описание обрезано до 1024 символов с `…`

#### Scenario: Большое тело
- **WHEN** тело навыка — 50 КиБ, во втором варианте — 70 КиБ
- **THEN** в первом варианте навык загружен, во втором — пропущен с `too_large`

#### Scenario: Пустое тело
- **WHEN** у навыка есть `name` и `description`, а тело пустое
- **THEN** навык загружен, есть `warning` `empty_body`

### Requirement: Каталог навыков сессии
Ядро SHALL строить неизменяемый снимок `SkillCatalog` чистой функцией из результата порта, конфигурации и правил разрешений (design.md change `add-agent-skills`, D2):
- имя из `skills.disabled` — `info`, навык пропущен;
- навыки сверх `skills.max_skills` в порядке приоритета — отброшены, `warning` `limit_exceeded`;
- навыки SHALL быть упорядочены по имени (байтово).

`modelVisible` — навыки без `disable-model-invocation`, которым политика разрешений не запрещает инструмент `skill` с этим именем (`permissions.tools.skill: deny` или правило `permissions.deny` `skill:<name>`); команды — навыки с `user-invocable`. Каталог живой сессии НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации; все потребители (секция промпта, инструмент `skill`, команды, повторное приложение после сжатия) SHALL читать один снимок сессии.

#### Scenario: Отключённый навык
- **WHEN** конфиг задаёт `skills.disabled: [pdf]`, а навык `pdf` валиден
- **THEN** навыка `pdf` нет ни в каталоге, ни в командах

#### Scenario: Навык, запрещённый правилом
- **WHEN** `permissions.deny` содержит `skill:pdf`
- **THEN** `pdf` нет ни в секции каталога, ни в `enum` схемы `skill`; команда `skill:pdf` есть

### Requirement: Секция каталога в системном промпте
Если capability `skills` включена и `modelVisible` не пуст, системный промпт SHALL содержать секцию `skills/catalog` (`prompts/skills/catalog.md`, `vars: [entries]`, `tools: [skill]`) на шаге 9a — после `mcp`, до `project_context` (design.md change `add-agent-skills`, D6; решение Q18). Текст секции — английский, написан для CodeLab: что такое навыки, когда вызывать инструмент `skill`, что пути внутри навыка относительны его каталога, и что инструкции навыка не отменяют правил безопасности и решений пользователя. Строки `entries`:
1. для каждого навыка по имени — `- <name>: <description>`, описание целиком; описание длиннее 1024 символов SHALL обрезаться до 1024 символов с `…` (предупреждение — при загрузке);
2. если сумма длин строк с переводами больше `skills.catalog_max_chars`, описания SHALL укорачиваться поровну: короткие описания остаются целыми, а одинаковая доля остатка бюджета делится между длинными, каждое режется по границе символа с `…`; лог `skills.catalog.truncated` (warning);
3. если не помещаются и строки без описаний — с конца удаляются строки, последняя строка — `[<N> more skills not listed]`.

В секции НЕ SHALL быть путей, дат и счётчиков, кроме строки об опущенных навыках; одинаковый снимок SHALL давать побайтово одинаковую секцию (SKL-4, PR-3). Без навыков `modelVisible` секции и инструмента нет (SKL-5).

#### Scenario: Golden секции
- **WHEN** промпт собирается с навыками `flutter-golden` и `release-notes`
- **THEN** результат совпадает с `test/prompts/golden/agent-serve-standard-skills.txt`, секция стоит после `mcp` и до `project_context`

#### Scenario: Описание целиком
- **WHEN** у единственного навыка описание из 900 символов, бюджет по умолчанию
- **THEN** строка содержит описание целиком, предупреждения нет

#### Scenario: Описания делятся поровну
- **WHEN** 40 навыков с описаниями по 1000 символов, один — с описанием из 50 символов, `catalog_max_chars: 8000`
- **THEN** длина `entries` не больше 8000, короткое описание целое, длинные укорочены до одинаковой длины с `…`, одна запись `skills.catalog.truncated`

#### Scenario: Навык только для команды
- **WHEN** единственный навык имеет `disable-model-invocation: true`
- **THEN** секции `skills/catalog` и схемы инструмента `skill` нет, команда `skill:<name>` есть

### Requirement: Блок навыка
Тело навыка SHALL передаваться модели блоком (design.md change `add-agent-skills`, D7; решения Q4, Q5, Q19, Q23, Q26): строка `<skill name="<name>" dir="<dir>"[ compatibility="<compatibility>"]>`, тело без frontmatter, `</skill>`, затем **всегда** строка о путях — одна для любого режима исполнения (решение Q26): `This skill's own files (scripts, references, assets and files named in its instructions) are relative to its directory; task data is relative to the project. In tool calls, refer to the skill's files by absolute path, and run its scripts with the project as the working directory.`; затем, если есть сопутствующие файлы, по строке `- <dir>/<file>`; если список неполон — последняя строка `[more files not listed]`. Экранирование:
- в теле каждый открывающий или закрывающий тег `skill` (`<`, необязательные пробелы, необязательный `/`, необязательные пробелы, `skill`, без учёта регистра ASCII) SHALL получать `\` сразу после `<`;
- в значениях атрибутов `"`, `<`, `>`, `\r`, `\n` SHALL заменяться на `_`.

#### Scenario: Тело не закрывает свой блок
- **WHEN** тело навыка содержит `</skill>` и `< / SKILL>`
- **THEN** в блоке они выглядят как `<\/skill>` и `<\ / SKILL>`, блок закрывается один раз

#### Scenario: compatibility в блоке
- **WHEN** навык задаёт `compatibility: Requires python3 and network access`
- **THEN** открывающий тег блока содержит атрибут `compatibility="Requires python3 and network access"`

#### Scenario: Строка о путях
- **WHEN** навык с `scripts/x.py` загружен в сессии встроенного агента, во втором варианте — в сессии `serve --stdio`, где команды исполняет клиент ACP, в третьем — навык без сопутствующих файлов
- **THEN** во всех трёх блоках после `</skill>` стоит одна и та же строка `This skill's own files (scripts, references, assets and files named in its instructions) are relative to its directory; task data is relative to the project. In tool calls, refer to the skill's files by absolute path, and run its scripts with the project as the working directory.`

#### Scenario: Неполный список файлов
- **WHEN** в каталоге навыка 60 файлов
- **THEN** блок перечисляет 50 файлов и заканчивается строкой `[more files not listed]`

### Requirement: Инструмент skill
Инструмент `skill` SHALL регистрироваться, только если capability `skills` включена и `modelVisible` не пуст (design.md change `add-agent-skills`, D7; решение Q12): уровень `read`, вид `read`, исполнение `parallel`, `permissionPattern` — имя навыка, `present` — заголовок `Load skill <name>` и `locations` `[<dir>/SKILL.md]`. Схема — объект с единственным обязательным полем `name` типа `string` с `enum` из имён `modelVisible` в байтовом порядке, без `additionalProperties`. Описание — `prompts/tool_descriptions/skill.md`.

Успех — блок навыка (требование «Блок навыка») из снимка: файл НЕ SHALL перечитываться. `outputTrust` — `trusted`. Повторная активация активного навыка — требование «Повторная активация». Ошибка (`isError: true`) — имени нет среди `modelVisible` (провайдер мог не соблюсти `enum`): `Unknown skill: <name>. Available skills: <a>, <b>.` (`<name>` обрезан до 64 символов по рунам).

#### Scenario: Загрузка тела моделью
- **WHEN** модель вызывает `skill` с `{"name":"release-notes"}`, у навыка есть `template.md`
- **THEN** результат — блок `<skill name="release-notes" dir="…">` с телом и строкой `- <dir>/template.md`, лог `skill.activated` с `via: tool`, `repeated: false` (`core/skill-tool-load-body`, SKL-3)

#### Scenario: Имена в схеме
- **WHEN** у сессии навыки `b-skill`, `a-skill` и `hidden` с `disable-model-invocation: true`
- **THEN** `enum` схемы — `["a-skill", "b-skill"]`

#### Scenario: Имя вне каталога
- **WHEN** модель вызывает `skill` с именем `hidden`
- **THEN** результат — ошибка `Unknown skill: hidden. Available skills: a-skill, b-skill.` без тела

### Requirement: Команды навыков
Для каждого навыка с `user-invocable` `AgentSession.commands` SHALL содержать команду `skill:<name>` с `description` навыка и `inputHint` — `argument-hint`, иначе `"arguments"`; источник — `SlashCommandSource.skill` (порядок — требование «Список команд сессии» capability `agent-slash-commands`).

Если первый текстовый блок промпта — команда (тот же разбор строки, что у шаблонов), а слово начинается с `skill:` и capability `skills` включена:
- навык есть и `user-invocable` — тело навыка с подставленными аргументами (та же функция подстановки, что у шаблонов: capability `agent-slash-commands`, «Разворачивание команды») SHALL оборачиваться промптом `prompts/skills/invoked.md` (`vars: [name, block]`, блок — требование «Блок навыка») и заменять этот блок промпта сообщением пользователя; остальные блоки идут после него; модель получает ход. Повтор активного навыка — требование «Повторная активация»;
- навыка нет или `user-invocable: false` — без модели одним сообщением агента `Unknown skill: <name>. Run /help to list commands.` (`<name>` обрезан до 64 символов по рунам), `TurnEnded` с `endTurn`, журнал не пишется.

При выключенной capability `skills` слово `skill:<x>` — неизвестная команда (`Unknown command`). `/help` SHALL помечать команды навыков суффиксом ` (skill)`. Лог — `command.expanded {name, source: "skill", args_bytes}` и `skill.activated {via: "command"}`; аргументы и тело в лог НЕ SHALL попадать.

#### Scenario: Вызов навыка пользователем
- **WHEN** приходит `/skill:release-notes v1.2 v1.3`, тело навыка — `Collect the changes between $1 and $2.`
- **THEN** модель получает сообщение пользователя с блоком навыка, содержащим `Collect the changes between v1.2 and v1.3.` (`acp/skill-invoke`)

#### Scenario: Тело без плейсхолдеров
- **WHEN** тело навыка не содержит плейсхолдеров, и приходит `/skill:notes draft`
- **THEN** сообщение пользователя заканчивается строкой `ARGUMENTS: draft`

#### Scenario: Неизвестный навык
- **WHEN** приходит `/skill:nope x`
- **THEN** модель не вызвана, ответ — ровно `Unknown skill: nope. Run /help to list commands.`, журнал без новых записей

#### Scenario: Навык без команды
- **WHEN** у навыка `user-invocable: false`
- **THEN** команды `skill:<name>` нет в списке, `/skill:<name>` отвечает `Unknown skill: <name>. Run /help to list commands.`, а инструмент `skill` его отдаёт

#### Scenario: Навыки выключены
- **WHEN** конфиг задаёт `skills.enabled: false`, и приходит `/skill:release-notes`
- **THEN** ответ — `Unknown command: /skill:release-notes. Run /help to list commands.`; команд `skill:*`, секции каталога и инструмента `skill` нет (SKL-5)

### Requirement: Активные навыки
Ядро SHALL иметь одну чистую функцию `activeSkills(SessionSnapshot snapshot, SkillCatalog catalog, SkillsConfig settings) → List<ActiveSkill>` — для повторной активации, приложения после сжатия и будущих закреплённых строк (K-06) (design.md change `add-agent-skills`, D15; решения Q6, Q10). Она возвращает список `ActiveSkill {name, full, content}` от новой активации к старой; `content` — SHA-256 содержимого активации: для инструмента `skill` и приложения после сжатия — обрезанного тела навыка, для команды `/skill:` — тела после подстановки её аргументов (`command.args` записи) без хвоста `ARGUMENTS:`:
1. `last` — последняя запись `compaction` на активной ветке (или нет);
2. навыки из `last.skills`, которые приложение после этой записи (capability `agent-compaction`, «Навыки после сжатия») приложило целиком (`full: true`) или усечённым (`full: false`); выпавшие по общему бюджету и отсутствующие в каталоге не входят;
3. активации на активной ветке после `last.firstKeptId` (или на всём пути без сжатий) дают `full: true` и ставят навык в начало; активация — сообщение пользователя с `command.source == "skill"` или успешный результат инструмента `skill` с блоком навыка (не строка повтора);
4. более новая запись о навыке заменяет более старую.

Шаг 2 зависит только от `last`, каталога и бюджетов, поэтому определение не замкнуто. Навык **активен** (для повторной активации) — если входит в результат с `full: true`. Чтение `SKILL.md` инструментом `read` активацией НЕ SHALL считаться. Новых видов записей журнала функция НЕ SHALL требовать.

#### Scenario: Активация ушла в резюме и приложена
- **WHEN** навык активирован, затем сжатие убрало активацию в резюме и приложило навык целиком
- **THEN** навык активен

#### Scenario: Приложен усечённым
- **WHEN** тело навыка больше `skills.reattach.per_skill_tokens`, и после сжатия оно приложено усечённым
- **THEN** навык не активен: повторный вызов `skill` возвращает полный блок

### Requirement: Повторная активация
Повторная активация активного навыка НЕ SHALL вставлять тело второй раз (design.md change `add-agent-skills`, D7, D8; решение Q10; руководство Agent Skills, «Deduplicate activations»):
- инструмент `skill` SHALL возвращать одну строку `Skill "<name>" is already loaded in this conversation; follow the instructions above.` с `isError: false`;
- команда `/skill:<name> <args>`: если навык активен и SHA-256 тела после подстановки этих аргументов (без хвоста `ARGUMENTS:`) равен `ActiveSkill.content`, сообщение пользователя SHALL быть строкой `The user invoked the skill "<name>" again; its instructions are already loaded above.` и, при непустом вводе, строкой `ARGUMENTS: <ввод>`; если отличается (плейсхолдеры с другими аргументами) — полный блок. Навык, загруженный моделью или приложенный после сжатия целиком, имеет `content` необработанного тела: `/skill:<name>` для тела без плейсхолдеров даёт строку повтора, для тела с плейсхолдерами — полный блок.

Лог — `skill.activated` с `repeated: true`.

#### Scenario: Модель загружает навык дважды
- **WHEN** модель вызывает `skill` с `release-notes` дважды в одной сессии без сжатия
- **THEN** второй результат — строка `Skill "release-notes" is already loaded in this conversation; follow the instructions above.`, тело во втором результате отсутствует

#### Scenario: Модель загрузила, пользователь вызвал
- **WHEN** модель загрузила навык `notes` (тело без плейсхолдеров), затем приходит `/skill:notes draft`
- **THEN** сообщение пользователя — строка повтора и `ARGUMENTS: draft`

#### Scenario: Повтор команды с другими аргументами
- **WHEN** тело навыка содержит `$1`, приходят `/skill:release-notes v1.2`, затем `/skill:release-notes v1.3`
- **THEN** второе сообщение — полный блок с `v1.3`; при повторе `/skill:release-notes v1.2` — короткая строка повтора

### Requirement: Сопутствующие файлы и скрипты навыка
Загрузчик SHALL перечислять сопутствующие файлы каталога навыка: обычные файлы на глубине до 3 уровней, не больше 50 путей в байтовом порядке (больше — признак неполного списка), без каталогов на `.`, без каталога `evals/` (тестовые запросы автора навыка, а не инструкции; `skill-creation/04-evaluating-skills.md`), без `SKILL.md` и без записей, чей `realpath` вне каталога навыка; содержимое при этом НЕ SHALL читаться.

Хост с файловой системой процесса агента (`AgentCoreServices.hostFiles`) SHALL получать для env сессии корни только для чтения — канонические каталоги загруженных навыков вне рабочей папки (capability `agent-execution-env`, «Корни только для чтения»). Модель читает файлы обычными `read` и `ls` с обычной политикой разрешений. Вывод `read` файла внутри каталога загруженного навыка, кроме подкаталога `evals/`, SHALL иметь доверие `trusted`, как тело `SKILL.md` (решение Q30): он НЕ SHALL огораживаться как недоверенный, даже если путь содержит сегменты `node_modules`, `.dart_tool` или `vendor`, а теги `skill` в нём SHALL экранироваться так же, как в теле (требование «Блок навыка»). Правило «не отменяет безопасность и не даёт прав» действует; доверие вывода других путей и `exec` не меняется. Запись в такой каталог инструментами `write` и `edit` SHALL отклоняться (`outsideWorkspace`); правка навыка внутри рабочей папки (`.codelab/skills/**`, `.agents/skills/**`) — критическая по PERM-11.

Скрипты навыка агент НЕ SHALL исполнять сам: только инструментом `exec` по политике разрешений (уровень `exec`). `exec` МОЖЕТ получать `cwd` в каталоге загруженного навыка (решение Q17; `docs/protocols/agent-skills/skill-creation/05-using-scripts.md`: команды навыка выполняются из его каталога), если env сессии исполняет команды на машине агента; если команды исполняет клиент ACP (`terminal/create`), такой `cwd` SHALL отклоняться инструментом `exec` до вызова env и до запроса клиенту — он видит, что `cwd` лежит в `readOnlyRoots` сессии, а env не исполняет там команды (`execInReadOnlyRoots == false`), — ошибкой инструмента `The working directory <dir> is outside the client workspace; run the skill script by its absolute path from the skill block, with the workspace as the working directory.` (решение Q23 (а); аналог `${CLAUDE_SKILL_DIR}` в Claude Code). Containment клиента не меняется: агент не отправляет клиенту `cwd` вне рабочей папки и не переписывает команду. Запись через `exec` в каталог навыка ловит PERM-11; критичность снимают только узкие исключения E1–E3 capability `agent-permissions` (решения Q24, Q25, Q29, Q33–Q38): скрипт под `<dir>/scripts/` без опций интерпретатора и без переменных окружения, рабочий каталог навыка — только для такого скрипта или команды белого списка чтения, ресурс под `<dir>/assets/` без `.md` аргументом скрипта того же навыка. `cwd` в каталоге навыка при локальном исполнении разрешён (Q17), но блок навыка советует запускать скрипты по абсолютному пути с рабочей папкой проекта (Q26).

#### Scenario: Чтение файла пользовательского навыка
- **WHEN** сессия ACP-хоста (`cwd` `/work/demo`) загрузила навык из `$CODELAB_HOME/skills/release-notes`, и модель вызывает `read` с `<home>/skills/release-notes/template.md`
- **THEN** вызов проходит политику как `read`, содержимое приходит из файловой системы агента, клиенту `fs/read_text_file` не отправляется

#### Scenario: Справочник навыка — инструкция, а не данные
- **WHEN** модель читает `read` файл `<home>/.codelab/skills/pdf/references/vendor/FORMS.md`, содержащий `</skill>`
- **THEN** вывод не огорожен `<untrusted-content>`, а `</skill>` в нём выглядит как `<\/skill>`

#### Scenario: Запись в каталог навыка
- **WHEN** модель вызывает `write` с путём внутри каталога навыка из `$CODELAB_HOME/skills`
- **THEN** результат — ошибка `Path is outside the workspace: <path>`, файл не изменён

#### Scenario: Скрипт навыка во встроенном агенте
- **WHEN** во встроенном агенте (env сессии локальный) модель вызывает `exec` с `python3 scripts/extract.py /work/demo/a.pdf` и `cwd` — каталог пользовательского навыка
- **THEN** вызов спрашивается как обычный `exec` (с вариантом `allow_always`), после одобрения процесс запускается в каталоге навыка

#### Scenario: Скрипт пользовательского навыка через клиента ACP
- **WHEN** env сессии — клиент ACP, модель вызывает `exec` с `cwd` в `$CODELAB_HOME/skills/release-notes`
- **THEN** `terminal/create` не отправляется, результат — ошибка инструмента с текстом `The working directory <dir> is outside the client workspace; run the skill script by its absolute path from the skill block, with the workspace as the working directory.`; повторный вызов `exec` с `python3 <dir>/scripts/x.py` и `cwd` рабочей папки спрашивается как обычный `exec` (с `allow_always`, без критического шаблона — решение Q25) и после одобрения уходит клиенту `terminal/create` с `cwd` рабочей папки

#### Scenario: Скрипт по абсолютному пути при локальном исполнении
- **WHEN** во встроенном агенте в режиме `bypass` модель вызывает `exec` с `python3 <home>/.codelab/skills/release-notes/scripts/x.py` и `cwd` рабочей папки
- **THEN** вызов выполняется без вопроса (обычная политика `bypass`), критического шаблона нет; с `> <home>/.codelab/skills/release-notes/out.md` в той же команде — критический шаблон

#### Scenario: Скрипт навыка проекта через клиента ACP
- **WHEN** env сессии — клиент ACP, модель вызывает `exec` с `cwd` `<cwd>/.codelab/skills/pdf` доверенного проекта
- **THEN** после одобрения клиенту отправляется `terminal/create` с этим `cwd` (он внутри рабочей папки сессии) (`acp/skill-script-exec`)

### Requirement: Конфигурация навыков
Раздел `skills` SHALL иметь ключи с потребителем (design.md change `add-agent-skills`, D11):
- `enabled` (bool, `true`) — `false` сужает capability `skills` до `off`;
- `extra_roots` (список путей, `[]`) — элемент со схемой `<scheme>://` SHALL быть проблемой `value` (`URI schemes are not supported in skills.extra_roots`);
- `disabled` (список имён, `[]`);
- `max_skills` (int, `200`, 1–1000);
- `catalog_max_chars` (int, `8000`, 1000–64000);
- `reattach.per_skill_tokens` (int, `5000`, 0–16384) и `reattach.total_tokens` (int, `25000`, 0–200000) — бюджеты повторного приложения после сжатия; `0` в любом из них выключает приложение.

Подраздел `skills.operative` SHALL оставаться без потребителя: каждый явно заданный лист — `config.key.not_applied`.

Доверие проектным слоям: `skills.enabled: false`, `skills.disabled`, уменьшение числовых ключей SHALL применяться из любого слоя; увеличение из проектного слоя — отброшено с `config.project.untrusted_key`; `skills.extra_roots` из `<cwd>/.codelab/config.yaml` SHALL отбрасываться всегда, из `<cwd>/.codelab/config.local.yaml` — если проект не доверенный; оба — с `config.project.untrusted_key`. В реестре настроек ключи `skills.*` SHALL быть `fileOnly`. Новые значения после перезагрузки конфигурации SHALL действовать на сессии, открытые после неё.

#### Scenario: Проект не даёт согласия
- **WHEN** доверенный проект задаёт `skills.extra_roots: ["~/.claude/skills"]` в `.codelab/config.yaml`
- **THEN** ключ отброшен с `config.project.untrusted_key`, каталог не читается

#### Scenario: Схема зарезервирована
- **WHEN** глобальный конфиг задаёт `skills.extra_roots: ["builtin://pdf"]`
- **THEN** проблема `value` с ключом `skills.extra_roots[0]`, `CoreConfig` не построен

#### Scenario: operative без потребителя
- **WHEN** глобальный конфиг задаёт `skills.operative.lines: ["Run tests."]` и `skills.max_skills: 50`
- **THEN** одно предупреждение `config.key.not_applied` для `skills.operative.lines`; `max_skills` применён без предупреждения

### Requirement: Навыки в хостах
`codelab-agent serve --stdio` и открыватели встроенного агента `codelab_embedded` SHALL передавать ядру `skillFiles` и `hostFiles` (файловую систему процесса агента). Пользовательский уровень — `$CODELAB_HOME` и домашний каталог процесса.

`codelab-agent serve --ws` НЕ SHALL передавать `skillFiles`: по WebSocket навыки не читаются по той же причине, что файлы проекта (agent-binary «Файлы проекта в бинаре»). С `--llm-script` пользовательский уровень (`$CODELAB_HOME/skills`, `~/.agents/skills`) НЕ SHALL читаться, проект — недоверенный, а абсолютные элементы `skills.extra_roots` из `--config` SHALL читаться.

#### Scenario: Навык пользователя по stdio
- **WHEN** `AgentHost.build` для `--stdio` получает временный `CODELAB_HOME` с `skills/release-notes/SKILL.md` и создаёт сессию
- **THEN** `session.commands` содержит `skill:release-notes`, системный промпт содержит секцию каталога

#### Scenario: WebSocket без навыков
- **WHEN** `AgentHost.build` для `--ws` получает тот же `CODELAB_HOME`
- **THEN** `AgentCoreServices.skillFiles` равен `null`, команд `skill:*` и секции каталога нет

### Requirement: Наблюдаемость навыков
Диагностики навыков SHALL писаться событием `project_files.diagnostic` (путь, строка, столбец, код, фиксированный текст) и печататься `config check`. События:
- `skills.loaded {session_id, count, names, project}` (info) после загрузки;
- `skills.catalog.truncated {session_id, shortened, omitted}` (warning);
- `skill.activated {session_id, name, via, repeated}` (info), `via` — `tool` или `command`;
- `skills.reattached {session_id, names, dropped, truncated}` (info) и `skills.reattach.changed {session_id, name}` (warning) — capability `agent-compaction`, «Навыки после сжатия».

Тело навыка, описание, аргументы команды и содержимое сопутствующих файлов НЕ SHALL попадать в логи.

#### Scenario: Лог без тела
- **WHEN** модель загружает навык, тело которого содержит строку `secret-token-123`, а пользователь вызывает `/skill:release-notes secret-arg`
- **THEN** логи содержат `skill.activated` с `via: tool` и `via: command`, `command.expanded` с `args_bytes`, и не содержат `secret-token-123` и `secret-arg`

### Requirement: Резервы для встроенных навыков, перечитывания и закреплённых строк
Этот change НЕ SHALL реализовывать встроенные навыки и указатели (E-18), перечитывание каталога без перезапуска (E-19), секцию закреплённых строк (K-06) и выполнение навыка в субагенте, но SHALL оставлять для первых трёх точки расширения (design.md change `add-agent-skills`, D10):
- приоритет корней SHALL задаваться порядком списка корней загрузчика; записи корня, не являющиеся каталогами, SHALL пропускаться молча;
- элемент `skills.extra_roots` со схемой `<scheme>://` SHALL быть проблемой конфига;
- правила `metadata.codelab-operative` SHALL проверяться и храниться в `SkillDefinition.operative`, но не применяться;
- активные навыки SHALL определяться одной функцией (требование «Активные навыки»), выводимой из журнала без новых видов записей.

#### Scenario: Будущий указатель не ломает загрузку
- **WHEN** в `$CODELAB_HOME/skills` лежат файл `pdf.link` и каталог `notes` с валидным `SKILL.md`
- **THEN** навык `notes` загружен, о `pdf.link` диагностики нет
