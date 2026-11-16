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
- `io.dart` — `agentDefinitionRowsAt` (с отменой внешним токеном `cancel`), которая читает `$CODELAB_HOME/agents` и, только для доверенного проекта, `<project>/.codelab/agents` функцией `codelab_agent_io`, общей с `config check`, с каталогом моделей итогового конфига и тайм-аутом 5 с; результат SHALL сообщать, существуют ли каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents` (без следования по символической ссылке: каталог-ссылка считается отсутствующим), и явный признак `projectTrusted` (без папки — ложь), чтобы клиент не проверял файловую систему сам и не выводил доверие из диагностики (design.md, D19);
- доверие проекта (канонический путь папки против `trusted_projects`, без раскрытого пути — недоверенный) SHALL считаться одной публичной функцией `codelab_agent_io`, которую вызывают и `config check`, и мост; вывод `config check` при этом НЕ SHALL меняться (SETUP-8; design.md, D19).

Строки SHALL идти в порядке: `default`, встроенные `general`, `explore`, `review`, `plan`, затем файлы по имени. Файл, отклонённый с диагностикой «модель вне каталога», SHALL получать статус `Model not configured`. Ядро отдаёт её кодом `invalid_value` с сообщением, равным публичной константе ядра (design.md, D18); мост SHALL распознавать её по коду `invalid_value` и точному равенству сообщения этой константе, без своей копии текста, а код диагностики и вывод `config check` НЕ SHALL меняться. Прочий `error` — `Error` со строкой диагностики; `duplicate` — `Not loaded: duplicate name`; пользовательский файл с `shadowed` — `Shadowed by project`. Встроенный тип, который заменило определение с тем же именем и областью `subagent` или `both`, SHALL получать статус `Overridden by <путь>`; при `subagents.enabled: false` встроенные типы SHALL оставаться в строках со статусом `Subagents off` (решение пользователя 2026-11-16, Q12 (а)). Имя строки отклонённого файла — имя файла без `.md`. Тела определений, имена неизвестных ключей и фрагменты файлов НЕ SHALL попадать в строки. У строк отклонённых файлов «где доступно», инструменты и модель SHALL быть пустыми (клиент показывает `—`); модель `session model` — только у `default`, встроенных типов и рабочих определений без модели (design.md, D19).

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

#### Scenario: Модель вне каталога по константе ядра
- **WHEN** `$CODELAB_HOME/agents/docs-writer.md` задаёт `model: openai/gpt-x`, а провайдера `openai` в итоговом конфиге нет
- **THEN** настоящий `parseAgentDefinitions` даёт диагностику `error` с кодом `invalid_value` и сообщением, равным константе ядра, строка моста `docs-writer` имеет статус `Model not configured`, а `codelab config check` печатает ту же диагностику без изменений

#### Scenario: Другой invalid_value не считается моделью
- **WHEN** `migrator.md` задаёт недопустимое значение другого поля (диагностика `invalid_value` с другим сообщением)
- **THEN** строка `migrator` имеет статус `Error` со строкой диагностики, а не `Model not configured`

#### Scenario: Признак наличия каталогов
- **WHEN** во временном `CODELAB_HOME` нет `agents`, а у доверенного проекта есть `.codelab/agents`
- **THEN** результат `agentDefinitionRowsAt` сообщает, что пользовательского каталога нет, а проектный есть; ни один каталог не создан

#### Scenario: Признак доверия в результате
- **WHEN** папка проекта не в `trusted_projects`, а `<project>/.codelab/agents` существует
- **THEN** `agentDefinitionRowsAt` возвращает `projectTrusted: false` и `projectDirectoryExists: true`; без папки — `projectTrusted: false` и `projectDirectory: null`

#### Scenario: Одно правило доверия с config check
- **WHEN** проект открыт по пути-ссылке `/tmp/demo-link`, а в `trusted_projects` записан канонический путь его цели
- **THEN** и мост (`projectTrusted: true`), и `codelab config check` (строки проектных файлов без `note: … the project is not trusted`) считают проект доверенным одной функцией `codelab_agent_io`; вывод `config check` совпадает с выводом до change

#### Scenario: Каталог-ссылка не считается существующим
- **WHEN** `<project>/.codelab/agents` доверенного проекта — символическая ссылка на каталог
- **THEN** `agentDefinitionRowsAt` возвращает `projectDirectoryExists: false`

#### Scenario: Пустые поля отклонённого файла
- **WHEN** `migrator.md` отклонён с диагностикой `error` и задаёт `tools: [read]`, `scope: both`
- **THEN** строка моста `migrator` не содержит инструментов, «где доступно» и модели, а строка `default` содержит модель сессии
