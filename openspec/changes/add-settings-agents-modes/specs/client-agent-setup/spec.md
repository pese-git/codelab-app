## ADDED Requirements

### Requirement: Умолчания новой сессии в мосте
Основной барель `codelab_setup` (чистый Dart, web-безопасно) SHALL давать `SessionDefaultsView` и `sessionDefaultsOf(AgentConfigSnapshot snapshot, EditableSettings access)` (design.md change `add-settings-agents-modes`, D6):
- итоговый режим новой сессии из разобранного итога загрузки (`CoreConfig`), а не из сырого листа: псевдонимы (`acceptEdits`, `alwaysAsk`) приводятся к `accept-edits`, `ask`; сочетание `ask` и `plan` даёт `ask` с признаком запрета `write` и `exec`;
- источник режима — `originOf('permissions.mode')`, без листа — `default` с умолчанием профиля хоста `standard`;
- для сочетания `ask` и `plan` источник — слой `user`, только если `permissions.mode` в листьях слоя `user` даёт `ask` (основной id или псевдоним `alwaysAsk`); иначе источник снимка без подмены. Ветки по режиму флага запуска (`autopilot`) представление НЕ SHALL иметь (design.md, D6);
- признак сужения проектом — предупреждение `config.project.untrusted_key` с путём `permissions.mode` в итоге загрузки;
- итоговый `agent.effort` и его источник, без листа — `default` и `medium`;
- предлагаемую цель записи: редактируемый слой источника `permissions.mode`, иначе `user`; `projectLocal` — только если его даёт `access`.

Клиенты НЕ SHALL сами разбирать слои, псевдонимы режимов и правила доверия для этих ключей (SETUP-8).

#### Scenario: Псевдоним и источник
- **WHEN** пользовательский слой задаёт `permissions.mode: acceptEdits`, а `agent.effort` не задан
- **THEN** `sessionDefaultsOf` возвращает режим `accept-edits` с источником `user` и effort `medium` с источником `default`

#### Scenario: Сужение проектом
- **WHEN** пользовательский слой задаёт `standard`, а недоверенный проект в `config.local.yaml` — `bypass`
- **THEN** режим — `standard`, признак сужения истинен

#### Scenario: Источник сочетания ask и plan из слоя user
- **WHEN** пользовательский слой задаёт `permissions.mode: alwaysAsk`, а недоверенный проект — `plan`
- **THEN** режим — `ask` с признаком запрета `write` и `exec`, источник — `user`, предлагаемая цель — `user`

#### Scenario: Сочетание ask и plan без ask в слое user
- **WHEN** `ask` задан не слоем `user` (окружение или `--config`), а недоверенный проект задаёт `plan`
- **THEN** источник режима — источник снимка, а не `user`

#### Scenario: Основной барель без dart:io
- **WHEN** выполняется `melos run web-compile`
- **THEN** `SessionDefaultsView`, `sessionDefaultsOf` и `AgentDefinitionRowView` компилируются в составе основного бареля без `dart:io`

### Requirement: Строки определений агентов в мосте
Мост SHALL давать строки таблицы определений агентов, построенные тем же разбором, что у агента и `config check` (design.md change `add-settings-agents-modes`, D7):
- основной барель — `AgentDefinitionRowView` (имя, описание, источник, «где доступно», инструменты, модель, статус, строка ошибки) и чистая функция построения строк по определениям, диагностике, встроенным типам субагентов и признаку `subagents.enabled`;
- `io.dart` — `agentDefinitionRowsAt`, которая читает `$CODELAB_HOME/agents` и, только для доверенного проекта, `<project>/.codelab/agents` функцией `codelab_agent_io`, общей с `config check`, с каталогом моделей итогового конфига и тайм-аутом 5 с; результат SHALL сообщать, существуют ли каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents`, чтобы клиент не проверял файловую систему сам.

Строки SHALL идти в порядке: `default`, встроенные `general`, `explore`, `review`, `plan`, затем файлы по имени. Файл, отклонённый с диагностикой кода `model`, SHALL получать статус `Model not configured`; другой `error` — `Error` со строкой диагностики; `duplicate` — `Not loaded: duplicate name`; пользовательский файл с `shadowed` — `Shadowed by project`. Встроенный тип, который заменило определение с тем же именем и областью `subagent` или `both`, SHALL получать статус `Overridden by <путь>`; при `subagents.enabled: false` встроенные типы SHALL оставаться в строках со статусом `Subagents off` (решение пользователя 2026-11-16, Q12 (а)). Имя строки отклонённого файла — имя файла без `.md`. Тела определений, имена неизвестных ключей и фрагменты файлов НЕ SHALL попадать в строки.

Вывод `config check` при этом НЕ SHALL меняться (spec agent-configuration «config check показывает диагностику файлов проекта»).

#### Scenario: Тот же разбор, что у config check
- **WHEN** `$CODELAB_HOME/agents/reviewer.md` содержит неизвестный ключ `color` в строке 4
- **THEN** `codelab config check` печатает `warning: …/reviewer.md:4:1: unknown frontmatter key`, а строка моста `reviewer` имеет статус `Error` со строкой `4` и тем же сообщением без `color`

#### Scenario: Недоверенный проект
- **WHEN** папка проекта не в `trusted_projects`, а в `<project>/.codelab/agents/` есть валидный `reviewer.md`
- **THEN** строк из проектного каталога нет, а результат содержит диагностику `untrusted_project` для `<project>/.codelab/agents`

#### Scenario: Определение заменяет встроенный тип
- **WHEN** `$CODELAB_HOME/agents/review.md` валиден со `scope: both`
- **THEN** строка встроенного `review` имеет статус «заменён» с путём `$CODELAB_HOME/agents/review.md` (app показывает `Overridden by ~/.codelab/agents/review.md`), а строка файла `review` — `Available` с «где доступно» `both`

#### Scenario: Выключенные субагенты
- **WHEN** итоговый конфиг задаёт `subagents.enabled: false`
- **THEN** строки `general`, `explore`, `review`, `plan` присутствуют со статусом `Subagents off`

#### Scenario: Признак наличия каталогов
- **WHEN** во временном `CODELAB_HOME` нет `agents`, а у доверенного проекта есть `.codelab/agents`
- **THEN** результат `agentDefinitionRowsAt` сообщает, что пользовательского каталога нет, а проектный есть; ни один каталог не создан
