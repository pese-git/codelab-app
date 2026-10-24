Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 3 (`dart-agent-and-clients/09-08-stage-3-sessions.md`) и требование спецификации.

Пути — в `packages/dart/codelab_agent_core/`, если не указано иное. Группы задач по итерациям (design.md, D13):
- группы 1–4 — итерация 1 (журнал в памяти);
- группы 5–6 — итерация 2 (JSONL на диске и ремонт);
- группы 7–9 — итерация 3 (сжатие).

Каждая итерация — отдельный PR в `develop`.

## 1. Порт идентификаторов и формат записей (3.1)

- [ ] 1.1 Тест (agent-core-ports «Порты детерминизма от хоста»): `test/util/determinism_ports_test.dart` — `SequentialIdGenerator.nextChars`: повторяемость, длина, алфавит, 100 уникальных значений; `RandomIdGenerator(Random(42))` повторяем; `test/session/ids_test.dart` — `newSessionId`: 26 символов Crockford base32, первые 10 — время `FakeClock` и сортируются по нему; `newRecordId`: 8 символов `0-9a-z`, повтор при совпадении, 12 символов после 16 совпадений (agent-sessions «Идентификаторы и дерево записей») (красные)
- [ ] 1.2 Реализовать `IdGenerator.nextChars` в `lib/src/util/ids.dart`, `RandomIdGenerator`, `SequentialIdGenerator.nextChars`, `lib/src/session/ids.dart` — 1.1 зелёные
- [ ] 1.3 Тест (agent-sessions «Формат журнала JSONL»): `test/session/records_test.dart` и фикстура `test/fixtures/sessions/all_records.jsonl` — каждая запись MVP §8.2 разобрана в свой тип и побайтово записывается обратно; неизвестные поля в `extra`; `"type":"branch"` → `CustomRecord("unknown:branch")`; пропущенные числа usage → `0`, `null` не пишется (красный)
- [ ] 1.4 Реализовать `lib/src/session/records.dart` — 1.3 зелёный
- [ ] 1.5 Тест (agent-sessions «Слова пользователя»): `test/session/user_words_test.dart` с фикстурой `all_origins.jsonl` — таблица на каждый `RecordOrigin.values`, полнота `recordOriginOf` по подклассам `MessageOrigin`, `isUserWordsEvent` совпадает с `isUserWords` записи писателя; `origin: "future_value"` → `false` и одно предупреждение `session.origin.unknown` (SES-14, SES-15) (красный)
- [ ] 1.6 Реализовать `lib/src/session/user_words.dart` — 1.5 зелёный

## 2. Разбор, дерево и проекции (3.1, 3.10, 3.11)

- [ ] 2.1 Тест (agent-sessions «Идентификаторы и дерево записей», «Открытие и ремонт журнала» — часть в памяти): `test/session/parse_test.dart` — заголовок, отсутствующий заголовок (`headerMissing`), неизвестная версия → `SessionOpenException(unsupportedVersion)`, оборванная последняя строка и мусор → карантин в отчёте, дубликат id → вторая копия в карантин, лист по правилу 2 с `leaf`, dangling leaf → `healedLeafFrom`, `brokenLinks`; `test/session/tree_test.dart` — `pathToLeaf` root-first, цикл (`session.cycle`), отсутствующий родитель (`session.broken_link`), защита по длине (красные)
- [ ] 2.2 Реализовать `lib/src/session/parse.dart`, `lib/src/session/tree.dart` — 2.1 зелёные
- [ ] 2.3 Тест (agent-sessions «Проекции журнала»): `test/session/projections_test.dart` — golden `buildLlmContext` по фикстурам; сжатие → резюме по `summary_wrapper`, записи до `firstKeptId` скрыты, `Usage.zero` у assistant до сжатия, `firstKeptId` не найден → лог `session.compaction.lost_anchor`; последние `model_change`/`mode_change`/`config_change`; `summarize` — заголовок из `session_info` и из первых слов пользователя (схлопывание, 80 символов, `…`), `updatedAt`, `messageCount`, `lastTurnFailed`; `buildReplay` — события по записям, служебные user-сообщения пропущены, `interrupted` → `failed` с `interrupted: true` (SES-7) (красный)
- [ ] 2.4 Реализовать `lib/src/session/projections.dart` (`buildLlmContext`, `summarize`, `buildReplay`); `ContextCompacted`, `SessionTitleChanged` и `ToolCallFinished.interrupted` в `lib/src/loop/agent_events.dart`; промпт `prompts/compaction/summary_wrapper.md` и перегенерация `prompts.g.dart` — 2.3 зелёный
- [ ] 2.5 Тест (agent-sessions «Продолжение прерванного хода»): `test/session/heal_interrupted_test.dart` — три случая таблицы §8.8 (сбой во время ответа — ничего; часть результатов пакета — недостающие; во время инструмента — один), текст результата, `toolMeta`, порядок как в ответе (красный)
- [ ] 2.6 Реализовать `healInterruptedTurn` в `projections.dart` — 2.5 зелёный

## 3. Хранилище и запись журнала (3.2)

- [ ] 3.1 Тест (agent-sessions «Порт SessionStore», «Список сессий и автоматический заголовок»): общий набор `test/session/session_store_contract.dart` и его прогон `test/session/memory_session_store_test.dart` — `create`, `append`, `open`, `close`, повторный `create` → `StateError`, нет сессии → `SessionNotFound`; `list` — фильтр по `cwd`, сортировка по `updatedAt` и `id`, курсор на границе страницы, неверный курсор → `InvalidCursor` (красный)
- [ ] 3.2 Реализовать `lib/src/session/session_store.dart` (порт, `SessionSnapshot`, `RepairReport`, `SessionSummary`, `SessionPage`, курсор, исключения), `lib/src/session/slug.dart` (`cwdSlug`, `fnv1a32Hex`), `lib/src/session/memory_session_store.dart` — 3.1 зелёный
- [ ] 3.3 Тест (agent-sessions «Запись журнала из событий»): `test/session/session_writer_test.dart` — таблица событие → запись → `durable` на fake-хранилище; `origin` служебных сообщений; `toolMeta` из `ToolCallStarted`, `diff` из `ToolCallFinished`; индекс снимка не меняется при ошибке записи; ошибка записи → `session.append.failed`, отмена хода `StorageFailure` (красный)
- [ ] 3.4 Реализовать `lib/src/session/session_writer.dart`; причина `StorageFailure` в `lib/src/cancel/cancel_token.dart` и её отображение в `TurnEnded(failed)` в `agent_loop.dart` — 3.3 зелёный

## 4. Runtime с журналом (3.4, 3.7, 3.10, 3.11)

- [ ] 4.1 Тест (agent-runtime «Профили хостов и сужение», «Минимальная сборка buildAgentCore»): `test/host/host_profile_test.dart` — `sessionPersistence` transport `jsonl-file` и `compaction` on в `agent-serve` и `embedded-cli`, сужение до `memory`; `test/host/build_agent_core_test.dart` — `jsonl-file` над `MemorySessionStore` → `HostWiringException(sessionPersistence)` (красные)
- [ ] 4.2 Реализовать `HostCapability.sessionPersistence` и `compaction`, `AgentCoreServices.sessions`, проверку §10.8 в `build_agent_core.dart`; обновить существующие тесты сборки на `MemorySessionStore` с сужением — 4.1 зелёные
- [ ] 4.3 Тест (agent-runtime «AgentRuntime и AgentSession», agent-sessions «Запись журнала из событий»): `test/session/deterministic_journal_test.dart` — два прогона сценария с `read` и `edit` дают побайтово одинаковый JSONL `MemorySessionStore`; `test/runtime/load_session_test.dart` — журнал после `createSession` начинается `model_change`; `loadSession` восстанавливает транскрипт, режим `plan` и план; `replay()`; другая модель журнала → `session.model.not_restored` и новая `model_change`; ошибка записи → `AgentError(storage)` и `TurnEnded(failed)` (красные)
- [ ] 4.4 Тест (agent-sessions «Продолжение прерванного хода»): `test/scenarios/resume_after_crash_test.dart` — `core/resume-after-crash-no-tool-recall` и `core/interrupted-tool-not-retried` на `MemorySessionStore`: `write a.txt` выполнен, долгий `exec` прерван «сбоем» (журнал без результата); после `loadSession` у `exec` синтетический `interrupted`, после `prompt("продолжай")` счётчик `write` = 1, запрос к модели содержит обе пары; двойная загрузка не дописывает второй результат (красный)
- [ ] 4.5 Тест (agent-sessions «Список сессий и автоматический заголовок»): `test/runtime/session_title_test.dart` — первый ход «Почини тест парсера» → `SessionTitleChanged`, `session_info` с `source: "auto"`, `listSessions()` с тем же заголовком; ход только из служебного сообщения заголовка не даёт; второй ход заголовок не меняет; `test/runtime/session_list_test.dart` — две сессии в `/a` и одна в `/b`, `listSessions(cwd: "/a")` — две, новая первой; неверный курсор → `InvalidCursor` (красные)
- [ ] 4.6 Реализовать в `lib/src/runtime/agent_runtime.dart` и `agent_session.dart`: `SessionWriter` первым подписчиком, `model_change` при создании, `loadSession`, `listSessions({cwd, cursor, pageSize})`, `replay()`, автоматический заголовок, `close()`; экспорт по design.md, D1 — 4.3–4.5 зелёные
- [ ] 4.7 Проверка итерации 1: `public_api_test.dart` — барель не экспортирует `session_writer.dart` и `compactor.dart` (D1); решение D10 (Python-сессии) отражено в документе ядра §16.1, если формулировка расходится; документ ядра §1.4, §5.6 и §8.4 получают сигнатуры D3 и D5; `fvm dart run melos run check` зелёный; PR итерации 1

## 5. JSONL на диске (3.3)

- [ ] 5.1 Тест (agent-sessions «JsonlSessionStore пакета codelab_agent_io»): `packages/dart/codelab_agent_io/test/session/jsonl_session_store_test.dart` — общий контрактный набор ядра во временном каталоге; имя файла и каталог слага; строка с `\n` → `StateError`; 100 параллельных `append` → 100 разбираемых строк с уникальными id (SES-4); `FsyncPolicy` через fake-счётчик `flush`; ошибка записи закрывает дескриптор, следующая запись проходит; `index.json` — попадание по `(size, mtime)`, повреждённый кеш пересоздаётся; слаги `/a/b-c` и `/a-b/c` различаются (красные)
- [ ] 5.2 Реализовать `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart`, `write_queue.dart`, экспорт `JsonlSessionStore` и `FsyncPolicy` из `lib/codelab_agent_io.dart` — 5.1 зелёные

## 6. Открытие и ремонт на диске (3.9)

- [ ] 6.1 Тест (agent-sessions «Открытие и ремонт журнала»): `packages/dart/codelab_agent_io/test/session/jsonl_repair_test.dart` — обрыв посреди последней строки: файл усечён, `.corrupt` с `reason: truncated`, запись после открытия прикрепляется к последней целой (SES-5, SES-6); мусор в середине: `.corrupt`, переписывание через `.tmp` и `rename` (SES-1); dangling `leaf`; цикл `parentId` и отсутствующий родитель; неизвестная версия — файл побайтово не изменён (SES-2); отсутствующий заголовок — синтез без записи в файл (красный)
- [ ] 6.2 Тест: `packages/dart/codelab_agent_io/test/session/jsonl_crash_recovery_test.dart` — файл, обрезанный посреди последней строки, загружается через `AgentRuntime.loadSession`, ход продолжается; `core/session-crash-mid-turn-loads` — дочерний процесс `dart run` пишет журнал хода и убивается `SIGKILL` посреди записи; сессия открывается, целые записи на месте, обрезанная строка в `.corrupt`, `RepairReport` не пуст, следующий `prompt` выполняется (красные)
- [ ] 6.3 Реализовать шаги 5a–5b §8.6 в `JsonlSessionStore.open` поверх `parseSessionLines` — 6.1, 6.2 зелёные
- [ ] 6.4 Проверка итерации 2: `fvm dart run melos run check` зелёный; документ ядра §8.5, §8.6 и §8.9 правятся там, где реализация уточнила контракт; PR итерации 2

## 7. Оценка токенов и пороги (3.5)

- [ ] 7.1 Тест (agent-compaction «Оценка токенов с якорем на usage», «Пороги сжатия»): `test/compaction/estimate_test.dart` — таблица на каждый вид блока, якорь с usage, с обнулённым usage, без usage, пример §9.3 (`53 659`); `effectiveContextWindow` с `cap`; `test/compaction/settings_test.dart` — таблица `forWindow` §9.4, переопределения больше `w/4` и `w/2` (красные)
- [ ] 7.2 Реализовать `lib/src/compaction/estimate.dart`, `settings.dart`; `CompactionOverrides` в `CoreConfig` — 7.1 зелёные

## 8. Точка среза и резюме (3.6)

- [ ] 8.1 Тест (agent-compaction «Точка среза»): `test/compaction/cut_point_test.dart` — golden примера §9.6; длинный пакет вызовов на границе (CMP-1); служебные записи перед срезом остаются с хвостом; один огромный ход → `splitTurn` и `turnStartIndex` (CMP-7); всё помещается в хвост → `null`; служебное user-сообщение ходом не считается (красный)
- [ ] 8.2 Реализовать `lib/src/compaction/cut_point.dart` — 8.1 зелёный
- [ ] 8.3 Тест (agent-compaction «Генерация резюме»): `test/compaction/summarizer_test.dart` на scripted модели — сериализация региона (заголовки, канонический JSON аргументов, сокращение длинных результатов), шаблон `summary.md` и `summary_update.md` с `previousSummary` (CMP-9), блок `<focus>` только при `focus`, разрезанный ход с дословной цитатой, запрос без инструментов с `cacheKey` `<id>:summary`, обязательные заголовки разделов в тексте запроса, `ErrorEvent` и пустой ответ → `CompactionFailed`, отмена → `CancelledException` (красный)
- [ ] 8.4 Написать промпты `prompts/compaction/system.md`, `summary.md`, `summary_update.md`, `turn_context.md`, `focus.md` (design.md, D9), перегенерировать `prompts.g.dart`; реализовать `lib/src/compaction/summarizer.dart` — 8.3 зелёный

## 9. Компактор и триггеры (3.6)

- [ ] 9.1 Тест (agent-compaction «Запись сжатия и пересборка»): `test/compaction/compactor_test.dart` — запись `compaction` с `firstKeptId`, `tokensBefore`, `tokensAfter` и `details`; `durable`; транскрипт из проекции; `ContextCompacted` после записи; до трёх проходов (CMP-5); `CompactionFailed` и отмена — журнал побайтово не изменён (CMP-2, CMP-3, CMP-4); `NothingToCompact` при пустом регионе (красный)
- [ ] 9.2 Реализовать `lib/src/compaction/compactor.dart` — 9.1 зелёный
- [ ] 9.3 Тест (agent-loop «Функция хода runAgentLoop», «Хуки и сборка payload», «События AgentEvent»): `test/loop/emergency_compact_test.dart` — `overflow` → один `emergencyCompact` и повтор; второй `overflow` → `TurnEnded(failed)` без второго вызова (CMP-8); `preflight` больше окна и `null` → синтетический `overflow` без вызова провайдера; без полей — поведение этапа 2; `ModelRequested.estimatedTokens` (красный)
- [ ] 9.4 Реализовать `estimateTokens` и `emergencyCompact` в `AgentLoopConfig`, шаг 5 сборки payload и шаг 14a хода в `agent_loop.dart`; `Agent.replaceMessages` — 9.3 зелёный
- [ ] 9.5 Тест (agent-compaction «Точки срабатывания сжатия», agent-runtime «Минимальная сборка buildAgentCore»): `test/compaction/overflow_then_compact_test.dart` — scripted LLM отвечает `overflow`, после сжатия — текстом; ход `completed`, в журнале `compaction`, событие `ContextCompacted`; `test/compaction/after_turn_test.dart` — фоновое сжатие после `completed`, следующий `prompt` ждёт его; после `cancelled` и `failed` не запускается; ошибка фонового сжатия → `AgentError(compaction)`; `test/compaction/long_session_test.dart` — окно 8 192, 30 ходов, проверка парности каждого запроса, оценка после сжатия ниже порога (CMP-1, CMP-5); `cap = 50 000` при окне 128 000 — порог и preflight от 50 000 (CMP-6); `CoreConfig.compaction.enabled: false` → capability off, `overflow` не сжимает (красные)
- [ ] 9.6 Реализовать триггеры в `AgentSession` (`afterTurn` в фоне, `emergencyCompact` сессии, ожидание в `prompt`), capability `compaction` в сборке — 9.5 зелёные
- [ ] 9.7 Definition of Done этапа: `fvm dart test packages/dart/codelab_agent_core packages/dart/codelab_agent_io` зелёный; `melos run guard` и `melos run web-compile` зелёные; DoD-тесты плана этапа (`jsonl_crash_recovery_test.dart`, `deterministic_journal_test.dart`, `overflow_then_compact_test.dart`, `core/session-crash-mid-turn-loads`, `core/resume-after-crash-no-tool-recall`, `core/interrupted-tool-not-retried`, `session_title_test.dart`, `session_list_test.dart`) зелёные; строки матрицы S-01, S-03 (ядро), S-05 (ядро), S-13 (ядро), K-01, K-03, K-04, L-14 (ядро) имеют доказательства; документ ядра §9 правится там, где реализация уточнила контракт; PR итерации 3
- [ ] 9.8 Перед архивированием: `openspec validate add-agent-core-sessions-and-compaction --strict`; заполнить Purpose новых спецификаций `agent-sessions` и `agent-compaction`
