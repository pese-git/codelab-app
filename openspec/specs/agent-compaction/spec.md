# agent-compaction Specification

## Purpose
Сжатие контекста Dart-агента: оценка размера в токенах с якорем на `usage`, пороги по окну модели, точка среза без разрыва пар вызов ↔ результат, резюме старой части ветки моделью сессии с итеративным обновлением, запись `compaction` в журнал и пересборка контекста, точки срабатывания `afterTurn`, `preflight`, `overflow` и `manual` (`agent-core-architecture` §9).
## Requirements
### Requirement: Оценка токенов с якорем на usage
`estimateTokens` SHALL оценивать сообщения эвристикой «4 символа UTF-16 ≈ 1 токен» по таблице §9.3 документа ядра:
- текст и рассуждение — `ceil(length / 4)`, у `redacted` рассуждения — по длине подписи;
- вызов — `ceil((name.length + jsonEncode(arguments).length) / 4)`;
- картинка — константа `1200`;
- `+4` на сообщение, у результата инструмента ещё `ceil(toolName.length / 4)`;
- системный промпт и схемы инструментов — по длине их текста.

`estimateContextTokens` SHALL якориться на последнем assistant-сообщении с ненулевым `usage.input + usage.cacheRead + usage.cacheWrite`: результат — эта сумма плюс `usage.output` плюс оценка сообщений после него. Без такого сообщения результат — оценка системного промпта, схем и всех сообщений.

`effectiveContextWindow(model, cap)` = `min(model.contextWindow, cap)` SHALL быть единственной функцией окна для порога сжатия, проверки перед запросом и `ModelRequested.estimatedTokens` (CMP-6).

#### Scenario: Пример из документа ядра
- **WHEN** ответ ассистента имеет `usage = {input: 41000, cacheRead: 9000, output: 600}`, а после него идут результат `read` на 12 000 символов и сообщение пользователя на 200 символов
- **THEN** `estimateContextTokens` возвращает `53 659`

#### Scenario: Обнулённый usage не якорь
- **WHEN** все assistant-сообщения проекции имеют `Usage.zero` после сжатия
- **THEN** оценка считается по символам всех сообщений, системного промпта и схем

#### Scenario: Одна функция окна
- **WHEN** окно модели 128 000, а `contextWindowCap` равен 50 000
- **THEN** порог, проверка перед запросом и `estimatedTokens` считаются от 50 000

### Requirement: Пороги сжатия
`CompactionSettings.forWindow(w)` SHALL вычислять `reserveTokens` и `keepRecentTokens` по алгоритму §9.4: `reserve` — от `w/4` в пределах `[1024, 16384]`, но не больше четверти крошечного окна; `keepRecent` — от `w/2` в пределах `[2048, 20000]`, но не больше половины крошечного окна; `keepRecentUserTurns` — 1. Порог — `w - reserve`; `shouldCompact` — оценка строго больше порога.

Значения `CompactionOverrides` SHALL заменять вычисленные и проходить те же ограничения сверху `w/4` и `w/2`.

#### Scenario: Таблица окон
- **WHEN** `forWindow` вызывается для окон 2 048, 8 192, 32 768, 128 000 и 200 000
- **THEN** `reserve`, `keepRecent` и порог совпадают с таблицей §9.4

#### Scenario: Переопределение больше четверти окна
- **WHEN** окно 8 192, а `CompactionOverrides.reserveTokens` равен 6 000
- **THEN** `reserveTokens` равен 2 048

### Requirement: Точка среза
`findCutPoint(region, settings)` SHALL выбирать первую запись хвоста по алгоритму §9.6:
- хвост копится с конца до `keepRecentTokens`;
- срез — только перед user- или assistant-сообщением (CMP-1);
- последние `keepRecentUserTurns` ходов пользователя (записи с `isUserWords`) остаются в хвосте;
- служебные записи (`model_change`, `mode_change`, `config_change`, `plan`, `session_info`, `label`) прямо перед срезом остаются с хвостом;
- срез внутри хода даёт `splitTurn = true` и `turnStartIndex`;
- нечего сжимать → `null`.

Регион — записи активной ветки начиная с `firstKeptId` последнего сжатия или с начала ветки.

#### Scenario: Пример из документа ядра
- **WHEN** регион из примера §9.6 сжимается с `keepRecentTokens = 4096`
- **THEN** сжимаются записи 0–3, `firstKeptId` — id записи 4 (`mode_change`), `splitTurn == false`

#### Scenario: Пакет вызовов не разрывается
- **WHEN** длинный пакет вызовов и результатов попадает на границу хвоста
- **THEN** первая запись хвоста — user- или assistant-сообщение, и ни один результат не отделён от своего вызова

### Requirement: Генерация резюме
Резюме SHALL генерироваться той же `StreamFunction` с моделью сессии, без инструментов, с системным промптом `compaction/system.md` и `cacheKey` `<sessionId>:summary` (§9.7, design.md, D8). Регион передаётся сериализованным текстом с заголовками `[user]`, `[notice]`, `[assistant]`, `[tool call <name>]`, `[tool result <name>]`; результаты длиннее 4 000 символов сокращаются до первых и последних 1 500 символов с пометкой.

Текст запроса SHALL строиться по шаблону:
- `compaction/summary.md` — при первом сжатии;
- `compaction/summary_update.md` с `previousSummary` — при повторном (CMP-9).

Блок `{{focus}}` — шаблон `compaction/focus.md` при указании `focus`, иначе пустая строка. При разрезанном ходе начало хода резюмируется по `compaction/turn_context.md`, а сообщение пользователя (до 2 000 символов) копируется в резюме дословно (CMP-7).

Ошибка модели и пустой ответ SHALL давать `CompactionFailed`; отмена SHALL пробрасываться как `CancelledException` (CMP-4). Тексты промптов пишутся для CodeLab (design.md, D9).

#### Scenario: Итеративное обновление
- **WHEN** второе сжатие сессии запускается после первого
- **THEN** запрос к суммаризатору построен по `summary_update.md` и содержит открытую просьбу из первого резюме

#### Scenario: Указание focus
- **WHEN** `compact` вызывается с триггером `manual` и `focus: "API changes"`
- **THEN** запрос к суммаризатору содержит блок `<focus>` с этим текстом; без `focus` и для других триггеров блока нет

### Requirement: Запись сжатия и пересборка
`compact(snapshot, trigger, ...)` SHALL выполнять алгоритм §9.8:
1. регион и точка среза; нет среза → `NothingToCompact`;
2. резюме; `CompactionFailed` → лог `compaction.failed`, `AgentError(cls: compaction, retrying: false)`, журнал и транскрипт не меняются (CMP-3);
3. проверка отмены после ответа модели;
4. запись `compaction` с `summary`, `firstKeptId`, `tokensBefore`, `tokensAfter` (по проекции с ещё не записанной записью) и `details` (прочитанные и изменённые файлы, `splitTurn`, модель резюме);
5. `append` с `durable`;
6. транскрипт сессии := сообщения `buildLlmContext`;
7. `ContextCompacted(tokensBefore, tokensAfter)`;
8. если оценка всё ещё выше порога — следующий проход, всего не более 3 (CMP-5).

Сжатие НЕ SHALL удалять или менять записи журнала (CMP-2).

#### Scenario: Ошибка суммаризатора
- **WHEN** суммаризатор возвращает `ErrorEvent`
- **THEN** журнал побайтово не изменился, транскрипт тот же, в событиях есть `AgentError(cls: compaction)`

#### Scenario: Отмена посреди генерации
- **WHEN** токен отменяется, пока суммаризатор отвечает
- **THEN** `compact` бросает `CancelledException`, записи `compaction` нет

### Requirement: Точки срабатывания сжатия
Сжатие SHALL запускаться (§9.5):
- `afterTurn` — после `TurnEnded(completed | maxTokens)` при `shouldCompact`, в фоне; следующий `prompt()` ждёт его завершения; после `cancelled` и `failed` не запускается;
- `preflight` — оценка payload шага больше окна (не порога): один аварийный вызов; запрос всё ещё больше окна → шаг завершается ошибкой `overflow`, ход — `TurnEnded(failed)`;
- `overflow` — провайдер вернул `errorClass: overflow`: сжатие и один повтор того же шага; второй `overflow` → `TurnEnded(failed)`;
- `manual` — вызов компактора с `focus` вне хода.

В пределах одного хода `preflight` и `overflow` вместе SHALL вызывать сжатие не более одного раза (CMP-8). При выключенной capability `compaction` сжатие не запускается ни одним триггером.

#### Scenario: Переполнение, затем успех
- **WHEN** scripted модель на первом запросе отвечает ошибкой `overflow`, а после сжатия — текстом
- **THEN** ход завершается `TurnEnded(completed)`, в журнале есть запись `compaction`, эмитится `ContextCompacted` (`overflow_then_compact_test.dart`)

#### Scenario: Повторное переполнение
- **WHEN** модель отвечает `overflow` и после сжатия
- **THEN** второго сжатия нет, ход завершается `TurnEnded(failed)`

#### Scenario: Длинная сессия продолжается
- **WHEN** сессия с окном 8 192 проходит 30 ходов с крупными результатами инструментов на scripted модели
- **THEN** сжатие срабатывает, каждый запрос к модели проходит проверку парности, оценка после каждого сжатия ниже порога (CMP-1, CMP-5)

