## ADDED Requirements

### Requirement: Модель сообщений и каноническая JSON-форма
Ядро SHALL описывать транскрипт неизменяемыми типами:
- `UserMessage` (блоки `TextContent`, `ImageContent`);
- `AssistantMessage` (блоки `TextContent`, `ThinkingContent`, `ToolCall`; `model`, `usage`, `stopReason`, `rawStopReason`, `errorMessage`, `errorClass`, `timestamp`);
- `ToolResultMessage` (`toolCallId`, `toolName`, блоки, `isError`).

`StopReason` SHALL принимать значения `stop`, `length`, `toolUse`, `error`, `aborted`. `LlmErrorClass` SHALL принимать значения `network`, `timeout`, `rateLimited`, `overflow`, `auth`, `badRequest`, `server`, `terminalFinish`, `aborted`, `unknown`.

Каждый тип SHALL иметь каноническую JSON-форму с дискриминатором (`type` у блока, `role` у сообщения) по таблице `agent-core-architecture` §2.2:
- поля со значением `null` при записи опускаются;
- отсутствующее поле при чтении равно `null` или значению по умолчанию;
- неизвестные поля при чтении игнорируются.

#### Scenario: Сообщения переживают сериализацию
- **WHEN** транскрипт из пользовательского сообщения с картинкой, ответа ассистента с рассуждением и подписью, вызова инструмента и результата инструмента сериализуется в JSON и читается обратно
- **THEN** прочитанный транскрипт равен исходному, а в JSON нет полей со значением `null`

#### Scenario: Неизвестное поле при чтении
- **WHEN** JSON сообщения содержит поле, которого нет в модели
- **THEN** сообщение читается без ошибки, поле игнорируется

#### Scenario: Списки неизменяемы
- **WHEN** код пытается изменить `content` прочитанного сообщения
- **THEN** операция бросает `UnsupportedError`

### Requirement: Контракт StreamFunction
`StreamFunction` — функция `(ModelRef, LlmContext, {CancelToken? cancel})` → `AssistantMessageEventStream`. Каждый адаптер и декоратор SHALL соблюдать контракт:
- поток возвращается синхронно;
- функция никогда не бросает — ни синхронно, ни через `result`; любой сбой становится `ErrorEvent` (LLM-1);
- работа начинается не раньше следующего microtask;
- в потоке ровно одно терминальное событие (`DoneEvent` или `ErrorEvent`), и оно последнее (LLM-2).

`EventStream.result` SHALL всегда завершаться: значением терминального события или `StateError`, если поток закрыт без терминала; без необработанной ошибки, даже если `result` никто не ждёт (LLM-3). События, отправленные до подписки, НЕ SHALL теряться. `push` после терминала SHALL игнорироваться.

#### Scenario: Поток закрыт без терминала
- **WHEN** производитель вызывает `end()` без терминального события
- **THEN** `result` завершается `StateError`, и обработчик необработанных ошибок зоны не вызывается

#### Scenario: События до подписки
- **WHEN** производитель отправляет `StartEvent` и `DoneEvent` до того, как потребитель подписался
- **THEN** потребитель получает оба события по порядку

#### Scenario: Исключение внутри разбора
- **WHEN** разбор чанка ответа провайдера бросает исключение
- **THEN** адаптер завершает поток `ErrorEvent`, а вызов и `result` не бросают

### Requirement: Грамматика событий и снимки
Поток SHALL подчиняться грамматике §2.3:
- первое событие — `StartEvent` или, при сбое до заголовков, `ErrorEvent`;
- блоки открываются `BlockStartEvent` с `index` и `BlockKind` (`text`, `thinking`, `toolCall`), дополняются `BlockDeltaEvent` и закрываются `BlockEndEvent` с тем же `index`;
- одновременно может быть открыто несколько блоков;
- перед `DoneEvent` все блоки закрыты (LLM-5).

Каждое событие SHALL нести неизменяемый снимок `partial` ответа на момент события (LLM-4). Построение снимка НЕ SHALL копировать накопленный ответ на каждую дельту. `ToolCall.arguments` в `BlockEndEvent` и `DoneEvent` SHALL быть разобранным JSON-объектом. Неразбираемые аргументы SHALL давать `{}` и пометку в `errorMessage`; частичный JSON наружу НЕ SHALL уходить (LLM-6).

#### Scenario: Парность блоков и один терминал
- **WHEN** адаптер разбирает ответ с текстом и двумя вызовами инструментов, фрагменты которых перемешаны
- **THEN** у каждого `BlockStartEvent` есть `BlockEndEvent` с тем же `index`, терминальное событие одно и последнее, `partial` каждого события содержит контент до этого события

#### Scenario: Неразбираемые аргументы
- **WHEN** аргументы вызова инструмента в ответе — незавершённый JSON
- **THEN** `BlockEndEvent` несёт `ToolCall` с `arguments: {}`, а итоговое сообщение — пометку в `errorMessage`

### Requirement: Декодирование SSE
`SseDecoder` SHALL превращать поток строк в `ServerSentEvent(event, data, id)` по правилам §2.6:
- разделители строк `\n`, `\r`, `\r\n`, в том числе `\r\n`, разрезанный границей чанка;
- BOM отбрасывается только в самом начале потока;
- строки-комментарии (`:`) игнорируются;
- срезается ровно один пробел после двоеточия;
- многострочный `data` склеивается через `\n`;
- `id` с `U+0000` отбрасывается;
- поле без двоеточия даёт пустое значение;
- незавершённое событие в конце потока отбрасывается.

#### Scenario: Нарезка не меняет результат
- **WHEN** один и тот же SSE-поток подаётся целиком, по одному символу и случайными кусками
- **THEN** декодер выдаёт одинаковую последовательность событий

#### Scenario: Пример §2.6
- **WHEN** на вход идут чанки `"﻿data: a\r"`, `"\ndata:b\n\n: ping\n"`, `"event: x\ndata: c\n\n"`
- **THEN** декодер выдаёт `ServerSentEvent(data: "a\nb")` и `ServerSentEvent(event: "x", data: "c")`

### Requirement: Адаптер OpenAI-совместимого API
Адаптер SHALL работать с любым сервером с `POST {baseUrl}/chat/completions` и SSE-стримингом (OpenAI, OpenRouter, Ollama, LM Studio, LiteLLM Proxy).

**Тело запроса** собирается по §2.7:
- системный промпт с ролью `systemRole`;
- текст пользователя строкой, картинки частями `image_url`, плейсхолдер для модели без картинок;
- вызовы ассистента в `tool_calls` с каноническим JSON аргументов;
- результаты как сообщения `tool`;
- `tools` и `tool_choice` — только при наличии инструментов;
- `stream_options.include_usage` и поле лимита ответа — по `ProviderConfig`.

**Разбор потока:**
- `reasoning_content`/`reasoning` — блок `thinking`, `content` — блок `text`;
- вызовы накапливаются по индексу и id. Повторно присланный кадр аргументов не удваивает JSON; новый id на занятом индексе открывает новый вызов; вызов без id получает `call_<n>`.

**Итог.** `finish_reason` отображается в итог по таблице §2.7; неизвестное значение — `ErrorEvent(unknown)` и лог `llm.finish_reason.unknown`. Usage считается с вычетом кэша из `input`.

#### Scenario: Вызов инструмента частями
- **WHEN** поток примера §2.7 (текст, вызов `read` в трёх фрагментах, `finish_reason: tool_calls`, usage в последнем чанке) разбирается адаптером
- **THEN** события идут как в примере: блок текста, блок вызова с аргументами `{"path": "a.txt"}`, `DoneEvent` со `stopReason: toolUse` и usage `input 388, cacheRead 512, output 40`

#### Scenario: Отказ фильтра
- **WHEN** поток завершается `finish_reason: content_filter`
- **THEN** поток завершается `ErrorEvent` с классом `terminalFinish` и текстом `Provider finish_reason: content_filter`

#### Scenario: Сервер вернул не поток
- **WHEN** ответ 200 пришёл с `Content-Type: text/html`
- **THEN** поток завершается `ErrorEvent` класса `badRequest` с подсказкой проверить `baseUrl`

### Requirement: Адаптер Anthropic Messages API
Адаптер SHALL отправлять `POST {baseUrl}/v1/messages` с заголовками `x-api-key`, `anthropic-version` и при необходимости `anthropic-beta`.

**Транскрипт преобразуется по §2.8:**
- подряд идущие сообщения одной роли сливаются;
- серия результатов инструментов становится одним `user`-сообщением с блоками `tool_result`;
- id вызовов нормализуются одной детерминированной функцией;
- пустые текстовые блоки опускаются;
- рассуждения другого диалекта или без подписи отбрасываются;
- подписи и `redacted_thinking` возвращаются только своему API.

**Разбор потока.** Именованные события (`message_start`, `content_block_*`, `message_delta`, `message_stop`, `ping`, `error`) разбираются по таблице §2.8:
- `signature_delta` меняет снимок без события;
- неизвестное событие игнорируется;
- `stop_reason` отображается в итог по таблице §2.8 (`model_context_window_exceeded` — `overflow`, `refusal` — `terminalFinish`).

#### Scenario: Рассуждение с подписью
- **WHEN** поток содержит блок `thinking` с `thinking_delta` и `signature_delta`, затем `tool_use`
- **THEN** итоговое сообщение содержит `ThinkingContent` с подписью и `api: anthropicMessages` и `ToolCall` с разобранными аргументами, а в следующем запросе этот блок уходит как `thinking` с той же подписью

#### Scenario: Перегрузка сервера
- **WHEN** поток содержит событие `error` с типом `overloaded_error`
- **THEN** поток завершается `ErrorEvent` класса `server`

### Requirement: Классификация ошибок провайдера
Класс ошибки SHALL ставиться один раз на границе адаптера по таблице §2.9. Декораторы SHALL решать о повторе и переключении только по `LlmErrorClass`, а не по тексту. Классы:
- сеть до ответа и обрыв тела — `network`;
- watchdog и HTTP 408 — `timeout`;
- HTTP 429 и `rate_limit_error` — `rateLimited`;
- 5xx (кроме 501 и 505), `overloaded_error`, `api_error` и неразбираемый JSON чанка — `server`;
- 400/404/405/413/415/422/501/505 и редирект на чужой origin — `badRequest`; при признаке переполнения — `overflow`;
- 401/403 — `auth`;
- `content_filter`/`refusal`/`safety` — `terminalFinish`;
- неизвестный finish reason — `unknown`;
- отмена — `aborted`.

`errorMessage` SHALL иметь вид `<provider> <status>: <message>`. Тело ошибки SHALL обрезаться до 2000 символов, а ключ API провайдера НЕ SHALL попадать в `errorMessage`.

#### Scenario: Таблица классов
- **WHEN** адаптер получает каждый статус и тип ошибки из таблицы §2.9
- **THEN** `ErrorEvent` несёт класс из таблицы

#### Scenario: Ключ не утекает в ошибку
- **WHEN** сервер отвечает 401 и повторяет в теле ошибки присланный ключ API
- **THEN** `errorMessage` не содержит значения ключа

### Requirement: Отмена доходит до HTTP-запроса
Ядро НЕ SHALL создавать `http.Client`: все запросы SHALL идти через клиент хоста из `CoreLlmServices` (LLM-10). Отмена через `CancelToken` SHALL давать `ErrorEvent` со `stopReason: aborted` и `errorClass: aborted` в пределах одного цикла событий после отмены, отменять подписку на тело ответа и закрывать запрос (LLM-7). Редиректы SHALL обрабатываться вручную: только same-origin (схема, хост и порт совпадают) и не больше пяти; иначе — `badRequest` `redirect to another origin is not allowed`.

#### Scenario: Отмена посреди ответа
- **WHEN** во время стрима ответа `MockClient` токен отменяют
- **THEN** поток завершается `ErrorEvent(aborted)` до следующего события провайдера, подписка на тело отменена, и запрос закрыт (`openai_compatible_test.dart: cancel mid-stream yields ErrorEvent(aborted) and closes the request`)

#### Scenario: Редирект на чужой хост
- **WHEN** сервер отвечает 307 с `Location` на другой хост
- **THEN** запрос к другому хосту не отправляется, поток завершается `ErrorEvent` класса `badRequest`

### Requirement: Сторожевые таймеры стрима
`withWatchdogs` SHALL давать каждой попытке дочерний токен отмены и следить за двумя таймерами:
- `connect` — от вызова до первого события; по умолчанию 30 с;
- `idle` — между событиями внутреннего потока; по умолчанию 120 с.

`idle` SHALL сбрасываться `StartEvent` и каждым событием блока любого вида, включая рассуждение, и только ими: keep-alive его НЕ SHALL сбрасывать. У модели с `hiddenReasoning` до первого контентного блока SHALL действовать `idleReasoning` (по умолчанию 600 с) (LLM-16).

Срабатывание SHALL отменять только попытку и переписывать её `aborted` в `ErrorEvent` класса `timeout` с текстом §2.10.1 или §2.10.5. Пользовательская отмена SHALL оставаться `aborted`.

#### Scenario: Нет заголовков
- **WHEN** ответ не приходит 30 с по `FakeClock`
- **THEN** поток завершается `ErrorEvent` класса `timeout` с текстом `connect_stall: no response headers within 30 s (connect watchdog)`

#### Scenario: Рассуждение не считается простоем
- **WHEN** модель шлёт дельты рассуждения каждые 100 с в течение 400 с при `idle` 120 с
- **THEN** `timeout` не наступает; а при одних `ping` каждые 30 с `timeout` наступает через 120 с после последнего события

#### Scenario: Закрытое рассуждение
- **WHEN** у модели с `hiddenReasoning` после `StartEvent` 500 с нет событий, затем приходит текст
- **THEN** запрос не прерывается; а при 600 с тишины поток завершается `timeout` с текстом про hidden reasoning

### Requirement: Повтор только до видимого вывода
`withTransientRetry` SHALL повторять попытку только до фиксации: первый `BlockStartEvent` или `DoneEvent`. `StartEvent` SHALL буферизоваться до фиксации и уходить наружу ровно один раз.

После фиксации ни один декоратор НЕ SHALL повторять запрос и НЕ SHALL переключать модель (LLM-8). Классы `aborted`, `overflow`, `auth`, `badRequest`, `terminalFinish` НЕ SHALL повторяться (LLM-9).

**Бюджеты:**
- `network`, `timeout`, `server`, `unknown` — `maxAttempts` (по умолчанию 4 попытки) с задержкой equal jitter §2.10.2;
- `rateLimited` — отдельный бюджет `rateLimitRetries`.

**`Retry-After`.** Значение берётся из `retry-after-ms` или `retry-after` (секунды или HTTP-date). Значение больше `maxRetryAfter` прекращает повторы. Задержка повтора SHALL прерываться отменой хода.

**Итог.** Итоговая ошибка SHALL содержать историю попыток. Usage неудачных попыток SHALL суммироваться в итог.

#### Scenario: Сбой до и после вывода
- **WHEN** первая попытка обрывается сетевой ошибкой до первого блока, вторая — после первого блока
- **THEN** первая повторяется, а ошибка второй уходит наружу без повтора (`decorators_test.dart: network error before first block is retried, after first block is surfaced`)

#### Scenario: Неповторяемые классы
- **WHEN** попытка завершается `content_filter`, 401, переполнением или отменой
- **THEN** повторной попытки нет

#### Scenario: Долгий Retry-After
- **WHEN** ответ 429 несёт `Retry-After: 200`, а `maxRetryAfter` — 120 с
- **THEN** декоратор не ждёт и сразу отдаёт итоговую ошибку `rateLimited`

### Requirement: Резервная модель
`withFallback(chain, forModel, onNotice)` SHALL пробовать модели цепочки по порядку. Цепочка из одной модели SHALL делать декоратор прозрачным.

Переход к следующей модели происходит при `ErrorEvent` до фиксации с классом `rateLimited`, `server`, `network`, `timeout`, `auth` или `unknown`, если следующая модель есть. Переход SHALL сообщаться `FallbackNotice(from, to, cause)` без дополнительной задержки. Классы `aborted`, `overflow`, `badRequest`, `terminalFinish` НЕ SHALL переключать модель. Ошибка после фиксации SHALL уходить потребителю как есть.

Итоговое сообщение SHALL нести `ModelRef` модели, которая ответила, и сумму usage всех моделей.

#### Scenario: 429 до вывода
- **WHEN** модель A отвечает 429 до вывода, а модель B отвечает текстом
- **THEN** вызывается `onNotice(A → B, rateLimited)`, а итоговое сообщение несёт `ModelRef` модели B

#### Scenario: Ошибка после вывода не переключает
- **WHEN** модель A обрывается после первого блока
- **THEN** модель B не вызывается

### Requirement: Переполнение контекста
`isContextOverflow(message, contextWindow)` SHALL признавать переполнение по правилам §2.11:
- класс `overflow`, поставленный адаптером;
- ошибка 400/413/422 с одной из фраз переполнения без признаков rate limit;
- «тихое» переполнение: `stop` при `input + cacheRead > contextWindow`;
- `length` с нулевым output при входе не меньше 99 % окна.

Адаптер SHALL ставить по этим правилам `errorClass: overflow`. Тихие случаи SHALL становиться `ErrorEvent`.

#### Scenario: Фраза переполнения с признаком rate limit
- **WHEN** ошибка 400 содержит `context length` и `tokens per minute`
- **THEN** это не переполнение

#### Scenario: Тихое переполнение
- **WHEN** ответ завершился `stop`, а `input + cacheRead` больше окна модели
- **THEN** сообщение получает класс `overflow` и уходит как `ErrorEvent`

### Requirement: Usage и стоимость
`Usage` SHALL хранить `input` без кэшированных токенов, `output` (включая рассуждение), `cacheRead`, `cacheWrite`, необязательный `reasoning` и `UsageCost` в долларах. Стоимость SHALL считаться как сумма по категориям «токены × ставка / 10⁶»: в `finish` и в `fail`, потому что частичный ответ тоже стоит денег. При неизвестных ценах (`ModelRef.cost == null`) стоимость SHALL быть 0. Usage шага SHALL быть суммой всех попыток и моделей.

#### Scenario: Формула стоимости
- **WHEN** ответ с usage `input 1000, output 500, cacheRead 2000` получен от модели с ценами `3 / 15 / 0.3` за миллион
- **THEN** стоимость равна `0.003 + 0.0075 + 0.0006` долларов

### Requirement: Кэш промпта
Адаптер Anthropic SHALL ставить `cache_control: {"type": "ephemeral"}` не больше чем на три блока:
- системный промпт;
- последнее определение инструмента;
- последний блок последнего `user`-сообщения из транскрипта.

Блоки, которые существуют только в payload, SHALL стоять после этой метки.

Адаптер OpenAI-совместимого API SHALL отправлять `prompt_cache_key = context.cacheKey` только при `ProviderConfig.promptCacheKey == true` и непустом ключе; иначе поля в теле НЕ SHALL быть (LLM-12). Значение по умолчанию флага — `true` для хоста `api.openai.com` и `false` для остальных.

Одинаковый снимок транскрипта и набор инструментов SHALL давать побайтово одинаковые системный промпт и список схем в payload (LLM-11). `cacheRead` и `cacheWrite` SHALL заполняться из usage провайдера.

#### Scenario: Метки Anthropic
- **WHEN** три последовательных запроса одной сессии собираются из растущего транскрипта
- **THEN** в каждом ровно три метки на указанных местах, а `system` и `tools` побайтово одинаковы во всех трёх

#### Scenario: Ключ только при флаге
- **WHEN** запрос к `https://api.openai.com/v1` с `cacheKey: "sess-1"` и к `http://localhost:11434/v1` с тем же ключом собираются с флагами по умолчанию
- **THEN** первое тело содержит `"prompt_cache_key": "sess-1"`, второе — нет

### Requirement: Параметр уровня рассуждения
Адаптер SHALL отправлять параметр рассуждения только модели с `supportsReasoning` и непустым `ModelRef.reasoningEffort` (LLM-15). Форма параметра:
- Anthropic, `ModelRef.thinkingMode: adaptive`: `thinking: {"type": "adaptive", "display": "summarized"}` и `output_config: {"effort": <уровень>}`, без `budget_tokens`;
- Anthropic, `ModelRef.thinkingMode: budget`: `thinking` с бюджетом 2048 / 8192 / 16384 для `low` / `medium` / `high`, ограниченным `max_tokens − 1024`; бюджет меньше 1024 рассуждение не включает;
- `reasoningFormat: openai`: `reasoning_effort`;
- `reasoningFormat: openrouter`: `reasoning.effort`;
- `reasoningFormat: none`: ничего.

Значение `reasoningFormat` по умолчанию — `openrouter` для хоста `openrouter.ai`, иначе `openai`.

#### Scenario: Модель без рассуждения
- **WHEN** запрос собирается для модели без `supportsReasoning`
- **THEN** тело не содержит ни `thinking`, ни `output_config`, ни `reasoning_effort`, ни `reasoning`

#### Scenario: Адаптивное рассуждение Anthropic
- **WHEN** модель Anthropic с `thinkingMode: adaptive` и `maxOutputTokens: 1800` получает `reasoningEffort: high`
- **THEN** тело содержит `"thinking": {"type": "adaptive", "display": "summarized"}` и `"output_config": {"effort": "high"}` и не содержит `budget_tokens`

#### Scenario: Бюджет ограничен лимитом ответа
- **WHEN** модель Anthropic с `thinkingMode: budget` и `maxOutputTokens: 4096` получает `reasoningEffort: high`
- **THEN** `budget_tokens` равен 3072

### Requirement: Статический каталог моделей
Порт `ModelCatalog` SHALL быть единственным источником `ModelRef` для ядра. `StaticModelCatalog` SHALL работать без сети (LLM-13).

**Список моделей:** модели конфига или флагов бинаря в порядке объявления, дубликаты `ModelId` отбрасываются.

**`resolve`.** Каждое поле `ModelRef` (`contextWindow`, `maxOutputTokens`, `cost`, `supportsImages`, `supportsReasoning`, `hiddenReasoning`, `thinkingMode`) SHALL разрешаться первым непустым значением по порядку источников:
1. явное значение конфига;
2. встроенный каталог (точный id, затем самый длинный префикс-ключ до `-` или конца, затем то же для части после последнего `/`);
3. безопасные значения: окно 32 000, лимит ответа 4 096, без картинок и рассуждения, `thinkingMode: adaptive`, цены неизвестны.

Затем `maxOutputTokens := min(maxOutputTokens, contextWindow − 1024)`, но не меньше 256. Использование безопасного значения, кроме цен и `thinkingMode`, SHALL давать одну запись `llm.catalog.default_used` на модель за процесс. Модель вне списка SHALL давать `null`. `refresh()` статического каталога SHALL ничего не делать.

#### Scenario: Неизвестная модель
- **WHEN** модель из конфига отсутствует во встроенном каталоге и не имеет явных полей
- **THEN** `resolve` даёт безопасные значения, и `Logger` получает ровно одно предупреждение `llm.catalog.default_used` (`static_model_catalog_test.dart: unknown model resolves to safe defaults with one warning`)

#### Scenario: Префикс встроенного каталога
- **WHEN** разрешается модель `anthropic/claude-opus-5-5-20260101`, а во встроенной таблице есть ключ `claude-opus-5-5`
- **THEN** окно и лимит ответа берутся из этой записи

#### Scenario: Корректность встроенной таблицы
- **WHEN** проверяется каждая запись встроенного каталога
- **THEN** окно больше 0, а лимит ответа меньше окна, а у моделей Claude 5.x `thinkingMode: adaptive`

### Requirement: Фабрика и закрытые адаптеры
Хост SHALL получать функцию модели только через `createStreamFunction(ProviderConfig, CoreLlmServices)`. Фабрика собирает цепочку §2.10: адаптер → `withWatchdogs` → `withTransientRetry` → `withFallback`. `CoreLlmServices` несёт `http.Client`, `Clock`, `Random` и `Logger` хоста. Публичный барель ядра НЕ SHALL экспортировать `lib/src/llm/providers/*` (PKG-5).

#### Scenario: Барель не раскрывает адаптеры
- **WHEN** проверяется файл `lib/codelab_agent_core.dart`
- **THEN** в нём нет экспорта `src/llm/providers/`

#### Scenario: Фабрика собирает устойчивую цепочку
- **WHEN** функция из фабрики получает сетевой сбой до вывода, а затем успешный ответ
- **THEN** потребитель видит один `StartEvent` и успешный ответ, а `Logger` — одну запись `llm.retry`

### Requirement: Детерминированная модель для тестов
`ScriptedStreamFunction` SHALL строить ответы модели из сценария в формате блока `llm` golden-фикстуры (`agent-core-architecture` §14.7) и экспортироваться только из `package:codelab_agent_core/testing.dart`.

**Порядок шагов.** n-й запрос к модели получает n-й шаг. `expect` шага — утверждение о запросе (последнее сообщение, результат инструмента, список схем). Несовпадение SHALL давать провал с diff ожидаемого и фактического запроса. Лишний запрос и неиспользованный шаг SHALL давать провал.

**Ответы:**
- текст режется на дельты по 16 символов;
- `delayMs` идёт по `FakeClock`;
- `waitForCancel` ждёт отмены и даёт `ErrorEvent(aborted)`;
- `error` даёт `ErrorEvent` с указанным классом;
- в `text` и `thinking` подставляются `${cwd}` и `${sessionId}`.

#### Scenario: Шаги строго по порядку
- **WHEN** сценарий из двух шагов обслуживает два запроса
- **THEN** первый запрос получает первый шаг, второй — второй, независимо от содержимого запросов (`scripted_stream_function_test.dart: steps are served strictly in order`)

#### Scenario: Провал expect
- **WHEN** последнее сообщение запроса не содержит текст из `expect.lastMessage.$textContains`
- **THEN** проверка падает с diff ожидаемого и фактического запроса (`scripted_stream_function_test.dart: expect mismatch fails with request diff`)

#### Scenario: Лишний запрос и неиспользованный шаг
- **WHEN** модель запрашивают больше раз, чем шагов в сценарии, или меньше
- **THEN** проверка сценария падает и называет лишний запрос или неиспользованный шаг
