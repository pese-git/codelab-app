## Context

Этапы 1 и 2 положили в `codelab_agent_core` LLM-контракт, цикл, инструменты, разрешения и прямой API `AgentRuntime` / `AgentSession`. История сессии пока живёт только в транскрипте `Agent`, а `listSessions()` перечисляет сессии текущего процесса. Этап 3 делает журнал единственным источником истории и добавляет сжатие контекста.

Контракты, алгоритмы, инварианты и тексты для модели уже описаны в принятом документе ядра:
- §8 — сессии (формат, дерево, хранилище, запись, ремонт, проекции, прерванный ход, раскладка, список);
- §9 — сжатие (оценка, пороги, точки срабатывания, точка среза, резюме, запись);
- §1 (PKG-6) — порты `Clock` и `IdGenerator`;
- §10 — capability `sessionPersistence` и `compaction`;
- §11 — промпты `compaction/*.md`.

Этот документ фиксирует только то, чего в документе ядра нет:
- какая часть контракта входит в этап 3, а какая подключается позже;
- раскладка кода;
- решения на стыках с этапами 2 и 4;
- уточнения, которые реализация этапа 2 сделала обязательными;
- порядок итераций.

Где ниже нет отдельного решения, действует документ ядра как есть.

## Goals / Non-Goals

**Goals:**
- Журнал каждой сессии: append-only JSONL, запись на `MessageEnded` до следующего действия цикла (SES-8), результат инструмента — с `durable` до следующего запроса к модели (SES-9).
- Сессия открывается после обрыва процесса посреди строки (SES-5); битые строки сохраняются в `.corrupt`, а не теряются.
- Продолжение прерванного хода без повторного вызова инструментов (SES-9, SES-10).
- Список сессий с фильтром по `cwd`, сортировкой и курсором; автоматический заголовок.
- Длинная сессия не упирается в окно: автосжатие после хода и аварийное сжатие внутри хода, срез никогда не разделяет вызов и результат (CMP-1).
- Детерминизм: два прогона одного сценария на `FakeClock` и `SequentialIdGenerator` дают побайтово одинаковый JSONL (PKG-6).

**Non-Goals:**
- вынос огромного результата (3.8, T-28) и редакция секретов (P-10) — D11;
- ACP-проекция реплея, `session_info_update`, `/compact`, `setConfigOption` (этап 4);
- загрузка `sessions.*` и `compaction.*` из файлов (этап 8);
- ветки, fork, перемотка, lease, сегменты и оконное открытие, запечатывание, `probeSummary`, роли моделей, структурное сжатие — после MVP;
- хранилища `app-documents` и IndexedDB (этап 10).

## Decisions

### D1. Раскладка и публичный API

Файлы ядра — по §1.3 документа ядра, `lib/src/session/`:
- `records.dart` — `SessionHeader`, `AgentInfo`, `SessionRecord` и подклассы, `toJson` / `fromJson`, поле `extra` для неизвестных полей;
- `parse.dart` — `parseSessionLines` (шаги 1–4 и 6–9 §8.6 в памяти: строки → заголовок, записи, карантин, лист, отчёт), `SessionOpenException`;
- `tree.dart` — правила дерева и `pathToLeaf` (§8.4);
- `projections.dart` — `buildLlmContext`, `buildReplay`, `summarize`, `healInterruptedTurn`;
- `user_words.dart` — `RecordOrigin`, `classifyOrigin`, `isUserWords`, `isUserWordsEvent`, `recordOriginOf` (§8.2.5);
- `ids.dart` — `newSessionId`, `newRecordId` (§8.4); `slug.dart` — `cwdSlug`, `fnv1a32Hex` (§8.9);
- `session_store.dart` — порт `SessionStore`, `SessionSnapshot`, `RepairReport`, `SessionPage`, `SessionSummary`, `InvalidCursor`, `SessionNotFound`, курсор;
- `memory_session_store.dart` — `MemorySessionStore`;
- `session_writer.dart` — `SessionWriter` (§8.3).

`lib/src/compaction/`: `estimate.dart`, `settings.dart` (`CompactionSettings`, `CompactionOverrides`, `forWindow`), `cut_point.dart`, `summarizer.dart` (сериализация региона и `generateSummary`), `compactor.dart` (`compact`, `CompactionOutcome`, `CompactionTrigger`).

`codelab_agent_io`: `lib/src/session/jsonl_session_store.dart`, `write_queue.dart`.

Барель ядра дополнительно экспортирует:
- формат журнала и порт хранилища: записи, `parseSessionLines`, `SessionStore`, `SessionSnapshot`, `RepairReport`, `SessionSummary`, `SessionPage`, исключения, `cwdSlug`. Их реализует `JsonlSessionStore` другого пакета, и их же реализуют хранилища этапа 10;
- `MemorySessionStore` — хранилище для тестов хоста и профиля без постоянного носителя;
- `CompactionOverrides` — часть `CoreConfig`;
- события `ContextCompacted`, `SessionTitleChanged`.

Барель НЕ экспортирует `SessionWriter`, проекции, компактор, точку среза и оценку токенов: это внутренние механизмы сессии (PKG-5). `public_api_test.dart` получает проверку `export 'src/session/session_writer.dart'` и `export 'src/compaction/compactor.dart'`.

### D2. Объём формата журнала этапа 3

Писатель этапа 3 пишет записи:
- `message` с полями записи `outcome`, `diff`, `toolMeta`, `origin` (`loop_nudge` с `nudge` и `attempt`, `loop_note` с `nudge`);
- `model_change` — первая запись новой сессии и смена модели;
- `mode_change`, `plan`, `compaction`, `session_info` (`source: "auto"`).

Читатель этапа 3 разбирает все записи MVP таблицы §8.2.4, включая `config_change`, `label`, `leaf` и `custom`; `leaf` участвует в вычислении листа (§8.4, правило 2). Записи после MVP (`branch`, `subagent`, `job` и прочие) и любой неизвестный `type` читаются как `CustomRecord("unknown:<type>")` с исходным объектом (§8.6, шаг 4b): строка не теряется и в проекциях не участвует. Неизвестные поля известной записи и поля после MVP (`diffs`, `command`, `auxUsage`, `spill`) сохраняются в `extra` и пишутся обратно при копировании.

`config_change` пишет этап 4 вместе с `setConfigOption`. Событие `ConfigOptionChanged` (§8.3) добавляется там же.

Предикат «слова пользователя» (§8.2.5) реализуется в этапе 3 целиком, потому что на нём стоят заголовок (§8.10) и точка среза (§9.6). Перечисление `RecordOrigin` содержит все значения §8.2.5, а `MessageOrigin` — только подклассы MVP (`LoopNudgeOrigin`, `LoopNoteOrigin`); тест полноты проверяет оба направления. Проверка литералов в CI (`tool/check_origin_literals.dart`) — после MVP вместе с остальными значениями `origin`.

### D3. Идентификаторы: `IdGenerator.nextChars`

Порт этапа 1 даёт только `nextId()`. Формат §8.4 требует символов из заданного алфавита, поэтому порт получает метод:

```dart
abstract interface class IdGenerator {
  String nextId();
  /// count символов из alphabet; для журнала — независимые и равновероятные.
  String nextChars(int count, String alphabet);
}
```

- `SessionId` = 10 символов времени по `Clock` + `nextChars(16, crockford32)` (ULID, §8.4).
- `RecordId` = `nextChars(8, '0-9a-z')`; повтор при совпадении в снимке не более 16 раз, затем 12 символов.
- `TurnId` и id вызовов по-прежнему из `nextId()`.
- Ядро получает `RandomIdGenerator(Random random)`: обе операции над `Random` хоста, хост передаёт `Random.secure()` (PKG-6: источник случайности приходит от хоста).
- `SequentialIdGenerator.nextChars` детерминирован: номер вызова в системе счисления алфавита, дополненный слева первым символом до `count`. Два генератора дают одинаковые последовательности, а 100 подряд идущих id записей уникальны.

Документ ядра §1.4 и §8.4 получают сигнатуру порта в том же PR.

### D4. AgentSession с журналом

`AgentSession` создаёт `SessionWriter` и подписывает его на `Agent` первым слушателем. Писатель пишет записи по таблице §8.3 в объёме D2 и отвечает за `durable`:
- результат инструмента, `compaction` и последняя запись хода (`TurnEnded`) пишутся с `durable: true`;
- остальное — без него.

Режим `fsync` применяет хранилище (D7).

- **`toolMeta` результата** — из `ToolCallStarted` того же вызова: писатель хранит `title`, `kind` и `locations` вызова до его `ToolCallFinished`, а `diff` берёт из `ToolCallFinished.diffs` (один файл — `diff`; несколько файлов в MVP не бывает).
- **Ошибка записи журнала** (SES-8). `SessionWriter` логирует `session.append.failed` и отменяет ход новой причиной `StorageFailure` (`CancelReason`). Сессия эмитит `AgentError(cls: storage, retrying: false)`. Цикл, отменённый этой причиной, завершает ход `TurnEnded(failed)`, а не `cancelled`.
- **`createSession`** создаёт файл (`SessionStore.create`) и первой записью пишет `model_change` модели сессии.
- **`loadSession(id, ports, {model})`**:
  1. `SessionStore.open`;
  2. `healInterruptedTurn` и запись синтетических результатов (`durable`);
  3. транскрипт `Agent` := `buildLlmContext(snapshot).messages`, режим — последняя `mode_change` ветки или режим по умолчанию;
  4. последний `plan` ветки восстанавливается в `PlanService` без события.
- **Модель загруженной сессии.** Этап 3 не восстанавливает модель из `model_change`: каталог моделей и `setConfigOption("model")` приходят на этапе 4. `loadSession` берёт `model` из аргумента или `CoreConfig.defaultModel`. Если последняя `model_change` ветки называет другую пару `provider/modelId`, сессия логирует `session.model.not_restored` и пишет `model_change` выбранной модели.
- **`replay()`** — `buildReplay(snapshot)` по активной ветке:
  - `message` user и assistant → `MessageStarted` и `MessageEnded`;
  - `toolResult` → `ToolCallStarted` (из `toolMeta`) и `ToolCallFinished`; синтетический `interrupted` даёт `outcome: failed` с `interrupted: true`;
  - `plan` → `PlanUpdated`, `mode_change` → `ModeChanged`;
  - `compaction` → `ContextCompacted`, `session_info` → `SessionTitleChanged`.

  Записи до сжатия реплей показывает: журнал их хранит, а ACP `session/load` воспроизводит всю видимую историю (§13.5, этап 4). Служебные user-сообщения (`isUserWords == false`) реплей пропускает.
- **`TurnResult`** не меняется. `AgentSession.close()` (стадия MVP, без `seal`) дожидается очереди записи и закрывает хранилище для этой сессии; `AgentRuntime.dispose` вызывает его для всех сессий.

### D5. `listSessions` со страницей

Документ ядра §5.6 описывает `listSessions({String? cwd})` со списком, а §8.3 и §8.10 — страницу с курсором у хранилища. ACP `session/list` пагинирует, а ACP-адаптер (этап 4) работает через `AgentRuntime`. Поэтому сигнатура этапа 3:

```dart
Future<SessionPage> listSessions({String? cwd, String? cursor, int pageSize = 50});
```

Она делегирует `SessionStore.list`. Неверный курсор — `InvalidCursor`. §5.6 получает эту сигнатуру в том же PR.

`SessionSummary` этапа 3 — поля MVP §8.10: `id`, `cwd`, `title`, `updatedAt`, `messageCount`, `lastTurnFailed`. Поля после MVP (`titleSource` и прочие) добавляются позже.

### D6. Автоматический заголовок

После первого `TurnEnded` хода, в котором есть запись с `isUserWords`, если на ветке ещё нет `session_info` с непустым `title`, `AgentSession`:
1. берёт заголовок по шагу 1 `summarize`: пробелы схлопнуты, 80 символов по границе слова с `…`;
2. пишет `session_info` с `source: "auto"`;
3. эмитит `SessionTitleChanged(title, updatedAt)`.

Запись идёт до проверки автосжатия. Ход, отменённый до первого ответа, заголовок тоже даёт: слова пользователя в журнале уже есть.

### D7. `JsonlSessionStore`

- Конструктор: `JsonlSessionStore({required String root, FsyncPolicy fsync = FsyncPolicy.checkpoints, required Clock clock, Logger? logger})`. `root` — каталог `sessions/` (по умолчанию хост передаёт `$CODELAB_HOME/sessions`, §15). Хранилище не читает переменные окружения само.
- Раскладка и имя файла — §8.9. Поиск файла по `sessionId` — по суффиксу `_<sessionId>.jsonl` в каталогах слагов. Внутри процесса хранилище держит карту `id → путь` для открытых и созданных сессий.
- Запись — алгоритм §8.5: строка кодируется до очереди; очередь — цепочка `Future` на путь, общая для процесса; дескриптор `RandomAccessFile` живёт до `close`; ошибка операции закрывает дескриптор и уходит вызывающему, следующая операция не наследует сбой.
- `FsyncPolicy`: `checkpoints` вызывает `flush` только для `durable`, `always` — после каждой записи, `never` — никогда.
- Открытие — `parseSessionLines` ядра плюс шаги 5a–5b §8.6 на диске: `.corrupt`, усечение оборванной последней строки или переписывание через `<file>.tmp` и `rename`. Синтез заголовка берёт `cwd` из `index.json` по имени файла, иначе `""`; `created` — `mtime`.
- `list` — шаги §8.10 с кешем `index.json` по `(size, mtime)`; открытие для списка — только чтение, ремонт в памяти без изменения файла. Кеш — производный файл: повреждённый `index.json` игнорируется и пересоздаётся.
- `SessionNotFound` — нет файла; `create` с существующим id — `StateError`.

### D8. Сжатие в этапе 3

- **Настройки.** `CoreConfig.compaction` — `CompactionOverrides(reserveTokens?, keepRecentTokens?, keepRecentUserTurns?, contextWindowCap?, enabled = true)`. Значения проходят ограничения §9.4. `enabled: false` выключает capability `compaction` при сборке (D12).
- **Модель резюме.** Модель сессии и та же `StreamFunction`; `LlmContext.cacheKey` = `<sessionId>:summary`. Роли моделей и `agent.summary_model` — после MVP (§17.10.5).
- **Окно.** `effectiveContextWindow(model, cap)` = `min(model.contextWindow, cap)`; одна функция для порога `afterTurn`, проверки `preflight` и `ModelRequested.estimatedTokens` (CMP-6).
- **Точки подключения цикла.** В `AgentLoopConfig` появляются поля, которые design.md этапа 2 (D7) обещал, но код не объявил:
  - `estimateTokens(LlmContext) → int` — оценка payload; цикл заполняет `ModelRequested.estimatedTokens`;
  - `emergencyCompact(CancelToken) → Future<LoopContext?>` — один аварийный вызов за ход, общий для `preflight` (§5.2, шаг 4) и `overflow` (§5.4, шаг 14a, CMP-8).

  `null` в любом поле — «сжатия нет», поведение этапа 2 не меняется.
- **`emergencyCompact` сессии** вызывает `compact` с триггером `preflight` или `overflow` по снимку журнала. После `Compacted` возвращает `LoopContext` с сообщениями проекции, после `NothingToCompact` и `CompactionFailed` — `null`. Цикл заменяет контекст шага, транскрипт `Agent` после шага — сообщения проекции плюс сообщения шага.
- **`afterTurn`.** После `TurnEnded(completed | maxTokens)` сессия проверяет `shouldCompact` и запускает сжатие в фоне. Следующий `prompt()` ждёт его завершения. После `cancelled` и `failed` сжатие не запускается. Ошибка фонового сжатия — `AgentError(cls: compaction)` в `events` и лог; журнал не меняется (CMP-3).
- **Транскрипт после сжатия** := `buildLlmContext(snapshot + rec).messages` (§9.8, шаг 11). Между ходами — существующий `Agent.replaceTranscript`, аварийный путь — через `LoopContext`.
- **`manual`.** `compact` принимает `CompactionTrigger.manual` и `focus`; тесты зовут компактор напрямую. Метод сессии для `/compact` добавляет этап 4 вместе с командой.
- **Резюме моделью** — алгоритм §9.7, разрезанный ход — §9.6. Ошибка модели → `CompactionFailed`, отмена → `CancelledException` наружу (CMP-4).

### D9. Промпты суммаризатора

Файлы `prompts/compaction/`: `system.md`, `summary.md`, `summary_update.md`, `turn_context.md`, `focus.md`, `summary_wrapper.md`. Константы генерирует `tool/gen_prompts.dart` этапа 2.

Тексты пишутся для CodeLab по-английски по §11.7 и §9.7, проходят ревью как код и не копируются из сторонних проектов (`AGENTS.md` §5). Шаблоны без условий (§11.4): необязательный блок `{{focus}}` — отдельный шаблон `focus.md`.

Обязательные разделы резюме из §9.7 проверяются тестом на scripted-модели только по наличию заголовков в запросе к суммаризатору.

### D10. Python-сессии не переносятся (3.7)

Python-агент хранил JSON-сессии в `$CODELAB_HOME/data/sessions` в формате доменного журнала другой структуры. Ядро пишет в `$CODELAB_HOME/sessions/`, форматы не пересекаются, оба агента живут рядом (§8.9, §16.1). Импорта нет: сессии быстро теряют актуальность, а перенос стоит дорого. Пользовательская документация этапа 9 предупреждает, что история Python-агента в Dart-агенте не видна.

### D11. Вынос результата — отдельный change

Задача 3.8 (T-28, Should, не блокирует MVP) выделяется в change `add-agent-core-output-spill`. Причины:
1. Файл выноса ДОЛЖЕН содержать отредактированный текст без сырых секретов (SPL-3), а редакция `Redactor` (P-10) в задачи этапа 3 не входит. Вынос до редакции оставил бы на диске секреты, которые нельзя «отозвать».
2. Вынос меняет единую точку исполнения (шаг 8c), `BoundedEnv` (`readOnlyRoots`), `exec` (`outputByteLimit`) и сборку (`outputSpill`). Это отдельный набор требований, который не нужен для Must этапа 3.

Поле записи `spill` читатель этапа 3 сохраняет в `extra` (D2), поэтому журнал с выносом откроется и этой версией. План этапа (`09-08-stage-3-sessions.md`) получает пометку в том же PR.

### D12. Сборка: capability, сервис и профили

- **`HostCapability`** получает `compaction` и `sessionPersistence`.
- **Профили** (§10.4):
  - `agent-serve` и `embedded-cli`: `sessionPersistence` — transport `jsonl-file`, `compaction` — on.
  - Тесты выключают `sessionPersistence` через `narrowed` и работают на `MemorySessionStore`. Сузить transport `{jsonl-file}` до `{memory}` нельзя: это не подмножество (HOST-2).
- **`AgentCoreServices.sessions`** — обязательный `SessionStore`: журнал пишется всегда, выключенная `sessionPersistence` означает только «не на постоянном носителе».
- **Проверка сервисов** (§10.8, HOST-3): включённая `sessionPersistence` над `MemorySessionStore` → `HostWiringException`, называющий `sessionPersistence`. Ядро не знает `JsonlSessionStore`, поэтому проверяется только «не `MemorySessionStore`».
- **`CoreConfig.compaction: false`** (`enabled`) → `compaction` off с причиной «выключено конфигом»; сжатие не запускается ни после хода, ни аварийно.
- `CorePlan` и лог `host.plan` показывают состояние обеих capability.

### D13. Итерации и TDD

Задачи идут парами «тест → реализация» (§9.0, правило 3); красные тесты коммитятся до кода. Итерации (§9.0, правило 8):

1. **Журнал в памяти.**
   - Задачи 3.1, 3.2, 3.4, 3.10 и 3.11 на `MemorySessionStore`.
   - Порт `nextChars`, `SessionWriter`, `loadSession`, `listSessions`, `replay`, автоматический заголовок, capability `sessionPersistence`.
   - DoD: `deterministic_journal_test.dart`, `session_title_test.dart`, `session_list_test.dart`, `core/resume-after-crash-no-tool-recall` и `core/interrupted-tool-not-retried` на памяти.
2. **JSONL на диске и ремонт.**
   - Задачи 3.3 и 3.9 в `codelab_agent_io`.
   - DoD: `jsonl_crash_recovery_test.dart`, `core/session-crash-mid-turn-loads`, 100 параллельных `append`, тесты ремонта §8.13.
3. **Сжатие.**
   - Задачи 3.5 и 3.6: оценка, пороги, точка среза, промпты, компактор, триггеры, поля цикла, capability `compaction`.
   - DoD: `overflow_then_compact_test.dart` и тесты §9.11.

Задача 3.7 — решение D10, закрывается в итерации 1.

Каждая итерация — отдельный PR в `develop` из `feature/add-agent-core-sessions-and-compaction`. Ветка удаляется после слияния и создаётся заново от `develop` для следующей итерации.

### D14. Уточнения контракта, найденные в итерации 1

Реализация уточнила контракт документа ядра. Документ правится в том же PR:

- **`SessionStore.flush(id)`.** Конец хода сбрасывает журнал на носитель без новой записи (таблица §8.3, строка `TurnEnded`); в эскизе порта §8.3 такого метода не было.
- **`summarize(snapshot)` в отдельной библиотеке `summary.dart`.** Сводку строят хранилища, в том числе `JsonlSessionStore` другого пакета, поэтому она экспортируется вместе с портом и `pageOf` (сортировка и курсор §8.10, шаги 4–6). Остальные проекции остаются внутренними.
- **`ParsedJournal`.** `parseSessionLines` возвращает снимок, строки карантина, `onlyTailBroken`, `missingFinalNewline` и исходные строки уцелевших записей `keptLines`. Хранилище переписывает файл этими строками как были, без повторного кодирования: запись новой версии с полями в другом порядке не меняется.
- **`journalModelRef(provider, id)`.** JSON сообщения хранит только провайдера и id модели (§2.2), а разбору журнала каталог недоступен. Сессия после загрузки заменяет такие ссылки моделью сессии при совпадении пары.
- **`findInterruptedCalls` и `meta` у `healInterruptedTurn`.** Заголовок прерванного вызова даёт `present()` инструмента, а он асинхронный и требует `ToolContext`. Сессия находит вызовы, получает заголовки и передаёт их чистой функции.
- **`StorageFailure` — причина отмены.** Писатель журнала — подписчик, и исключение подписчика цикл принял бы за ошибку хука. Отмена этой причиной останавливает ход на границе, цикл отображает её в `TurnEnded(failed)`.
- **`SessionTitleChanged` — после `TurnEnded`.** Заголовок — событие уровня сессии: `TurnEnded` остаётся последним событием хода (LOOP-1), а заголовок приходит следом, до возврата `prompt()`.
- **`sessionPersistence: off` в тестах** (D12): сузить transport `{jsonl-file}` до `{memory}` нельзя (HOST-2).
- **FNV-1a в dart2js.** Формула §8.9 «произведение помещается в 53 бита» неверна: оно доходит до 2^56. Множитель раскладывается на `0x193` и `0x01000000`; §8.9 исправлен.

### D15. Уточнения контракта, найденные в итерации 2

Документ ядра правится в том же PR (§8.5, §8.6, §8.9, §8.10):

- **Проверка переводов строк недостижима через `jsonEncode`.** Кодировщик экранирует `\n` и `\r` внутри строк, поэтому `StateError` шага 1 §8.5 — защита от дефекта кодирования, а не поведение, которое можно вызвать записью. Тест 5.1 проверяет обратное: текст с переводами строк занимает одну строку файла и читается без изменений.
- **`FileSync` — шов для тестов.** Конструктор принимает `@visibleForTesting FileSync? sync` (по умолчанию `RandomAccessFile.flush`). Через него тесты считают `fsync` по `FsyncPolicy` и вызывают сбой операции.
- **`create` — точка сохранения.** Заголовок пишется с `durable`: при `checkpoints` и `always` новый журнал сразу сбрасывается на носитель.
- **`open` закрывает дескриптор до ремонта.** Переписывание заменяет файл через `rename`, и открытый дескриптор писал бы в удалённый файл. Следующая запись открывает файл заново.
- **Целая последняя строка без `\n`** получает перевод строки при открытии: иначе следующая запись склеилась бы с ней (`missingFinalNewline`, D14).
- **Формат `index.json`**: `{"v":1,"sessions":{"<слаг>/<файл>":{"size","mtime","id","cwd","title","updatedAt","messageCount","lastTurnFailed"}}}`; `mtime` — миллисекунды. Ключ — путь относительно `root` через `/`. Кеш пишется через `index.json.tmp` и `rename`; `list` с `cwd` сохраняет строки других каталогов.
- **Лог `session.quarantined`** (`warning`, поля `session_id`, `lines`, `truncated`) — при каждом карантине на диске.
- **Обрыв посреди `write` в тесте 6.2.** Дочерний процесс сам оставляет в файле начало следующей строки, печатает `ready` и получает `SIGKILL`: момент сигнала внутри `write` не воспроизводится надёжно (Risks).

## Risks / Trade-offs

- **[Формат журнала закрепляется надолго]** → версия формата в заголовке с первого дня. Тест неизвестной версии: файл не открывается и побайтово не меняется (SES-2). Golden-фикстуры `test/fixtures/sessions/*.jsonl` содержат каждую запись MVP; неизвестные поля и типы сохраняются (D2).
- **[Падение посреди `write` на macOS и Linux ведёт себя по-разному]** → тест обрыва имитирует результат (файл, обрезанный посреди строки), а не сам сигнал. Тест `kill -9` реального процесса — интеграционный на Dart VM с дочерним процессом `dart run`, только в `codelab_agent_io`.
- **[Сводка при сжатии теряет важные детали]** → обязательные разделы резюме, дословная цитата последнего запроса пользователя (CMP-7), итеративное обновление (CMP-9). Пороги настраиваются `CompactionOverrides`. Context Manager — только по условию §7б плана.
- **[Оценка chars/4 ошибается на коде и не-латинице]** → якорь на usage провайдера для всего, кроме хвоста (§9.3); аварийный путь `overflow` ловит недооценку (CMP-8).
- **[Фоновое сжатие гонится с новым `prompt()`]** → `prompt()` ждёт завершения сжатия (D8). Отмена сессии отменяет и сжатие, журнал не меняется (CMP-3).
- **[Модель загруженной сессии не восстанавливается до этапа 4]** → явное поведение и лог `session.model.not_restored` (D4); тест на это поведение.
- **[Вынос результата откладывается]** → до change `add-agent-core-output-spill` огромный вывод усекается по §6.3.5, как в этапе 2 (D11).
- **[Журнал и сырые секреты]** → редакции до журнала ещё нет (P-10): журнал хранит вывод инструментов как есть, как и транскрипт этапа 2. Это известное ограничение до задачи P-10.

## Migration Plan

Новые сессии сразу пишут журнал; существующих журналов Dart-агента нет. Python-сессии не переносятся (D10). Клиенты не меняются. Откат — revert PR итерации.

## Open Questions

- Задача редакции секретов P-10 (Should, этап 3 по матрице целей) не входит в список задач плана этапа 3. Она нужна до change выноса результата (D11). Нужно решить, в каком этапе и каким change она выполняется.
