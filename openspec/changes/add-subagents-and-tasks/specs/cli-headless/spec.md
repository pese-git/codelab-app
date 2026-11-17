## ADDED Requirements

### Requirement: Операции со списком задач в headless
В headless (`-p`) элемент `TaskOpsItem` (acp-client-kit «Операции со списком задач в ленте») SHALL печататься в stderr одной строкой с текстом kit — например `Tasks #1–#4 added to the plan` — вместо строк вызовов, которые он заменяет (design.md change `add-subagents-and-tasks`, D27, D35). Строка SHALL печататься ровно один раз на элемент, когда элемент перестал расти: после него в транскрипте появился другой элемент или ход завершился. Промежуточные состояния сливающегося элемента НЕ SHALL печататься. Неуспешная операция печатается обычной строкой вызова с причиной. stdout при этом не меняется (требование «Вывод headless»).

#### Scenario: Четыре создания подряд в headless
- **WHEN** в `-p` модель создаёт четыре пункта подряд, затем отвечает `done`
- **THEN** stderr содержит ровно одну строку `Tasks #1–#4 added to the plan` и не содержит строк `Task #1 added to the plan`, `Tasks #1–#2 added to the plan`, `Tasks #1–#3 added to the plan`; stdout равен `done\n`

#### Scenario: Операции, разделённые вызовом
- **WHEN** в `-p` модель создаёт `#1`, вызывает `read`, создаёт `#2`, ход завершается
- **THEN** stderr содержит по порядку `Task #1 added to the plan`, строку `read` и `Task #2 added to the plan`, каждую — один раз
