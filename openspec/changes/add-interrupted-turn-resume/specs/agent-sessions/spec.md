## ADDED Requirements

### Requirement: Незавершённый ход
Ядро SHALL предоставлять чистую функцию `unfinishedTurnOf(SessionSnapshot)`, которая возвращает `UnfinishedTurn` или `null` по активной ветке (design.md change `add-interrupted-turn-resume`, D3; SES-17):

1. найти последнюю запись `message` в `pathToLeaf`; записи других типов при поиске пропускаются; записи нет → `null`;
2. это сообщение роли `assistant` со `stopReason`, отличным от `aborted` (в том числе `error` и `origin: loop_note`) → `null`;
3. после него в ветке есть запись `custom` с `customType: "codelab.turn_stopped"` → `null`;
4. иначе ход незавершён;
5. `UnfinishedTurn.interruptedCalls` — вызовы последнего `assistant`-сообщения текущего хода, результат которых записан с `outcome: interrupted` или `outcome: cancelled`, в порядке ответа, каждый с `toolCallId`, именем инструмента и аргументами из журнала. Текущий ход начинается с последней записи `user`, для которой `isUserWords` истинно и `origin` не `steer`, или с записи `user` с `origin: turn_resume`. Без ответа модели в текущем ходе список пуст.

Функция SHALL быть детерминированной и НЕ SHALL менять снимок. `AgentSession.unfinishedTurn` SHALL возвращать `unfinishedTurnOf` текущего снимка писателя, а во время хода — `null`. При открытии сессии с незавершённым ходом SHALL писаться лог `session.turn.unfinished` (info) с `session_id` и числом `interrupted_calls`, без аргументов и текстов.

#### Scenario: Сбой во время инструмента
- **WHEN** журнал кончается ответом модели с вызовами `write` и `exec`, результатом `write` и, после лечения при открытии, синтетическим результатом `exec` с `outcome: interrupted`
- **THEN** `unfinishedTurnOf` возвращает ход с одним прерванным вызовом `exec` и его аргументами

#### Scenario: Сбой во время ответа модели
- **WHEN** журнал кончается сообщением пользователя без ответа модели
- **THEN** `unfinishedTurnOf` возвращает ход без прерванных вызовов

#### Scenario: Отмена пользователем после пакета инструментов
- **WHEN** ход отменён `session/cancel` после результатов пакета инструментов, и хвост ветки — `toolResult`, за которым следует запись `codelab.turn_stopped` с `reason: cancelled`
- **THEN** `unfinishedTurnOf` возвращает `null`

#### Scenario: Остановка процесса во время инструмента
- **WHEN** сессия закрыта `AgentSession.close()` во время `exec`, результат `exec` записан с `outcome: cancelled`, отметки `codelab.turn_stopped` нет
- **THEN** `unfinishedTurnOf` возвращает ход с вызовом `exec` в `interruptedCalls`

#### Scenario: Разрыв во время ответа модели
- **WHEN** ход отменён причиной `ConnectionLost` во время ответа модели, хвост ветки — ответ `aborted` без отметки
- **THEN** `unfinishedTurnOf` возвращает ход без прерванных вызовов

#### Scenario: Завершённый ход
- **WHEN** последнее сообщение ветки — ответ модели с `stopReason: stop` или `error`, либо ответ `aborted`, за которым следует отметка `codelab.turn_stopped`
- **THEN** `unfinishedTurnOf` возвращает `null`

#### Scenario: Служебная запись после хвоста
- **WHEN** после результата `interrupted` в ветке записаны `mode_change` и `compaction`
- **THEN** `unfinishedTurnOf` по-прежнему возвращает незавершённый ход

#### Scenario: Новый промпт оборван до ответа
- **WHEN** после загрузки с прерванным `exec` пользователь отправил «продолжай», и процесс упал до ответа модели
- **THEN** `unfinishedTurnOf` возвращает ход с пустым `interruptedCalls`: вызовы прошлого хода в список не попадают

## MODIFIED Requirements

### Requirement: Продолжение прерванного хода
`healInterruptedTurn` SHALL находить вызовы последнего assistant-сообщения ветки без результата и строить для каждого синтетическую запись `toolResult` с `outcome: "interrupted"`, `isError: true`, `toolMeta` вызова и текстом §8.8 (S-13). `AgentSession` SHALL записать их с `durable` сразу после `open()`, до реплея и до любого нового шага; `RepairReport.interruptedToolCalls` содержит их `toolCallId` (SES-10).

Вызовы с результатом НЕ SHALL повторяться; прерванный вызов НЕ SHALL перезапускаться автоматически. Сессия после загрузки — в состоянии `idle`, ход сам НЕ SHALL начинаться; следующий `prompt()` видит полную историю (SES-9).

Незавершённый ход (требование «Незавершённый ход») SHALL продолжаться двумя путями:
- обычным промптом пользователя — как прежде;
- командой `/continue` (capability `agent-slash-commands`, «Команда /continue») — ход цикла начинается со служебного сообщения `user` с `origin: "turn_resume"`, без слов пользователя (design.md change `add-interrupted-turn-resume`, D1, D6).

Ни один путь НЕ SHALL исполнять вызовы журнала заново. Повтор прерванного вызова моделью проходит правило политики «Повтор прерванного вызова» (capability `agent-permissions`).

#### Scenario: Сбой после инструмента
- **WHEN** ход выполнил `write a.txt`, начал долгий `exec`, и процесс остановился до результата `exec`
- **THEN** после `loadSession` у `write` результат из журнала, у `exec` — синтетический `interrupted`; после `prompt("продолжай")` счётчик вызовов `write` равен 1, а запрос к модели содержит обе пары вызов-результат

#### Scenario: Прерванный вызов не повторяется
- **WHEN** сессия с прерванным вызовом открывается дважды подряд
- **THEN** синтетический результат дописан один раз, инструмент не вызывался

#### Scenario: Продолжение командой
- **WHEN** после сценария «Сбой после инструмента» приходит `/continue`
- **THEN** запрос к модели содержит обе пары вызов-результат и последним — сообщение `user` с текстом продолжения; в журнале новая запись `user` с `origin: "turn_resume"` и нет записи с текстом `/continue`; счётчики вызовов `write` и `exec` не изменились до решения модели

#### Scenario: Загрузка не начинает ход
- **WHEN** сессия с незавершённым ходом открывается через `loadSession`
- **THEN** ни одного запроса к модели и ни одного вызова инструмента нет, пока не придёт `prompt()`

### Requirement: Слова пользователя
Решение «этот текст написал пользователь» по записи журнала SHALL принимать только `isUserWords`, а по событию — `isUserWordsEvent` (§8.2.5, SES-14):
- запись не `message` или роль не `user` → `false`;
- запись `user` без `origin` → `true`;
- известный `origin` → по `classifyOrigin`: `steer` и `parent_message` — слова пользователя, остальные значения `RecordOrigin` — служебные, в том числе `turn_resume` — служебное сообщение хода `/continue` (design.md change `add-interrupted-turn-resume`, D6);
- неизвестный `origin` → `false` и одно предупреждение `session.origin.unknown` на значение за процесс.

Классификация SHALL быть полной: каждый элемент `RecordOrigin` и каждый подкласс `MessageOrigin` имеют явный класс (SES-15). Сообщение с неизвестным `origin` остаётся в контексте модели.

#### Scenario: Полнота классификации
- **WHEN** `user_words_test.dart` проходит таблицу всех записей фикстуры `all_origins.jsonl`
- **THEN** ответ совпадает с ожидаемым для каждой строки, а таблица ожиданий содержит строку на каждый элемент `RecordOrigin.values`

#### Scenario: Подсказка цикла не слова пользователя
- **WHEN** запись `user` имеет `origin: "loop_nudge"`
- **THEN** `isUserWords` возвращает `false`, а `buildLlmContext` включает сообщение в контекст

#### Scenario: Продолжение хода не слова пользователя
- **WHEN** запись `user` имеет `origin: "turn_resume"`
- **THEN** `isUserWords` возвращает `false`; `buildLlmContext` включает сообщение в контекст; реплей не отправляет по нему `user_message_chunk`; заголовок сессии из него не строится

### Requirement: Запись журнала из событий
`SessionWriter` SHALL быть первым подписчиком `Agent` сессии и писать журнал по таблице §8.3 (design.md change `add-agent-core-sessions-and-compaction`, D2, D4; change `add-subagents-and-tasks`, D7, D12, D29; change `add-interrupted-turn-resume`, D3):

| Событие | Запись | `durable` |
|---|---|---|
| `MessageEnded` (user, assistant) | `message`; у служебных сообщений — `origin` из `MessageStarted.origin` (у хода `/continue` — `turn_resume`) | нет |
| `MessageEnded` (toolResult) | `message` с `outcome`, `diff`, `toolMeta` вызова | да |
| `ModeChanged` | `mode_change` | нет |
| `TaskListChanged` | `task` из `change` (только в журнале корневой сессии); при `change.op == restore` — ничего: состояние выводится из ветки (TSK-1) | нет |
| `SubagentStarted` | `subagent` со `status: running` | да |
| `SubagentFinished` | итоговая `subagent` со `status`, `failure`, `report`, `usage` | да |
| `SubagentProgress`, `SubagentActivity` | ничего | — |
| `ContextCompacted` | `compaction` пишется компактором до события | да |
| `SessionTitleChanged` | `session_info` | нет |
| `TurnEnded` с `stopMark` | `custom` с `customType: "codelab.turn_stopped"` и `data: {"reason": "cancelled" \| "failed" \| "budget"}`, у бюджета ещё `limit` — вид лимита; затем сброс | да |
| `TurnEnded` без `stopMark` | ничего; сброс последней записи хода | да |

Каждое сообщение транскрипта SHALL быть записано до перехода цикла к следующему действию (SES-8). Результат каждого инструмента SHALL быть записан с `durable` до следующего запроса к модели (SES-9). Итоговая запись `subagent` SHALL быть записана до `ToolCallFinished(agent)` (SUB-10). Индекс снимка в памяти обновляется только после успешной записи. Запись `codelab.turn_stopped` в контекст модели и в реплей НЕ SHALL попадать.

`TurnEnded.stopMark` SHALL ставить только `AgentLoop` (design.md change `add-interrupted-turn-resume`, D3):
- `cancelled` — ход отменён причиной `UserCancel`;
- `failed` — ход завершился `failed`;
- `budget` — задан `budgetExceeded`.

Отмена причинами `ShutdownCancel` и `ConnectionLost` `stopMark` НЕ SHALL давать. `TurnEnded` встроенных команд и `TurnEnded`, собранный вне цикла, `stopMark` НЕ SHALL иметь.

Ошибка записи SHALL давать лог `session.append.failed`, `AgentError(cls: storage, retrying: false)` и `TurnEnded(failed)`: ход, который нельзя сохранить, не продолжается (design.md change `add-agent-core-sessions-and-compaction`, D4).

#### Scenario: Побайтово одинаковый журнал
- **WHEN** один сценарий с вызовами `read`, `edit`, `task_create` и `agent` дважды выполняется на `FakeClock` и `SequentialIdGenerator`
- **THEN** оба журнала корня и оба журнала ребёнка побайтово равны (`deterministic_journal_test.dart`, PKG-6)

#### Scenario: Восстановление списка не пишется
- **WHEN** `TaskList.restore(announce: true)` публикует `TaskListChanged` с `op: restore`
- **THEN** журнал побайтово не изменился, записи `task` нет (`task_list_restore_test.dart`)

#### Scenario: Ошибка записи завершает ход
- **WHEN** хранилище возвращает ошибку на записи результата инструмента
- **THEN** эмитится `AgentError(cls: storage)`, ход завершается `TurnEnded(failed)`, следующий запрос к модели не делается

#### Scenario: Отметка остановки при отмене
- **WHEN** ход отменён `session/cancel` после результатов пакета инструментов
- **THEN** последняя запись хода — `custom` `codelab.turn_stopped` с `reason: cancelled`, записанная с `durable`

#### Scenario: Отметка остановки по бюджету
- **WHEN** ход исчерпал `maxSteps` после шага с вызовами инструментов
- **THEN** последняя запись хода — `codelab.turn_stopped` с `reason: budget` и `limit: steps`

#### Scenario: Обычный ход без отметки
- **WHEN** ход завершился финальным ответом модели; во втором варианте встроенная команда `/compact` отменена; в третьем `/compact` завершился `failed` (`CompactionFailed`)
- **THEN** ни в одном варианте записи `codelab.turn_stopped` нет

#### Scenario: Остановка процесса без отметки
- **WHEN** ход отменён `AgentSession.close()` (`ShutdownCancel`) или истечением grace (`ConnectionLost`) после результатов пакета инструментов
- **THEN** `TurnEnded` — `cancelled` без `stopMark`, записи `codelab.turn_stopped` нет

### Requirement: Журнал usage сессии
Ядро SHALL строить журнал usage сессии чистой функцией записей журнала (`SessionSnapshot`): одинаковые записи дают равный журнал, время построения и другие значения вне журнала в него не входят (OBS-10 в редакции change `add-usage-ledger`; design.md, D1). Правила свёртки:
- **шаг** — запись `message` роли `assistant`, кроме `origin: loop_note`; usage — `message.usage`, модель — `<provider>/<id>` из `message.model`; ответы с `stopReason: error` — тоже шаги; номер шага — с 0 внутри хода по порядку записей; шаг несёт `recordId` и `toolCallIds` — id блоков `toolCall` ответа в их порядке;
- **`noUsage`** у шага — `stopReason` не `error`, и `input`, `output`, `cacheRead`, `cacheWrite` равны нулю (правило D6 и D26 change `add-usage-extension`);
- **ход** — начинается с записи `user`, для которой `isUserWords` истинно и `origin` не `steer`, а также с записи `user` с `origin: turn_resume` (ход `/continue`; design.md change `add-interrupted-turn-resume`, D6); остальные записи до следующего начала хода принадлежат ходу (решение Q9 (а)); подпись хода — по правилу заголовка сессии S-16 (`sessionTitleFrom`: пробелы и переводы строк схлопываются, края обрезаются, предел 64 руны), для записи с `command` — исходный текст команды, для записи `turn_resume` — `/continue`; ход без шагов в журнал не входит;
- **субагенты** — последняя запись `subagent` каждого `subagentId` в файле с завершённым статусом и `usage`: число прогонов и сумма usage; usage прогона входит в итог хода, в котором лежит эта запись, и в итог сессии, но шагом не считается; журналы детей не читаются;
- **суммаризатор** — записи `compaction` с `details.usage` и записи учёта отброшенных проходов `custom` `codelab.compaction_discarded` (требование «Отброшенные вызовы суммаризатора в журнале usage»; change `fix-discarded-compaction-usage`, D3): число, число отброшенных `discarded`, сумма и отсортированный список различных моделей `details.summaryModel` и `data.summaryModel`; вызов со всеми нулевыми счётчиками — `noUsage`, причина входит в `summaries` и итог; входит в итог сессии, не в ход;
- **модели** — суммы шагов по модели, в лексикографическом порядке; субагенты и суммаризатор в модели не входят;
- **порядок** — ходы и шаги по пути до активного листа (§8.4); итог, модели, субагенты и суммаризатор — по всем записям файла; суммирование — в порядке файла;
- в журнал НЕ SHALL попадать тексты сообщений, аргументы и результаты инструментов, кроме подписи хода.

Отчёт для показа SHALL дополнять журнал состоянием файла (D3: `upToDate`, `rebuilt` с причиной `missing`, `invalid`, `stale`, `explicit`, `inMemory`, `notSaved` с причиной) и множеством моделей без цены, посчитанным по каталогу моделей сессии в момент построения отчёта: у модели нет цен или её нет в каталоге (решение Q4 (а)). Признак цены в журнал и в `usage.json` НЕ SHALL записываться. Цена групп без шагов (design.md, D2): запись суммаризатора — с ценой, если её `summaryModel` есть в каталоге с ценами, иначе при ненулевых токенах — без цены; прогон субагента с ненулевыми токенами и нулевой стоимостью — без цены (модели детей не видны, эвристика Q13 (б) change `add-usage-extension`); группа с частями без цены получает `noPrice`, а без единой части с ценой — не имеет стоимости. `AgentSession` SHALL отдавать отчёт операцией с параметром `rebuild` и вариантом построения в памяти без файла (для засева адаптера, capability `agent-acp-server`, «Полная сумма сессии после session/load»).

#### Scenario: Ходы и шаги
- **WHEN** журнал содержит промпт, ответ модели с вызовом `read`, результат инструмента, второй ответ модели, затем второй промпт и ответ модели
- **THEN** в журнале usage два хода: первый с двумя шагами (у первого — `toolCallIds` с id вызова), второй с одним; итог равен сумме трёх шагов (`usage_ledger_test.dart`)

#### Scenario: Steering не открывает ход
- **WHEN** посреди хода в журнале есть запись `user` с `origin: steer`, за ней ответ модели
- **THEN** этот ответ — шаг того же хода; число ходов не растёт

#### Scenario: Заметка цикла не шаг
- **WHEN** в журнале есть запись `assistant` с `origin: loop_note`
- **THEN** шагом она не считается и в итог не входит

#### Scenario: Субагент и суммаризатор
- **WHEN** в ходе есть завершённая запись `subagent` с usage, а после хода — запись `compaction` с `details.usage`
- **THEN** итог хода включает usage субагента; `subagents.runs` — 1; `summaries.count` — 1; итог сессии — сумма шагов, субагента и суммаризатора; в моделях нет ни субагента, ни суммаризатора

#### Scenario: Детерминизм
- **WHEN** журнал usage строится дважды из одного снимка
- **THEN** сериализации равны побайтово (`core/usage-ledger-rebuild-deterministic`, OBS-10)

#### Scenario: Цена по каталогу
- **WHEN** в журнале шаги моделей A (с ценами в каталоге) и B (без цен), и отчёт строится
- **THEN** модель B в множестве моделей без цены, A — нет; содержимое журнала от каталога не зависит

#### Scenario: Ход продолжения
- **WHEN** журнал содержит прерванный ход с одним шагом, затем запись `user` с `origin: turn_resume` и два ответа модели
- **THEN** в журнале usage два хода: прерванный с одним шагом и ход с подписью `/continue` и двумя шагами; итог хода `/continue` в свёртке равен итогу его живого снимка `turn`
