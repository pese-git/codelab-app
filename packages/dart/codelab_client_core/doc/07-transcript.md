# Транскрипт: проекция, стриминг, заметки

Глава разбирает, как слой превращает ходы сессии в ленту `SessionView.transcript`: какие бывают элементы, как проекция обрабатывает поток кусков ответа, почему повторные и поздние события ей не вредят, какие заметки слой добавляет сам и как устроены вызовы субагентов. Одобрения внутри ленты — [глава 8](08-approvals.md).

## Что хост видит

`SessionView.transcript` — `List<TranscriptItem>`: готовые к отображению элементы, а не сырые `session/update`. Протокольные данные и read-модель `AcpSession` — не представление (корневой `AGENTS.md` §7), поэтому хост показывает ленту через `switch`:

| Элемент | Что это |
|---|---|
| `UserItem(id, text)` | текст промпта пользователя |
| `AgentTextItem(id, text)` | сплошной отрезок `agent_message_chunk` |
| `ThoughtItem(id, text)` | сплошной отрезок `agent_thought_chunk` |
| `ToolCallItem` | вызов инструмента: `toolCallId`, `title`, `details` (`ToolCallView`), `approval`, `childApprovals`, `children`, `tail`, `subtreeCalls` |
| `TaskOpsItem` | тихая строка операций со списком задач вместо вызова `think` |
| `NoticeItem(id, kind, text, failure, reason)` | итог хода или события связи, которых не видно из обновлений агента |

Порядок: ходы сессии по порядку; в ходе — промпт, затем элементы по порядку обновлений агента, затем одобрения вызовов, о которых агент не объявлял `tool_call`, затем итоговые заметки.

`id` элемента стабилен, пока элемент живёт: растущий текст сохраняет `id`, и по нему хост держит ключ виджета. Реальный пример (временный скрипт на `KitAgent`): ход с текстом из двух кусков и вызовом `read`, пришедшим дважды.

```text
after duplicate tool_call:
  turn-1/prompt  UserItem  "read a.dart"
  turn-1/text-0  AgentTextItem  "Looking at it."
  turn-1/tool-c1  ToolCallItem  "Read a.dart" queued Read lib/a.dart
after the turn ended with max_tokens:
  turn-1/prompt  UserItem  "read a.dart"
  turn-1/text-0  AgentTextItem  "Looking at it."
  turn-1/tool-c1  ToolCallItem  "Read a.dart" succeeded Read lib/a.dart
  turn-1/stopped  NoticeItem  turnStopped "The model reached its token limit, so the turn ended."
```

`turn-1/text-0` — отрезок текста, начавшийся с обновления номер 0; `turn-1/tool-c1` — вызов `c1`. Два куска `Looking` и ` at it.` слились в один элемент, а повторный `tool_call` не добавил второй `ToolCallItem`.

## Проектор

Проекция живёт в `TranscriptProjector` (`lib/src/transcript/transcript_projector.dart`, из бареля не экспортируется). Он нужен потому, что раньше транскрипт пересчитывался с нуля на каждое изменение сессии, и длинные ходы дорожали с каждым словом (design D5 change `extract-acp-client-kit`).

Как работает:

- один проектор на сессию (`_SessionHandle._projector`); `apply(AcpSession)` вызывается с каждым снимком по порядку;
- на каждый ход есть `_TurnProjection`; он помнит, сколько обновлений уже обработано (`_processed`), и разбирает только новые;
- снимок, ход которого не изменился (тот же объект, `identical`), — пустая операция: `apply` вернёт `false`, `items` останется тем же списком;
- статус вызова и одобрение читаются из живой read-модели хода (`turn.toolCalls`, `turn.approvals`), а не из обновления: так же их показывал прежний пересчёт;
- дерево вызовов потомков строится из плоского списка на каждом применении: родитель может прийти позже ребёнка.

**Эталон.** `projectTranscript(session)` пересчитывает ленту с нуля по всем ходам. Результат инкрементальной проекции на каждом шаге обязан совпадать с ним: это свойство проверяет `test/transcript/transcript_projector_test.dart` на каждой фикстуре корпуса с ролью `client` ([глава 14](14-testing.md)). Любое изменение проекции вносится в обе ветки: и в `_TurnProjection`, и в `_rebuildTurn`.

### Куски ответа

Правило отрезков: подряд идущие `agent_message_chunk` дописываются в один `AgentTextItem`, подряд идущие `agent_thought_chunk` — в один `ThoughtItem`. Любое другое обновление закрывает отрезок: вызов инструмента, план, смена вида куска. Текст отрезка обрезается по краям (`trim`): отрезок из одних пробелов элемента не создаёт.

### Идемпотентность и поздние события

Стриминг в слое ведёт себя предсказуемо (`AGENTS.md` §9):

- **Повторный `tool_call`.** Тот же `toolCallId` обновляет элемент на прежней позиции (`_toolPositions`), второго не добавляет.
- **Повторный снимок.** `identical`-снимок — пустая операция и в проекторе, и в `SessionHandle.update`: `revision` не растёт.
- **Реплей `session/load`.** Id ходов реплея могут совпасть с прежними, поэтому рабочее пространство сбрасывает проекцию самим событием загрузки (`TranscriptProjector.reset`). Если ходов стало меньше, проектор тоже строит ленту заново: внутри одной сессии ходы не исчезают, меньший список значит, что сессию заменили.
- **Поздние события старого соединения.** Отбрасывает ядро клиента по поколению соединения, не проектор. Слой на это опирается и проверяет `test/workspace/superseded_attempt_test.dart` и `test/approvals/approvals_dropped_on_connection_change_test.dart`.

Что слой **не** делает: не сверяет `seq` и не сортирует обновления. Порядок — порядок прихода `session/update`, как его принимает ядро клиента.

## Статус вызова

`ToolCallView.status` (`ToolCallStatusView`):

| Значение | Откуда |
|---|---|
| `queued` | `ToolCallStatus.pending` |
| `running` | `inProgress` |
| `succeeded` | `completed` |
| `failed` | `failed` |
| `cancelled` | признак `cancelledByClient` (клиент отправил `session/cancel`) или `_meta.codelab.outcome: cancelled` у `failed`-кадра |

`cancelled` — вид слоя: в ACP такого статуса у вызова нет. Первый источник — ядро клиента: `session/cancel` помечает объявленные вызовы флагом, статус остаётся `failed`. Второй — признак агента CodeLab, он же возвращается при реплее.

`ToolCallView` несёт и готовые для строки поля: `kind`, `command` (из `rawInput.command`), `rawInput`, `paths`, `textOutput` (тексты `content`).

Короткую строку «Read lib/a.dart» строит `ToolRowFormatter.format(item, cwd:)` (`lib/src/transcript/tool_row.dart`): метка по виду (`Read`, `Edit`, `Delete`, `Move`, `Search`, `Run`, `Fetch`, `Think`, `Mode`; у `other` — сам `title`, а при пустом `title` — `Tool`), деталь (путь относительно `cwd`, команда, шаблон поиска, адрес без схемы и query) и `secondary` — первая строка ошибки у `failed`. Деталь очищается от управляющих символов, секреты маскируются `SecretRedactor`, длина ограничена `maxDetailLength` = 160. Хост рисует `ToolRowView` своими средствами; сырой `rawInput` он не показывает.

## Заметки `NoticeItem`

Заметка — итог хода или события связи, которого нет в обновлениях агента. Текст `NoticeItem.text` английский и нужен CLI; хост с локализацией строит текст по типизированному полю.

| `kind` | Когда | `text` | Поле для хоста |
|---|---|---|---|
| `error` | ход сорвался | `Failed to send prompt: <причина>`; префикс типа исключения срезается | `failure` — `PromptFailure` (заголовок строит хост) |
| `emptyTurn` | ход завершён без вывода агента | `Completed with stopReason <причина>.` (без причины — `unknown`) | `reason` — `EmptyTurnReason(stopReason)` |
| `turnStopped` | `stopReason` — `max_tokens`, `max_turn_requests` или `refusal` | см. ниже | `reason` — `TurnStoppedReason(stopReason, budgetLimit)` |
| `detached` | сессия потеряла связь с агентом ([глава 4](04-sessions.md)) | `The agent cannot restore sessions after reconnecting.` или `Session <id> could not be restored after reconnecting.` | `reason` — `SessionRestoreReason` |
| `reconnected` | при восстановлении создана новая сессия вместо прежней ([глава 5](05-restore.md)) | `The agent cannot restore sessions; a new session was started.` или `Session <id> could not be restored; a new session was started.` | `reason` — `SessionRestoreReason` |

Тексты `turnStopped`:

- `max_tokens` — `The model reached its token limit, so the turn ended.`
- `max_turn_requests` — `The turn reached the limit of model requests.`; если агент назвал лимит бюджета из известного набора (`steps`, `tokens`, `cost`, `duration`, `deadline`), то `The turn stopped: budget exceeded: <лимит>.`; незнакомое значение даёт прежний текст — подставлять строку агента в заметку нельзя;
- `refusal` — `The agent refused to continue.`

Правила:

- `turnStopped` добавляется всегда, даже если агент что-то вывел; id заметок — `<turnId>/stopped`, `<turnId>/completed`, `<turnId>/error`. Ходу с `turnStopped` заметка `emptyTurn` не добавляется; сорвавшемуся ходу тоже: его объясняет `error`.
- **Реплей `session/load` заметки исхода не получает.** ACP не передаёт `stopReason` в реплее, а клиент исход хода не хранит. Ход реплея без вывода агента получит `emptyTurn` с «stopReason unknown». Это принятое решение (D27, Q36), а не дефект проекции; живой ход после загрузки получает заметку как обычно.
- Заметки `detached` и `reconnected` добавляет не проектор, а рабочее пространство: они встают в ленту на месте, где были в момент прихода (`_noticeAt`), и следующие ходы идут ниже. Если проекция стала короче, заметка встаёт в конец.

Причины — `sealed class NoticeReason`: `EmptyTurnReason`, `TurnStoppedReason`, `SessionRestoreReason`. Проекция с нуля и инкрементальная дают равные причины (`test/transcript/notice_reason_test.dart`).

## Вызовы потомков и субагенты

Агент CodeLab запускает субагента вызовом `agent`, который приходит как вызов `think` с признаком `_meta.codelab.subagent`. Слой разбирает это в готовые поля; хост `_meta` не парсит.

- **Признак вызова.** `ToolCallView.subagentCall` — `SubagentCallView(id, type)` из `_meta.codelab.subagent` первого кадра; `null` — обычный вызов (сторонний агент). У реплея отклонённого вызова `id` нет, и придумывать его нельзя.
- **Итог.** `ToolCallView.subagentSummary` — `SubagentSummaryView`: число вызовов, токены, длительность; строки `N tool calls · N.Nk tokens · <время>` — `text` и `shortText`. Причина отказа — `subagentFailure`.
- **Дерево вызовов.** Клиент объявляет расширение `subagentToolCalls` при `initialize` (`codelabClientExtensionsMeta` в `codelab_client_acp`), и агент CodeLab присылает кадры вызовов потомков обычным потоком `tool_call` с `_meta.codelab.parentToolCallId`. `buildToolCallTree` складывает их в `ToolCallItem.children` под строкой `agent`. Вызов с неизвестным родителем и вызовы в цикле родителей остаются на верхнем уровне — ошибки нет. Без этого объявления агент кадров потомков не шлёт, и лента плоская.
- **Хвост работающего `agent`.** `ToolCallItem.tail` — три последних вызова поддерева и число остальных (`moreCount`); `subtreeCalls` — число вызовов поддерева для счётчика `N tool calls`. Совпадает с `summary.toolCalls` итога, поэтому счётчик не прыгает на финале.
- **Операции со списком задач.** Вызов `think` со списком задач слой показывает `TaskOpsItem` — тихой строкой «Task #3 added to the plan», «Tasks #1–#4 added to the plan», «Task #2 done», «Task #2 removed», «Task #2 updated»; подряд идущие операции одного родителя сливаются. Данные — из `plan._meta.codelab.taskChange`.
- **Панель Agents.** `SessionView.subagents` — `SubagentRowView` на каждый вызов `agent`, любой глубины: состояние (`running`, `awaitingApproval`, `completed`, `failed`, `cancelled`), глубина, путь по `TranscriptItem.id`, время начала, итог, последнее действие, пункты плана и ожидающее одобрение. Строки считает `subagentRowsOf` с памятью `SubagentRowMemory` на сессию: первое появление вызова по часам `ClientWorkspace` (параметр `clock`) и последний итоговый статус.

Разбор терпимый: неизвестные ключи и неверная форма означают «данных нет», а не ошибку обработки обновления; поздний кадр без поля не стирает известное значение. Тесты — `test/transcript/subagent_*_test.dart`, `task_ops_item_test.dart`, `test/session/session_subagents_test.dart`.

## Инспектор по ходу

`InspectorProjection` строит из `AcpSession` записи об одобрениях, вызовах, обновлениях и ходе ([глава 11](11-inspector-diagnostics-frames.md)). Это отдельная проекция: лента для чтения, инспектор — для диагностики протокола.
