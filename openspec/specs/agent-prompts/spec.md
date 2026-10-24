# agent-prompts Specification

## Purpose
Промпты Dart-агента: исходники в Markdown под `prompts/`, генерация Dart-констант с проверкой синхронизации в CI, шаблоны с объявленными переменными и детерминированная сборка системного промпта из секций, где одинаковые входы дают побайтово одинаковый текст (`agent-core-architecture` §11).
## Requirements
### Requirement: Промпты в Markdown и генерация констант
Тексты промптов, которые видит модель, SHALL лежать файлами `packages/dart/codelab_agent_core/prompts/**/*.md`. У каждого файла есть frontmatter с ключами `id`, `description`, `vars` и необязательным `tools`.

Генератор `tool/gen_prompts.dart` SHALL компилировать файлы в один файл `lib/src/prompts/prompts.g.dart` по алгоритму §11.3 документа ядра:
- файлы обрабатываются в порядке относительного пути;
- `id` совпадает с путём;
- имя константы — путь в lowerCamelCase;
- результат форматируется `DartFormatter`;
- режим `--check` сравнивает результат с файлом на диске.

Генератор SHALL завершаться ошибкой с путём файла в случаях:
- нет frontmatter;
- неизвестный ключ frontmatter;
- подстановка не объявлена в `vars` или объявлена, но не используется;
- дубликат `id`;
- файл под `tools/` без непустого `tools`.

Сгенерированный файл SHALL соответствовать исходникам (PR-1). В `lib/` ядра вне `prompts.g.dart` НЕ SHALL быть многострочных строковых литералов промптов (PR-2).

Тексты SHALL быть английскими, написанными для CodeLab (`AGENTS.md` §5). Файлы этапа 2:
- `system/base.md`, `system/untrusted.md`, `modes/plan.md`;
- `tools/read.md`, `tools/edit.md`, `tools/listing.md`, `tools/exec.md`, `tools/plan.md`;
- `tool_descriptions/<tool>.md` для семи встроенных инструментов.

#### Scenario: Синхронизация с исходниками
- **WHEN** тест генерирует файл в памяти
- **THEN** результат побайтово равен `lib/src/prompts/prompts.g.dart` (`prompts_sync_test.dart`)

#### Scenario: Ошибки генератора
- **WHEN** генератор получает файл с неизвестной подстановкой, файл с необъявленной переменной, файл с ключом `author` и два файла с одним `id`
- **THEN** каждый случай даёт ошибку, называющую путь файла

### Requirement: Шаблоны
`PromptTemplate(id, vars, text, tools)` SHALL подставлять только именованные значения `{{имя}}`, а `\{{` превращать в литерал `{{`. Значения вставляются как есть, без повторной подстановки. `render` с неполным или лишним набором значений SHALL давать `ArgumentError` (PR-4). Условий, циклов и вложенных шаблонов нет.

#### Scenario: Рендеринг
- **WHEN** шаблон `A {{x}} \{{y}}` рендерится со значением `x = "{{z}}"`
- **THEN** результат — `A {{z}} {{y}}`, а `render` без `x` бросает `ArgumentError`

### Requirement: Детерминированная сборка системного промпта
`composeSystemPrompt(PromptInputs)` SHALL собирать секции в фиксированном порядке §11.5 документа ядра и соединять их через пустую строку:
1. `system/base` с `cwd`, датой `yyyy-MM-dd`, платформой и именем режима.
2. `system/untrusted`.
3. `modes/plan` в режиме `plan`.
4. `tools/read`.
5. `tools/edit`.
6. `tools/listing` при `fileListing`.
7. `tools/exec` при `shellExec`.
8. `tools/plan`.

Одинаковые входы SHALL давать побайтово одинаковый результат; секций выключенных capability в нём нет (PR-3, HOST-4).

Секция с непустым `tools` SHALL входить в промпт, только если включены все её инструменты (PR-6). База и секции без `tools` НЕ SHALL называть ни одного инструмента по имени, которое не совпадает с обычным английским словом.

#### Scenario: Golden на профиль и режим
- **WHEN** промпт собирается для профилей `agent-serve` и `embedded-cli` в режимах `standard` и `plan` с фиксированной датой
- **THEN** результат совпадает с `test/prompts/golden/<profile>-<mode>.txt`

#### Scenario: Секция выключенного инструмента
- **WHEN** набор инструментов сессии не содержит `ls`, а затем не содержит `write` и `edit`
- **THEN** в первом промпте нет `tools/listing`, во втором есть `tools/read` и нет `tools/edit`

#### Scenario: База не называет инструментов
- **WHEN** тест-сторож проверяет `system/base.md` и `system/untrusted.md`
- **THEN** в них нет слов `exec`, `ls`, `update_plan` и подстроки `mcp__`

