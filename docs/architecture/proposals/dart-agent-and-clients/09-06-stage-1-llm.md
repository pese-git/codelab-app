# 9.6. Этап 1 — LLM

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.5. Этап 0 — Фундамент](09-05-stage-0-foundation.md) · [Оглавление](../dart-agent-and-clients.md) · [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) →

**Цель.** Слой между циклом и моделью: модель сообщений, стриминговые события, контракт
`StreamFunction`, отмена, декораторы устойчивости, два адаптера провайдеров и детерминированный
`ScriptedStreamFunction` для всех следующих тестов.

**Задачи.** Все пути — в `packages/dart/codelab_agent_core/`.

1. **1.1. Отмена:** `lib/src/cancel/cancel_token.dart` (`CancelToken`, `CancelTokenSource`,
   связывание токенов, `whenCancelled`) по документу ядра §3. Тест: `test/cancel/cancel_token_test.dart`.
2. **1.2. Модель сообщений:** `lib/src/llm/messages.dart` (`ContentBlock`, `Message`, `StopReason`),
   `lib/src/llm/usage.dart` (`Usage`), `lib/src/llm/model_ref.dart` (`ModelRef`, `ModelCost`),
   `lib/src/llm/errors.dart` (`LlmErrorClass`).
3. **1.3. События и поток:** `lib/src/llm/events.dart`,
   `lib/src/llm/event_stream.dart` (`EventStream<T, R>`: один терминал, `result` всегда
   завершается), `lib/src/llm/stream_function.dart` (`typedef StreamFunction`, `LlmContext`,
   `ToolSchema`). Тест: `test/llm/event_stream_test.dart`.
4. **1.4. `ScriptedStreamFunction`** — `lib/src/testing/scripted_stream_function.dart`, экспорт
   из отдельной точки входа `lib/testing.dart` (не из основного бареля). Сценарий: список шагов,
   каждый шаг — текст, мысли, вызовы инструментов с аргументами, ошибка с `LlmErrorClass`,
   задержка по `FakeClock` или ожидание отмены. Шаги отдаются строго по порядку: n-й запрос к
   модели получает n-й шаг; `expect` шага — утверждение о запросе (последнее сообщение, результат
   инструмента, список схем), а не условие выбора: несовпадение — провал с diff запроса; лишний
   запрос или неиспользованный шаг — провал (agent-core-architecture §14.7). В тексте ответа
   подставляются `${cwd}` и `${sessionId}`. Формат сценария совпадает с секцией `llm` фикстуры
   (§14.7), поэтому один файл питает и тест ядра, и conformance ACP, и `--llm-script` бинаря
   (задача 4.6). Тест: `test/testing/scripted_stream_function_test.dart` (порядок шагов, провал
   `expect`, лишний запрос, неиспользованный шаг, подстановка переменных).
5. **1.5. SSE-декодер:** `lib/src/llm/sse.dart`
   (`StreamTransformer<String, ServerSentEvent>`; правила — документ ядра §2). Тест:
   `test/llm/sse_decoder_test.dart` (нарезка по одному символу, CRLF, BOM, комментарии,
   многострочный `data`, незавершённое событие в конце).
6. **1.6. Адаптер OpenAI-совместимый:** `lib/src/llm/providers/openai_compatible.dart`.
   Тест на `MockClient` из `package:http/testing.dart` и SSE-фикстурах
   `test/fixtures/sse/openai/*.sse` (текст, вызов инструмента частями, два вызова, usage в
   последнем чанке, `finish_reason: length`, `content_filter`, 429 с `Retry-After`, 200 без SSE).
   Фикстуры пишутся вручную по публичной документации API, без секретов.
7. **1.7. Адаптер Anthropic:** `lib/src/llm/providers/anthropic.dart`, фикстуры
   `test/fixtures/sse/anthropic/*.sse` (именованные события, `thinking` с подписью, `tool_use`,
   `overloaded_error`).
8. **1.8. Декораторы:** `lib/src/llm/decorators/watchdog.dart`,
   `retry.dart`, `fallback.dart`; учёт стоимости — `lib/src/llm/usage.dart`; признак переполнения —
   `lib/src/llm/overflow.dart`. Тест-матрица `test/llm/decorators_test.dart`:
   сбой до видимого вывода повторяется; после первого `BlockStartEvent` — нет; `content_filter`,
   401, overflow, aborted не повторяются; rate limit уважает `Retry-After`; fallback порождает
   `FallbackNotice`.
9. **1.9. Фабрика:** `lib/src/llm/providers/provider_factory.dart` (`ProviderConfig`,
   `createStreamFunction(ProviderConfig config, CoreLlmServices services)`, agent-core-architecture §2.10).
   Хост получает уже обёрнутую функцию; классы адаптеров наружу не экспортируются (PKG-5).
10. **1.10. Ручной smoke** `packages/dart/codelab_agent_core/tool/llm_smoke.dart` — один запрос к
    реальному провайдеру по ключу из env; в CI не запускается, используется для проверки
    фикстур.
11. **1.11. Порты детерминизма** (PKG-6, agent-core-architecture §1.3, §1.5; `Logger` — §12.3):
    `lib/src/util/clock.dart` (`Clock`: `now()`, таймеры ожидания), `lib/src/util/ids.dart`
    (`IdGenerator`: id сессий, записей, вызовов), `lib/src/util/logger.dart` (`Logger`, `LogLevel`,
    `LogRecord` по контракту §12.3); `Random` — `dart:math`, экземпляр передаёт хост. Тестовые
    реализации в `lib/src/testing/`: `fake_clock.dart` (`FakeClock`: время двигается только
    вручную, `delayMs` сценария идёт по нему), `sequential_id_generator.dart`
    (`SequentialIdGenerator`: `id-1`, `id-2`, …), экспорт через `lib/testing.dart`. Порты нужны уже
    декораторам этапа 1 (задержки повтора, джиттер, `Retry-After`) и `ScriptedStreamFunction`.
    Тест: `test/util/determinism_ports_test.dart` (`FakeClock` не двигается сам; два
    `SequentialIdGenerator` дают одинаковые последовательности; `Random(42)` повторяем).
12. **1.12. Каталог моделей: порт и источники без сети** (agent-core-architecture §2.12.2, L-15):
    `lib/src/llm/model_catalog.dart` (`ModelId`, `ModelInfo`, `ModelEntry`, порт `ModelCatalog`
    и `StaticModelCatalog` — модели из конфига или флагов, затем встроенный каталог, затем
    безопасные значения), `lib/src/llm/builtin_models.dart` (встроенная таблица). Каталог нужен
    `buildAgentCore` (шаг 3 §10.7: `defaultModel` есть в каталоге, у модели есть окно — этап 2),
    опциям `model` и `effort` в `configOptions` (§13.6, `supportsReasoning` — этап 4) и
    минимальному конфигу бинаря (задача 4.6). Endpoint `/models`, удалённый каталог метаданных,
    кэш на диске и фоновое `refresh()` — этап 8 (L-15, Should; `refresh()` статического каталога
    ничего не делает). Тесты: `test/llm/static_model_catalog_test.dart` (порядок моделей,
    `resolve` по источникам, `min(maxOutputTokens, contextWindow − 1024)`),
    `builtin_models_test.dart` (каждая запись: окно > 0, лимит ответа < окна).

**OpenSpec change.** `add-agent-core-llm-contract` — scope: модель сообщений, события,
`StreamFunction`, `CancelToken`, адаптеры OpenAI-совместимый и Anthropic, декораторы, учёт
стоимости, порты `Clock`/`IdGenerator`/`Logger` и их тестовые реализации, порт `ModelCatalog` со
статическими источниками. Вне scope: другие провайдеры, resume стрима, сетевые источники
каталога моделей (этап 8). `tasks.md` — пары «тест → реализация» со ссылкой на критерий (§9.0,
правило 3).

**Что прочитать.** Документ ядра §1 (PKG-6), §2 (весь), §3, §12 (модель ошибок, `Logger`), §14.7
(формат сценария), §15 (секция провайдеров в конфигурации).

**Definition of Done.**

* `fvm dart test packages/dart/codelab_agent_core/test/llm packages/dart/codelab_agent_core/test/cancel packages/dart/codelab_agent_core/test/testing packages/dart/codelab_agent_core/test/util` зелёный.
* Тест `openai_compatible_test.dart: cancel mid-stream yields ErrorEvent(aborted) and closes the request` — инвариант LLM-7, LLM-10.
* Тест `decorators_test.dart: network error before first block is retried, after first block is surfaced` — LLM-8.
* Тест `event_stream_test.dart: end() without terminal completes result with StateError` — LLM-3.
* `melos run web-compile` проходит: `test/web_smoke/main.dart` выполняет один шаг на `ScriptedStreamFunction`.
* `scripted_stream_function_test.dart: expect mismatch fails with request diff` и `...: steps are served strictly in order` — §14.7.
* `static_model_catalog_test.dart: unknown model resolves to safe defaults with one warning` — §2.12.2.
* `melos run guard`: ядро зависит только от allowlist.

**Зависимости.** Этап 0.

**Риски.** Расхождения форматов потоков у OpenAI-совместимых серверов (Ollama, LM Studio,
OpenRouter) — фикстуры на каждый известный вариант, строка матрицы на каждого провайдера;
особенности Zen, Go, LMStudio берутся из Python (этап 2) только при падении строки. Изменения
API провайдеров — адаптеры изолированы за `StreamFunction`, тесты на фикстурах ловят регрессии.

---

← [9.5. Этап 0 — Фундамент](09-05-stage-0-foundation.md) · [Оглавление](../dart-agent-and-clients.md) · [9.7. Этап 2 — Цикл, инструменты, разрешения](09-07-stage-2-loop-tools-permissions.md) →
