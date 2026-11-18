Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Красные тесты пишутся одной задачей и коммитятся отдельно, до кода, — только по явной просьбе пользователя. В скобках — сценарий спецификации, решение design.md или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон): `[agent]` — `codelab_agent_core`. Задач `[protocol]`, `[client]`, `[desktop]` нет: мост ACP, фикстуры и клиенты кода не меняют (design.md, D8); задача 2.2 только прогоняет их проверки.

Порядок: 0 → 1.1 → 1.2 → 1.3 → 1.4 → 2 → 3.1 (change якоря уже влит в `develop`). Одна ветка `feature/fix-config-change-during-background-compaction`, один PR в `develop`.

Проверки — только затронутое (корневой `AGENTS.md` §21); полный `melos run check` — по просьбе пользователя.

## 0. Документы

- [x] 0.1 `[agent]` Документы ядра до кода (выполнено архитектором 2026-11-17; `codelab_agent_core/AGENTS.md`, «сначала документ»):
  - `docs/architecture/proposals/agent-core/08-sessions.md` — §8.4 правило 1 (родитель вычисляется в очереди писателя), §8.5 «Сериализация» (очередь писателя, D1), §8.11 SES-16, §8.13 (тест одновременных записей);
  - `docs/architecture/proposals/agent-core/09-compaction.md` — §9.2 (причина `stale`), §9.8 шаг 10 и абзац «Запись на текущий лист» (D2, D3, D5), лог `compaction.skipped` с `reason: "stale"`, §9.9 CMP-12, §9.11 (тесты);
  - `docs/architecture/proposals/agent-core/12-observability-and-errors.md` — строка `compaction` каталога событий: `reason: "stale"`.

## 1. Ядро (`codelab_agent_core`)

- [x] 1.1 `[agent]` Красные тесты писателя и компактора (SES-16, CMP-12; agent-sessions «Последовательная запись журнала», agent-compaction «Запись сжатия ложится на текущий лист»). Хранилище с задержкой записи — обёртка над `MemorySessionStore` по образцу `test/session/recording_store.dart`, где `append` ждёт `Completer`, переданный тестом (можно добавить поле в `RecordingStore`).
  - `test/session/session_writer_test.dart`, «Одновременные записи образуют цепочку»: первая `append` висит на `Completer` хранилища, вторая вызывается без ожидания; после отпускания — `B.parentId == A.id`, лист — `B`, `pathToLeaf` содержит обе. На текущем коде красный: у `B` родитель — лист до `A`.
  - `session_writer_test.dart`, «Сбой записи не останавливает очередь»: `A` падает (`failAppends`), `B` в очереди пишется с родителем — листом до `A`; снимок без `A`.
  - `session_writer_test.dart`, «Запись по текущему снимку»: `appendWith` при записи в очереди получает снимок после неё; `null` — ничего не пишется, снимок не меняется.
  - `test/compaction/compactor_test.dart`, «Смена режима во время резюме»: суммаризатор теста ждёт `Completer`; пока он висит, `writer.append` пишет `ModeChangeRecord`; после ответа — запись `compaction` с `parentId` = id `mode_change`, лист — `compaction`, `pathToLeaf` содержит `mode_change`; `tokensBefore`/`tokensAfter` равны числам такого же прохода без смены (контрольный прогон в том же тесте). То же для `ModelChangeRecord`, `ConfigChangeRecord` (`effort`, `agent`) и `SessionInfoRecord` — табличный тест. На текущем коде красный: родитель записи — прежний лист.
  - `compactor_test.dart`, «Сообщение во время резюме» (D3): пока суммаризатор висит, пишется `MessageRecord`; ожидается `NothingToCompact` с `reason == 'stale'`, записи `compaction` нет, `ContextCompacted` нет, `onCompacted` не вызван, лог `compaction.skipped` (`info`) с `session_id`, `trigger`, `pass: 1`, `reason: 'stale'` и без текста резюме. Второй случай — неизвестный вид записи (`CustomRecord`) даёт тот же исход (fail-closed, R5). Третий — `stale` на втором проходе: исход — `Compacted` первого.
  - `compactor_test.dart`, «Отмена, пока запись ждёт очереди» (CMP-3, CMP-4): суммаризатор ответил, но хранилище держит предыдущую запись (`mode_change`) на `Completer`; токен отменяется; после отпускания — `CancelledException`, записи `compaction` нет.
- [x] 1.2 `[agent]` Красные тесты сессии — новый файл `test/runtime/config_during_compaction_test.dart` (agent-runtime «Смена конфигурации во время сжатия сохраняется в журнале»). Риг — по образцу `test/compaction/after_turn_test.dart` (окно `modelWithWindow(16384)`, ходы `textStep('a' * 8000)`, `textStep('b' * 36000)` запускают фоновое `afterTurn`) и `test/runtime/load_session_test.dart` (общий `MemorySessionStore`, `dispose` первого рантайма, `loadSession` вторым). Суммаризатор удерживается обёрткой `streamFunction`, которая на запросе с `cacheKey`, оканчивающимся на `:summary`, ждёт `Completer` теста перед ответом (тот же признак запроса резюме, что в `anchor_runtime_test.dart` ветки `anchor-context-estimate-after-compaction`). Каталог моделей — две модели, обе с рассуждением, чтобы `loadSession` не писал `session.model.not_restored`.
  - «Режим во время фонового сжатия»: два хода; дождаться, что запрос резюме ушёл; `await session.setMode(ModeId.plan)` завершается **до** отпускания `Completer` (проверка: `setMode` вернулся, `Completer` ещё не завершён); отпустить; `prompt` третьего хода (дожидается фона) или `close()`; `loadSession` → `mode == ModeId.plan`; в журнале одна `compaction`, и она на активной ветке. На текущем коде красный: режим после загрузки прежний.
  - «Модель во время фонового сжатия»: то же с `setModel` → после `loadSession` модель выбранная, лога `session.model.not_restored` нет.
  - «Уровень рассуждения во время фонового сжатия»: `setEffort(ReasoningEffort.high)` → после `loadSession` `effort == high`.
  - «Агент во время фонового сжатия»: определение агента с `mode: plan` и моделью каталога (источник определений — как в существующих тестах `setAgent`) → после `loadSession` `agent` — его имя, режим и модель — его.
  - «Режим во время ручного сжатия»: `prompt('/compact')` без `await`; пока резюме висит — `await setMode(plan)`; отпустить; ответ команды — `Compacted: …`; после `loadSession` режим — `plan`.
  - «Модель во время аварийного сжатия»: первый запрос хода отвечает `overflow`; пока резюме висит — `await setModel(...)`; отпустить; `TurnEnded(completed)`, одна `compaction`; после `loadSession` модель — выбранная.
  - «Смена режима во время записи сообщения хода» (agent-sessions, SES-16): хранилище держит запись ответа модели на `Completer`, `setMode(plan)` без ожидания, отпустить; после хода и `loadSession` режим — `plan`, ответ модели — на активной ветке (`replay` содержит его).
- [x] 1.3 `[agent]` Реализация 1.1–1.2:
  - `lib/src/session/session_writer.dart`: внутренняя очередь (`Future`-цепочка; сбой не рвёт хвост); `append` вызывает построитель в очереди; `appendBuilt` — через очередь; новая `appendWith<R>(R? Function(SessionSnapshot current) build, {bool durable})` (D1, D2). Doc-комментарии класса, `append`, `appendBuilt`, `appendWith` — почему/для чего/как, ссылки на SES-16 и D1.
  - `lib/src/compaction/compactor.dart`: запись через `appendWith` с построителем D2 (отмена → `null` и `CancelledException`; закрытый список разрешённых записей между листами — константа рядом с построителем со ссылкой на CMP-12, R5; перестроенная запись `parentId` = текущий лист, id — прежний или новый при совпадении); исход `stale` — лог `compaction.skipped` с `reason: 'stale'` и `done ?? const NothingToCompact('stale')` (D3). Doc-комментарии `compact` и `NothingToCompact` (причины `no cut point`, `no reduction`, `stale`) обновить.
  - `agent_runtime.dart` не меняется (D4). Новых публичных символов и экспортов барели нет.
- [x] 1.4 `[agent]` Рефакторинг и сверка: имена и шаги в `08-sessions.md` §8.5 и `09-compaction.md` §9.8 совпадают с кодом; устаревших комментариев в `session_writer.dart` и `compactor.dart` нет (в том числе комментарий `_compactNow` «двух сжатий одной ветки одновременно нет» остаётся верным).

## 2. Проверки

- [x] 2.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_core` (в том числе `test/session/deterministic_journal_test.dart` и `deterministic_journal_agent_test.dart` — журналы без гонок побайтово прежние, D1).
- [x] 2.2 `[agent]` `fvm dart test` в `packages/dart/codelab_agent_acp` и `fvm dart run melos run conformance:agent` (ожидание по D8 — без правок фикстур). Если фикстура краснеет — остановиться и вернуть вопрос архитектору: правка фикстуры — задача `[protocol]`.
- [x] 2.3 `[agent]` `fvm dart run melos run web-compile` (изменён web-безопасный `codelab_agent_core`) и `openspec validate fix-config-change-during-background-compaction --strict`.

## 3. Согласование с влитым `anchor-context-estimate-after-compaction`

- [x] 3.1 `[agent]` Тест `test/compaction/anchor_runtime_test.dart` «the toolset changes after the compaction…» (вызывает `setMode(plan)` во время фонового `afterTurn`) расширить проверкой: после `dispose` и `loadSession` того же хранилища режим — `plan`, запись `compaction` и `mode_change` на активной ветке (design.md, D7). Прогон: `fvm dart test test/compaction/` в `codelab_agent_core`.
