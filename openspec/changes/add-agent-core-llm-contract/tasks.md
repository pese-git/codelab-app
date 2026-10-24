Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 1 (`dart-agent-and-clients/09-06-stage-1-llm.md`) и требование спецификации. Все пути — в `packages/dart/codelab_agent_core/`. Группы 1–4 — итерация 1 (фундамент контракта), 5–8 — итерация 2 (провода), 9–13 — итерация 3 (устойчивость и сборка); каждая итерация — отдельный PR в `develop` (design.md, D11).

## 1. Порты детерминизма и логирования (1.11)

- [x] 1.1 Тест (agent-core-ports «Порты детерминизма от хоста»): `test/util/determinism_ports_test.dart` — `FakeClock` не двигается сам, `advance` срабатывает таймерами по порядку сроков, `delay` завершается только после продвижения; два `SequentialIdGenerator` дают `id-1…id-3`; `Random(42)` повторяем (красный)
- [x] 1.2 Реализовать `lib/src/util/clock.dart` (`Clock`, `ClockTimer`, `SystemClock`), `lib/src/util/ids.dart` (`IdGenerator`), `lib/src/util/logger.dart` (`Logger`, `LogLevel`, `LogRecord`), `lib/src/testing/fake_clock.dart`, `sequential_id_generator.dart`, `recording_logger.dart` (design.md, D6) — 1.1 зелёный
- [x] 1.3 `lib/testing.dart` — экспорт тестовых реализаций; основной барель их не экспортирует

## 2. Отмена (1.1)

- [x] 2.1 Тест (agent-cancellation, все сценарии): `test/cancel/cancel_token_test.dart` — слушатель в microtask (CAN-1), первая причина выигрывает, `UserCancel` по умолчанию, `throwIfCancelled`, иерархия родитель → внук и обратное направление (CAN-3), потомок отменённого родителя, `dispose`; `raceCancel` без необработанной ошибки; `delayCancellable` по `FakeClock` (красный)
- [x] 2.2 Реализовать `lib/src/cancel/cancel_token.dart` по §3.2 — 2.1 зелёный

## 3. Модель сообщений, события и поток (1.2, 1.3)

- [x] 3.1 Тест (agent-llm «Модель сообщений и каноническая JSON-форма»): `test/llm/messages_test.dart` — круговая сериализация каждой формы таблицы §2.2, опускание `null`, игнор неизвестного поля, неизменяемые списки, `Usage +` и `UsageCost +` (красный)
- [x] 3.2 Реализовать `lib/src/llm/messages.dart`, `usage.dart`, `model_ref.dart` (`ModelRef`, `ModelCost`, `ReasoningEffort`, `ProviderApi`), `errors.dart` (`LlmErrorClass`); `Message.fromJson` с `ModelResolver` (design.md, D1, D2) — 3.1 зелёный
- [x] 3.3 Тест (agent-llm «Контракт StreamFunction», «Грамматика событий и снимки»): `test/llm/event_stream_test.dart` — `end() without terminal completes result with StateError` без необработанной ошибки (LLM-3), события до подписки не теряются, `push` после терминала игнорируется, второй `listen` — `StateError`; `test/llm/stream_state_test.dart` — `ProviderStreamState`: парность блоков, ленивые снимки `partial` без копирования на каждую дельту, `closeBlock` с неразбираемым JSON → `{}` и заметка (LLM-4…LLM-6) (красные)
- [x] 3.4 Реализовать `lib/src/llm/events.dart`, `event_stream.dart`, `stream_function.dart` (`StreamFunction`, `LlmContext`, `ToolSchema`), `stream_state.dart` (`ProviderStreamState`, `runProvider` §2.5) — 3.3 зелёные
- [x] 3.5 Экспорт модели, событий, потока, отмены и портов из `lib/codelab_agent_core.dart`

## 4. ScriptedStreamFunction и web-smoke (1.4)

- [x] 4.1 Тест (agent-llm «Детерминированная модель для тестов»): `test/testing/scripted_stream_function_test.dart` — `steps are served strictly in order`, `expect mismatch fails with request diff`, лишний запрос и неиспользованный шаг в `verify()`, дельты по 16 символов, `toolCall` и `thinking` в ответе, `error` с классом, `delayMs` по `FakeClock`, `waitForCancel` → `ErrorEvent(aborted)`, подстановка `${cwd}` и `${sessionId}`, разбор блока `llm` фикстуры `acp/prompt-tool-permission-allow` (красный)
- [x] 4.2 Реализовать `lib/src/testing/scripted_stream_function.dart` (`ScriptedStreamFunction.fromJson`, `verify()`, `ScriptedLlmFailure`; design.md, D8) и экспорт из `lib/testing.dart` — 4.1 зелёный
- [x] 4.3 `test/web_smoke/main.dart` выполняет один шаг на `ScriptedStreamFunction` и печатает текст ответа (workspace-architecture «Web-smoke выполняет шаг модели»); `fvm dart run melos run web-compile` зелёный, `fvm dart run packages/dart/codelab_agent_core/test/web_smoke/main.dart` печатает текст ответа
- [x] 4.4 Проверка итерации 1: `fvm dart run melos run check` зелёный; PR итерации 1

## 5. SSE-декодер (1.5)

- [x] 5.1 Тест (agent-llm «Декодирование SSE»): `test/llm/sse_decoder_test.dart` — нарезка целиком, по одному символу и случайными кусками даёт одно и то же; CRLF на границе чанка; одиночный `\r`; BOM только в начале; комментарии; многострочный `data`; `id` с `U+0000`; поле без двоеточия; незавершённое событие в конце; пример §2.6 (красный)
- [x] 5.2 Реализовать `lib/src/llm/sse.dart` — 5.1 зелёный

## 6. Классификация ошибок и HTTP (1.6, 1.7)

- [x] 6.1 Тест (agent-llm «Классификация ошибок провайдера», «Отмена доходит до HTTP-запроса»): `test/llm/error_classification_test.dart` — таблица §2.9 строка за строкой; 200 с HTML → `badRequest` с подсказкой; пустой поток → `network`; `errorMessage` без значения ключа API и заголовков, тело не длиннее 2000 символов (design.md, D7); `Retry-After`: `retry-after-ms`, секунды, HTTP-date по `FakeClock`, отрицательное → 0, мусор → `null` (§2.10.4) (красный)
- [x] 6.2 Реализовать `lib/src/llm/providers/http_support.dart`: `classifyHttpError`, `classifyException`, `describeHttpError`, разбор `Retry-After`, отправка `AbortableRequest` с ручными same-origin редиректами (не больше 5; design.md, D5); поднять `http` в `pubspec.yaml` ядра до `^1.5.0` — 6.1 зелёный
- [x] 6.3 `lib/src/llm/provider_config.dart` (вне `providers/`, design.md, D1): `ProviderConfig` (поля D3, значения по умолчанию от хоста `baseUrl`), `LlmTimeouts`, `ReasoningFormat`, `CoreLlmServices`; тест значений по умолчанию (`api.openai.com` → `promptCacheKey: true`, `openrouter.ai` → `reasoningFormat: openrouter`, `idleReasoning < idle` → `ArgumentError`)

## 7. Адаптер OpenAI-совместимого API (1.6)

- [x] 7.1 SSE-фикстуры `test/fixtures/sse/openai/*.sse`, написанные по публичной документации (design.md, D9): текст; вызов инструмента частями (пример §2.7); два перемешанных вызова; повтор кадра аргументов; новый id на индексе 0; вызов без id; `reasoning_content` и `reasoning`; usage в последнем чанке с `cached_tokens` и с `prompt_cache_hit_tokens`; `finish_reason: length`; `content_filter`; неизвестный `finish_reason`; конец тела без `finish_reason` с контентом и без; объект `error` в чанке
- [x] 7.2 Тест (agent-llm «Адаптер OpenAI-совместимого API», «Контракт StreamFunction»): `test/llm/openai_compatible_test.dart` на `MockClient` — события и итог каждой фикстуры, `cancel mid-stream yields ErrorEvent(aborted) and closes the request` (LLM-7, LLM-10), исключение в разборе → `ErrorEvent` (LLM-1), 429 с `Retry-After`, 200 без SSE, редирект same-origin проходит, на чужой хост — `badRequest`; тело запроса: преобразование транскрипта по §2.7 (картинки и плейсхолдер, результаты с картинками, канонический JSON аргументов), без `tools` при пустом списке (красный)
- [x] 7.3 Тест (agent-llm «Кэш промпта», «Параметр уровня рассуждения»): `test/llm/openai_request_test.dart` — `prompt_cache_key` только при флаге (LLM-12), `cached_tokens`/`cache_write_tokens` → `cacheRead`/`cacheWrite` и `input` без них; `reasoning_effort` и `reasoning.effort` по `reasoningFormat`, модель без `supportsReasoning` — без полей (LLM-15); два одинаковых снимка дают побайтово одинаковое тело (LLM-11) (красный)
- [x] 7.4 Реализовать `lib/src/llm/providers/openai_compatible.dart` — 7.2 и 7.3 зелёные

## 8. Адаптер Anthropic и ручной smoke (1.7, 1.10)

- [x] 8.1 SSE-фикстуры `test/fixtures/sse/anthropic/*.sse` по публичной документации: текст; `thinking` с `signature_delta`; `redacted_thinking`; `tool_use` с `input_json_delta`; `max_tokens`; `refusal`; `model_context_window_exceeded`; событие `error` с `overloaded_error`; `ping` и неизвестное событие; usage `cache_read_input_tokens`/`cache_creation_input_tokens`
- [x] 8.2 Тест (agent-llm «Адаптер Anthropic Messages API», «Кэш промпта», «Параметр уровня рассуждения»): `test/llm/anthropic_test.dart` на `MockClient` — события и итог каждой фикстуры; тело запроса: слияние ролей, серия результатов в одном `user`, нормализация id (`tool_use.id` = `tool_result.tool_use_id`), пустые тексты опущены, подписи только своему API, чужие и неподписанные рассуждения отброшены; ровно три метки `cache_control`, `system` и `tools` побайтово одинаковы в трёх запросах растущего транскрипта (LLM-11); `thinking.budget_tokens` по уровню и `min(B, max_tokens − 1024)`, `B < 1024` — без `thinking`; отмена посреди ответа (красный)
- [x] 8.3 Реализовать `lib/src/llm/providers/anthropic.dart` — 8.2 зелёный
- [x] 8.4 `tool/llm_smoke.dart` (1.10) — один запрос к реальному провайдеру через адаптер по `CODELAB_SMOKE_PROVIDER` (`openai-compatible` | `anthropic`), `CODELAB_SMOKE_BASE_URL`, `CODELAB_SMOKE_MODEL` и ключу из `CODELAB_SMOKE_API_KEY`; печатает события и usage; в CI не запускается; описание запуска — в `packages/dart/codelab_agent_core/AGENTS.md`
- [x] 8.5 Проверка итерации 2: `fvm dart run melos run check` зелёный; PR итерации 2. `tool/llm_smoke.dart` прогнан на OpenRouter (OpenAI-совместимый адаптер): `openai/gpt-4.1-mini` — вызов инструмента фрагментами, `toolUse`, usage; `anthropic/claude-sonnet-4.5` с `reasoning.effort: low` — `thinking` из `delta.reasoning`, затем текст и вызов, `reasoning_tokens`; расхождений с фикстурами нет. LM Studio и прямой Anthropic — в задаче 13.6

## 9. Сторожевые таймеры (1.8)

- [x] 9.1 Тест (agent-llm «Сторожевые таймеры стрима»): `test/llm/watchdog_test.dart` на `FakeClock` — нет заголовков 30 с → `timeout` с текстом `connect_stall…`; тишина 120 с после события → `timeout`; пользовательская отмена остаётся `aborted`; watchdog не отменяет родительский токен; `core/thinking-resets-idle-timeout` — дельты рассуждения каждые 100 с 400 с, только `ping` → `timeout` через 120 с, `hiddenReasoning` 500 с — нет `timeout`, 600 с — `timeout` с текстом про hidden reasoning, после первого блока 121 с — `timeout` по `idle` (LLM-16) (красный)
- [x] 9.2 Реализовать `lib/src/llm/decorators/watchdog.dart` — 9.1 зелёный

## 10. Повтор и fallback (1.8)

- [x] 10.1 Тест (agent-llm «Повтор только до видимого вывода»): `test/llm/decorators_test.dart` на scripted внутренней функции и `FakeClock` — `network error before first block is retried, after first block is surfaced` (LLM-8); задержки в пределах формулы equal jitter с `Random(42)`; `content_filter`, 401, overflow, aborted не повторяются (LLM-9); отдельный бюджет 429 и `Retry-After`; `Retry-After: 200` при `maxRetryAfter` 120 с — без ожидания; `StartEvent` наружу ровно один раз; история попыток в итоговой ошибке; usage попыток суммируется; лог `llm.retry`; отмена во время задержки (красный)
- [x] 10.2 Реализовать `lib/src/llm/decorators/retry.dart` (`RetryPolicy`, `withTransientRetry`) — 10.1 зелёный
- [x] 10.3 Тест (agent-llm «Резервная модель»): `test/llm/fallback_test.dart` — 429 до вывода → `FallbackNotice` и ответ модели B с `ModelRef` B; ошибка после вывода не переключает; `aborted`, `overflow`, `badRequest`, `terminalFinish` не переключают; цепочка из одной модели прозрачна; usage моделей суммируется (красный)
- [x] 10.4 Реализовать `lib/src/llm/decorators/fallback.dart` — 10.3 зелёный

## 11. Переполнение и стоимость (1.8)

- [x] 11.1 Тест (agent-llm «Переполнение контекста», «Usage и стоимость»): `test/llm/overflow_detection_test.dart` — каждая фраза §2.11; фраза + признак rate limit → не overflow; тихое переполнение; `length` с нулевым output; `test/llm/cost_test.dart` — формула, неизвестные цены → 0, стоимость считается и в `fail` (красные)
- [x] 11.2 Реализовать `lib/src/llm/overflow.dart`, `calculateCost` в `usage.dart`, применение правил 2–4 §2.11 в `ProviderStreamState` — 11.1 зелёные

## 12. Каталог моделей без сети (1.12)

- [x] 12.1 Тест (agent-llm «Статический каталог моделей»): `test/llm/static_model_catalog_test.dart` — порядок моделей конфига, дубликаты отброшены; `resolve` по источникам «конфиг → встроенный → безопасные» для каждого поля; префиксный поиск встроенного каталога; `min(maxOutputTokens, contextWindow − 1024)`, не меньше 256; `unknown model resolves to safe defaults with one warning`; модель вне списка → `null`; `refresh()` ничего не делает; `test/llm/builtin_models_test.dart` — каждая запись: окно > 0, лимит ответа < окна (красные)
- [x] 12.2 Реализовать `lib/src/llm/model_catalog.dart` (`ModelId`, `ModelInfo`, `ModelInfoSource`, `ModelEntry`, `ModelCatalog`, `StaticModelCatalog`) и `lib/src/llm/builtin_models.dart` с источником значений в комментарии (design.md, D10) — 12.1 зелёные

## 13. Фабрика и завершение (1.9)

- [x] 13.1 Тест (agent-llm «Фабрика и закрытые адаптеры»): `test/llm/provider_factory_test.dart` — цепочка `адаптер → watchdogs → retry → fallback` (сбой до вывода, затем успех: один `StartEvent`, одна запись `llm.retry`); выбор адаптера по `ProviderApi`; `test/public_api_test.dart` — барель не экспортирует `src/llm/providers/` (PKG-5) (красные)
- [x] 13.2 Реализовать `lib/src/llm/provider_factory.dart` (`createStreamFunction`, вне `providers/` — design.md, D1; design.md, D4) и экспорт `ProviderConfig`, `CoreLlmServices`, `createStreamFunction`, декораторов и каталога из бареля — 13.1 зелёные
- [x] 13.3 `tool/llm_smoke.dart` переходит на `createStreamFunction` — запрос идёт через всю цепочку декораторов
- [x] 13.4 Документ ядра §2.7: эскиз `ProviderConfig` дополнен полями `timeouts` и `retry` (design.md, D3)
- [x] 13.5 Definition of Done `09-06`: `fvm dart test packages/dart/codelab_agent_core/test/llm packages/dart/codelab_agent_core/test/cancel packages/dart/codelab_agent_core/test/testing packages/dart/codelab_agent_core/test/util` зелёный; `melos run guard` и `melos run web-compile` зелёные; `fvm dart run melos run check` зелёный; PR итерации 3
- [ ] 13.6 Перед архивированием: `tool/llm_smoke.dart` прогнан на OpenAI-совместимом сервере (LM Studio: Qwen3 и Gemma 4 — разные шаблоны чата) и, при наличии ключа, на Anthropic; расхождения с фикстурами исправлены со ссылкой на документацию провайдера; `openspec validate add-agent-core-llm-contract --strict`; архивировать change после слияния последней итерации (§9.0, правило 6)

## 14. Адаптивное рассуждение Anthropic (design.md D12)

- [x] 14.1 Тест (agent-llm «Параметр уровня рассуждения», «Статический каталог моделей»): `anthropic_test.dart` — `thinkingMode: adaptive` даёт `thinking: {"type": "adaptive", "display": "summarized"}` и `output_config.effort` по уровню без `budget_tokens`, без уровня или без `supportsReasoning` — ни `thinking`, ни `output_config`, режим `budget` без `output_config`; `static_model_catalog_test.dart` — `thinkingMode` из встроенной таблицы, явное значение конфига выигрывает, безопасное значение `adaptive`; `builtin_models_test.dart` — у моделей Claude 5.x `adaptive` (красный)
- [x] 14.2 Реализовать `ThinkingMode` в `model_ref.dart`, поле в `ModelInfo` и разрешение в `StaticModelCatalog`, форму тела в `providers/anthropic.dart`, пометки во встроенной таблице; `CODELAB_SMOKE_THINKING` в `tool/llm_smoke.dart`; документы §2.8, §2.12.2, §2.12.3, §15.4 — 14.1 зелёный, `fvm dart run melos run check` зелёный
