# agent-subagents Specification

## Purpose
Субагенты Dart-агента (строка C-06 матрицы целей): инструмент модели `agent` поручает часть работы ребёнку встроенного (`general`, `explore`, `review`, `plan`) или пользовательского типа с отдельным контекстом, своим набором инструментов и промптом `subagent/*`. Ребёнок собирается из сервисов корневой сессии, его разрешения идут через gate корневой сессии, вложенность ограничена `subagents.max_depth` (до 3) и слотами дерева, бюджет и `usage` считаются по дереву. Жизненный цикл и отмена связаны с вызовом `agent`: отчёт ребёнка возвращается результатом вызова, журнал ребёнка пишется отдельным файлом со ссылкой из записи `subagent` родителя, события потомков переизлучаются в поток родителя (`SubagentActivity`). Проекция в ACP — только через объявленные расширения `_meta.codelab` (capability `agent-acp-server`). Это базовый этап и этап 2 дорожной карты §6.4 (`delivery-roadmap.md`); фоновые субагенты, продолжение и прочие этапы 3–6 — отдельными changes. Решения — `design.md` архивного change `2026-11-18-add-subagents-and-tasks` (D1–D53), `agent-core-architecture` §17.3, §17.16.
## Requirements
### Requirement: Инструмент agent и типы субагентов
Ядро SHALL регистрировать инструмент `agent` на сессию при `subagents.enabled` (по умолчанию `true`; `false` — ни схемы, ни секции промпта) и только если эффективное окно контекста текущей модели сессии (`effectiveContextWindow` с `compaction.context_window_cap`) не меньше 32 768 токенов (design.md change `add-subagents-and-tasks`, D40). При меньшем окне `agent` в схемах нет, ошибки нет, сессия пишет лог `subagent.unavailable` (`session_id`, `reason: context_window`, `window`, `min_window`). Смена модели сессии и применённая перезагрузка настроек, меняющая эффективное окно (`compaction.context_window_cap`), пересчитывают правило со следующего шага: модель с малым окном убирает `agent` из схем, с достаточным — возвращает (лог `subagent.available`); идущие дети не прерываются. `agent` — tier `read`, kind `think`, `outputTrust` `untrusted`, `permissionPattern` — имя типа (agent-core-architecture §17.3.2).

Схема базового этапа:
- `description` — обязательное, 3–60 символов после обрезки пробелов;
- `prompt` — обязательное, 1–32768 символов;
- `type` — `enum` из имён типов субагентов, по умолчанию `general`;
- `task` — необязательное, id пункта списка задач; поле есть только в схеме корневой сессии.

Полей `output_schema` и `run_in_background` в базе нет.

Типы SHALL браться из встроенных определений `general`, `explore`, `review`, `plan` (`source: builtin:<name>`) и из определений агентов со `scope` `subagent` или `both`. Пользовательское определение с тем же именем заменяет встроенное с логом `subagent.type_overridden`. Определение со `scope: session` в `enum` не входит. Снимок типов и `enum` SHALL фиксироваться при создании сессии.

Заголовок вызова (`ToolPresentation.title`) SHALL быть `Subagent <type>: <description>` с `description` после обрезки пробелов; если `description` нет, оно не строка или пусто после обрезки, — `Subagent <type>` без двоеточия (`type` — из аргументов, иначе `general`). Заголовок строится и для вызова, который затем отклонит проверка (design.md, D41, п. 3).

Ошибки проверки SHALL давать результат-ошибку без создания ребёнка тем же механизмом, что отказ точки исполнения: это текст ядра, а не вывод ребёнка, поэтому в ограду `untrusted-content` он не попадает (огораживается только отчёт, требование «Отчёт ребёнка»). Тексты:
- `Invalid agent call: description must be 3-60 characters.`;
- `Invalid agent call: prompt must be 1-32768 characters.`;
- `Unknown agent type "<x>". Available: <имена через ", ">.`;
- `Unknown task #<id>. …` (§17.16.3).

#### Scenario: Enum типов
- **WHEN** у доверенного проекта есть определения `reviewer` (`scope: both`) и `notes` (`scope: session`)
- **THEN** `enum` поля `type` — `explore`, `general`, `plan`, `review`, `reviewer` по алфавиту, без `notes` (`agent_tool_schema_test.dart`)

#### Scenario: Смена модели на малое окно
- **WHEN** в сессии с моделью окна 128 000 пользователь выбирает модель с окном 8 192, затем возвращает прежнюю
- **THEN** первый запрос с малой моделью не содержит схемы `agent` (лог `subagent.unavailable`), первый запрос после возврата снова её содержит (лог `subagent.available`); вызовы `agent` в истории остаются (`subagent_window_test.dart`; D40)

#### Scenario: Перезагрузка ограничения окна
- **WHEN** в сессии с моделью окна 128 000 перезагрузка конфига ставит `compaction.context_window_cap: 16384`, затем убирает ограничение
- **THEN** первый запрос после первой перезагрузки не содержит схемы `agent` (лог `subagent.unavailable` с `window: 16384`), первый запрос после второй — содержит (лог `subagent.available`); ход, шедший во время перезагрузки, свой текущий запрос не меняет (`subagent_window_test.dart`; D40)

#### Scenario: Неверный заголовок
- **WHEN** модель вызывает `agent` с `description` из двух символов
- **THEN** результат — ошибка `Invalid agent call: description must be 3-60 characters.`, ни дочерней сессии, ни журнала не создано

#### Scenario: Вызов без описания
- **WHEN** модель вызывает `agent` с пустыми аргументами `{}`, затем с `{"type": "explore", "description": "   "}`
- **THEN** `ToolCallStarted` первого вызова несёт заголовок `Subagent general`, второго — `Subagent explore`, оба без двоеточия; оба вызова получают результат-ошибку проверки, ребёнок не создаётся (`agent_tool_schema_test.dart`; D41, п. 3)

### Requirement: Сборка ребёнка
`SubagentManager.spawn` SHALL строить ребёнка из текущего состояния родителя по §17.3.3:
- **Инструменты.** `base` — схемы текущего шага родителя. Набор ребёнка = `type.tools == null ? base : base ∩ type.tools`. `agent` SHALL входить в набор, только если `depth < max_depth`. `agent` НЕ SHALL входить в набор, если эффективное окно контекста модели ребёнка меньше 32 768 токенов — то же правило, что у сессии (требование «Инструмент agent и типы субагентов»; design.md, D40 «Ребёнок», D45 Т10). Инструменты списка задач SHALL входить только детским вариантом (agent-tools «Инструменты списка задач»). Инструмент типа, которого нет у родителя, не добавляется (SUB-1).
- **Режим.** Эффективный режим SHALL вычисляться при каждом решении как `narrow(parentMode(), type.mode)` по всей цепочке предков (SUB-2).
- **Модель.** `type.model`, иначе текущая модель родителя.
- **Промпт.** `composeSystemPrompt` для набора и режима ребёнка, затем `subagent/system`, затем профиль типа, затем строка назначенного пункта, если он есть.
- **Задача.** Ребёнок получает одно user-сообщение с текстом `prompt`; истории родителя он не видит. Активные навыки родителя (capability `agent-skills`, «Активные навыки») ребёнку НЕ SHALL передаваться (design.md, D34; решение Q17.2 (а)).
- **Защищённые пути.** Политика ребёнка SHALL использовать тот же набор защищаемых путей конфигурации агента (PERM-11), что и корневая сессия, — пути хоста и пути сессии, — а не вычислять его заново при создании дочерней сессии (SUB-1; design.md, D34).
- **Навыки.** Ребёнку SHALL передаваться тот же неизменяемый снимок каталога навыков, что у родителя; повторной загрузки файлов навыков для ребёнка НЕ SHALL быть. Инструмент `skill` SHALL входить в набор ребёнка по общему правилу набора и только если ребёнку передан снимок каталога; без снимка инструмент с именем `skill` из набора убирается. При переданном снимке секция `skills/catalog` промпта ребёнка строится из того же снимка, а `readOnlyRoots` его `BoundedEnv` — каталоги навыков этого снимка вне рабочей папки, те же, что у env родителя (каталог выноса ребёнка добавится к ним вместе с выносом вывода, §17.4, §17.3.6); `execInReadOnlyRoots` — как у env родителя (design.md, D34; решения Q17.1 (а), Q17.4 (а)).
- **Хуки хоста.** Хуки хоста `extraBeforeToolCall` корневой сессии SHALL подключаться к циклу потомка любой глубины последними в цепочке `beforeToolCall`, после хука политики потомка, как у корня. Хук SHALL получать вызов с `id`, равным цепочке `toolCallId` потомка (design.md, D8) — тому же id, что у его запроса разрешения; префикс цепочки передаётся по дереву отдельным значением, строки id не разбираются (D45 Т3). Хуки `extraAfterToolCall` к потомкам не подключаются (design.md, D48 п. 1; решение пользователя 2026-11-15, Q33 (б)).

#### Scenario: Пересечение инструментов
- **WHEN** родитель без `exec` вызывает `agent` с типом `review`
- **THEN** набор ребёнка — `read`, `ls`, `search` и детский вариант задач, без `exec` (`subagent_tools_intersection_test.dart`)

#### Scenario: Ребёнок с малым окном
- **WHEN** при `max_depth: 3` и окне модели корня 128 000 корень запускает ребёнка типа, у которого `model` с окном 8 192
- **THEN** набор ребёнка не содержит `agent`, остальные инструменты по общему правилу в нём есть (`subagent_tools_intersection_test.dart`, итерация 4; D40)

#### Scenario: Защищённые пути корня у ребёнка
- **WHEN** корневая сессия в режиме `bypass`, ребёнок `general` вызывает `write` в `.codelab/config.yaml` рабочей папки, затем `exec` с командой `cp /tmp/a.md <$CODELAB_HOME>/agents/a.md`
- **THEN** оба вызова — критические так же, как у корня, и не исполняются без решения пользователя; политика ребёнка получает набор защищаемых путей корневой сессии, а не новый (`subagent_protected_paths_test.dart`, итерация 2)

#### Scenario: Нет снимка каталога — нет skill
- **WHEN** в наборе родителя есть инструмент с именем `skill`, а ребёнку `general` снимок каталога навыков не передан
- **THEN** набор ребёнка не содержит `skill`, остальные инструменты родителя в нём есть (`subagent_tools_intersection_test.dart`, итерация 2)

#### Scenario: Каталог ребёнка — снимок родителя
- **WHEN** у сессии навыки `a-skill` и `b-skill`, корень вызывает `agent` с типом `general`
- **THEN** схема `skill` ребёнка имеет `enum` `["a-skill", "b-skill"]`, секция `skills/catalog` его промпта побайтово равна секции родителя, порт файлов навыков за время запуска ребёнка не вызывается (`subagent_skills_test.dart`, задача 2s.1)

#### Scenario: Тип без skill
- **WHEN** в той же сессии корень вызывает `agent` с типом `explore`
- **THEN** у ребёнка нет `skill` и секции `skills/catalog`

#### Scenario: Файлы навыка пользователя у ребёнка
- **WHEN** ребёнок `general` загрузил навык `notes` из `$CODELAB_HOME/skills`, затем вызывает `read` и `write` по пути `<$CODELAB_HOME>/skills/notes/ref.md`
- **THEN** `read` возвращает содержимое, `write` — `outsideWorkspace` без обращения к env (`subagent_skills_test.dart`, задача 2s.1)

#### Scenario: Активные навыки родителя не наследуются
- **WHEN** родитель загрузил навык `notes` инструментом `skill`, затем вызывает `agent`
- **THEN** первый запрос ребёнка к модели содержит системный промпт и одно user-сообщение с `prompt`, без блока `<skill`

#### Scenario: Корень навыков выше cwd у ребёнка
- **WHEN** доверенный проект с корнем git `/repo`, рабочая папка `/repo/app`, навык в `/repo/.agents/skills/x`; ребёнок `general` в режиме `bypass` вызывает `exec` с `cp /tmp/e /repo/.agents/skills/x/SKILL.md`
- **THEN** вызов критический, как у корня, и без решения пользователя не исполняется (`subagent_skills_test.dart`, задача 2s.1; SKL-9)

#### Scenario: Смена режима родителя посреди работы ребёнка
- **WHEN** ребёнок `general` работает, а пользователь переключает корневую сессию в `plan`
- **THEN** следующий вызов `write` ребёнка отклонён причиной режима `plan` без вопроса (`subagent_mode_narrow_test.dart`)

#### Scenario: Хук хоста видит вызов потомка
- **WHEN** хост передал в сессию хук `extraBeforeToolCall`, корень вызывает `agent` (`call_1`), ребёнок вызывает `read` (`call_1`), затем запускает внука (`call_2`), внук вызывает `ls` (`call_1`)
- **THEN** хук вызван для `call_1/call_1` и `call_1/call_2/call_1` после проверки разрешений этих вызовов; вызов, отклонённый политикой, хук не видит (`subagent_host_hooks_test.dart`, итерация 5)

### Requirement: Вложенность и слоты дерева
Глубина ребёнка SHALL быть глубиной родителя плюс 1 (корневая сессия — 0) и не больше `subagents.max_depth` (1–3, по умолчанию 3). У потомка глубины `max_depth` инструмента `agent` SHALL не быть (SUB-24).

`SubagentTree` (один на корневую сессию) SHALL держать `max_concurrent` слотов на всё дерево:
- слот держит потомок в `running` или в `waiting` с `waitingFor: approval`;
- потомок, у которого начал ждать детей первый блокирующий `agent` сессии, SHALL переходить в `waiting` с `waitingFor: subagents` и возвращать слот; остальные вызовы той же группы SHALL исполняться без слота и его не ждать;
- когда последний такой `agent` дождался своих детей, этот вызов SHALL получать слот снова — раньше новых детей очереди — до своего результата, поэтому его `ToolCallFinished` идёт после повторного взятия слота (SUB-23); отмена в очереди за слотом даёт вызову `cancelled`;
- пока у потомка открыт вопрос пользователю, `waitingFor` SHALL быть `approval`, даже если он ждёт и детей (design.md, D46, п. 1);
- новые дети SHALL получать слоты в порядке `spawn`;
- число `spawn` во всём дереве за ход корневой сессии SHALL быть не больше `max_per_turn`. Сверх лимита — ошибка `Subagent limit reached: at most <N> subagents per turn. …` (SUB-5);
- ребёнок, отменённый в очереди, SHALL не делать запросов к модели и не создавать журнал.

Значения `max_concurrent`, `max_per_turn` и бюджетов SHALL браться из ключей `subagents.*` текущего `CoreConfig` при каждом `spawn` (agent-configuration «Ключи subagents в схеме и реестре настроек»). `max_depth` SHALL браться из конфига корневой сессии при её создании и действовать на всё её дерево — описание `agent` корня и потомков и наборы потомков (design.md, D46, п. 2); `max_depth` и `enabled` меняют схему `agent` только в новых корневых сессиях.

#### Scenario: Нет взаимоблокировки при одном слоте
- **WHEN** `max_concurrent: 1`, `max_depth: 3`, ребёнок запускает внука, внук — правнука
- **THEN** все трое завершаются, ход корня завершается `end_turn` (`core/subagent-nested-no-deadlock`)

#### Scenario: Возвращающийся родитель раньше нового ребёнка
- **WHEN** при `max_concurrent: 1` внук завершился, а в очереди уже стоит новый ребёнок корня, поставленный позже
- **THEN** слот получает ребёнок-родитель внука, новый ребёнок — после него (`subagent_nested_slots_test.dart`)

#### Scenario: Предел слотов дерева
- **WHEN** корень вызывает в одном ответе три `agent`, каждый ребёнок — по два `agent`, при `max_concurrent: 2`
- **THEN** в любой момент слот держат не больше двух потомков

#### Scenario: Слот в смешанной группе
- **WHEN** при `max_concurrent: 1` ребёнок в одном ответе вызывает `agent` и `exec`, внук ждёт слота
- **THEN** ребёнок в `waiting` с `waitingFor: subagents`, внук получает слот, `exec` ребёнка исполняется без слота; после завершения внука `ToolCallFinished` вызова `agent` ребёнка приходит после лога `subagent.slot.resume` (`subagent_nested_slots_test.dart`; D46, п. 1)

#### Scenario: Вопрос во время ожидания детей
- **WHEN** ребёнок ждёт внука блокирующим `agent`, а параллельный `exec` того же ребёнка ждёт решения пользователя
- **THEN** снимок ребёнка — `waiting` с `waitingFor: approval`; после ответа, пока внук работает, — `waitingFor: subagents` (`subagent_nested_slots_test.dart`)

#### Scenario: Перезагрузка max_depth посреди дерева
- **WHEN** корневая сессия создана при `max_depth: 3`, затем перезагрузка конфига ставит `max_depth: 1`, и корень запускает ребёнка
- **THEN** набор ребёнка содержит `agent`, его описание обещает ещё один уровень; новая корневая сессия создаётся уже без вложенности (`subagent_nested_slots_test.dart`; D46, п. 2)

#### Scenario: Внук получает пути и снимок корня
- **WHEN** при `max_depth: 3` ребёнок `general` запускает внука `general`
- **THEN** набор защищаемых путей политики внука — набор корневой сессии; при переданном снимке каталога навыков схема `skill` внука и его `readOnlyRoots` навыков совпадают с корневыми (`subagent_nested_skills_test.dart`, итерация 4)

#### Scenario: Лимит запусков считает внуков
- **WHEN** `max_per_turn: 3`, корень запускает двух детей, первый из них — двух внуков
- **THEN** второй внук получает ошибку лимита, остальные работают

### Requirement: Бюджет и usage дерева
Usage потомка SHALL входить в usage прямого родителя (`subagentUsage`) и транзитивно в usage хода корневой сессии.

У потомка SHALL быть свой `TurnBudget` из `subagents.max_steps`, `max_tokens`, `max_cost`, `max_duration`. На каждой границе шага потомок SHALL проверять также остаток `maxTokens`/`maxCost` всех предков до бюджета хода корня. Исчерпан бюджет любого из них → потомок останавливается с `failed` и `failure: budget_exceeded:<limit>` (SUB-11).

#### Scenario: Бюджет корня останавливает внука
- **WHEN** `maxTokens` хода корня исчерпан usage внука, пока корень и ребёнок ждут
- **THEN** внук останавливается на своей границе шага с `budget_exceeded:tokens`, его usage входит в `TurnEnded.usage` корня (`subagent_tree_budget_test.dart`)

### Requirement: Жизненный цикл и отмена
Хэндл SHALL проходить состояния `queued`, `running`, `waiting`, `completed`, `failed`, `cancelled`. Терминальное состояние SHALL наступать ровно один раз; `report` SHALL завершаться ровно один раз и никогда ошибкой. При гонке отмены и завершения выигрывает первое записанное терминальное состояние.

Токен ребёнка SHALL быть потомком токена хода его родителя: отмена хода корня отменяет всё дерево, отмена ребёнка — его и его потомков, но не родителя и не соседей (SUB-6). `SubagentTool` SHALL ждать остановки детей не дольше `cancel_grace` от момента отмены, затем возвращать `cancelled`. `TurnEnded(cancelled)` родителя SHALL приходить после `ToolCallFinished` всех его `agent` (CAN-5).

События ребёнка после терминального состояния хэндла SHALL не переизлучаться, а его вопрос из очереди SHALL сниматься с исходом `cancelled`.

#### Scenario: Отмена хода корня
- **WHEN** во время работы ребёнка и внука клиент шлёт `session/cancel`
- **THEN** оба получают `cancelled`, `TurnEnded(cancelled)` корня приходит после `ToolCallFinished(agent)` с `cancelled` (`subagent_cancel_test.dart`)

#### Scenario: Отмена в момент завершения
- **WHEN** отмена хода приходит, когда ребёнок уже эмитит `TurnEnded(completed)`
- **THEN** у хэндла ровно одно терминальное состояние, вызов `agent` получает ровно один результат, лишних событий ребёнка после него в потоке родителя нет

### Requirement: Отчёт ребёнка
Отчёт SHALL строиться по §17.3.5 без ремонта по схеме: текст последнего ответа ребёнка; статус по `TurnEnded.reason`; усечение до `report_max_bytes` с пометкой.

Ответ, оборванный лимитом ответа модели (`TurnEnded.reason: maxTokens`), SHALL различаться по тексту последнего ответа (решение пользователя 2026-11-15; design.md change `add-subagents-and-tasks`, D41 п. 6):
- текст пуст после обрезки пробелов → `failed`, `failure: max_tokens`; модель родителя получает `reason="max_tokens"`, тело `Subagent stopped: it hit the output token limit before writing a report.` и `isError: true`;
- текст не пуст → `completed`; строка `[report truncated: the subagent hit the output token limit]` SHALL дописываться к тексту **после** усечения до `report_max_bytes` (§17.3.5, шаг 5), чтобы усечение её не отрезало; обёртка получает `truncated="true"`. Если сработали оба обрыва, отчёт несёт две пометки — сначала пометку усечения, затем пометку лимита, — а атрибут `truncated` один. Итоговый отчёт МОЖЕТ превысить `report_max_bytes` на длину пометки лимита — это сознательно.

Значение `max_tokens` SHALL записываться в `failure` итоговой записи `subagent` и уходить в `_meta.codelab.subagent.failure` (agent-acp-server «Проекция субагентов и списка задач»). `SubagentReport.toolCalls` и `usage` SHALL включать вызовы и usage всех потомков ребёнка (транзитивно), `duration` — время от получения слота до терминального состояния; у ребёнка, отменённого в очереди, — нули (design.md change `add-subagents-and-tasks`, D24).

Модель родителя SHALL получать один блок `<subagent-report id agent status steps tool_calls …>` внутри ограды `untrusted-content source="agent"`. Вхождения `</subagent-report` в тексте отчёта экранируются (SUB-7). Атрибуты и тела исходов — по таблице §17.3.5.

#### Scenario: Обёртка отчёта
- **WHEN** ребёнок `explore` завершается текстом с подстрокой `</subagent-report>`
- **THEN** результат `agent` — одна обёртка с `status="completed"` внутри ограды, подстрока экранирована (`subagent_report_wrapper_test.dart`)

#### Scenario: Итог с потомками
- **WHEN** ребёнок сделал 2 вызова и запустил внука, который сделал 3 вызова
- **THEN** `SubagentReport.toolCalls` ребёнка равен 6 (2 вызова, 1 вызов `agent` и 3 вызова внука), его `usage` — сумма usage ребёнка и внука

#### Scenario: Пустой отчёт по лимиту ответа
- **WHEN** последний ответ ребёнка `review` завершается `stopReason: length`, и весь ответ — рассуждение без текста
- **THEN** результат `agent` — `isError: true`, обёртка со `status="failed"` и `reason="max_tokens"`, тело `Subagent stopped: it hit the output token limit before writing a report.`; итоговая запись `subagent` — `failed` с `failure: max_tokens` (`subagent_report_wrapper_test.dart`; D41 п. 6)

#### Scenario: Оборванный отчёт по лимиту ответа
- **WHEN** последний ответ ребёнка `explore` — текст `Found three callers: a.dart, b.dart` и `stopReason: length`
- **THEN** результат `agent` — `isError: false`, обёртка со `status="completed"` и `truncated="true"`, тело — текст и строка `[report truncated: the subagent hit the output token limit]` (`subagent_report_wrapper_test.dart`)

#### Scenario: Оборванный и длинный отчёт
- **WHEN** последний ответ ребёнка длиннее `report_max_bytes` и завершается `stopReason: length`
- **THEN** тело — начало текста, затем пометка `[report truncated: <N> of <M> bytes shown; …]`, затем строка `[report truncated: the subagent hit the output token limit]`, каждая по одному разу; атрибут `truncated="true"` в обёртке один (`subagent_report_wrapper_test.dart`)

#### Scenario: Бюджет ребёнка
- **WHEN** `max_steps: 2`, а ребёнку нужно три шага
- **THEN** результат — `isError: true`, атрибут `reason="budget_exceeded:steps"`

### Requirement: Журнал субагента и прерывание
Журнал потомка любой глубины SHALL лежать в `<журнал корневой сессии без .jsonl>/subagents/`. Его заголовок SHALL содержать `parent` с полями `sessionId` (прямой родитель), `rootSessionId`, `toolCallId`, `subagentId`, `agent`, `depth`.

В журнал прямого родителя SHALL писаться запись `subagent`:
- `status: running` — при получении слота;
- итоговая запись с `status`, `failure`, `report`, `usage`, `toolCalls`, `durationMs` — `durable`, до `ToolCallFinished(agent)` (SUB-9, SUB-10); у отчёта, усечённого по `report_max_bytes` или оборванного лимитом ответа, — ещё `truncated: true`. Запись без поля SHALL читаться как не усечённая (design.md, D43, п. 5).

Дочерние журналы НЕ SHALL попадать в `session/list` и `index.json`. Lease корневой сессии SHALL покрывать журналы всего дерева.

После сбоя `healInterruptedTurn` SHALL для каждого вызова `agent` без результата:
- взять результат из итоговой записи `subagent`, если она есть, с атрибутом обёртки `truncated="true"` при `truncated: true`;
- иначе записать `interrupted`, дописать `subagent{status: failed, failure: interrupted}` и рекурсивно вылечить журнал ребёнка.

Ни один потомок НЕ SHALL перезапускаться. Если журнал потомка не открывается или его лечение падает, сессия SHALL писать лог `subagent.heal_failed` (`session_id`, `subagent_id`, `error_class`, без пути и текстов) и продолжать: результат `interrupted` и запись `subagent{status: failed, failure: interrupted}` у родителя пишутся, корневая сессия открывается (design.md, D46, п. 5).

#### Scenario: Раскладка внука
- **WHEN** ребёнок запускает внука
- **THEN** журнал внука лежит в `subagents/` корневой сессии, его заголовок — `parent.sessionId` ребёнка и `depth: 2`, запись `subagent` внука — в журнале ребёнка (`subagent_journal_test.dart`)

#### Scenario: Усечённый отчёт после сбоя
- **WHEN** итоговая запись `subagent` несёт отчёт, усечённый по `report_max_bytes` (во втором варианте — оборванный лимитом ответа), и `truncated: true`, а процесс убит до результата вызова `agent`
- **THEN** после `open` результат `agent` — та же обёртка с `truncated="true"`, что вживую; запись без поля `truncated` даёт обёртку без атрибута (`subagent_journal_test.dart`, задача 3.6)

#### Scenario: Рекурсивное лечение
- **WHEN** процесс убит, когда ребёнок ждёт внука, а внук исполняет `read`
- **THEN** после `open` вызов `agent` корня — `interrupted`, в журнале ребёнка вызов `agent` — `interrupted` и запись `subagent` внука `failed`/`interrupted`, в журнале внука вызов `read` — `interrupted`; ни один потомок не запущен снова (`subagent_journal_test.dart`, итерация 4)

#### Scenario: Журнал потомка не открывается
- **WHEN** после сбоя журнал ребёнка в статусе `running` удалён
- **THEN** корневая сессия открывается, вызов `agent` — `interrupted`, записан лог `subagent.heal_failed` с `subagent_id` (`subagent_journal_test.dart`; D46, п. 5)

#### Scenario: Сбой с двумя детьми
- **WHEN** процесс убит, когда ребёнок A завершён (итоговая запись есть), а B работает
- **THEN** после `open` вызов A получает отчёт из записи, B — `interrupted`, ни один ребёнок не запущен снова (`core/subagent-interrupted-not-restarted`)

### Requirement: События потомков в потоке родителя
`SubagentManager` SHALL эмитить в поток родителя `SubagentStarted`, `SubagentProgress` и `SubagentFinished`:
- порядок: `ToolCallStarted(agent)` → `SubagentStarted` → `SubagentProgress`… → `SubagentFinished` → `ToolCallFinished(agent)`;
- ребёнок, отменённый в очереди, даёт только `SubagentFinished(cancelled)`.

Каждое событие дочерней сессии родитель SHALL переизлучать как `SubagentActivity(subagentId, parentToolCallId, path, depth, event)`:
- обёртка плоская: событие внука переизлучается с исходным `event` и адресом внука;
- вложенных `SubagentActivity` нет (SUB-24).

`SubagentTool` SHALL вызывать `onUpdate` строкой прогресса `<agent> · <state> · <steps> steps · <toolCalls> tool calls · <tokens> tokens[ · <n> subagents][ · <lastActivity>]` (§17.3.4):
- при каждом `SubagentProgress`, но не чаще `progress_interval`;
- без событий — раз в `heartbeat_interval`.

#### Scenario: Адрес события внука
- **WHEN** внук вызывает `read`
- **THEN** поток корневой сессии содержит `SubagentActivity` с `depth: 2`, `path: [id ребёнка]`, `parentToolCallId` вызова `agent` ребёнка и `event` типа `ToolCallStarted`; журнал корня этого события не содержит (`subagent_activity_test.dart`)

