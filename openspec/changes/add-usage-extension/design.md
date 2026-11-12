## Context

Решения пользователя 2026-11-13 по Q1–Q9 первой редакции внесены (раздел «Решения пользователя 2026-11-13»; D1, D3, D5, D11, D12, D17). Задача пользователя: первый из четырёх changes панели Usage (экран 17 холста; пул 1.x, `delivery-roadmap.md` §4.6, §6.2 п. 1). Этот change — только контракт usage по ACP, его проекция в агенте, разбор и модель отображения в `codelab_client_core`, строка статуса desktop и сегменты U-13 статус-строки CLI. Следующие changes — `add-usage-ledger` (L-29), `add-desktop-usage-pane` (панель, CSV), `add-session-deadline` (C-15).

Источники:
- `AGENTS.md` §3.4 (ACP не придумывается; расширение — только через OpenSpec), §7, §9, §10, §12, §16;
- `docs/protocols/acp/protocol/15-Extensibility.md`: методы с `_` — расширения; неизвестные уведомления получатель SHOULD игнорировать; расширения объявляются в `_meta` capability-объектов; корневые поля в типах спецификации запрещены;
- `docs/architecture/acp-boundary.md` §12–§19, §22, §49; `streaming.md` §7–§11, §24–§28, §33; `concurrency.md`; `session-lifecycle.md`; `observability.md`;
- `agent-core/13-acp-adapter.md` §13.2 (схема объявлений), §13.7 (проекция, ACP-6), §13.8 (итог хода), §13.12 (строка `add-usage-extension`), §13.14 (ACP-1…ACP-12);
- `agent-core/12-observability-and-errors.md` §12.6, §12.6.1; `16-non-mvp-and-open-questions.md` §16.3;
- `dart-agent-and-clients/12-1-view-model.md` §12.1.1, §12.1.5, VIEW-6; `12-2-cli-display-and-input.md` §12.2.6; `12-3-desktop-display.md` A7, DSK-11, тесты D-09;
- design.md change `add-subagents-and-tasks`, D4 (usage дерева), D9 (схема объявлений `_meta.codelab`);
- макеты `docs/design/claude-design/Usage.dc.html` (строка статуса, «~», «usage: —»), `CliStatus.dc.html`.

Что есть в коде (`develop` d99cc6b5, проверено):
- **Ядро.** `Usage` (`input`, `output`, `cacheRead`, `cacheWrite` — `int` с нулём по умолчанию, `reasoning` — `int?`), `UsageCost` в долларах, `calculateCost(usage, ModelCost?)`: без цен стоимость — `UsageCost.zero`, то есть «бесплатно» и «цена неизвестна» в `Usage` неразличимы; различает их только `ModelRef.cost == null`. `AgentLoop.run` суммирует `response.usage` каждого шага, включая шаги с ошибкой, и отдаёт сумму в `TurnEnded.usage`; `StepEnded.result` несёт `response` (с `model` ответившей модели) и `usage` шага. `AgentLoopConfig` уже содержит `estimateTokens` и `contextWindowCap`; `estimateContextTokens` якорится на usage последнего ответа (§9.3); порог сжатия — `shouldCompact(tokens, window, settings)` в `AgentRuntime`. Usage вызова суммаризатора в `TurnEnded.usage` не входит.
- **Бюджет C-13.** `TurnBudget`, ключи `budget.max_*`, проекция `stopReason: max_turn_requests` с `_meta.codelab.budgetExceeded` (`codelab_agent_acp/lib/src/event_projection.dart`), фикстура `acp/prompt-turn-budget-exceeded`. Клиент причину не читает: `PromptTurnCompleted` несёт только `stopReason`, заметка — «The turn reached the limit of model requests.».
- **Клиент.** `AcpClientApplication` отбрасывает любое неизвестное уведомление (`case JsonRpcNotification(): break`). В `codelab_client_core` нет ни `UsageView`, ни `SessionStatusBar`, ни `StatusBarProjector` — они только в документе §12.1. TUI-статус-строка (`apps/codelab_cli/lib/src/tui/core/status_line.dart`): профиль, режим, модель, очередь. В desktop строки статуса под композером нет; `ToolPane.usage` в `codelab_ui` — только значение перечисления. REPL строку статуса после хода не печатает; `stream-json` не реализован.
- **Схема объявлений D9** описана в `13-acp-adapter.md` §13.2 и в дельтах change `add-subagents-and-tasks`, но не реализована (его задачи 1.5, 1.6 открыты).
- **`usage_update`** Claude Code сейчас пропускается как незнакомый вид `session/update`; в вендоренной спецификации ACP его нет.

## Goals / Non-Goals

**Goals:**
- Закрыть §16.3 «передача usage клиенту» одной формой расширения, объявляемой по схеме D9.
- Дать клиенту usage шага, хода и сессии, стоимость и заполнение контекста так, чтобы дубли, поздние события и несколько соединений не портили суммы (`AGENTS.md` §9).
- Никогда не показывать неизвестное как ноль (VIEW-6, DSK-11); частичное — с «~».
- Показать это в строке статуса desktop и в статус-строке TUI; назвать лимит бюджета в заметке хода.

**Non-Goals:** панель Usage, CSV, журнал `usage.json`, `/usage`, дедлайн, Timeline, чтение чужого `usage_update`, ветка git (proposal, «Не входит»).

## Decisions

### D1. Форма: уведомление `_codelab/session/usage` (решение пользователя, Q1 (а))

Агент шлёт уведомление JSON-RPC `_codelab/session/usage` (агент → клиент, без `id`) с полным снимком usage сессии. Имя — в пространстве `_codelab/session/*` по образцу `_codelab/session/steer` (§17.7.3.1): уведомление относится к сессии и несёт её `sessionId` (уточнение пользователя к Q1). Правила расширения ACP, которым следует форма, — D17. Поводы (`trigger`): `step` — после каждого `StepEnded`; `turn` — по `TurnEnded`, до ответа на `session/prompt`; `compaction` — после `ContextCompacted`.

Почему уведомление, а не поле ответа:
- **Живые значения.** Ход из 40 шагов идёт минутами; поле в ответе даёт число только в конце. Строка статуса и будущая Timeline (D-22) хотят шаг сразу.
- **Несколько соединений.** Ответ на `session/prompt` уходит только отправителю (§13.7, SESM-15), а уведомления хода — всем соединениям сессии. С полем в ответе второе окно не увидело бы расход вообще.
- **Сжатие вне хода.** Фоновое сжатие `afterTurn` идёт после ответа; заполнение контекста меняется, а ответа уже нет.
- **Стандарт.** `15-Extensibility.md` прямо разрешает методы с `_`, и получатель SHOULD игнорировать незнакомые уведомления — сторонний клиент не ломается.

*Альтернативы:*
- (б) `_meta.codelab.usage` в ответе `session/prompt` — проще, но без шагов, без сжатия и без второго соединения (выше). При сбое хода (`-32603`) пришлось бы дублировать поле в `data.codelab`.
- (в) Читать `usage_update` (Claude Code) и слать его же. Вида нет в вендоренной спецификации ACP (`17-Schema.md`); трактовать его — значит придумывать semantics (`AGENTS.md` §3.4). Возможен только после обновления `docs/protocols/acp/` отдельным change; `UsageDecoder` (D8) держит форму в одном месте, поэтому второй источник добавится локально.
- (г) `session_info_update` с `_meta.codelab.usage` — стандартный вид, тот же порядок с `session/update`, но смысл вида — метаданные сессии (заголовок, время), а не счётчики; сторонний клиент получал бы пустые `session_info_update` на каждом шаге.

### D2. Параметры `_codelab/session/usage`, версия 1

Пример (значения условные):

```json
{"jsonrpc":"2.0","method":"_codelab/session/usage","params":{
  "sessionId":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","seq":4,"trigger":"step","turnId":"01JC0F3A7Q5M2N8P4R6T1V3X9Z",
  "step":{"index":1,"model":"anthropic/claude-sonnet-4","tokens":{"input":1200,"output":310,"cacheRead":9800,"cacheWrite":0},"cost":"0.00954"},
  "turn":{"steps":2,"tokens":{"input":2400,"output":520,"cacheRead":19600,"cacheWrite":1200,"reasoning":40},"cost":"0.0183"},
  "session":{"turns":3,"steps":7,"tokens":{"input":9100,"output":2100,"cacheRead":51000,"cacheWrite":1200},"cost":"0.0372","partial":["beforeLoad"]},
  "currency":"USD",
  "context":{"used":22900,"size":200000,"compactAt":183616}
}}
```

| Поле | Тип | Обязательно | Смысл |
|---|---|---|---|
| `sessionId` | строка | да | сессия ACP |
| `seq` | целое ≥ 1 | да | номер снимка сессии; строго растёт в пределах сессии агента (D7) |
| `trigger` | строка | да | `step`, `turn`, `compaction`; незнакомое значение клиент принимает как снимок без шага |
| `turnId` | строка | при `step` и `turn` | id хода ядра (`TurnId`); у `compaction` нет |
| `step` | объект | только при `step` | `index` (номер шага в ходе с 0, `StepResult.stepIndex`), `model` (`<provider>/<id>` ответившей модели), `tokens`, `cost`, `partial` |
| `turn` | агрегат | при `step` и `turn` | ход: при `step` — сумма шагов до этого момента, при `turn` — итог (D4) |
| `session` | агрегат | да | все ходы сессии, видимые агенту (D4, D6) |
| `currency` | строка ISO 4217 | если есть хоть одно `cost` | в v1 всегда `USD` (цены каталога — доллары) |
| `context` | объект | нет | `used` и `size` — целые; `compactAt` — целое, порог автосжатия; отсутствует, если автосжатие выключено (D5, Q3 (б)) |

Агрегат: `tokens` — `input`, `output`, `cacheRead`, `cacheWrite` (целые ≥ 0, обязательны) и `reasoning` (только если провайдер его сообщил, как в `Usage.toJson`); `cost` — десятичная строка (D9), отсутствует, если цена неизвестна целиком; `steps` (и у сессии `turns`) — целые; `partial` — массив причин неполноты (D6), отсутствует, если пуст.

Правила совместимости:
- неизвестные поля и неизвестные строки в `partial` обе стороны игнорируют;
- новое необязательное поле добавляется без смены версии (например, лимиты бюджета для панели — Q5);
- изменение смысла или типа существующего поля — только `usage: {"version": 2}` и OpenSpec change; агент шлёт форму версии, не превышающей объявленную клиентом.

### D3. Объявление и кому слать

- Клиент CodeLab добавляет `usage: {"version": 1}` в `clientCapabilities._meta.codelab` (схема D9 change `add-subagents-and-tasks`).
- Агент добавляет `usage: {"version": 1}` в `agentCapabilities._meta.codelab` всегда, когда отвечает этим блоком (то есть клиент прислал объект `_meta.codelab`). Агент без usage не бывает: ядро считает его всегда; неизвестную цену выражает `cost` и `partial`.
- Агент шлёт `_codelab/session/usage` только соединениям, чей `clientCapabilities._meta.codelab.usage.version` — целое ≥ 1. Остальные соединения сессии (Zed, старый клиент) ничего не получают.
- Клиент принимает `_codelab/session/usage` и без объявления агента (как данные `_meta.codelab.task` по D9): объявление управляет только тем, что показывать до первого снимка (D8, «ожидание» против «агент не сообщает»).

*Почему не слать всем:* в отличие от `_meta` у стандартных обновлений, отдельное уведомление на каждом шаге — лишний трафик и записи в журналах стороннего клиента; без объявления не меняется ни один из 62 существующих кадров фикстур (D13).

### D4. Агрегаты в агенте: источник и отсутствие двойного учёта

Агрегаты считает `codelab_agent_acp` на **сессию сервера**, а не на соединение: все соединения сессии видят одни и те же числа и один `seq`.

1. **Шаг** — `StepEnded.result.usage` и `StepEnded.result.response.model`. Резервная модель и повторы уже внутри шага: `AssistantMessage` несёт сумму usage всех моделей и `model` ответившей (`agent-llm`, LLM-контракт); отдельно они не складываются.
2. **Ход во время хода** — сумма шагов этого хода.
3. **Ход в конце** — `TurnEnded.usage` (сумма шагов по `AgentLoop.run`), а не собственная сумма адаптера. Когда change `add-subagents-and-tasks` добавит usage детей в usage хода родителя (D4 того change, SUB-11), итог хода включит его без правки этого change; шаги детей до клиента как шаги корня не доходят. До итога хода живые снимки детей не учитывают — это записано в риске R3.
4. **Сессия** — сумма итогов завершённых ходов плюс текущий ход по п. 2. Клиент суммы не считает (D8), поэтому дубли и несколько соединений ничего не удваивают.
5. **Ход без шагов** (встроенная команда `/usage`, `/mode`, отмена до первого запроса) — уведомления нет: расхода не было, а `agent-acp-server` «Встроенные команды» запрещает команде лишние кадры.
6. **Суммаризатор.** Usage вызова суммаризатора при сжатии в `TurnEnded.usage` не входит и в v1 в сумму сессии не попадает: события `ContextCompacted` его не несут. Учёт — change `add-usage-ledger` (`summaries` в §12.6.1). Записано в R2.
7. **Стоимость** считается в целых микродолларах: стоимость шага — `round(usage.cost.total × 10⁶)`, хода в конце — `round(TurnEnded.usage.cost.total × 10⁶)`, сессии — сумма микроединиц ходов. Сумма `double` по 1 000 ходам не накапливает ошибку (§12.1.5).

### D5. Заполнение контекста — из ядра

Адаптер токены не оценивает. `StepEnded` получает поле `context` (`ContextFill(used, window, compactAt)`; имя — исполнителю, смысл фиксирует это решение):
- `used` — `estimateContextTokens` по контексту цикла после добавления результатов инструментов шага; якорь — usage только что полученного ответа, поэтому оценивается лишь хвост результатов (§9.3);
- `window` — `effectiveContextWindow(model, cap: contextWindowCap)` модели, которая будет у следующего запроса;
- `compactAt` — порог автосжатия `afterTurn` в токенах (то же правило, что `shouldCompact` в `AgentRuntime`: окно минус `reserve_tokens`); рантайм передаёт его циклу через `AgentLoopConfig` вместе с `contextWindowCap`; при выключенном сжатии (`compaction.enabled: false` или профиль без сжатия) — `null`;
- без оценщика в `AgentLoopConfig` (`estimateTokens == null`) поле `null`, и `context` в уведомлении отсутствует.

После `ContextCompacted` адаптер шлёт снимок с `context.used = tokensAfter` и `size` и `compactAt` из последнего `StepEnded` этой сессии; если шагов в этом сервере ещё не было — без `context`.

*Альтернатива:* геттер `AgentSession.contextFill` — во время хода `Agent.messages` ещё не содержит сообщений хода (они добавляются после `runAgentLoop`), и значение отставало бы на ход.

### D6. Причины неполноты `partial`, версия 1

| Причина | Где | Когда |
|---|---|---|
| `noUsage` | шаг; ход и сессия — объединение | успешный ответ модели (`stopReason` не `error` и не `aborted`) с `input + output == 0`: настоящий ответ всегда тратит входные токены, значит провайдер usage не прислал (DF-15). Ответ с ошибкой и нулём — не причина |
| `noPrice` | шаг; ход и сессия — объединение | у модели шага нет цен (`ModelRef.cost == null`), а `input + output + cacheRead + cacheWrite > 0` |
| `beforeLoad` | только сессия | сессия открыта в этом сервере через `session/load`, и в её журнале были ответы модели: ранние ходы в сумму не вошли. Снимается change `add-usage-ledger` (Q7 (а)) |

`cost` агрегата отсутствует, если ни у одного шага агрегата цена не известна; при смешанных — присутствует с `noPrice`. Клиент ставит «~» перед токенами при `noUsage` или `beforeLoad`, перед стоимостью — при любой причине (D8). Обнуляемые `cacheRead`/`cacheWrite` ядра в v1 не вводятся (Q2 (а)).

### D7. Порядок, дубли, поздние события, гонка отмены

- **Порядок на проводе.** Уведомление ставится в ту же `OutboundQueue` соединения, что и `session/update`, в момент проекции события. Снимок `turn` идёт после последнего `session/update` хода и до ответа на `session/prompt` — в том числе при `cancelled` и перед ошибкой `-32603` (ACP-3, ACP-5, ACP-7 не меняются). Потраченное до отмены — настоящий расход, его нужно показать.
- **`seq`.** Счётчик на сессию сервера, с 1, растёт на каждый снимок. Снимок — полное состояние, поэтому клиенту не нужны промежуточные: пропуски номеров (соединение загрузило сессию позже) — норма, не ошибка (`streaming.md` §10, §33).
- **Клиент** применяет снимок, только если его `seq` больше последнего применённого для этой сессии в текущем поколении соединения; равный или меньший — дубль или опоздание, отбрасывается с DEBUG-записью. Смена соединения (`reconnect`, перезапуск агента) сбрасывает `UsageView` сессии в «ожидание»: поздние кадры старого соединения бэкенд kit уже отбрасывает (`codelab_client_core/AGENTS.md` §3), а `seq` нового агента может начаться с 1.
- **Гонка отмены и завершения.** На стороне агента её решает ядро: `TurnEnded` одно, и снимок `turn` строится из него, какой бы ни была причина. На стороне клиента usage не участвует в автомате хода: снимок, пришедший после ответа (сторонний или ошибочный агент), не оживляет ход и не меняет его статус, а только обновляет числа по правилу `seq`.
- **Неизвестная сессия.** Уведомление для сессии, которой нет в рабочем пространстве клиента, отбрасывается с DEBUG-записью.

### D8. Клиент: где разбор и какая модель

| Слой | Что |
|---|---|
| `codelab_client_acp` | объявление `usage`; `case JsonRpcNotification(method: '_codelab/session/usage')` передаёт `sessionId` и сырые `params` подписчику (поток расширений приложения, привязанный к поколению соединения); разбирать содержимое не обязан |
| `codelab_client_core` | `lib/src/usage/`: `UsageDecoder` — одна конкретная функция/класс без интерфейса (одна форма — одна реализация, `AGENTS.md` §13); `UsageView` в `SessionView.usage`; свёртка по `seq` |

Модель (эскиз, имена уточняет исполнитель):

```dart
final class UsageView {
  final UsageSupport support;          // unknown — агент не объявил и не прислал; awaiting — объявил, снимков нет; reported
  final UsageTotals? lastTurn;         // ход последнего снимка с turnId (идущий или завершённый)
  final UsageTotals? session;
  final ContextFillView? context;      // used, size; fraction — null без size
  final int lastSeq;
}
final class UsageTotals { final TokenCounts tokens; final Money? cost; final int steps; final Set<UsagePartial> partial; }
final class TokenCounts { final int input, output, cacheRead, cacheWrite; final int? reasoning; }
final class Money { final int micros; final String currency; }
enum UsagePartial { noUsage, noPrice, beforeLoad }   // незнакомые строки отбрасываются
```

Правила:
- обязательные поля (`sessionId`, `seq`, `trigger`, `session.tokens`) не разобрались → снимок отброшен целиком, предупреждение `usage.decode_failed` (D14); необязательное поле неверного типа → поле отсутствует, то же предупреждение; исключений нет (§12.1.10);
- `lastTurn` заменяется, когда приходит снимок с другим `turnId`; между ходами показывается последний ход;
- клиент суммы не считает и окно модели не оценивает: всё — из снимка (отличие от §12.1.5 п. 3 первой редакции, где клиент суммировал ходы сам; документ правится задачей 0.x);
- `SessionStatusBar` и `StatusBarProjector` из §12.1.1 этим change не вводятся: модель и режим клиенты уже берут из опций сессии, ветка git вне объёма (Q9 (б)), а второй слой ради одного поля — церемония. `SessionView.usage` — единственное новое поле.

*Альтернатива:* типизированная модель уведомления в `codelab_acp_protocol`, общая для агента и клиента. Отклонена ради единообразия: пакет протокола моделирует только вендоренную спецификацию, а все расширения `_meta.codelab.*` строятся адаптером и разбираются клиентом на краях (D2 change `add-subagents-and-tasks`); форму на проводе с обеих сторон закрепляют фикстуры с ролями `agent` и `client` (D13).

### D9. Деньги на проводе и в клиенте (решение пользователя, Q4 (а))

- На проводе — десятичная строка `^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$`: целая часть, точка и до 6 знаков без хвостовых нулей; ноль — `"0"`. Агент печатает её из целых микродолларов (D4, п. 7), поэтому строка детерминирована для фикстур. Валюта — `currency` в корне параметров.
- Клиент разбирает строку в `Money.micros` без `double`; больше 6 знаков, знак, экспонента или пустая строка — поле неверно (D8). `cost` без `currency` — тоже.
- Цена неизвестна — `cost` нет → клиент показывает «—» (DSK-11), никогда не `$0`.

*Альтернативы:* число JSON (`0.0041`) — `double` на обеих сторонах, неточное представление в фикстурах; целые микроединицы (`4100`) — точно, но имя поля и масштаб легко перепутать стороннему читателю протокола; стоимость по категориям (`input`/`output`/…, как `UsageCost`) — избыточна для строки статуса, нужна только панели, и её можно добавить необязательным полем.

### D10. Причина остановки по бюджету в клиенте (решение пользователя, Q5 (а))

- `codelab_client_acp` читает `_meta.codelab.budgetExceeded` ответа `session/prompt` со `stopReason: max_turn_requests` и кладёт строку в итог хода (`PromptTurn`). Значение — открытое множество: `steps`, `tokens`, `cost`, `duration`, `deadline` и любые будущие; не строка — игнорируется.
- `codelab_client_core`: заметка хода `turnStopped` для известного значения — `The turn stopped: budget exceeded: <limit>.`; без значения или с незнакомым — прежний текст «The turn reached the limit of model requests.».
- Живой прогресс бюджета (`92k / 200k`, артборд Usage) — change `add-desktop-usage-pane`; лимиты, если понадобятся, придут необязательным полем `_codelab/session/usage` без смены версии (D2).

### D11. Desktop: строка статуса под композером

- Виджет `CodeLabSessionStatusBar` в `codelab_ui` (имя по соглашению пакета `CodeLab*`; в §12.3 — `AcpSessionStatusBar`): получает готовые подписи и тон, логики нет (`codelab_ui/AGENTS.md`).
- Маппер desktop (`ui_mappers.dart`) строит данные из `SessionView.usage` и опций сессии: модель · режим · контекст · токены хода (`вход → выход`, вход = `input + cacheRead + cacheWrite`) · стоимость хода · `· session $…`. Подсказка — пять счётчиков и причины `partial`.
- Состояния: `unknown` — «usage: —» с подсказкой «agent does not report usage»; `awaiting` — сегментов usage нет, во время хода рядом крутится индикатор; `reported` — значения; «~» по D6; стоимость `null` при известных токенах — «—» с подсказкой «price unknown»; контекст без `size` скрыт, `0 %` не показывается.
- Тон контекста: ≥ 80 % — `warning`, ≥ 95 % — `danger`; подпись `compaction soon` — при известном `compactAt` и `used ≥ 0.9 × compactAt`; без `compactAt` (автосжатие выключено) подписи нет (Q3 (б)).
- Деньги форматируются из `Money.micros` без `double`: меньше 0,01 — две значащие цифры после первой ненулевой, иначе два знака (§12.3, A7).
- Клик по строке (переход в панель Usage) — change `add-desktop-usage-pane`; в v1 строка некликабельна.
- Ключи тестов: `status-bar-usage`, `status-bar-cost`, `status-bar-context` (§12.3).

### D12. CLI: статус-строка

- **TUI** (`status_line.dart`): после модели — `ctx N%`, затем `↑<вход> ↓<выход>` суммы сессии, затем `$<стоимость сессии>`; «~» — префиксом перед числом по D6 (как в §12.2.6 и desktop; артборд CliStatus ставит «~» после суммы — отступление подтвердил пользователь 2026-11-13, артборд поправить). Порядок отбрасывания на узком экране: профиль, стоимость, токены, контекст, модель (сначала сокращается); режим и очередь не отбрасываются. Без данных сегмент не выводится и `0` не печатается (VIEW-6). Цвет контекста ≥ 80 % — жёлтый, ≥ 95 % — красный (только в `render`).
- **REPL** (Q9 (б)): после каждого хода на `ansi` (приглушённо) и `plain` печатается одна строка `─ <режим> · <модель> · ctx N% · ↑… ↓… · $…`; на `raw` и в headless — нет.
- Числа: до 1000 — как есть, далее `12.3k`, `1.2M`; деньги — `$` и два знака, меньше 0,01 — `$0.004` (из микроединиц).

### D13. Фикстуры conformance

Все новые — с `extensions: ["usage"]` (FIX-4) и ссылками `spec` на `15-Extensibility.md` и `05-Prompt Turn.md`:

| Фикстура | Роли | Что |
|---|---|---|
| `acp/prompt-usage-steps` | `agent`, `client` | клиент объявил `usage`; два шага модели с ценами: `step` после каждого шага, `turn` перед ответом `end_turn`; `seq` 1…3; `context` с `compactAt` |
| `acp/prompt-usage-unpriced` | `agent` | модель без цен и шаг без usage: `cost` нет, `partial: ["noUsage","noPrice"]` у шага, хода и сессии |
| `acp/prompt-usage-cancelled` | `agent` | отмена посреди инструмента: снимок `turn` после `tool_call_update` `failed` и до `stopReason: cancelled` |
| `acp/compact-usage-context` | `agent` | `/compact`: снимок `compaction` с меньшим `context.used` |
| `acp/prompt-usage-compaction-off` | `agent` | `compaction.enabled: false`: `context` без `compactAt` |
| `acp/session-load-usage-partial` | `agent` | `session/load` журнала с ответами модели: снимков до хода нет, затем ход — `session.partial` содержит `beforeLoad` (Q7 (а)) |

Изменения существующих: `acp/initialize-codelab-extensions` (change `add-subagents-and-tasks`) ожидает `usage` в обоих блоках; клиентские фикстуры, где kit шлёт `initialize`, ожидают `usage` в `clientCapabilities._meta.codelab`; `acp/prompt-turn-budget-exceeded` получает роль `client` (если её нет) и проверку заметки `budget exceeded: tokens`. Фикстуры без объявления `usage` не меняются: это и есть проверка «стороннему клиенту ничего нового». Списки ожидаемого покрытия FIX-2 не затрагиваются: `_codelab/session/usage` не вид `sessionUpdate` и не метод `acp_method_codec.dart`.

Имя критерия L-11 в матрице `acp/prompt-usage-meta` меняется на `acp/prompt-usage-steps` (задача 0.7).

### D14. Наблюдаемость

- **Агент.** Новых событий лога на шаг нет: usage хода уже пишет `turn.end`. При `initialize` в существующую запись согласованных возможностей соединения попадает `usage` (если запись есть; иначе — debug `acp.extensions.negotiated {connection, keys}`).
- **Клиент.** DEBUG `usage.received {session_id, seq, trigger}`; DEBUG `usage.stale {session_id, seq, last_seq}`; WARNING `usage.decode_failed {session_id, field, reason}` — не чаще раза на сессию и причину. Payload — только в developer-only трассировке протокола (`category=protocol`), как для пропущенных `session/update`. Секретов в уведомлении нет; id модели — не секрет.

### D15. Пакеты, зависимости, безопасность

| Пакет (ADR-0002) | Что | Исполнитель |
|---|---|---|
| `codelab_agent_core` | `StepEnded.context` (D5) | `[agent]` |
| `codelab_agent_acp` | объявление, агрегаты, проекция в `_codelab/session/usage` | `[protocol]` |
| `codelab_acp_testing` | фикстуры D13; режим usage scripted-агента для e2e app и CLI | `[protocol]` |
| `codelab_acp_protocol` | без изменений (`_meta` capability-объектов и уведомления JSON-RPC уже моделируются) | — |
| `codelab_client_acp` | объявление, маршрут уведомления, `budgetExceeded` | `[client]` |
| `codelab_client_core` | `UsageDecoder`, `UsageView`, `SessionView.usage`, заметка бюджета | `[client]` |
| `apps/codelab_cli` | TUI-сегменты, строка REPL после хода, PTY-e2e | `[client]` |
| `codelab_ui`, `apps/codelab_desktop` | строка статуса | `[desktop]` |

- Направление зависимостей прежнее: `codelab_agent_acp → codelab_agent_core`; `codelab_client_core → codelab_client_acp → codelab_acp_protocol`; клиенты к `codelab_agent_*` не обращаются.
- Новых зависимостей нет; allowlist ядра (PKG-2) и kit не меняются. Граф в `README.md` не меняется. Новых правил сторожа (`codelab_architecture_tests/test/support/rules.dart`) не нужно: код ложится в пакеты с действующими правилами (PKG-1, PKG-3, web-безопасность kit).
- Web-безопасность: `codelab_client_core`, `codelab_client_acp`, `codelab_agent_core`, `codelab_agent_acp` — чистый Dart без новых импортов; `melos run web-compile` — в итерациях 1 и 2.
- Разрешения и containment не затрагиваются: уведомление только читает счётчики, клиент ничего не исполняет.
- WebSocket: usage и стоимость уходят по всем транспортам одинаково (Q6 (а)): держатель токена WebSocket уже видит весь транскрипт, а уведомление секретов не несёт.

### D16. Итерации

Каждая — отдельный PR в `develop`, красные тесты коммитятся до кода (только по просьбе пользователя):
- **0 — документы.** Этот change, решения пользователя 2026-11-13, правки документов архитектуры.
- **1 — протокол и агент.** `StepEnded.context`; объявление `usage`; агрегаты и проекция; фикстуры с ролью `agent`; `13-acp-adapter.md`.
- **2 — клиентский слой.** Объявление и маршрут в `codelab_client_acp`; `UsageDecoder`, `UsageView`, `SessionView.usage`; `budgetExceeded`; клиентская роль фикстур.
- **3 — desktop и CLI.** Строка статуса desktop; TUI-сегменты; строка статуса после хода в REPL; scripted-агент с usage; PTY-e2e `cli/status-line-usage`; интеграционный тест app (приёмка `release/*`).

Зависимости: 1 ← 0 и задачи 1.5, 1.6 change `add-subagents-and-tasks` (схема D9 в коде; Q8 (а)); 2 ← 1; 3 ← 2. Архивация — после change `add-subagents-and-tasks` (R1).

### D17. Соответствие правилам расширения ACP

Пользователь попросил расширить ACP, не нарушая правил документации протокола. Источник — `docs/protocols/acp/protocol/15-Extensibility.md` (разделы «The `_meta` Field», «Extension Methods», «Custom Notifications», «Advertising Custom Capabilities»); вендоренная спецификация не меняется (`AGENTS.md` §3.4). Пункт за пунктом:

1. **Свой метод — только с префиксом `_`.** Спецификация резервирует имена, начинающиеся с `_`, под расширения. Метод — `_codelab/session/usage`; пространство `_codelab/*` уже используется (`_codelab/session/steer`, §13.12), поэтому столкновения с будущими методами ACP нет. Пространство `_codelab/session/*` объединяет методы, относящиеся к сессии, но не одну capability: `_codelab/session/steer` объявляет `steering`, методы дерева сессии — `sessionTree`, а `_codelab/session/usage` — только ключ `usage`.
2. **Объявление через `_meta` capability-объектов в `initialize` (SHOULD).** Клиент объявляет `clientCapabilities._meta.codelab.usage: {"version": 1}`, агент отвечает `agentCapabilities._meta.codelab.usage: {"version": 1}` по схеме D9 change `add-subagents-and-tasks` (D3). Агент шлёт уведомление только соединению, объявившему `usage`, — строже, чем требует спецификация.
3. **Никаких своих полей в корне типов спецификации (MUST NOT).** Новых корневых полей нет ни в `InitializeRequest`/`InitializeResponse`, ни в `ClientCapabilities`/`AgentCapabilities`, ни в `PromptResponse`; нового значения `sessionUpdate` тоже нет — значения `SessionUpdate` перечисляет спецификация (`17-Schema.md`), и своё значение было бы тем же корневым расширением типа. Причина остановки по бюджету остаётся в `_meta.codelab.budgetExceeded` ответа `session/prompt` (D10). Ключи `traceparent`, `tracestate`, `baggage` корня `_meta` не используются: всё лежит под `_meta.codelab`.
4. **Получатель SHOULD игнорировать неизвестное уведомление.** Сторонний клиент (Zed), если бы и получил `_codelab/session/usage`, по спецификации его проигнорирует; по D3 он его не получает вовсе. Метод — уведомление, а не запрос: ответа нет, поэтому ни у одной стороны не возникает `-32601 Method not found` («Custom Requests»). Клиент CodeLab, получивший незнакомое уведомление `_codelab/*`, тоже лишь отбрасывает его (`acp-protocol-client`).
5. **Forward compatibility.** Версия — целое `version` в объявлении; неизвестные поля, ключи объявления и причины `partial` обе стороны игнорируют; новое необязательное поле добавляется без смены версии, изменение смысла — только `version: 2` и OpenSpec change (D2).

Проверки: сценарии `agent-acp-server` «Клиент без объявления» и «Стандартные типы без новых полей», `acp-protocol-client` «Ответ без новых корневых полей»; инвариант корпуса FIX-4 (фикстура без `extensions` не содержит `_codelab/*`).

## Risks / Trade-offs

- **R1. Пересечение дельт с `add-subagents-and-tasks`.** Оба change меняют требования `initialize` и «Расширения протокола этапа 4» (`agent-acp-server`) и «Объявление расширений CodeLab при initialize» (`acp-protocol-client`). Дельты этого change написаны поверх текста того change (объединение), поэтому этот change архивируется после него (решение пользователя, Q8 (а)).
- **R2. Недосчёт суммаризатора.** Сумма сессии в v1 не включает вызовы суммаризатора (D4, п. 6) и после `add-usage-ledger` может вырасти на их величину. Альтернатива — причина `partial` после каждого сжатия — сделала бы «~» постоянным у длинных сессий без пользы.
- **R3. Субагенты в живых снимках.** До итога хода расход детей не виден; в итоге хода он появляется скачком (D4, п. 3). Панель Agents показывает итог ребёнка отдельно (D24 того change).
- **R4. Эвристика `noUsage`.** Нулевой `input + output` у успешного ответа считается «провайдер не сообщил». Ложное срабатывание невозможно для настоящего ответа модели; scripted-модель без `usage` в фикстурах даёт `noUsage` — это ожидаемо и проверяется фикстурой `acp/prompt-usage-unpriced`.
- **R5. `beforeLoad` почти всегда после перезапуска.** Внешний агент по stdio живёт столько же, сколько соединение, поэтому после перезапуска клиента сумма сессии — «~» до change `add-usage-ledger` (Q7 (а)).
- **R6. Объём трафика.** Одно уведомление на шаг (не на дельту) — порядка десятков на ход; дешевле, чем поток `agent_message_chunk`.
- **R7. Гонки.** Порядок «снимок `turn` → ответ» обеспечивает очередь соединения, а не дисциплина (§13.15); на клиенте `seq` закрывает дубли, опоздания и несколько соединений (D7).

## Migration Plan

Миграции данных нет: журнал сессии и `Usage` ядра не меняются, клиент ничего не сохраняет. Старый клиент без `usage` в объявлении получает прежний поток; новый клиент со сторонним агентом показывает «usage: —». Откат — удаление ключа `usage` из объявления клиента: агент перестаёт слать уведомление.

## Решения пользователя 2026-11-13

- **Q1 — (а), уведомление** с уточнением: имя метода `_codelab/session/usage` по образцу `_codelab/session/steer`, а не `_codelab/usage`; объявление `usage: {"version": 1}` с обеих сторон по D9; агент шлёт только объявившему клиенту; расширение не нарушает правил `15-Extensibility.md` (D1, D3, D17).
- **Q2 — (а):** «~» в v1 только по причинам D6; обнуляемые `cacheRead`/`cacheWrite` — позже отдельным change.
- **Q3 — (б):** поле `context.compactAt` — порог автосжатия, отсутствует при выключенном автосжатии; подпись `compaction soon` при `used ≥ 0.9 × compactAt`; тон 80/95 % размера окна (D2, D5, D11, D12).
- **Q4 — (а):** стоимость — десятичная строка до 6 знаков и `currency`; в клиенте — микроединицы; неизвестная цена — «—» (D9).
- **Q5 — (а):** клиент читает `budgetExceeded` и называет лимит в заметке хода; живой прогресс бюджета и поля лимитов — change `add-desktop-usage-pane` (D10).
- **Q6 — (а):** одинаково по всем транспортам, в том числе `serve --ws` (D15).
- **Q7 — (а):** после `session/load` сумма сессии — только по ходам после загрузки с `beforeLoad`; снимков до первого хода нет; полная сумма — change `add-usage-ledger` (D6, D13).
- **Q8 — (а):** итерация 1 стартует после задач 1.5 и 1.6 change `add-subagents-and-tasks`; архивация — после него (D16, R1).
- **Q9 — (б):** TUI-статус-строка и строка статуса после хода в REPL на `ansi`/`plain`; ветка git — вне change (D12).

Отклонённые варианты и их доводы — в D1 (альтернативы формы), D5, D9, D10.

## Open Questions

Нет.
