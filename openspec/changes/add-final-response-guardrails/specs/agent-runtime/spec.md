## ADDED Requirements

### Requirement: Проверки финального ответа сессии
`AgentRuntime` SHALL ставить в `AgentLoopConfig` корневой сессии составной хук `beforeFinalResponse` из встроенных проверок, включённых ключом `loop.final_response.checks` (design.md change `add-final-response-guardrails`, D1–D3). `maxResponseRevisions` цикла корня SHALL равняться верхней границе схемы `5`. Фактический лимит, политику и список проверок хук SHALL брать при каждом вызове из снимка конфигурации этой сессии: у сессии в корне запуска — из применённого снимка процесса, у сессии другой папки — из конфигурации её папки (без порта папки — `CoreConfig.withoutProject`; требование «Конфигурация сессии вне корня запуска»). Сессия субагента любого уровня составного хука НЕ SHALL получать (D9).

Встроенные проверки SHALL быть детерминированными, без вызова модели и без ввода-вывода, и вызываться в порядке каталога, а не в порядке списка конфига:
1. `open_tasks` — замечание, если в списке задач корневой сессии есть пункт со статусом `in_progress` и владельцем `main`; пункты `pending` и пункты субагентов не считаются; без списка задач проверка молчит. Текст: `Tasks still in progress: #<id>, #<id>. Finish them, or update their status with task_update before you answer.` — не больше пяти id по возрастанию, после пятого `and <n> more`. `subject` пунктов НЕ SHALL попадать в замечание: это текст модели, а заметка — сообщение цикла вне ограды (TOOL-10).
2. `unverified_success` — замечание, если текстовые блоки ответа (без `thinking`) утверждают, что тесты или сборка прошли (английские и русские формы), а в `TurnInfo.toolOutcomes` нет ни вызова `exec` с исходом `completed` или `failed`, ни вызова `agent` с исходом `completed`. Вызовы с исходом `rejected` или `cancelled` попыткой проверить НЕ SHALL считаться. Текст: `The answer says that tests or the build pass, but no command ran in this turn. Run the check with exec, or say plainly that it was not verified.`

Вердикт составного хука:
- нет замечаний или пустой список проверок → `Accept`;
- есть замечания и `TurnInfo.revisions` меньше `loop.final_response.max_revisions` → `Revise` с одной заметкой:
  ```text
  [Final answer check] Your answer was not accepted:
  [<id>] <замечание>
  …
  Revise the answer. If you need to verify something, use the tools first.
  ```
- есть замечания, лимит исчерпан → при `on_revise_limit: hold` — `Hold("revision limit reached: [<id>] <замечание>; …")`, обрезанный до 500 рун (Unicode code points) с `…`; при `accept` — `Accept`.

Исключение отдельной проверки НЕ SHALL завершать ход: проверка пропускается с логом `loop.final_check.error` (warning: `session_id`, `turn_id`, `check`, `error_class`, `stack`; без текста исключения). Решения SHALL логироваться `loop.final_check.revise` (info: `session_id`, `turn_id`, `step_index`, `revisions`, `checks`) и `loop.final_check.limit` (те же поля и `policy`). Текст ответа, замечаний, пунктов задач и исключений в логи НЕ SHALL попадать.

Шаг ревизии SHALL быть обычным шагом: он входит в `TurnBudget`, `TurnEnded.usage` и учёт usage сессии. Отмена хода во время или после вердикта SHALL давать `cancelled`. Бюджет, исчерпанный на границе после `Revise`, SHALL завершать ход с `budgetExceeded` без `held`.

#### Scenario: Пустой список проверок
- **WHEN** `loop.final_response.checks` пуст, модель отвечает текстом `All tests pass.` без вызовов
- **THEN** ход завершается `TurnEnded(completed)` за один шаг, `held` равен `null`, логов `loop.final_check.*` нет

#### Scenario: Незакрытая задача и ревизия
- **WHEN** `checks: [open_tasks]`, модель создала задачу `#1 Run the tests`, перевела её в `in_progress` и ответила текстом; на следующем шаге закрыла задачу через `task_update` и ответила снова
- **THEN** транскрипт содержит заметку цикла `[open_tasks] Tasks still in progress: #1. …` без текста `Run the tests`, ход завершается `TurnEnded(completed)` без `held`

#### Scenario: Задачи pending и задачи субагента
- **WHEN** `checks: [open_tasks]`, в списке есть пункт `pending` владельца `main` и пункт `in_progress` владельца-субагента, модель отвечает текстом
- **THEN** гейт возвращает `Accept`, дополнительного шага нет

#### Scenario: Успех без запуска
- **WHEN** `checks: [unverified_success]`, `max_revisions: 2`, модель трижды отвечает `All tests pass.` без вызовов
- **THEN** выполняются ровно два дополнительных шага, ход завершается `TurnEnded(completed, held: "revision limit reached: [unverified_success] The answer says …")`, лог `loop.final_check.limit` с `policy: hold`

#### Scenario: Успех после запуска
- **WHEN** `checks: [unverified_success]`, в ходе был исполнен `exec` (исход `completed` или `failed`), затем ответ `Тесты прошли.`
- **THEN** гейт возвращает `Accept`

#### Scenario: Отклонённый exec не считается
- **WHEN** `checks: [unverified_success]`, `max_revisions: 0`, вызов `exec` отклонён режимом `plan` (исход `rejected`), затем ответ `All tests pass.`
- **THEN** ход завершается с `held`

#### Scenario: Проверка через субагента
- **WHEN** `checks: [unverified_success]`, в ходе вызов `agent` завершился с исходом `completed`, корень сам `exec` не вызывал и отвечает `All tests pass.`
- **THEN** гейт возвращает `Accept`

#### Scenario: Политика accept
- **WHEN** `checks: [unverified_success]`, `max_revisions: 0`, `on_revise_limit: accept`, модель отвечает `The build succeeded.` без вызовов
- **THEN** ход завершается за один шаг без `held`, лог `loop.final_check.limit` с `policy: accept`

#### Scenario: Две проверки в одной заметке
- **WHEN** `checks: [unverified_success, open_tasks]` и обе дают замечание
- **THEN** заметка `Revise` одна, строка `[open_tasks]` идёт перед строкой `[unverified_success]`

#### Scenario: Сбой проверки
- **WHEN** проверка бросает исключение с текстом `secret-xyz`, а вторая включённая проверка замечаний не имеет
- **THEN** гейт возвращает `Accept`, лог `loop.final_check.error` с `check` и `error_class` не содержит `secret-xyz`, ход не `failed`

#### Scenario: Обрезка причины по рунам
- **WHEN** причина `Hold` длиннее 500 рун и 500-я руна — эмодзи из суррогатной пары
- **THEN** `held` содержит ровно 500 рун с `…`, суррогатная пара не разорвана

#### Scenario: Бюджет во время ревизий
- **WHEN** `checks: [unverified_success]`, `TurnBudget.maxSteps: 2`, модель каждый раз отвечает `All tests pass.` без вызовов
- **THEN** после второго шага ход завершается `TurnEnded(completed, budgetExceeded: steps)`, `held` равен `null`

#### Scenario: Отмена во время ревизии
- **WHEN** гейт вернул `Revise`, а `session/cancel` пришёл до следующего запроса к модели
- **THEN** следующего запроса нет, ход завершается `TurnEnded(cancelled)`

#### Scenario: Субагент без гейта
- **WHEN** `checks: [unverified_success]`, ребёнок отвечает отчётом `All tests pass.` без вызовов `exec`
- **THEN** ребёнок завершается за один шаг, его отчёт уходит родителю без ревизии

#### Scenario: Перезагрузка включает проверку
- **WHEN** сессия открыта с `checks: []`, затем перезагрузка конфига ставит `checks: [unverified_success]`, и в следующем ходе модель отвечает `All tests pass.` без вызовов
- **THEN** гейт этого хода возвращает `Revise`

#### Scenario: Сессия другой папки
- **WHEN** проектный конфиг корня запуска задаёт `checks: [unverified_success]`, а сессия открыта в другой папке без такого ключа
- **THEN** гейт этой сессии на ответ `All tests pass.` без вызовов возвращает `Accept`
