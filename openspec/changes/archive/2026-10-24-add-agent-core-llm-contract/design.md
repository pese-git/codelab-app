## Context

Источник решений — принятые документы (ADR-0001, Status: Accepted):

- `docs/architecture/proposals/agent-core/`:
  - `01-layers-and-packages.md` — раскладка §1.3, PKG-5, PKG-6;
  - `02-llm-contract.md` — весь;
  - `03-cancellation.md`;
  - `12-observability-and-errors.md` — §12.2, §12.3;
  - `14-golden-fixtures.md` — §14.7;
  - `15-configuration.md` — §15.4, ключи провайдера;
- `docs/architecture/proposals/dart-agent-and-clients/09-06-stage-1-llm.md` — задачи 1.1–1.12 и Definition of Done;
- `docs/architecture/proposals/agent-parity-goals.md` — цели L-01, L-02, L-04…L-07, L-11, L-13, L-14, L-16, L-31 (этап 1);
- `packages/dart/codelab_agent_core/AGENTS.md` — PKG-1…PKG-6, TDD, критерии завершённой итерации.

**Текущее состояние.** `codelab_agent_core` — пустой каркас: барель с именем пакета, `test/web_smoke/main.dart`. Сторож импортов (PKG-1) и allowlist зависимостей (PKG-2: `http`, `meta`, `collection`, `async`, `crypto`) уже работают в CI. В корпусе golden-фикстур (`acp_testing/fixtures/acp/`) у фикстур с ролью `agent` есть блок `llm` — сценарий для `ScriptedStreamFunction`.

## Goals / Non-Goals

**Goals:**

- контракт `StreamFunction`, на котором этап 2 строит цикл агента, а этап 4 — ACP-адаптер и `--llm-script`;
- два адаптера провайдеров с поведением, закреплённым тестами на записанных вручную SSE-фикстурах;
- декораторы устойчивости с тест-матрицей на `FakeClock`, без реального времени;
- детерминированная модель `ScriptedStreamFunction` на формате блока `llm` фикстур;
- ядро остаётся web-безопасным, и web-smoke это проверяет исполнением, а не только компиляцией.

**Non-Goals:**

- Gemini и прочие провайдеры, кварки совместимости, пул ключей, OAuth (§17.10);
- resume прерванного стрима;
- сетевой каталог моделей: `/models`, удалённые метаданные, кэш на диске, фоновое `refresh()` (этап 8);
- цепочка резервных моделей из конфига и роли моделей (этап 8);
- загрузка и валидация конфигурации (§15) — хост передаёт `ProviderConfig` готовым;
- полный редактор секретов (§12.4);
- опция сессии `effort` и её хранение (этап 4) — здесь только отображение `ModelRef.reasoningEffort` в тело запроса.

## Decisions

### D1. Раскладка и точки входа

Файлы — по §1.3:

- `lib/src/cancel/cancel_token.dart`;
- `lib/src/util/` — `clock.dart`, `ids.dart`, `logger.dart` (канонический JSON payload — `jsonEncode` с порядком вставки ключей, §2.7 шаг 5: отдельный модуль не нужен);
- `lib/src/llm/` — `messages.dart`, `model_ref.dart`, `events.dart`, `event_stream.dart`, `stream_function.dart`, `errors.dart`, `sse.dart`, `stream_state.dart`, `usage.dart`, `overflow.dart`, `model_catalog.dart`, `builtin_models.dart`;
- `lib/src/llm/decorators/` и `lib/src/llm/providers/` (адаптеры и HTTP-слой `http_support.dart`);
- `lib/src/llm/provider_config.dart` и `lib/src/llm/provider_factory.dart` — вне `providers/`: барель экспортирует `ProviderConfig` и `createStreamFunction`, а проверка PKG-5 запрещает в бареле любой `export 'src/llm/providers/` (§1.7). Раскладка §1.3, где фабрика лежит в `providers/`, уточняется здесь;
- `lib/src/testing/`.

Основной барель `lib/codelab_agent_core.dart` экспортирует:

- модель сообщений, события, `StreamFunction` и `LlmContext`;
- `CancelToken` и связанные типы;
- порты `Clock`, `IdGenerator`, `Logger`;
- `ModelCatalog`, `StaticModelCatalog`;
- `ProviderConfig`, `CoreLlmServices`, `createStreamFunction`;
- декораторы — они нужны хостам и тестам: `withFallback` строит цепочку из `ModelRoleResolver` на этапе 8.

`lib/src/llm/providers/*` барель не экспортирует (PKG-5). `lib/testing.dart` экспортирует `ScriptedStreamFunction`, `FakeClock`, `SequentialIdGenerator` и `RecordingLogger` — последний нужен тестам, которые проверяют события лога.

### D2. Модели — вручную, без генерации кода

Allowlist PKG-2 не содержит `freezed` и `json_serializable`. Поэтому типы ядра — `final`/`sealed` классы с ручными `toJson`/`fromJson`, `==` и `hashCode`. Равенство нужно тестам сериализации; `collection` даёт сравнение списков и отображений. Списки внутри — `List.unmodifiable`.

JSON сообщения ассистента хранит только `{provider, id}` модели (§2.2). Поэтому `Message.fromJson` принимает функцию `ModelResolver(provider, id) → ModelRef`: журнал этапа 3 передаёт в неё каталог моделей, тесты — фиксированную модель.

Альтернатива — расширить allowlist генераторами кода. Отклонено: каждая сборка ядра (CI, web, бинарь агента) получила бы шаг `build_runner`, а моделей мало, и они стабильны.

### D3. `ProviderConfig` этапа 1

Поля §2.7, кроме тех, что появляются после MVP:

- остаются: `name`, `api`, `baseUrl`, `apiKey`, `authHeader`, `headers`, `maxTokensField`, `includeUsage`, `reasoningFormat`, `systemRole`, `anthropicVersion`, `anthropicBeta`, `promptCacheKey`, `listModels` (поле есть, но читается только каталогом этапа 8);
- после MVP: `quirks`, `credentials`.

Вычисляемые значения по умолчанию — функции от `baseUrl`, а не константы:

- `promptCacheKey` — `true` для хоста `api.openai.com`;
- `reasoningFormat` — `openrouter` для хоста `openrouter.ai`.

Тогда конфиг этапа 8 только переопределяет их.

**Таймауты и бюджеты повторов.** §2.7 не показывает их в `ProviderConfig`, но §2.10.1 и §15.4 задают их на провайдера (`connect_timeout`, `idle_timeout`, `idle_timeout_reasoning`, `transient_retries`, `rate_limit_retries`). Поэтому `ProviderConfig` получает поля `timeouts` (`LlmTimeouts`: `connect` 30 с, `idle` 120 с, `idleReasoning` 600 с) и `retry` (`RetryPolicy` §2.10). Фабрика передаёт их декораторам. `idleReasoning < idle` — `ArgumentError` при создании `LlmTimeouts`: §15.5 называет это ошибкой конфигурации. Документ ядра §2.7 правится в этом change: в эскиз `ProviderConfig` добавляются оба поля.

Альтернатива — отдельные параметры `createStreamFunction`. Отклонено: значения принадлежат провайдеру, и с ролями этапа 8 их всё равно придётся сводить в одном месте.

### D4. Фабрика этапа 1 строит цепочку одной модели

`createStreamFunction(config, services)` собирает: адаптер → `withWatchdogs` → `withTransientRetry` → `withFallback([model])`. Цепочка из одной модели делает `withFallback` прозрачным (§2.10.3). Декоратор полностью реализуется и тестируется отдельно. Цепочку из нескольких моделей, в том числе разных провайдеров, собирает `ModelRoleResolver` этапа 8. `CoreLlmServices` — `http.Client`, `Clock`, `Random`, `Logger`.

Уточнение итерации 3: фабрика отдаёт функцию для любой модели, поэтому `withFallback([model], …)` строится на каждый вызов из запрошенной модели; цепочка из одной модели прозрачна (§2.10.3). Api без адаптера (`gemini`) отвечает `ErrorEvent(badRequest)`, а не исключением.

### D5. Отмена HTTP-запроса

`package:http` 1.5+ даёт `AbortableRequest` с `abortTrigger`. Адаптер отправляет `AbortableRequest(abortTrigger: cancel.onCancel)` и отменяет подписку на тело при отмене (§2.8, общие правила). Так соединение закрывается и на клиенте хоста `IOClient`, и в браузере. Ограничение зависимости ядра поднимается с `http: ^1.2.0` до `^1.5.0`. Пакет остаётся в allowlist, так что OpenSpec-расширения PKG-2 не нужно. В lock-файле уже 1.6.0.

Кроме `abortTrigger`, `client.send` гоняется с токеном (`raceCancel`): отмена даёт `aborted` в пределах одного цикла событий и с клиентом, который `abortTrigger` не поддерживает, а поздний ответ сливается (`drain`), чтобы освободить соединение.

`MockClient` из `package:http/testing.dart` прерывание запроса не моделирует. Поэтому тест отмены проверяет наблюдаемое: `ErrorEvent(aborted)` до следующего события, отменённую подписку на тело (поток ответа из `StreamController`, у которого видно `onCancel`) и завершённый `abortTrigger`.

### D6. `Clock` и таймеры

Контракт порта:

```dart
abstract interface class Clock {
  DateTime now();
  Future<void> delay(Duration d, {CancelToken? cancel});
  ClockTimer timer(Duration d, void Function() onFire);
}
```

- `ClockTimer.cancel()` останавливает таймер;
- `delayCancellable(clock, d, cancel)` из §3.2 — тонкая обёртка над `clock.delay`;
- `SystemClock` реализует порт на `Timer` из `dart:async`;
- `FakeClock.advance(d)` двигает время вручную и срабатывает таймерами по порядку их сроков, сам по себе не двигается.

Watchdogs, повторы с джиттером, `Retry-After` с HTTP-date и `delayMs` сценария работают только через порт. Поэтому вся тест-матрица §2.15 идёт без реального ожидания.

### D7. Редакция секретов в ошибках провайдера на этапе 1

§2.9 требует, чтобы тело ошибки проходило редакцию секретов §12.4. Полный `Redactor` со слоями (§12.4.1) в этот change не входит. На этапе 1 адаптер:

- заменяет в `errorMessage` точное значение `ProviderConfig.apiKey` и значения заголовков `ProviderConfig.headers` на `[REDACTED]`;
- обрезает тело до 2000 символов.

Тело ошибки целиком в лог не пишется. Когда появится `Redactor`, он встанет в ту же точку — `describeHttpError`. Контракт для потребителей (`errorMessage` без ключа) не меняется.

### D8. `ScriptedStreamFunction` не бросает: провал — через `verify()`

Функция модели обязана никогда не бросать (LLM-1), а §14.7 требует, чтобы несовпадение `expect` в тесте было провалом с diff. Поэтому:

- несовпадение `expect` и лишний запрос дают `ErrorEvent` класса `badRequest` с текстом расхождения — так их видит бинарь `--llm-script` (§14.7);
- одновременно расхождение записывается в сценарий;
- `verify()` бросает `ScriptedLlmFailure` со всеми расхождениями: diff ожидаемого и фактического запроса, лишние запросы, неиспользованные шаги.

Тесты ядра и агентский драйвер фикстур (этап 4) вызывают `verify()` в конце. Сценарий читается из JSON блока `llm` (`ScriptedStreamFunction.fromJson`). Ядро не зависит от `acp_testing`, поэтому разбор свой. Он падает `FormatException` на неизвестном ключе шага: загрузчик фикстур проверяет тот же формат, а свой разбор нужен бинарю.

### D9. SSE-фикстуры адаптеров

Фикстуры `test/fixtures/sse/openai/*.sse` и `test/fixtures/sse/anthropic/*.sse` пишутся вручную по публичной документации форматов потоков (OpenAI Chat Completions streaming, Anthropic Messages streaming): формат провода — факт интерфейса, а не чужой код. Файлы с примерами из других проектов не копируются (`AGENTS.md` §5, `07-decision-sources.md` §7а). В файле фикстуры нет ключей и реальных идентификаторов. Тест подаёт фикстуру `MockClient` целиком, по одному символу и случайными кусками.

### D9a. Каталог моделей этапа 1

- `ModelCatalog.resolve(id, {ReasoningEffort? effort})`: вместо `ModelRole` (роли моделей — после MVP, L-10) метод принимает эффективный уровень рассуждения сессии — он нужен шагу `reasoningEffort := supportsReasoning ? effort : null` (§2.12.2). Параметр роли добавится вместе с ролями, без изменения существующих вызовов.
- Источники: явные значения конфига (`CatalogProvider.models`) → встроенная таблица → безопасные значения. Имя модели — `displayName` конфига, иначе id модели (§2.12.2, шаг 4; встроенная таблица имени не даёт).
- Предупреждение `llm.catalog.default_used` не считает неизвестные цены: у локальной модели их нет, и предупреждение на каждой такой модели было бы шумом.

### D10. Встроенный каталог моделей

`builtin_models.dart` — таблица `id → ModelInfo` для моделей, которые MVP использует по умолчанию (OpenAI, Anthropic). Значения окна, лимита ответа и цен берутся из публичных страниц провайдеров. Источник указывается в комментарии рядом с таблицей с датой сверки. Это факты о продуктах, а не воспроизведённый чужой код, поэтому запись в `THIRD_PARTY_NOTICES.md` не нужна. Таблица меняется обычным изменением кода с тестом `builtin_models_test.dart`.

### D11. Итерации и TDD

Change делится на три итерации, каждая — отдельный PR в `develop` (§9.0, правила 3 и 8):

1. **Фундамент контракта:** порты, отмена, модель сообщений, события и поток, `ScriptedStreamFunction`, web-smoke с шагом модели. После неё этап 2 может начинать цикл на scripted-модели.
2. **Провода:** SSE-декодер, классификация ошибок, адаптеры OpenAI-совместимый и Anthropic с кэшем промпта и уровнем рассуждения, отмена HTTP.
3. **Устойчивость и сборка:** watchdogs, повтор, fallback, переполнение, стоимость, статический каталог, фабрика, ручной smoke.

Задачи в `tasks.md` идут парами «тест → реализация»; красный тест виден в истории коммитов до кода.

### D12. Форма рассуждения Anthropic: `thinkingMode`

Модели Claude 4.6 и новее принимают `thinking: {"type": "adaptive"}` с уровнем в `output_config.effort`, а Claude 5.x отвечают на `{"type": "enabled", "budget_tokens": B}` ошибкой 400; Claude 4.5 и старше знают только бюджет. Источник — документация Anthropic по adaptive thinking (https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking), сверено 2026-10-23.

- В `ModelRef` и `ModelInfo` добавляется `thinkingMode: adaptive | budget`, он разрешается каталогом в том же порядке источников, что и остальные поля; ключ конфига — `providers.<id>.models.<m>.thinking_mode` (§15.4). Встроенные модели Claude 5.x помечены `adaptive`.
- Безопасное значение — `adaptive`: его принимают все текущие модели, а старые модели с бюджетом задаются явно. Значение по умолчанию не даёт предупреждения `llm.catalog.default_used`: это выбор диалекта, а не неизвестный лимит, и для не-Anthropic провайдеров оно не используется.
- `adaptive` при `reasoningEffort != null`: `thinking: {"type": "adaptive", "display": "summarized"}` и `output_config: {"effort": <уровень>}`. `summarized` — потому что умолчание API `omitted` отдаёт блоки рассуждения с пустым текстом: клиент видел бы долгую паузу вместо мыслей агента. При `reasoningEffort == null` ни `thinking`, ни `output_config` не отправляются (LLM-15).
- Отклонено: выбор формы по префиксу id модели в адаптере — ломается на алиасах и id прокси; отдельный флаг в `ProviderConfig` — модели одного провайдера различаются.

## Risks / Trade-offs

- **[Совместимые серверы отличаются от OpenAI в мелочах]** → фикстура на каждый известный вариант (`reasoning_content` и `reasoning`, `prompt_cache_hit_tokens`, повтор кадра аргументов, индекс 0 для последовательных вызовов); кварки — после MVP.
- **[Фикстуры, написанные по документации, расходятся с реальным потоком]** → ручной `tool/llm_smoke.dart` на реальном провайдере перед архивированием change (задача 13.6); расхождение исправляет фикстуру со ссылкой на документацию провайдера.
- **[`MockClient` не моделирует прерывание соединения]** → тест проверяет сработавший `abortTrigger` и отменённую подписку на тело (D5); реальное закрытие соединения видно в ручном smoke.
- **[Ручные модели без генерации кода — больше рутинного кода]** → тест сериализации на каждую форму §2.2 и тест равенства; моделей немного.
- **[Значения встроенного каталога устаревают]** → безопасные значения по умолчанию и предупреждение `llm.catalog.default_used`; сетевой каталог этапа 8 перекрывает встроенные данные.

- **[Новые модели Anthropic (Claude 5.x) используют адаптивное рассуждение]** → снят решением D12: документация Anthropic подтверждает, что Fable 5.1, Opus 5.5, Sonnet 5.5 и Haiku 5.5 отвечают на `budget_tokens` ошибкой 400. Прямой smoke Anthropic в задаче 13.6 не прогонялся (нет ключа); форма на реальном API подтверждается первым прогоном `tool/llm_smoke.dart` с ключом.
- **[Привязка блоков рассуждения Claude 5.x к префиксу разговора]** (preserved thinking: подпись блока фиксирует `system`, набор `tools` и предыдущие сообщения) → транскрипт ядра только дописывается, а `system` и `tools` побайтово стабильны (LLM-11). Перенос метки `cache_control` на последний `user`-блок меняет разметку, а не содержимое; что API её не учитывает, проверит многоходовый smoke Anthropic — в задаче 13.6 он не прогонялся (нет ключа) и остаётся открытым риском.
- **[Документация OpenAI называет для последних моделей (GPT-6.x) Responses API]**, а адаптер ходит в `chat/completions` (§2.7). Smoke на OpenRouter прошёл, прямой вызов OpenAI с моделями GPT-6.x не проверен; если они недоступны через Chat Completions, адаптер Responses API — отдельный change (после MVP, рядом с §17.10).

## Migration Plan

Только новый код ядра и тесты; поведение клиентов не меняется. Откат — revert pull request итерации.

## Open Questions

- Нет.
