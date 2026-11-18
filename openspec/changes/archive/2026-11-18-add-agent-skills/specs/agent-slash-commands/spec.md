## MODIFIED Requirements

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требования «Встроенные команды MVP» и «Встроенные команды config и mcp») в порядке §13.4 — `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help`; отсутствующая команда пропускается, порядок остальных не меняется (design.md change `add-agent-builtin-slash-commands`, D2), — затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён, затем команды навыков `skill:<name>` (`source: skill`) для навыков с `user-invocable` в байтовом порядке имён навыков (capability `agent-skills`, «Команды навыков»; design.md change `add-agent-skills`, D8). `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`; `inputHint` навыка — `argument-hint`, иначе `"arguments"`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9). Инструменты модели, в том числе `skill`, в список НЕ SHALL попадать (R-07, SKL-6).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource`, capability `compaction` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help`, `review`

#### Scenario: Без capability compaction и без конфига
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, шаблонов нет
- **THEN** список — `mode`, `model`, `status`, `help`

#### Scenario: Перезагрузка не меняет список
- **WHEN** после открытия сессии перезагрузка добавляет проект в `trusted_projects`, и у проекта есть `.codelab/prompts/fix.md`
- **THEN** список живой сессии не изменился; новая сессия того же `cwd` тоже без `fix` до перезапуска (доверие закреплено, R0-1); `/config reload` отвечает строкой `Restart required: trusted_projects`

#### Scenario: Навыки после шаблонов
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, у сессии есть шаблон `review`, навыки `release-notes` (с `argument-hint: "<from-tag> <to-tag>"`) и `flutter-golden` (без подсказки) и навык `internal` с `user-invocable: false`
- **THEN** список — `mode`, `model`, `status`, `help`, `review`, `skill:flutter-golden` (`inputHint: "arguments"`), `skill:release-notes` (`inputHint: "<from-tag> <to-tag>"`); `skill:internal` и `skill` в списке нет

### Requirement: Неизвестная команда
Если первый текстовый блок промпта начинается с `/`, слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$`, но не является ни объявленной в сессии встроенной командой, ни именем шаблона, ни командой навыка (слово с префиксом `skill:` и непустым именем при включённой capability `skills` и непустом снимке навыков сессии обрабатывает требование «Команды навыков» capability `agent-skills`: ответ на отсутствующий навык — `Unknown skill: <name>. Run /help to list commands.`; без capability, с пустым снимком или с пустым именем — неизвестная команда этого требования), `AgentSession.prompt` НЕ SHALL отправлять промпт модели и SHALL отвечать без модели одним сообщением агента `Unknown command: /<name>. Run /help to list commands.` (`agent-core-architecture` §13.6, правило 3; §17.2.6, шаг 7; R-08); `<name>` обрезается до 64 символов по рунам. Ход — по общим правилам встроенных команд: `TurnEnded` с `endTurn`, ни промпт, ни ответ в журнал не пишутся, слот хода занят на время ответа. Лог — `command.unknown {session_id, name_bytes}` (info), без имени и аргументов: имя пришло от пользователя (`AGENTS.md` §16).

Слово, которое не соответствует регулярному выражению (`/usr/bin/foo`), и блок с ведущим пробелом командой не являются и уходят модели без изменений (требование «Разворачивание команды»). Имя MCP prompt (`<server>:<prompt>`) в этой версии неизвестная команда: MCP prompts — вне этой спецификации (строка матрицы E-24).

#### Scenario: Неизвестная команда не уходит модели
- **WHEN** шаблонов `nope` нет, и приходит `/nope x`
- **THEN** ответ — ровно `Unknown command: /nope. Run /help to list commands.`, `TurnEnded` с `endTurn`, scripted-модель не получила запросов, журнал без новых записей (R-08)

#### Scenario: Путь — не команда
- **WHEN** приходит `/usr/bin/foo is broken`
- **THEN** модель получает текст без изменений

#### Scenario: Длинное имя обрезается
- **WHEN** приходит `/` и имя из 100 символов `a`
- **THEN** ответ содержит `/` и ровно 64 символа `a`, лог `command.unknown` не содержит имени

#### Scenario: skill без навыков
- **WHEN** capability `skills` выключена, и приходит `/skill:release-notes`; во втором варианте capability включена, но навыков у сессии нет
- **THEN** в обоих вариантах ответ — ровно `Unknown command: /skill:release-notes. Run /help to list commands.`, модель не вызвана, лог `command.unknown`

### Requirement: Разворачивание команды
`AgentSession.prompt` SHALL разбирать только первый текстовый блок промпта. Если блок начинается с `/`, а слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$` и совпадает с именем шаблона, тело шаблона с подставленными аргументами SHALL заменить этот блок; остальные блоки идут после него в исходном порядке. Встроенная команда с тем же именем проверяется раньше шаблона, но шаблон с именем встроенной команды не загружается (требование «Резервные имена команд»). Слово, которое соответствует выражению, но не является ни встроенной командой, ни шаблоном, — неизвестная команда (требование «Неизвестная команда»). Если блок не начинается с `/` или слово не соответствует выражению, промпт SHALL уходить модели без изменений.

Подстановка SHALL выполняться одним проходом слева направо:
- `$ARGUMENTS` → остаток строки как введён (`raw`: после ведущих пробелов, без завершающего `\r?\n`);
- `$1`…`$9` → аргументы `splitArguments`, отсутствующий — пустая строка;
- `$$` → `$`;
- `\$` → `$`; `\$1` и `\$ARGUMENTS` поэтому остаются литералами `$1` и `$ARGUMENTS` (design.md change `add-agent-skills`, D8; решения пользователя Q7, Q15 (а)): литерал `$` записывается и как `$$`, и как `\$` — в шаблонах и в телах навыков;
- `\` перед любым другим символом остаётся литералом; `\\` копируется как два символа, и следующий за ним `$…` разбирается обычным правилом (`\\$1` → `\\` и первый аргумент) — так шаблоны с `\\` до этого change не меняют смысла (design.md change `add-agent-skills`, D18);
- `$10` → первый аргумент и `0`;
- `$` перед другим символом остаётся литералом.

Те же правила подстановки SHALL разворачивать тела навыков (`/skill:<name>`, capability `agent-skills`, «Команды навыков»); у навыка хвост `ARGUMENTS:` идёт после блока навыка, а не внутри него, и в содержимое активации не входит. Подставленные значения НЕ SHALL сканироваться повторно; `{{…}}` в теле не обрабатывается. Без плейсхолдеров в теле (`\$…` плейсхолдером не считается) при непустом `raw` SHALL дописываться `\n\nARGUMENTS: <raw>`. `splitArguments`: разделитель — пробельные символы; `"…"` и `'…'` группируют слово; внутри `"…"` экранируются `\"` и `\\`; вне кавычек `\` даёт следующий символ; незакрытая кавычка закрывается концом ввода (D8). Разбор НЕ SHALL исполнять shell и читать файлы (SKL-8).

#### Scenario: Шаблон с аргументами
- **WHEN** тело `review.md` — `Review $1 focusing on $2. All: $ARGUMENTS`, а промпт — `/review lib/parser "error handling"`
- **THEN** модель получает сообщение пользователя `Review lib/parser focusing on error handling. All: lib/parser "error handling"` (`acp/prompt-template-command`, E-07)

#### Scenario: Значение не разворачивается повторно
- **WHEN** тело — `X $1`, а промпт — `/t '$ARGUMENTS'`
- **THEN** модель получает `X $ARGUMENTS`

#### Scenario: Незакрытая кавычка
- **WHEN** тело — `[$1]`, а промпт — `/t "error handling`
- **THEN** модель получает `[error handling]`

#### Scenario: Завершающий CRLF
- **WHEN** тело — `[$ARGUMENTS|$1]`, а промпт клиента на Windows — `/t lib\r\n`
- **THEN** модель получает `[lib|lib]`, без `\r` и `\n`

#### Scenario: Не команда
- **WHEN** промпт — `/usr/bin/foo is broken`
- **THEN** модель получает текст без изменений

#### Scenario: Слово команды без шаблона
- **WHEN** промпт — `/nope x`, а шаблона `nope` нет
- **THEN** модель не вызвана, ответ — `Unknown command: /nope. Run /help to list commands.` (требование «Неизвестная команда»)

#### Scenario: Наблюдаемость
- **WHEN** разворачивается `/review secret-token-123`
- **THEN** лог `command.expanded` содержит `name: review`, `source: template`, `args_bytes` и не содержит `secret-token-123`

#### Scenario: Литерал доллара через обратную косую
- **WHEN** тело шаблона — `cost \$1, arg $1`, а промпт — `/t x`
- **THEN** модель получает `cost $1, arg x`

#### Scenario: Литерал доллара удвоением
- **WHEN** тело шаблона — `cost $$1, arg $1`, а промпт — `/t x`
- **THEN** модель получает `cost $1, arg x`

#### Scenario: Литерал доллара в навыке
- **WHEN** тело навыка `notes` — `Use \$HOME and $$PATH; topic: $1`, а промпт — `/skill:notes cache`
- **THEN** блок навыка содержит `Use $HOME and $PATH; topic: cache`

#### Scenario: Обратная косая перед обратной косой
- **WHEN** тело шаблона — `a\\$1`, а промпт — `/t x`
- **THEN** модель получает `a\\x`

#### Scenario: Отсутствующий аргумент
- **WHEN** тело — `[$1|$2]`, а промпт — `/t a`
- **THEN** модель получает `[a|]`: отсутствующий аргумент — пустая строка, как до этого change (у Claude Code плейсхолдер остался бы текстом — сознательное отличие, design.md change `add-agent-skills`, решение Q28)
