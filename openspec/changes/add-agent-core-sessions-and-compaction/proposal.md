## Why

Этапы 1 и 2 дали работающего агента в памяти: ход, инструменты, разрешения, прямой API `AgentRuntime` / `AgentSession`. Но история сессии живёт только в транскрипте `Agent`. Перезапуск или падение процесса её теряет. Длинная сессия рано или поздно упирается в окно контекста модели и падает с `overflow`.

Этап 3 (`docs/architecture/proposals/dart-agent-and-clients/09-08-stage-3-sessions.md`) делает сессии долговечными и длинными:
- журнал сессии — append-only JSONL, единственный источник истории;
- сессия открывается после обрыва процесса и продолжается без повторного вызова инструментов;
- старая часть истории сжимается резюме модели, когда перестаёт помещаться в окно.

Без этого слоя нет ни `session/load` и `session/list` ACP-адаптера (этап 4), ни продолжения работы после сбоя. Этап закрывает цели паритета уровня Must S-01, S-03, S-05, S-13 и K-01 в части ядра, Should K-03 и K-04, ядерную часть L-14 (`agent-parity-goals.md`). Источник решений — принятый документ ядра `agent-core-architecture.md`: §8, §9, §1 (PKG-6), §10 (capability `sessionPersistence` и `compaction`), §11 (промпты суммаризатора).

## What Changes

- **Записи и дерево (3.1).** Типы записей журнала MVP §8.2 (`SessionHeader`, `SessionRecord` и подклассы), разбор строк, `parentId` и лист, `pathToLeaf`, предикат «слова пользователя» `isUserWords` (§8.2.5), слаг `cwd` (§8.9). Проекции журнала:
  - `buildLlmContext` — сообщения для модели с обнулением usage до сжатия;
  - `buildReplay` — события для реплея на уровне `AgentEvent`;
  - `summarize` — сводка для списка;
  - `healInterruptedTurn` — синтетические результаты прерванных вызовов.
- **Порт хранилища (3.2).** `SessionStore`, `SessionSnapshot`, `RepairReport` и `MemorySessionStore`. `SessionWriter` пишет журнал как подписчик событий `Agent` («хост сохраняет, цикл эмитит», §8.3).
- **JSONL на диске (3.3).** `JsonlSessionStore` в `codelab_agent_io`:
  - одна строка — один вызов `write`;
  - очередь записи на путь;
  - политика `fsync` (`checkpoints` по умолчанию);
  - раскладка `<root>/<cwd-slug>/<created>_<sessionId>.jsonl`;
  - кеш сводок `index.json`.
- **`loadSession`, `listSessions`, `replay` (3.4).** `AgentRuntime.loadSession` открывает журнал, восстанавливает транскрипт, режим и план. `listSessions` возвращает страницу сводок с фильтром по `cwd` и курсором. `AgentSession.replay()` отдаёт события журнала для `session/load`.
- **Оценка токенов (3.5).** Символы / 4 с якорем на usage последнего ответа (§9.3) и `effectiveContextWindow` — одна функция окна для порога и проверки перед запросом (CMP-6).
- **Компактор (3.6).** Пороги `forWindow`, точка среза, резюме через ту же `StreamFunction` по промптам `compaction/*.md`, запись `compaction` и пересборка транскрипта (§9.4–§9.8). Триггеры:
  - `afterTurn` — после хода;
  - `preflight` и `overflow` — аварийно внутри хода, не больше одного раза за ход (CMP-8);
  - `manual` — с указанием `focus`, вызывается компактором; команда `/compact` — этап 4.
- **Python-сессии не переносятся (3.7).** Решение фиксируется в design.md.
- **Открытие и ремонт журнала (3.9).** Проверка версии заголовка, синтез отсутствующего заголовка, карантин битых строк в `.corrupt`, усечение оборванной последней строки, переписывание через `.tmp` и `rename`, dangling `leaf`, цикл `parentId`, отчёт `RepairReport` (§8.6).
- **Продолжение прерванного хода (3.10).** Вызовы без результата получают синтетический результат `interrupted` сразу после открытия, до реплея и нового шага; выполненные вызовы не повторяются (SES-9, SES-10).
- **Заголовок и список (3.11).** Автоматический заголовок после первого завершённого хода со словами пользователя (`session_info` с `source: "auto"`, событие `SessionTitleChanged`); `list` с сортировкой, курсором и ошибкой `InvalidCursor` (§8.10).
- **Цикл.** `AgentLoopConfig` получает `estimateTokens` и `emergencyCompact` (§5.2, шаг 4; §5.4, шаг 14a), `ModelRequested.estimatedTokens` — настоящую оценку, иерархия событий — `ContextCompacted` и `SessionTitleChanged`.
- **Порт идентификаторов.** `IdGenerator.nextChars(count, alphabet)` для `SessionId` в формате ULID и 8-символьных `RecordId` (§8.4).
- **Сборка.** Capability `sessionPersistence` и `compaction` (§10.2, §10.4, §10.8), сервис `AgentCoreServices.sessions`, настройки сжатия в `CoreConfig`.

Не входит:
- вынос огромного результата в файл (задача 3.8, T-28, Should): отдельный change `add-agent-core-output-spill` после редакции секретов, потому что файл выноса не должен содержать сырых секретов (SPL-3, design.md, D11);
- редакция секретов `Redactor` (P-10): шаг 8b единой точки исполнения по-прежнему пропускается;
- ACP-проекция реплея и `session_info_update`, команда `/compact`, `setConfigOption` и запись `config_change` (этап 4);
- загрузка `sessions.*` и `compaction.*` из файлов конфигурации (этап 8): хост и тесты передают значения напрямую;
- роли моделей и отдельная модель резюме (`agent.summary_model`, §17.10.5), ветки, fork, перемотка, lease, оконное открытие, запечатывание, быстрая проба заголовка — после MVP.

## Capabilities

### New Capabilities
- `agent-sessions`: журнал сессии — формат JSONL и записи MVP, идентификаторы и дерево, порт `SessionStore` и `MemorySessionStore`, `JsonlSessionStore`, запись журнала из событий, открытие и ремонт, проекции `buildLlmContext` / `buildReplay` / `summarize`, продолжение прерванного хода, раскладка на диске, список и автоматический заголовок.
- `agent-compaction`: сжатие контекста — оценка токенов с якорем на usage, функция окна, пороги `forWindow`, точка среза, генерация резюме, запись сжатия и пересборка, триггеры и правило «аварийное сжатие один раз за ход».

### Modified Capabilities
- `agent-runtime`:
  - «AgentRuntime и AgentSession в памяти» переименовывается в «AgentRuntime и AgentSession»: `loadSession`, `listSessions` со страницей и курсором, `replay`, журнал каждой сессии, автоматический заголовок, автосжатие после хода;
  - «Профили хостов и сужение» — capability `sessionPersistence` и `compaction` в профилях `agent-serve` и `embedded-cli`;
  - «Минимальная сборка buildAgentCore» — сервис `sessions` и его проверка, настройки сжатия.
- `agent-loop`:
  - «События AgentEvent» — `ContextCompacted`, `SessionTitleChanged`, признак `interrupted` у `ToolCallFinished` реплея;
  - «Хуки и сборка payload» — `estimateTokens` и `emergencyCompact`, проверка размера перед запросом;
  - «Функция хода runAgentLoop» — ответ `overflow` вызывает аварийное сжатие и один повтор шага.
- `agent-core-ports`: «Порты детерминизма от хоста» — `IdGenerator.nextChars` и детерминированная реализация в `SequentialIdGenerator`.

## Impact

- **`packages/dart/codelab_agent_core`:**
  - новые каталоги `lib/src/session/` (`records.dart`, `parse.dart`, `tree.dart`, `projections.dart`, `user_words.dart`, `ids.dart`, `slug.dart`, `session_store.dart`, `memory_session_store.dart`, `session_writer.dart`) и `lib/src/compaction/` (`estimate.dart`, `settings.dart`, `cut_point.dart`, `summarizer.dart`, `compactor.dart`);
  - промпты `prompts/compaction/*.md` и перегенерированный `prompts.g.dart`;
  - изменения `loop/`, `runtime/`, `host/`, `util/ids.dart`, `testing/sequential_id_generator.dart`;
  - расширенный барель и тесты, фикстуры `test/fixtures/sessions/*.jsonl`.
- **`packages/dart/codelab_agent_io`:** `lib/src/session/jsonl_session_store.dart` и `write_queue.dart`, экспорт `JsonlSessionStore` и `FsyncPolicy`; интеграционные тесты на реальной файловой системе во временном каталоге, только на Dart VM (`AGENTS.md` §21).
- **Зависимости.** Новых нет; allowlist PKG-2 и allowlist `codelab_agent_io` не меняются.
- **Документы.** Документ ядра правится там, где реализация уточняет контракт (design.md, D3, D4, D5, D8), в том же PR. План этапа 3 (`09-08-stage-3-sessions.md`) отмечает перенос задачи 3.8 в отдельный change.
- **Не меняются:** клиенты, ACP-контракты, поведение `codelab_app` и пакетов `acp_*`.
