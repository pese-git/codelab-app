## ADDED Requirements

### Requirement: Каталоги шаблонов команд и доверие
Шаблоны команд SHALL читаться из `*.md` первого уровня, без рекурсии:
- `<cwd>/.codelab/prompts/` — только если канонический `cwd` сессии есть в `CoreConfig.trustedProjects`;
- `$CODELAB_HOME/prompts/` — всегда.

Если каталог проекта существует, а проект не доверенный, файлы НЕ SHALL читаться, а загрузчик SHALL дать одну диагностику `info` `untrusted_project`. При одинаковом имени шаблон проекта SHALL заменять пользовательский, а пользовательский — получать диагностику `info` `shadowed`.

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, а `<cwd>/.codelab/prompts/review.md` существует
- **THEN** команды `review` в `available_commands_update` нет, есть диагностика `untrusted_project`

#### Scenario: Проект перекрывает пользователя
- **WHEN** проект доверенный, `review.md` есть и в проекте, и в `$CODELAB_HOME/prompts`
- **THEN** `/review` разворачивается телом проектного файла, у пользовательского — диагностика `shadowed`

### Requirement: Формат шаблона и проверка
Имя команды SHALL быть именем файла без `.md` по правилу `^[a-z0-9][a-z0-9-]{0,63}$`; другое имя — диагностика `warning` `invalid_name`, файл пропущен. Frontmatter необязателен; если он есть, SHALL разбираться в строгом профиле CFG-21 и содержать только `description` (1–200 символов) и `argument-hint` (1–80 символов). Другой ключ — `error` `unknown_key`, нарушение профиля — `error` `profile` или `syntax` со строкой и столбцом; файл пропускается. Без `description` описанием SHALL быть первая непустая строка тела, обрезанная до 200 символов. Тело SHALL быть непустым и не больше 32 КиБ, файл — не больше 64 КиБ, файлов в каталоге — не больше 100 (лишние — `limit_exceeded`). Файл не в UTF-8 — `not_utf8`.

Ошибка файла НЕ SHALL прерывать создание сессии.

#### Scenario: Битый frontmatter
- **WHEN** `review.md` начинается с frontmatter, где ключ `description` повторён дважды
- **THEN** команды `review` нет, диагностика `profile` называет путь файла и обе позиции, сессия создана

#### Scenario: Неверное имя
- **WHEN** в каталоге лежат `Review.md` и `my_cmd.md`
- **THEN** обе команды отсутствуют, у каждого файла диагностика `invalid_name`

### Requirement: Резервные имена команд
Имена встроенных команд §13.4 (`compact`, `mode`, `model`, `status`, `usage`, `redact`, `config`, `mcp`, `rename`, `branches`, `branch`, `rewind`, `fork`, `label`, `approve`, `timer`, `memory`, `tasks`, `help`) и `skill` SHALL быть зарезервированы. Шаблон с таким именем НЕ SHALL загружаться и SHALL давать диагностику `warning` `reserved_name` (SKL-7).

#### Scenario: Шаблон с именем встроенной команды
- **WHEN** в `$CODELAB_HOME/prompts` лежит `help.md`
- **THEN** команды `help` из шаблона нет, есть диагностика `reserved_name`, промпт `/help` не разворачивается этим файлом

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён. `inputHint` SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия. Инструменты модели в список НЕ SHALL попадать (R-07).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

### Requirement: Разворачивание команды
`AgentSession.prompt` SHALL разбирать только первый текстовый блок промпта. Если блок начинается с `/`, а слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$` и совпадает с именем шаблона, тело шаблона с подставленными аргументами SHALL заменить этот блок; остальные блоки идут после него в исходном порядке. Иначе промпт SHALL уходить модели без изменений.

Подстановка SHALL выполняться одним проходом слева направо:
- `$ARGUMENTS` → остаток строки как введён (`raw`);
- `$1`…`$9` → аргументы `splitArguments`, отсутствующий — пустая строка;
- `$$` → `$`;
- `$10` → первый аргумент и `0`;
- `$` перед другим символом остаётся литералом.

Подставленные значения НЕ SHALL сканироваться повторно; `{{…}}` в теле не обрабатывается. Без плейсхолдеров в теле при непустом `raw` SHALL дописываться `\n\nARGUMENTS: <raw>`. `splitArguments`: разделитель — пробельные символы; `"…"` и `'…'` группируют слово; внутри `"…"` экранируются `\"` и `\\`; вне кавычек `\` даёт следующий символ; незакрытая кавычка закрывается концом ввода (D8). Разбор НЕ SHALL исполнять shell и читать файлы (SKL-8).

#### Scenario: Шаблон с аргументами
- **WHEN** тело `review.md` — `Review $1 focusing on $2. All: $ARGUMENTS`, а промпт — `/review lib/parser "error handling"`
- **THEN** модель получает сообщение пользователя `Review lib/parser focusing on error handling. All: lib/parser "error handling"` (`acp/prompt-template-command`, E-07)

#### Scenario: Значение не разворачивается повторно
- **WHEN** тело — `X $1`, а промпт — `/t '$ARGUMENTS'`
- **THEN** модель получает `X $ARGUMENTS`

#### Scenario: Незакрытая кавычка
- **WHEN** тело — `[$1]`, а промпт — `/t "error handling`
- **THEN** модель получает `[error handling]`

#### Scenario: Не команда
- **WHEN** промпт — `/usr/bin/foo is broken` или `/nope x`, а шаблонов `usr` и `nope` нет
- **THEN** модель получает текст без изменений

#### Scenario: Наблюдаемость
- **WHEN** разворачивается `/review secret-token-123`
- **THEN** лог `command.expanded` содержит `name: review`, `source: template`, `args_bytes` и не содержит `secret-token-123`

### Requirement: Исходный текст команды в журнале
Запись `message` сообщения пользователя, полученного разворачиванием, SHALL нести поле записи `command: {"source": "template", "name": <имя>, "args": <raw>}`. Модель поле НЕ SHALL видеть. `replay()` для такой записи SHALL отдавать первым блоком текст `/<name>` (или `/<name> <args>` при непустом `args`), затем остальные блоки сообщения, кроме развёрнутого текста.

#### Scenario: Реплей показывает команду
- **WHEN** сессия с ходом `/review lib/parser "error handling"` загружается в новом соединении
- **THEN** реплей содержит `user_message_chunk` с текстом `/review lib/parser "error handling"`, а не развёрнутое тело
