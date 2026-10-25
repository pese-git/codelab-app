# 9.8. Этап 3 — Сессии и сжатие

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) →

**Цель.** Сессии переживают перезапуск и обрыв процесса; длинные сессии не упираются в окно
контекста.

**Задачи.**

1. **3.1. Записи и дерево:** `packages/dart/codelab_agent_core/lib/src/session/records.dart`
   (типы записей, `parentId`, `leaf`), `parse.dart`, `tree.dart`, `projections.dart` (сообщения для LLM,
   события для реплея, сводка для списка). Документ ядра §8, §1.3.
2. **3.2. Порт хранилища:** `lib/src/session/session_store.dart` (порт `SessionStore` и `MemorySessionStore`).
3. **3.3. JSONL на диске:** `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart` —
   запись построчно, `flush` по политике `sessions.fsync` (agent-core-architecture §8.5); битые строки при
   открытии — задача 3.9; файл — `$CODELAB_HOME/sessions/<cwd-slug>/<created в ISO-8601 UTC>_<sessionId>.jsonl` (agent-core-architecture §8.9).
4. **3.4. `loadSession`/`listSessions`** в `AgentRuntime`; `AgentSession.replay()`.
5. **3.5. Оценка токенов:** `lib/src/compaction/estimate.dart` (символы / 4 с якорем по
   `usage.input + usage.cacheRead + usage.cacheWrite + usage.output` последнего ответа провайдера,
   agent-core-architecture §9.3).
6. **3.6. Компактор:** `lib/src/compaction/cut_point.dart` (точка отреза), `compactor.dart` (порог от
   окна контекста; сводка старой части через ту же `StreamFunction`; запись `compaction` в
   журнал (событие `ContextCompacted`); при ошибке переполнения от провайдера — сжатие и повтор шага один раз).
7. **3.7. Python-сессии не переносятся** («чистый лист», agent-core-architecture §16.1): `design.md` фиксирует решение, пользовательская документация этапа 9 предупреждает о нём.
8. **3.8. Вынос огромного результата в файл (T-28)** — *Should — не блокирует MVP*: порт `packages/dart/codelab_agent_core/lib/src/spill/spill_store.dart`, сервис `lib/src/spill/spill_service.dart`, `LocalSpillStore` в `codelab_agent_io/lib/src/spill/local_spill_store.dart`; файлы `<файл журнала без .jsonl>/spills/<n>.txt`, поле записи `spill`, корень только для чтения в `BoundedEnv`, capability `outputSpill`, ключи `tools.spill` (agent-core-architecture §17.4); тесты из блока «Как проверить» §17.4. Расширение ACP `_meta.codelab.spill` — после этапа 9 через OpenSpec.
9. **3.9. Открытие и ремонт журнала** (S-01, agent-core-architecture §8.6): `open(sessionId)` в
   `parse.dart` и `jsonl_session_store.dart` — проверка версии заголовка
   (`SessionOpenException(unsupportedVersion)`, файл не трогается), синтез отсутствующего
   заголовка в памяти, перенос битых строк (оборванная последняя и мусор в середине) в файл-карантин
   `.corrupt`, переписывание файла через `.tmp` и `rename`, отчёт о ремонте (`RepairReport`),
   dangling `leaf`, цикл `parentId` и отсутствующий родитель. Тесты — блок «Как проверить» §8.13
   (обрыв посреди строки, мусор в середине, dangling leaf, цикл, неизвестная версия).
10. **3.10. Продолжение прерванного хода** (S-13, SES-9, SES-10, agent-core-architecture §8.8):
    `healInterruptedTurn` (чистая функция ядра §8.3, `projections.dart`) — вызовам без результата дописываются
    синтетические результаты `interrupted` сразу после `open()`, до реплея и нового шага; вызовы с
    результатом не повторяются, прерванный вызов автоматически не перезапускается; следующий
    `prompt()` видит полную историю. Проекция реплея (`interrupted` → `failed` с
    `_meta.codelab.outcome: "interrupted"`) — этап 4 (фикстура `acp/session-load-interrupted-turn`).
11. **3.11. Заголовок сессии и сводка для списка** (S-05, S-03, agent-core-architecture §8.10, §8.2.5):
    `summarize` в `projections.dart` (заголовок из последней `session_info` или из первого
    сообщения со словами пользователя — пробелы схлопнуты, 80 символов по границе слова с `…`;
    `updatedAt`, `messageCount`, `lastTurnFailed`), `list(cwd, cursor, pageSize)` с сортировкой,
    курсором и кешем `index.json`; автоматический заголовок — после первого завершённого хода со
    словами пользователя `AgentSession` пишет `session_info` с `source: "auto"` и эмитит
    `SessionTitleChanged` (ACP `session_info_update` — этап 4, `acp/session-info-title`).
    Заголовок моделью — после 9 (§16.1).

**OpenSpec change.** `add-agent-core-sessions-and-compaction` — scope: формат JSONL (версия
формата в первой записи), правила восстановления после обрыва, политика сжатия, ремонт
журнала при открытии, продолжение прерванного хода, автоматический заголовок. Вынос огромного
результата в файл (задача 3.8: раскладка `spills/`, квоты, удаление сирот; без расширения ACP) —
отдельный change `add-agent-core-output-spill` после редакции секретов (P-10, перенесена на этап 4,
задача 4.11): файл выноса не должен содержать сырых секретов (SPL-3; design.md change этапа, D11). `tasks.md` — пары
«тест → реализация» со ссылкой на критерий (§9.0, правило 3).

**Что прочитать.** Документ ядра §8, §9, §17.4, §1 (PKG-6: `Clock` и `IdGenerator`).

**Definition of Done.**

* `test/session/jsonl_crash_recovery_test.dart` (в `codelab_agent_io`): файл, обрезанный
  посреди последней строки, загружается; ход продолжается.
* `test/session/deterministic_journal_test.dart` (в ядре): два прогона одного сценария дают
  побайтово одинаковый JSONL.
* `test/compaction/overflow_then_compact_test.dart`: scripted LLM сначала отвечает ошибкой
  `overflow`, после сжатия — успехом; ход завершается `completed`, в журнале есть запись `compaction` (событие `ContextCompacted`).
* `core/session-crash-mid-turn-loads` (S-01): процесс убит посреди записи строки, последняя строка
  обрезана → сессия открывается через прямой API; все целые записи на месте, обрезанная строка
  перенесена в `.corrupt`, отчёт о ремонте не пуст; следующий `prompt` выполняется.
* `core/resume-after-crash-no-tool-recall` и `core/interrupted-tool-not-retried` (S-13): ход —
  `write a.txt` выполнен, запущен долгий `exec`, процесс убит; после открытия `write` — с
  результатом, `exec` — синтетический `interrupted`; после `prompt("продолжай")` счётчик вызовов
  `write` = 1, запрос к модели содержит обе пары вызов-результат.
* `session_title_test.dart` (S-05, уровень ядра): первый ход «Почини тест парсера» завершён →
  событие `SessionTitleChanged` с непустым заголовком, запись `session_info` с `source: "auto"`;
  `list()` возвращает тот же заголовок.
* `session_list_test.dart` (S-03): две сессии в `/a` и одна в `/b`; `list(cwd: "/a")` — две, более
  новая первой; неверный курсор → `InvalidCursor`.
* `fvm dart test packages/dart/codelab_agent_core packages/dart/codelab_agent_io` зелёный.
* Если сделано (задача 3.8, Should — не блокирует MVP): тесты блока «Как проверить» §17.4.

**Зависимости.** Этап 2.

**Риски.** Формат журнала закрепляется надолго — версия формата в первой записи и тест чтения
старых версий с первого дня. Сводка при сжатии теряет важные детали — порог и промпт сводки
настраиваются; Context Manager — только по условию §7б.

---

← [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) →
