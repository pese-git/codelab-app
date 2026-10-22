# 9.8. Этап 3 — Сессии и сжатие

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) →

**Цель.** Сессии переживают перезапуск и обрыв процесса; длинные сессии не упираются в окно
контекста.

**Задачи.**

1. **3.1. Записи и дерево:** `packages/dart/codelab_agent_core/lib/src/session/records.dart`
   (типы записей, `parentId`, `leaf`), `parse.dart`, `tree.dart`, `projections.dart` (сообщения для LLM,
   события для реплея, сводка для списка). Документ ядра §8, §1.3.
2. **3.2. Порт хранилища:** `lib/src/session/session_store.dart` (порт `SessionStore` и `MemorySessionStore`).
3. **3.3. JSONL на диске:** `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart` —
   запись построчно, `flush` по политике `sessions.fsync` (agent-core-architecture §8.5); при чтении последняя неполная строка
   отбрасывается с предупреждением; файл — `$CODELAB_HOME/sessions/<cwd-slug>/<created в ISO-8601 UTC>_<sessionId>.jsonl` (agent-core-architecture §8.9).
4. **3.4. `loadSession`/`listSessions`** в `AgentRuntime`; `AgentSession.replay()`.
5. **3.5. Оценка токенов:** `lib/src/compaction/estimate.dart` (символы / 4 с якорем по
   `usage.input + usage.cacheRead + usage.cacheWrite + usage.output` последнего ответа провайдера,
   agent-core-architecture §9.3).
6. **3.6. Компактор:** `lib/src/compaction/cut_point.dart` (точка отреза), `compactor.dart` (порог от
   окна контекста; сводка старой части через ту же `StreamFunction`; запись `compaction` в
   журнал (событие `ContextCompacted`); при ошибке переполнения от провайдера — сжатие и повтор шага один раз).
7. **3.7. Python-сессии не переносятся** («чистый лист», agent-core-architecture §16.1): `design.md` фиксирует решение, пользовательская документация этапа 9 предупреждает о нём.
8. **3.8. Вынос огромного результата в файл (T-28):** порт `packages/dart/codelab_agent_core/lib/src/spill/spill_store.dart`, сервис `lib/src/spill/spill_service.dart`, `LocalSpillStore` в `codelab_agent_io/lib/src/spill/local_spill_store.dart`; файлы `<файл журнала без .jsonl>/spills/<n>.txt`, поле записи `spill`, корень только для чтения в `BoundedEnv`, capability `outputSpill`, ключи `tools.spill` (agent-core-architecture §17.4); тесты из блока «Как проверить» §17.4. Расширение ACP `_meta.codelab.spill` — после этапа 9 через OpenSpec.

**OpenSpec change.** `add-agent-core-sessions-and-compaction` — scope: формат JSONL (версия
формата в первой записи), правила восстановления после обрыва, политика сжатия, вынос огромного
результата в файл (раскладка `spills/`, квоты, удаление сирот; без расширения ACP).

**Что прочитать.** Документ ядра §8, §9, §17.4, §1 (PKG-6: `Clock` и `IdGenerator`).

**Definition of Done.**

* `test/session/jsonl_crash_recovery_test.dart` (в `codelab_agent_io`): файл, обрезанный
  посреди последней строки, загружается; ход продолжается.
* `test/session/deterministic_journal_test.dart` (в ядре): два прогона одного сценария дают
  побайтово одинаковый JSONL.
* `test/compaction/overflow_then_compact_test.dart`: scripted LLM сначала отвечает ошибкой
  `overflow`, после сжатия — успехом; ход завершается `completed`, в журнале есть запись `compaction` (событие `ContextCompacted`).
* `fvm dart test packages/dart/codelab_agent_core packages/dart/codelab_agent_io` зелёный.

**Зависимости.** Этап 2.

**Риски.** Формат журнала закрепляется надолго — версия формата в первой записи и тест чтения
старых версий с первого дня. Сводка при сжатии теряет важные детали — порог и промпт сводки
настраиваются; Context Manager — только по условию §7б.

---

← [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) · [Оглавление](../dart-agent-and-clients.md) · [9.9. Этап 4 — ACP-адаптер и codelab-agent](09-09-stage-4-acp-adapter.md) →
