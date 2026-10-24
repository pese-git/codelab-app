## Why

Этап 0 закрыт: в монорепозитории есть пустой каркас `codelab_agent_core`, сторож границ, CI и корпус golden-фикстур ACP. Этап 1 (`docs/architecture/proposals/dart-agent-and-clients/09-06-stage-1-llm.md`, веха M1 в `delivery-roadmap.md`) строит слой между будущим циклом агента и моделью. Без него этап 2 (цикл, инструменты, разрешения) не начинается, а цели паритета L-01, L-02, L-04…L-07, L-11, L-13, L-14, L-16, L-31 (`agent-parity-goals.md`) не закрываются. Источник решений — принятый документ ядра (`agent-core-architecture.md`, §1.3, §1.5, §2, §3, §12.3, §14.7; ADR-0001).

## What Changes

- **Отмена (1.1).** `CancelToken`, `CancelTokenSource` с иерархией родитель → потомок, `raceCancel`, `delayCancellable`, причины `UserCancel`, `WatchdogFired`, `ShutdownCancel` (§3, CAN-1…CAN-3).
- **Модель сообщений (1.2).** `ContentBlock` (`TextContent`, `ThinkingContent`, `ToolCall`, `ImageContent`), `Message` (`UserMessage`, `AssistantMessage`, `ToolResultMessage`), `StopReason`, `LlmErrorClass`, `Usage`/`UsageCost`, `ModelRef`/`ModelCost`, `ReasoningEffort`, `ToolSchema`, `LlmContext`. Каноническая JSON-форма — будущий формат журнала (§2.2).
- **События и поток (1.3).** Закрытая иерархия `AssistantMessageEvent` с грамматикой «один терминал последним», `EventStream`/`AssistantMessageEventStream` (`result` всегда завершается), `typedef StreamFunction`, ленивые снимки `partial` без квадратичной стоимости (§2.3–§2.5, LLM-1…LLM-6).
- **`ScriptedStreamFunction` (1.4)** — детерминированная модель для всех следующих тестов: формат блока `llm` фикстуры (§14.7), шаги строго по порядку, `expect` как утверждение с diff запроса, подстановка `${cwd}`/`${sessionId}`. Экспорт только через `package:codelab_agent_core/testing.dart`.
- **SSE-декодер (1.5)** по правилам §2.6.
- **Адаптеры (1.6, 1.7)** OpenAI-совместимого API (OpenAI, OpenRouter, Ollama, LM Studio, любой `baseUrl`) и Anthropic Messages с рассуждениями. Оба: преобразование транскрипта в payload, разбор потока, классификация ошибок (§2.9), отмена до HTTP-запроса, ручные редиректы только same-origin. Кроме того, метки кэша промпта и `prompt_cache_key` (§2.12.1) и параметр уровня рассуждения (§2.12.3). SSE-фикстуры адаптеров пишутся вручную по публичной документации API.
- **Декораторы (1.8)** `withWatchdogs` (включая долгое закрытое рассуждение, §2.10.5), `withTransientRetry` (повтор только до видимого вывода, отдельный бюджет 429, `Retry-After`), `withFallback`; учёт стоимости и признак переполнения контекста (§2.10–§2.12).
- **Фабрика (1.9)** `createStreamFunction(ProviderConfig, CoreLlmServices)` — хост получает уже обёрнутую функцию, классы адаптеров наружу не экспортируются (PKG-5).
- **Ручной smoke (1.10)** `tool/llm_smoke.dart` — один запрос к реальному провайдеру по ключу из env; в CI не запускается.
- **Порты детерминизма (1.11)** `Clock`, `IdGenerator`, `Logger`/`LogLevel`/`LogRecord` и тестовые `FakeClock`, `SequentialIdGenerator` (PKG-6, §12.3).
- **Каталог моделей без сети (1.12)** — порт `ModelCatalog`, `StaticModelCatalog` (конфиг или флаги → встроенный каталог → безопасные значения), встроенная таблица моделей (§2.12.2).
- **Web-smoke ядра** выполняет один шаг на `ScriptedStreamFunction` вместо печати имени пакета.

Не входит:
- другие провайдеры (Gemini и прочие — §17.10);
- продолжение (resume) прерванного стрима;
- endpoint `/models`, удалённый каталог метаданных, кэш каталога на диске и фоновое `refresh()` (этап 8, L-15);
- цепочка резервных моделей из конфига и `ModelRoleResolver` (этап 8, L-08) — декоратор `withFallback` делается сейчас, фабрика этапа 1 строит цепочку из одной модели или из списка, переданного хостом;
- загрузка конфигурации (§15) — хост сам передаёт `ProviderConfig`;
- полный редактор секретов (§12.4);
- всё, что после MVP (`withCredentials`, `withPromptTools`, кварки провайдеров, `RateLimitInfo`, `StallClass`).

## Capabilities

### New Capabilities
- `agent-cancellation`: кооперативная отмена ядра агента — токены, иерархия, гонка с отменой, отменяемая задержка.
- `agent-core-ports`: порты детерминизма и логирования ядра (`Clock`, `IdGenerator`, `Logger`) и их тестовые реализации.
- `agent-llm`: LLM-контракт ядра — модель сообщений и событий, `StreamFunction`, SSE, адаптеры OpenAI-совместимый и Anthropic, классификация ошибок, декораторы устойчивости, usage и стоимость, кэш промпта, переполнение контекста, уровень рассуждения, статический каталог моделей, фабрика и `ScriptedStreamFunction`.

### Modified Capabilities
- `workspace-architecture`: «Границы пакетов monorepo» — web-smoke ядра не только компилируется, но и выполняет шаг на `ScriptedStreamFunction`.

## Impact

- `packages/dart/codelab_agent_core`:
  - `lib/src/cancel/`, `lib/src/util/`, `lib/src/llm/` (вместе с `decorators/`, `providers/`), `lib/src/testing/`;
  - новый `lib/testing.dart`, расширенный барель `lib/codelab_agent_core.dart`;
  - `test/` с SSE-фикстурами `test/fixtures/sse/`, `tool/llm_smoke.dart`, `test/web_smoke/main.dart`.
- **Зависимости ядра.** Новых нет: `http`, `async`, `collection`, `meta` уже в allowlist PKG-2; `package:http/testing.dart` используется только тестами. Сторож и allowlist не меняются.
- **Документы.** `AGENTS.md` пакета ядра и `docs/architecture/` правятся только там, где реализация уточняет контракт (design.md).
- Клиенты, ACP-контракты и поведение `codelab_app` не меняются.
