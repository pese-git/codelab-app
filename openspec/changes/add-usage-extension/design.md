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
- **Клиент.** `AcpClientApplication` отбрасывает любое неизвестное уведомление (`case JsonRpcNotification(): break`). В `codelab_client_core` нет ни `UsageView`, ни `SessionStatusBar`, ни `StatusBarProjector` — они только в документе §12.1. TUI-статус-строка (`apps/codelab_cli/lib/src/tui/core/status_line.dart`): профиль, режим, модель, очередь. В desktop строки статуса под композером нет; `ToolPane.usage` в `codelab_ui` — только значение перечисления. REPL строку статуса после хода не печатает; `stream-json` не реализован. *Сверка клиентского слоя 2026-11-16 (`develop` fd979232) перед итерацией 2 — D21.*
- **Схема объявлений D9** описана в `13-acp-adapter.md` §13.2 и в дельтах change `add-subagents-and-tasks` и реализована: его задачи 1.5 и 1.6 закрыты, итерация 2 влита в `develop` (97e91de2). Агент объявляет `tasks` и, при включённых субагентах, `subagents` с эффективной `maxDepth`; клиент объявляет `tasks` и `subagents` и считает расширение согласованным только при `version`, равном целому JSON-числу `1` (`codelab_client_acp/lib/src/domain/codelab_extensions.dart`). Разбора объявлений клиента на стороне агента ещё нет: первым он понадобится `subagentToolCalls` (итерация 5 того change) или `usage` (итерация 1 этого). *Сверка 2026-11-16 (`develop` b05eea88):* разбор уже есть — `subagentToolCallsConsent` (итерация 5 того change); места в коде, расхождения и уточнения — D18.
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
- **Несколько соединений.** Ответ на `session/prompt` уходит только отправителю (§13.7, SESM-15), а уведомления хода — всем соединениям сессии. С полем в ответе второе окно не увидело бы расход вообще. *Уточнение 2026-11-16 (Q11 (а)):* сейчас у сессии один владелец, веер на все соединения — после MVP (SESM-15); довод остаётся в силе для перехода сессии к новому соединению (`reattach`, сюда же — перенесённый ход) и для будущего SESM-15.
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
| `context` | объект | нет | `used` и `size` — целые; `compactAt` — целое, порог автосжатия; отсутствует, если автосжатие выключено (D5, Q3 (б)); в снимке `turn` — заполнение последнего `StepEnded` хода (D19 п. 4) |

Агрегат: `tokens` — `input`, `output`, `cacheRead`, `cacheWrite` (целые ≥ 0, обязательны) и `reasoning` (только если провайдер его сообщил, как в `Usage.toJson`); `cost` — десятичная строка (D9), отсутствует, если цена неизвестна целиком; `steps` (и у сессии `turns`) — целые; `turns` считает ходы с шагами, включая текущий (D19 п. 3); `partial` — массив причин неполноты (D6) в порядке строк таблицы D6, отсутствует, если пуст (D19 п. 2).

Правила совместимости:
- неизвестные поля и неизвестные строки в `partial` обе стороны игнорируют;
- новое необязательное поле добавляется без смены версии (например, лимиты бюджета для панели — Q5);
- изменение смысла или типа существующего поля — только `usage: {"version": 2}` и OpenSpec change. Версия в объявлении — не диапазон: по D9 change `add-subagents-and-tasks` обе стороны считают ключ согласованным только при известной им версии (в v1 — целое JSON-число `1`), поэтому переход на v2 решает тот change, который её введёт (например, объявлением нескольких версий).

### D3. Объявление и кому слать

- Клиент CodeLab добавляет `usage: {"version": 1}` в `clientCapabilities._meta.codelab` (схема D9 change `add-subagents-and-tasks`).
- Агент добавляет `usage: {"version": 1}` в `agentCapabilities._meta.codelab` всегда, когда отвечает этим блоком (то есть клиент прислал объект `_meta.codelab`). Агент без usage не бывает: ядро считает его всегда; неизвестную цену выражает `cost` и `partial`.
- Агент шлёт `_codelab/session/usage` только соединениям, чей `clientCapabilities._meta.codelab.usage` — объект с `version`, равным целому JSON-числу `1` (правило согласования D9 change `add-subagents-and-tasks`: не `1.0`, не `"1"`, не другое число). Остальные соединения сессии (Zed, старый клиент, клиент с другой версией) ничего не получают. До редакции 2026-11-15 здесь стояло «целое ≥ 1»; приведено к правилу D9 при сверке дельт (R1), поведение для клиента CodeLab v1 не меняется.
- Клиент принимает `_codelab/session/usage` и без объявления агента (как данные `_meta.codelab.task` по D9): объявление управляет только тем, что показывать до первого снимка (D8, «ожидание» против «агент не сообщает»).

*Почему не слать всем:* в отличие от `_meta` у стандартных обновлений, отдельное уведомление на каждом шаге — лишний трафик и записи в журналах стороннего клиента; без объявления не меняется ни один из 62 существующих кадров фикстур (D13).

### D4. Агрегаты в агенте: источник и отсутствие двойного учёта

Агрегаты считает `codelab_agent_acp` на **сессию сервера**, а не на соединение: все соединения сессии видят одни и те же числа и один `seq`. Сессия сервера — `SessionBridge` (D18 Т5): при переходе сессии к новому соединению (`reattach`) агрегаты и `seq` продолжаются без сброса (Q11 (а)).

1. **Шаг** — `StepEnded.result.usage` и `StepEnded.result.response.model`. Резервная модель и повторы уже внутри шага: `AssistantMessage` несёт сумму usage всех моделей и `model` ответившей (`agent-llm`, LLM-контракт); отдельно они не складываются.
2. **Ход во время хода** — сумма шагов этого хода.
3. **Ход в конце** — `TurnEnded.usage` (сумма шагов по `AgentLoop.run`), а не собственная сумма адаптера. Когда change `add-subagents-and-tasks` добавит usage детей в usage хода родителя (D4 того change, SUB-11), итог хода включит его без правки этого change; шаги детей до клиента как шаги корня не доходят. До итога хода живые снимки детей не учитывают — это записано в риске R3. *Сверка 2026-11-16:* уже сделано — `TurnEnded.usage` = свои шаги + дети, дети отдельно в `TurnEnded.subagentUsage` (D18, Т3; Q13 (б)).
4. **Сессия** — сумма итогов завершённых ходов плюс текущий ход по п. 2. Клиент суммы не считает (D8), поэтому дубли и несколько соединений ничего не удваивают.
5. **Ход без шагов** (встроенная команда `/status`, `/mode`, отмена до первого запроса; `/usage` в коде ещё нет — D18, Т7) — уведомления нет: расхода не было, а `agent-acp-server` «Встроенные команды» запрещает команде лишние кадры.
6. **Суммаризатор.** Usage вызова суммаризатора при сжатии в `TurnEnded.usage` не входит и в v1 в сумму сессии не попадает: события `ContextCompacted` его не несут. Учёт — change `add-usage-ledger` (`summaries` в §12.6.1). Записано в R2.
7. **Стоимость** считается в целых микродолларах: стоимость шага — `round(usage.cost.total × 10⁶)`, хода в конце — `round(TurnEnded.usage.cost.total × 10⁶)`, сессии — сумма микроединиц ходов. Сумма `double` по 1 000 ходам не накапливает ошибку (§12.1.5).

### D5. Заполнение контекста — из ядра

Адаптер токены не оценивает. `StepEnded` получает поле `context` (`ContextFill(used, window, compactAt)`; имя — исполнителю, смысл фиксирует это решение):
- `used` — `estimateContextTokens` по контексту цикла после добавления результатов инструментов шага; якорь — usage только что полученного ответа, поэтому оценивается лишь хвост результатов (§9.3);
- `window` — `effectiveContextWindow(model, cap: contextWindowCap)` модели, которая будет у следующего запроса;
- `compactAt` — порог автосжатия `afterTurn` в токенах (то же правило, что `shouldCompact` в `AgentRuntime`: окно минус `reserve_tokens`); рантайм передаёт его циклу через `AgentLoopConfig` вместе с `contextWindowCap`; при выключенном сжатии (`compaction.enabled: false` или профиль без сжатия) — `null`;
- без оценщика в `AgentLoopConfig` (`estimateTokens == null`) поле `null`, и `context` в уведомлении отсутствует. *Решение 2026-11-16 (Q10 (а)):* оценщик заполнения — отдельное поле `AgentLoopConfig.contextEstimator`, рантайм передаёт его всегда (`estimateLlmContext`), поэтому `context` есть и при выключенном автосжатии; `estimateTokens` и проверка перед запросом не меняются (D18 Т2).

После `ContextCompacted` адаптер шлёт снимок с `context.used = tokensAfter` и `size` и `compactAt` из последнего `StepEnded` этой сессии; если шагов в этом сервере ещё не было — без `context`.

*Альтернатива:* геттер `AgentSession.contextFill` — во время хода `Agent.messages` ещё не содержит сообщений хода (они добавляются после `runAgentLoop`), и значение отставало бы на ход.

### D6. Причины неполноты `partial`, версия 1

| Причина | Где | Когда |
|---|---|---|
| `noUsage` | шаг; ход и сессия — объединение | успешный ответ модели (`stopReason` не `error` и не `aborted`) с `input + output == 0`: настоящий ответ всегда тратит входные токены, значит провайдер usage не прислал (DF-15). Ответ с ошибкой и нулём — не причина |
| `noPrice` | шаг; ход и сессия — объединение | у модели шага нет цен (`ModelRef.cost == null`), а `input + output + cacheRead + cacheWrite > 0`; у итога хода (и сессии) ещё — `TurnEnded.subagentUsage` с ненулевыми токенами и нулевой стоимостью: цены моделей детей адаптеру не видны (Q13 (б); ложный «~» возможен только у явно бесплатной модели ребёнка) |
| `beforeLoad` | только сессия | сессия открыта в этом сервере через `session/load`, и в её журнале были ответы модели: ранние ходы в сумму не вошли. Снимается change `add-usage-ledger` (Q7 (а)) |

`cost` агрегата отсутствует, если ни у одного шага агрегата цена не известна; при смешанных — присутствует с `noPrice`. `cost` шага на модели с известными ценами присутствует всегда, при нуле токенов — `"0"` (причина `noUsage` остаётся): «бесплатно» и «цена неизвестна» различаются на проводе (решение пользователя 2026-11-16, D20). Клиент ставит «~» перед токенами при `noUsage` или `beforeLoad`, перед стоимостью — при любой причине (D8). Обнуляемые `cacheRead`/`cacheWrite` ядра в v1 не вводятся (Q2 (а)).

### D7. Порядок, дубли, поздние события, гонка отмены

- **Порядок на проводе.** Уведомление ставится в ту же `OutboundQueue` соединения, что и `session/update`, в момент проекции события. Снимок `turn` идёт после последнего `session/update` хода и до ответа на `session/prompt` — в том числе при `cancelled` и перед ошибкой `-32603` (ACP-3, ACP-5, ACP-7 не меняются). `session_info_update` с названием сессии — событие сессии после `TurnEnded`, а не обновление хода: оно идёт после снимка `turn` (D19 п. 5). Потраченное до отмены — настоящий расход, его нужно показать.
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
- каждый снимок с `turnId` заменяет `lastTurn` агрегатом `turn` (тот же `turnId` — ход идёт); снимок без `turnId` `lastTurn` не меняет; новый `turnId` без разобранного `turn` — `lastTurn` пуст; между ходами показывается последний ход (уточнено D22 п. 2);
- клиент суммы не считает и окно модели не оценивает: всё — из снимка (отличие от §12.1.5 п. 3 первой редакции, где клиент суммировал ходы сам; документ правится задачей 0.x);
- `SessionStatusBar` и `StatusBarProjector` из §12.1.1 этим change не вводятся: модель и режим клиенты уже берут из опций сессии, ветка git вне объёма (Q9 (б)), а второй слой ради одного поля — церемония. `SessionView.usage` — единственное новое поле.

*Альтернатива:* типизированная модель уведомления в `codelab_acp_protocol`, общая для агента и клиента. Отклонена ради единообразия: пакет протокола моделирует только вендоренную спецификацию, а все расширения `_meta.codelab.*` строятся адаптером и разбираются клиентом на краях (D2 change `add-subagents-and-tasks`); форму на проводе с обеих сторон закрепляют фикстуры с ролями `agent` и `client` (D13).

### D9. Деньги на проводе и в клиенте (решение пользователя, Q4 (а))

- На проводе — десятичная строка `^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$`: целая часть, точка и до 6 знаков без хвостовых нулей; ноль — `"0"`. Агент печатает её из целых микродолларов (D4, п. 7), поэтому строка детерминирована для фикстур. Валюта — `currency` в корне параметров.
- Клиент разбирает строку в `Money.micros` без `double`; больше 6 знаков, знак, экспонента или пустая строка — поле неверно (D8). `cost` без `currency` — тоже. Целая часть — не более 9 цифр (не более `999999999.999999`): тогда микроединицы меньше `2^53` и остаются точным целым и на web; большее значение — цена неизвестна, WARNING `usage.decode_failed` с `reason: wrong_format` (D22 п. 3).
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

Все новые — с меткой `usage` в `extensions` (FIX-4; у фикстур с инструментом `task_create` ещё `task`, D19 п. 8) и ссылками `spec` на `15-Extensibility.md` и `05-Prompt Turn.md`:

| Фикстура | Роли | Что |
|---|---|---|
| `acp/prompt-usage-steps` | `agent`, `client` | клиент объявил `usage`; два шага модели с ценами: `step` после каждого шага, `turn` перед ответом `end_turn`; `seq` 1…3; `context` с `compactAt` |
| `acp/prompt-usage-unpriced` | `agent` | модель без цен: шаг с токенами — `partial: ["noPrice"]`, шаг без usage — `["noUsage"]`; ход и сессия — `["noUsage","noPrice"]`; `cost` и `currency` нет (D19 п. 2) |
| `acp/prompt-usage-cancelled` | `agent` | отмена посреди инструмента: снимки `step` прерванного шага и `turn` после `tool_call_update` `failed` и до `stopReason: cancelled` |
| `acp/compact-usage-context` | `agent` | `/compact`: снимок `compaction`; `setup.config.compaction.keep_recent_tokens: 512`, поэтому только `conformance:agent`; чанк «Compacted…» и снимок — без фиксированного порядка; `context.used` — `$any`, неравенство проверяет `usage_projection_test.dart` (D19 п. 1, 5) |
| `acp/prompt-usage-compaction-off` | `agent` | `compaction.enabled: false`: `context` без `compactAt` |
| `acp/session-load-usage-partial` | `agent` | `session/load` журнала с ответами модели: снимков до хода нет, затем ход — `session.partial` содержит `beforeLoad` (Q7 (а)) |

Изменения существующих: `acp/initialize-codelab-extensions` (change `add-subagents-and-tasks`) ожидает `usage` в обоих блоках; клиентские фикстуры, где kit шлёт `initialize`, ожидают `usage` в `clientCapabilities._meta.codelab`; `acp/prompt-turn-budget-exceeded` роль `client` уже имеет (`roles` не задан — обе роли) и получает проверку причины `tokens` и заметки `budget exceeded: tokens` (где какая — D21 Т7). Фикстуры без объявления `usage` не меняются: это и есть проверка «стороннему клиенту ничего нового». Списки ожидаемого покрытия FIX-2 не затрагиваются: `_codelab/session/usage` не вид `sessionUpdate` и не метод `acp_method_codec.dart`.

Имя критерия L-11 в матрице `acp/prompt-usage-meta` меняется на `acp/prompt-usage-steps` (задача 0.7).

### D14. Наблюдаемость

- **Агент.** *Решение 2026-11-16 (Q14 (б), заменяет предложение ниже):* каждая отправка снимка — debug `acp.usage.sent {session_id, seq, trigger, turn_id?}`, без токенов и денег; `turn_id` — у `step` и `turn` (ход известен), у `compaction` его нет (D20 п. 5). Новых событий лога на шаг нет: usage хода уже пишет `turn.end`. При `initialize` в существующую запись согласованных возможностей соединения попадает `usage` (если запись есть; иначе — debug `acp.extensions.negotiated {keys}`; поле `connection` снято — D18 Т9, D19 п. 7). *Сверка 2026-11-16:* `turn.end` в коде нет, записи согласованных возможностей нет, id соединения в логах нет — D18, Т9; Q14 (б).
- **Клиент.** DEBUG `usage.received {session_id, seq, trigger}`; DEBUG `usage.stale {session_id, seq, last_seq}`; WARNING `usage.decode_failed {session_id, field, reason}` — не чаще раза на сессию и поле (как в дельте acp-client-kit). Окончательный состав записей и полей — D22 п. 1. Payload — только в developer-only трассировке протокола (`category=protocol`), как для пропущенных `session/update`. Секретов в уведомлении нет; id модели — не секрет.

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

Зависимости: 1 ← 0 и задачи 1.5, 1.6 change `add-subagents-and-tasks` (схема D9 в коде; Q8 (а)) — выполнено: задачи закрыты, итерации 1 и 2 того change влиты в `develop` (97e91de2), итерация 1 этого change разблокирована; 2 ← 1; 3 ← 2. Архивация — по-прежнему после change `add-subagents-and-tasks` (R1).

### D17. Соответствие правилам расширения ACP

Пользователь попросил расширить ACP, не нарушая правил документации протокола. Источник — `docs/protocols/acp/protocol/15-Extensibility.md` (разделы «The `_meta` Field», «Extension Methods», «Custom Notifications», «Advertising Custom Capabilities»); вендоренная спецификация не меняется (`AGENTS.md` §3.4). Пункт за пунктом:

1. **Свой метод — только с префиксом `_`.** Спецификация резервирует имена, начинающиеся с `_`, под расширения. Метод — `_codelab/session/usage`; пространство `_codelab/*` уже используется (`_codelab/session/steer`, §13.12), поэтому столкновения с будущими методами ACP нет. Пространство `_codelab/session/*` объединяет методы, относящиеся к сессии, но не одну capability: `_codelab/session/steer` объявляет `steering`, методы дерева сессии — `sessionTree`, а `_codelab/session/usage` — только ключ `usage`.
2. **Объявление через `_meta` capability-объектов в `initialize` (SHOULD).** Клиент объявляет `clientCapabilities._meta.codelab.usage: {"version": 1}`, агент отвечает `agentCapabilities._meta.codelab.usage: {"version": 1}` по схеме D9 change `add-subagents-and-tasks` (D3). Агент шлёт уведомление только соединению, объявившему `usage`, — строже, чем требует спецификация.
3. **Никаких своих полей в корне типов спецификации (MUST NOT).** Новых корневых полей нет ни в `InitializeRequest`/`InitializeResponse`, ни в `ClientCapabilities`/`AgentCapabilities`, ни в `PromptResponse`; нового значения `sessionUpdate` тоже нет — значения `SessionUpdate` перечисляет спецификация (`17-Schema.md`), и своё значение было бы тем же корневым расширением типа. Причина остановки по бюджету остаётся в `_meta.codelab.budgetExceeded` ответа `session/prompt` (D10). Ключи `traceparent`, `tracestate`, `baggage` корня `_meta` не используются: всё лежит под `_meta.codelab`.
4. **Получатель SHOULD игнорировать неизвестное уведомление.** Сторонний клиент (Zed), если бы и получил `_codelab/session/usage`, по спецификации его проигнорирует; по D3 он его не получает вовсе. Метод — уведомление, а не запрос: ответа нет, поэтому ни у одной стороны не возникает `-32601 Method not found` («Custom Requests»). Клиент CodeLab, получивший незнакомое уведомление `_codelab/*`, тоже лишь отбрасывает его (`acp-protocol-client`).
5. **Forward compatibility.** Версия — целое `version` в объявлении; неизвестные поля, ключи объявления и причины `partial` обе стороны игнорируют; новое необязательное поле добавляется без смены версии, изменение смысла — только `version: 2` и OpenSpec change (D2).

Проверки: сценарии `agent-acp-server` «Клиент без объявления» и «Стандартные типы без новых полей», `acp-protocol-client` «Запрос без новых корневых полей»; инвариант корпуса FIX-4 (фикстура без `extensions` не содержит `_codelab/*`).

### D18. Сверка с кодом перед итерацией 1 (2026-11-16, `develop` b05eea88)

Технические уточнения: имена, места в коде, существующие механизмы. Поведение и требования не меняются; расхождения, требовавшие решения пользователя, решены 2026-11-16 (Q10–Q14, раздел «Решения пользователя 2026-11-16»).

**Т1. События ядра** (`codelab_agent_core/lib/src/loop/agent_events.dart`, `loop_config.dart`):
- `StepEnded` сейчас несёт только `result: StepResult` (`stepIndex`, `response`, `results`, `usage`); поля заполнения контекста нет. Новое поле — `StepEnded.context` типа `ContextFill?` с целыми `used`, `window` и `int? compactAt` (имена из `agent-core/05-agent-loop.md`); тип объявляется рядом с событиями и экспортируется барелем ядра (адаптер видит ядро только через барель, `codelab_agent_acp/AGENTS.md` §2). `StepResult` не меняется: его получает и `prepareNextStep`, а заполнение нужно только событию.
- `TurnEnded` — `reason`, `usage`, `budgetExceeded`, `held`, `subagentUsage`; `turnId` у него нет. Адаптер берёт `turnId` из `TurnStarted.turnId` своего хода.
- `ContextCompacted(tokensBefore, tokensAfter)` эмитит `compaction/compactor.dart` при `/compact`, `afterTurn` и аварийном сжатии; реплей журнала (`session/projections.dart`) тоже отдаёт `ContextCompacted`, но реплей идёт мимо `_onEvent` моста (`SessionBridge.replayInto`) и в агрегаты не попадает.
- `StepEnded` эмитится и для шага с ошибкой или отменой (`stopReason` `error`/`aborted`, `results` пустой), и для синтетического `overflow` проверки перед запросом (`_exhausted`, usage нулевой). Для всех них заполнение считается одинаково; `noUsage` у них не ставится (D6).

**Т2. Вычисление заполнения** (`codelab_agent_core/lib/src/loop/agent_loop.dart`):
- Оценщик — `AgentLoopConfig.estimateTokens` типа `EstimateTokens = int Function(LlmContext)`; рантайм передаёт `estimateLlmContext` (`compaction/estimate.dart`, обёртка `estimateContextTokens` с якорем §9.3). Цикл оценивает `LlmContext(systemPrompt: _context.systemPrompt, messages: _transcript, tools: <схемы _context.tools>)` после `_append` всех результатов шага и до `emit(StepEnded)`; `transformContext` не применяется — та же база, что у проверки `afterTurn` (`_agent.messages`).
- Окно — `effectiveContextWindow(_config.model, cap: _config.contextWindowCap)` (`compaction/estimate.dart`). `StepEnded` эмитится до `prepareNextStep` (`agent_loop.dart`, «После `StepEnded`»), поэтому модель — текущая модель цикла; смена модели посреди хода видна со следующего `StepEnded` (Q12 (а): дельта `agent-loop` говорит «текущей модели цикла на момент `StepEnded`»).
- Порог — существующая функция `compactionThreshold(window, CompactionSettings.forWindow(window, overrides: …))` (`compaction/settings.dart`); `shouldCompact` — строго больше неё. Проверка `afterTurn` живёт в `_Session._compactAfterTurn` (`runtime/agent_runtime.dart`), а не в `AgentRuntime`; там же `_compaction` (`CompactionOverrides?`, `null` — capability `compaction` выключена). Цикл получает их новым полем `AgentLoopConfig.compaction` (`CompactionOverrides?`, `null` — автосжатие выключено, `compactAt = null`); рантайм ставит его при сборке `Agent` рядом с `contextWindowCap` и обновляет в `_Session._refreshSettings` тем же `copyWith`, что `contextWindowCap` (CFG-16: «со следующего хода»).
- `compaction.enabled: false` — ключ процесса: `buildAgentCore` выключает capability `compaction` (`host/build_agent_core.dart`), а сессия без неё получает `estimateTokens: null` (`agent_runtime.dart`, сборка `AgentLoopConfig`). Поэтому оценщик заполнения — отдельное поле `AgentLoopConfig.contextEstimator` (`EstimateTokens?`), которое рантайм передаёт всегда; `estimateTokens: compaction ? estimateLlmContext : null` и проверка перед запросом не меняются (Q10 (а)).

**Т3. Стоимость.** `UsageCost` — `double` в долларах по категориям; `Usage.cost` считает провайдерский поток (`llm/stream_state.dart`, `calculateCost(usage, model.cost)`), цены — `ModelCost` в долларах за 10⁶ токенов, `ModelRef.cost == null` — цены неизвестны. Микродоллары D4 п. 7 — `(cost.total * 1e6).round()` в адаптере; ядро не меняется. `TurnEnded.usage` уже включает usage детей (`_usage + _childUsage`, D36 Т8 change `add-subagents-and-tasks`), а `TurnEnded.subagentUsage` несёт их отдельно; цены моделей детей адаптеру не видны — эвристика `noPrice` по `subagentUsage` (D6, Q13 (б)).

**Т4. Объявление в `initialize`** (`codelab_agent_acp/lib/src/agent_server.dart`):
- Блок строит статический `_codelabExtensions(clientMeta, subagents)` соединения; ключ `usage: {"version": 1}` добавляется в его возвращаемый объект безусловно.
- Отдельного «флага объявления» в коде нет и не нужно: `clientCapabilities` соединения хранятся в `_client` и в `ClientLink.capabilities` (`connection/client_requests.dart`; `reattach` подменяет их на возможности нового соединения), а согласие читается чистой функцией в момент события — образец `subagentToolCallsConsent(acp.ClientCapabilities)` в `lib/src/subagent_chain.dart` (D47 Т3 change `add-subagents-and-tasks`). Для usage — такая же функция `usageConsent` по тому же правилу (объект, `version is int && version == 1`); где она лежит — решает исполнитель (рядом с агрегатами usage), общий помощник для двух ключей допустим, рефакторинг `subagentToolCallsConsent` — нет (AGENTS.md §19).
- Точные ожидания блока уже есть в `test/initialize_test.dart` и `test/initialize_subagents_test.dart` — их правит красный тест 1.2; отдельного `initialize_extensions_test.dart` нет.

**Т5. Отправка уведомления** (`codelab_agent_acp/lib/src/session_bridge.dart`, `connection/outbound_queue.dart`):
- «Сессия сервера» D4, D7 — объект `SessionBridge`: он один на `sessionId` в `_server._sessions`, переживает `reattach` и создаётся заново, только когда `session/load` открывает сессию, которой в сервере нет. Агрегаты, `seq` и признак `beforeLoad` живут в нём (или в небольшом объекте, которым он владеет).
- Мост ставит кадры через `sink: SessionUpdateSink = void Function(acp.SessionNotification)`, а `acp.encodeAcpNotification` принимает только методы ACP (`requireAcpMethod`). Кадр `_codelab/session/usage` строится напрямую `JsonRpcMessage.notification(method: …, params: …)` и уходит в ту же `OutboundQueue` соединения-владельца (`_AcpConnection._outbound`). Новый путь кадра ОБЯЗАН вести себя как `_send`: придерживаться в буфере реплея `_replayHeld` в общем порядке с `session/update`, глохнуть в `detach` (сейчас `sink = (_) {}`) и переключаться в `reattach` вместе с `sink`. Как именно (второй колбэк или общий тип кадра в буфере) — решает исполнитель.
- Снимок `turn` ставится в `_onEvent` на `TurnEnded`, то есть до `_finishTurn`: ответ `session/prompt` (в том числе ошибка `-32603`) и `session_info_update` с `_meta.codelab.turnEnded` у перенесённого хода (`_turnMoved`) уходят после него той же очередью (ACP-3).
- `projectEvent` (`lib/src/event_projection.dart`) — чистая функция, возвращающая только `acp.SessionUpdate`; уведомление в неё не входит. Таблица ACP-6 — константа `projectionTable` там же: строки `StepEnded`, `TurnEnded`, `ContextCompacted` получают текст с `_codelab/session/usage`. Тест таблицы — `test/projection/every_agent_event_is_projected_test.dart` (сейчас проверяет только состав ключей и непустые строки; задача 1.4 добавляет проверку этих трёх строк).
- Сессий с несколькими одновременными соединениями в коде нет: у моста один владелец, второй `session/load` во время хода получает `sessionBusy`, без хода — забирает сессию `reattach` (§13.7 п. 4: веер на все соединения — после MVP, SESM-15). Сценарий переписан под одного владельца — «Сессия перешла к новому соединению» (Q11 (а)).
- `beforeLoad` ставится только мосту, созданному веткой `_sessionLoad` без существующего моста, и только если в событиях реплея (`session.replay()`/`replayTree()`, которые `replayInto` уже читает) есть `AssistantMessage`; при `reattach` признак не меняется.

**Т6. `_codelab/session/steer` в коде нет** — только в документах (§17.7.3.1, `12-2-cli-display-and-input.md`); «по образцу» D1 относится к имени. `_codelab/session/usage` — первый метод `_codelab/*` на проводе: инвариант FIX-4 (`codelab_acp_testing/test/support/corpus_invariants.dart`) его уже знает, агентский драйвер сравнивает кадры как JSON без декодирования по методу.

**Т7. Встроенной команды `/usage` в коде нет**: `usage` только в `reservedCommandNames` (`commands/command_template.dart`), объявляются `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help` (`commands/builtin_commands.dart`); фикстуры `acp/usage-and-redact-commands` нет (она описана в §13.16 на после MVP). Проверка «ход без шагов» — на `/status` (D4 п. 5; сценарий «Встроенная команда без модели» дельты `agent-acp-server` поправлен так же).

**Т8. Фикстуры** (`codelab_acp_testing`):
- Цен модели в формате нет: `fixtureFormatKeys['llmModel']` — `provider`, `modelId`, `contextWindow` (и `_schema.json` так же). Чтобы `acp/prompt-usage-steps` шла «во всех режимах» (встроенный агент и `codelab-agent serve --stdio` пропускают фикстуры с `setup.config`, `apps/codelab_cli/lib/src/scenario/agent_connector.dart`), цены задаются в блоке `llm`: новое необязательное поле `llm.model.cost` — `{"input", "output", "cacheRead"?, "cacheWrite"?}`, доллары за 10⁶ токенов, как `ModelCost`; без поля цены неизвестны. `ScriptedStreamFunction` поле не читает (`llm.steps` прежний); читают его фабрика агентского прогона (`codelab_agent_acp/test/conformance_test.dart`, `_FixtureConfig.parse` → `_model`), `LlmScript._modelRefs` (`codelab_agent_io/lib/src/scripted/llm_script.dart`) для встроенного агента и `--llm-script`, и `withScriptedProviders` (`scripted_providers.dart`: ключи конфига `cost_input`, `cost_output`, `cost_cache_read`, `cost_cache_write`, `config/schema.dart`). Документ формата — `agent-core/14-golden-fixtures.md` §14.4, §14.7.
- usage шага в `llm.steps[].usage` уже есть (`Usage.fromJson`); стоимость шага пересчитывает поток по `model.cost`, поле `cost` в сценарии не нужно.
- Объявление клиента в новых фикстурах — через `setup.clientCapabilities` (преамбула `initialize` драйвера, `agent_conformance.dart`) с `_meta.codelab.usage`; метка расширения — `usage`.
- Фабрика агентского прогона принимает в `setup.config.compaction` только `keep_recent_tokens`; для `acp/prompt-usage-compaction-off` она получает ключ `enabled` (громкий провал неизвестных ключей сохраняется). Фикстуры с `setup.config` и `setup.sessions` (`acp/prompt-usage-compaction-off`, `acp/session-load-usage-partial`, а также `acp/compact-usage-context` — D19 п. 1) идут только в `conformance:agent`; остальные новые (`acp/prompt-usage-steps`, `-unpriced`, `-cancelled`) — без них, чтобы шли и в `conformance:embedded`.
- Разбиение по итерациям без красного `conformance:client` между PR: в итерации 1 у `acp/initialize-codelab-extensions` меняется только кадр `a2c` (ответ агента с `usage`) и `extensions` (`["capabilities", "usage"]`); кадр `c2a` клиента не меняется — блок агента от ключей клиента не зависит, а клиент незнакомый ключ ответа игнорирует. `usage` в `c2a` и в точных кадрах `initialize` клиентских фикстур (например, `acp/session-load-interrupted-turn`) добавляет задача 2.7. Новые фикстуры итерации 1 — с `roles: ["agent"]`; роль `client` у `acp/prompt-usage-steps` добавляет задача 2.7.

**Т9. Наблюдаемость.** Записи `turn.end` в коде нет (она описана в `12-observability-and-errors.md`, но не реализована), записи согласованных возможностей соединения тоже, а id соединения в полях логов адаптера нет. Поэтому D14 в части агента сводится к debug `acp.extensions.negotiated {keys}` при `initialize`, где `keys` — ключи `_meta.codelab` клиента, признанные согласованными; на отправку снимка — `acp.usage.sent {session_id, seq, trigger}` (Q14 (б)).

**Т10. Пути тестов итерации 1:** 1.1 — новый `codelab_agent_core/test/loop/agent_loop_context_fill_test.dart` на `test/loop/loop_harness.dart`; 1.2 — существующие `codelab_agent_acp/test/initialize_test.dart` и `initialize_subagents_test.dart`; 1.3 — новый `codelab_agent_acp/test/usage_projection_test.dart` на `test/support/server_harness.dart` (`ServerHarness`: `InProcessAcpLink`, `FakeClock`, `ScriptedStreamFunction`, `scriptedModel`, `JournalStore` для `session/load`); 1.4 — `codelab_agent_acp/test/projection/every_agent_event_is_projected_test.dart`; 1.9 — существующий `apps/codelab_agent/test/agent_host_test.dart` (в нём уже есть прогоны `--stdio` и `--ws`).

### D19. Допущения красных тестов итерации 1 (2026-11-16)

Технические уточнения, принятые исполнителем протокола при написании тестов 1.2–1.5a и фикстур D13 и принятые оркестратором. Требования и решения пользователя не меняются: каждое уточняет незаданную деталь формы D2 или порядок кадров, уже следующий из D7 и D18. Сверено с `codelab_agent_acp/test/usage_projection_test.dart`, `test/initialize_test.dart`, `codelab_acp_testing/test/fixtures_schema_sync_test.dart`, `fixtures_load_test.dart` и фикстурами `acp/{prompt-usage-*,compact-usage-context,session-load-usage-partial}`.

1. **`acp/compact-usage-context` с `setup.config`.** Фикстура несёт `setup.config.compaction.keep_recent_tokens: 512`, как `acp/slash-compact`: с порогом хвоста по умолчанию (16384 токена) короткая история фикстуры не сжимается, и `ContextCompacted` не возникает. Поэтому фикстура идёт только в `conformance:agent`, а не во встроенном агенте и не в `codelab-agent serve --stdio` (уточняет D13, D18 Т8, задачу 1.5).
2. **Причины `partial`.** У шага: токены без цен → `["noPrice"]`, успешный ответ без usage → `["noUsage"]`; обе сразу у шага не бывают — `noPrice` требует ненулевых токенов (D6). У хода и сессии — объединение причин шагов (у хода ещё эвристика `subagentUsage`, у сессии `beforeLoad`). Порядок в массиве — порядок строк таблицы D6: `noUsage`, `noPrice`, `beforeLoad`; клиент читает массив как множество (D8), порядок нужен только для точного сравнения кадров фикстур. Прежний текст D13 («`["noUsage","noPrice"]` у шага») исправлен.
3. **`session.turns`** — число ходов сессии сервера, в которых был хотя бы один `StepEnded`, включая текущий: в снимке `step` первого хода `turns == 1`. Ход без шагов (`/status`) не считается — снимков у него нет (D4 п. 5).
4. **`context` снимка `turn`** равен `context` последнего `StepEnded` хода; нового вычисления на `TurnEnded` нет.
5. **Порядок кадров.** Снимок `turn` идёт до необязательного `session_info_update` с названием сессии: название — событие сессии `SessionTitleChanged`, которое рантайм публикует после `TurnEnded` (`_afterTurn`), а снимок `turn` ставится в `_onEvent(TurnEnded)` (D18 Т5). В `acp/compact-usage-context` чанк отчёта «Compacted…» и снимок `compaction` проверяются без фиксированного порядка (`unordered`): порядок кадров одного события спецификация не задаёт.
6. **Формат фикстур.** Объект цен в `fixtureFormatKeys` и `_schema.json` называется `llmModelCost`: ключи `input`, `output` (обязательные), `cacheRead`, `cacheWrite`, все — числа; `llmModel` получает ключ `cost` (задача 1.6a).
7. **Наблюдаемость `initialize`.** Debug `acp.extensions.negotiated {keys}` — одна запись на `initialize`; `keys` — список строк: ключи `_meta.codelab` клиента, признанные согласованными (известный ключ и версия); неизвестные ключи и `usage` другой версии в него не входят. Поля `connection` нет (D14, D18 Т9).
8. **Метки фикстур.** `acp/prompt-usage-steps` и `acp/prompt-usage-unpriced` вызывают `task_create`, поэтому кроме `usage` несут метку `task` (FIX-4); прежняя формулировка «с `extensions: ["usage"]`» в D13 и дельте `acp-golden-fixtures` заменена на «`extensions` содержит `usage`».
9. **Отмена.** В `acp/prompt-usage-cancelled` перед снимком `turn` идёт снимок `step` прерванного шага: ответ модели получен, его расход учитывается (D7, «потраченное до отмены — настоящий расход»).

Ни одно допущение не вводит нового поля, значения или метода на проводе и не меняет видимого клиенту поведения сверх D2, D6, D7.

### D20. Исправления по двойному ревью итерации 1 (2026-11-16)

Решения пользователя 2026-11-16 после ревью архитектуры и безопасности итерации 1. Новых методов, полей и значений на проводе нет; уточняются граничные случаи D2, D6, D9, D14 и формат входных цен.

1. **`cost "0"` у шага с ценами.** У шага на модели с известными ценами `cost` есть всегда; при нуле токенов — `"0"`, причина `noUsage` остаётся (D6, D9: ноль — `"0"`). Прежняя строка дельты `agent-acp-server` («`cost` отсутствует, если ни у одной модели шагов агрегата нет цен») читалась наоборот и заменена явным правилом присутствия; добавлен сценарий «Шаг без usage на модели с ценами». *Альтернатива:* опускать `cost` при нуле токенов — клиент показал бы «—» вместо `$0` у модели с ценами, и «бесплатно» смешалось бы с «неизвестно» (DSK-11).
2. **Проверка цен на входе.** Находка ревью безопасности: `cost_input: .inf` в конфиге давал `Infinity` в `UsageCost`, `(Infinity * 1e6).round()` бросал `UnsupportedError` в `SessionBridge._onEvent`, и любой клиент получал `-32603` на каждый ход; отрицательная цена печаталась как `"0.999999"` (остаток от деления отрицательных микроединиц). Поэтому `cost_input`/`cost_output`/`cost_cache_read`/`cost_cache_write` принимают только неотрицательные конечные числа — проблема ключа с текстом `must be a finite number not less than 0` при загрузке и в `config check` (ядро, `config/resolve.dart`, `_modelInfo`; новое требование `agent-configuration` «Цены моделей конфигурации»: ADDED, а не MODIFIED «Схема и строгая проверка», потому что то требование уже меняет активный change `add-agent-skills`); то же для `llm.model.cost` фикстур (отрицательное и не число — `FixtureFormatException` с путём `$.llm.model.cost.<ключ>`; не конечное `1e999` раньше разбора полей отсекает канонизация `AcpFixture.fromJson` — путь `$`, «is not JSON») и `--llm-script`/`LlmScript` (`LlmScriptException` `llm.model.cost.<key>: must be a finite number not less than 0` вместо молчаливого `cost == null`). Документы: `agent-core/15-configuration.md` (таблица ключей модели), `agent-core/14-golden-fixtures.md` §14.7.
3. **Защита адаптера.** Проверка на входе не закрывает переполнение: конечные большие цены × большие токены дают `Infinity`, а сторонний `ModelCost` в коде встраивающего хоста проверку конфига обходит. Поэтому `_micros` в `usage_accounting.dart` считает стоимость неизвестной (`noPrice`, 0 микроединиц), если она не конечна, отрицательна или больше `2^53 − 1` микроединиц (предел точного целого на web; `codelab_agent_acp` web-безопасен, D15); если невалиден итог `TurnEnded.usage`, у хода `cost` нет и есть `noPrice` (*техническое решение оркестратора 2026-11-16 по коду:* итог берётся из ядра и включает детей, поэтому невалидному итогу нельзя доверять; сумма корректных микроединиц шагов, предложенная сначала, не учла бы детей и выдала бы заниженную стоимость за точную). Ход не падает. *Альтернатива:* ошибка хода — расход уже случился, и прерывать ход из-за учёта хуже, чем показать «~».
4. **Согласие и учёт в одном месте.** `usageConsent` переезжает из `subagent_chain.dart` в `usage_accounting.dart`; признание ключа согласованным (`initialize`: `acp.extensions.negotiated.keys`, и момент события: `usageConsent`) — одна функция, чтобы лог и поведение не расходились (D19 п. 7). `stepEnded` возвращает `bool` «снимок нужен» вместо побочного состояния; `usageSink` — обязательный параметр и конструктора `SessionBridge`, и `reattach`, без подстановки `?? ((_) {})`: мост, созданный или перешедший к новому соединению без приёмника, терял бы снимки молча (Q11 (а); *техническое решение оркестратора 2026-11-16*).
5. **`turn_id` в `acp.usage.sent`.** Для корреляции с записями хода (§16 AGENTS.md: `session_id`, `request_id`, `tool_call_id`) запись получает `turn_id` у `step` и `turn`; у `compaction` хода нет (D14). Токенов и денег по-прежнему нет (Q14 (б)).
6. **Незакрытый ход.** Ядро обещает ровно одно `TurnEnded` последним событием хода (LOOP-1, `agent_loop.dart`); проверено, держится ли это обещание на всех путях рантайма. *Итог проверки 2026-11-16 (задачи 1.18, 1.20):* `AgentLoop.run` ловит исключение хода, публикует `AgentError` и безусловно выпускает `TurnEnded` (LOOP-1); встроенные команды `agent_runtime.dart` завершаются `TurnEnded` в каждой ветке. Пути без `TurnEnded` нет, поэтому кода переноса незакрытого хода в `UsageAccounting` нет; гарантия описана в doc-комментарии `UsageAccounting.turnStarted`.
7. **`AgentLoopConfig.copyWith`.** `compaction` может быть `null` осмысленно (автосжатие выключено, Q10 (а)), поэтому `copyWith` принимает запись `({CompactionOverrides? value})?`: `null` — не менять, `(value: null)` — сбросить. Это внутренний API ядра, поведение на проводе не меняется.
8. **Придержанный кадр и согласие.** *Находка ревью безопасности, техническое решение оркестратора 2026-11-16.* Кадр `_codelab/session/usage`, поставленный в буфер реплея `_replayHeld`, проверял согласие только при постановке: соединение A с `usage` → кадр придержан → A рвётся → соединение B без `usage` загружает сессию (`reattach`) → при выпуске буфера кадр уходил B. Правило: придержанный usage-кадр НЕ уходит соединению без согласия — ни сразу, ни при выпуске буфера после `reattach`. Способ выбирает исполнитель: при выпуске заново проверить согласие текущего соединения (`usageConsent` текущих возможностей) либо очищать придержанные usage-кадры при `detach`. Оба способа удовлетворяют сценарию «Придержанный снимок и соединение без согласия» дельты `agent-acp-server`; `seq` у сессии сервера не откатывается (пропуск номера клиент переносит, D7). Придержанные `session/update` не затрагиваются. *Альтернатива:* полагаться на согласие в момент постановки — передаёт данные о расходе соединению, которое их не запрашивало (D3: шлём только объявившему).
9. **Покрытие граничных случаев стоимости.** Сценарии «Шаг без usage на модели с ценами» и «Не конечная стоимость» проверяют два файла: `codelab_agent_acp/test/usage_bridge_test.dart` — `cost "0"` при нуле токенов, `Infinity`/`NaN` и переполнение больше `2^53 − 1` микроединиц (на уровне моста, без ядра); `usage_projection_test.dart` — отрицательная цена через ядро (`ServerHarness`).

### D21. Сверка с кодом перед итерацией 2 (2026-11-16, `develop` fd979232)

Технические уточнения клиентского слоя: места в коде, существующие механизмы, пути тестов. Поведение и решения пользователя не меняются; вопрос сверки решён пользователем 2026-11-16 — Q15 (б), раздел «Решения пользователя 2026-11-16». Итерация 1 этого change и итерации 1–6 change `add-subagents-and-tasks` влиты.

**Т1. Объявление** (`codelab_client_acp/lib/src/domain/codelab_extensions.dart`):
- Блок клиента — константа `codelabClientExtensionsMeta` (строки 22–28: `tasks`, `subagents`, `subagentToolCalls`); `AcpClientApplication` кладёт её в `ClientCapabilities.meta` при `initialize` (`acp_client_application.dart`, строка 696). Ключ `usage: {"version": 1}` добавляется туда же.
- Согласованные расширения — `CodelabExtensions.parse` (строки 52–79) по правилу «объект с `version is int && == 1`»; доступ — `ClientConnectionReady.codelabExtensions`. Признак `usage` — новое поле `CodelabExtensions.usage` тем же `known('usage')`. Оговорка строк 59–61 действует и для `usage`: на web `1.0 is int` истинно, поэтому сценарий «Версия usage не целое 1» с `1.0` проверяется только на VM.
- Точные ожидания: `test/application/initialize_codelab_request_test.dart` (строка 48 — весь `_meta` запроса), `test/application/initialize_codelab_extensions_test.dart` (разбор ответа). Пути задачи 2.1 исправлены: в `test/` без `application/` таких файлов нет.
- Механизм D9 после слияний не менялся: правило `known` и состав ключей — прежние, требование «Объявление расширений CodeLab при initialize» change `add-subagents-and-tasks` не менялось после пересборки 264375a2 — каждая его строка есть в дельте `acp-protocol-client` этого change (повтор сверки задачи 0.8; пересборка не нужна).

**Т2. Маршрут уведомления** (`acp_client_application.dart`):
- `_handleInboundMessage`: `case JsonRpcNotification(): break` (строки 1199–1202) отбрасывает любое незнакомое уведомление; маршрута своих методов `_codelab/*` нет — `_codelab/session/usage` первый. Новая ветка `case JsonRpcNotification(method: '_codelab/session/usage')` стоит перед общей.
- Защита от поздних событий уже есть и стоит раньше маршрутизации: `_bindTransport` (строки 1066–1083) запоминает поколение подписки и отбрасывает входящее сообщение прежнего транспорта с DEBUG `event_ignored {reason: stale_generation, kind: inbound_message}`. Поэтому уведомление старого соединения до маршрута не доходит, и «пометить его прежним поколением» нечем; сценарий «Уведомление старого соединения» дельты `acp-protocol-client` переписан под этот механизм, наблюдаемое поведение (состояние не меняется) прежнее.
- Поколение (`_generation`, публичный геттер `generation`) всё же передаётся вместе с уведомлением: kit сбрасывает `lastSeq` по смене поколения, а не по началу своего `reconnect`. Начало `reconnect` в kit (`_SessionHandle.suspend`) наступает раньше, чем `_generation++` в `_replaceTransport` (строка 814), и снимок старого агента, пришедший в этом окне, после сброса поднял бы `lastSeq`, а снимок `seq: 1` нового агента был бы отброшен.
- Доставка — новый публичный broadcast-поток `AcpClientApplication` (`sync: true`, как `sessionChanges`; закрывается в `dispose`) с записью «`sessionId`, `params`, поколение»; имя — исполнителю. Уведомление без строкового `params.sessionId` отбрасывается в `codelab_client_acp` с DEBUG без payload. Порт `AgentBackend` (`codelab_client_core/lib/src/backend/agent_backend.dart`) получает зеркальный член; реализация одна — `AcpClientBackend`, тестовых подделок порта нет (все тесты kit строят `AcpClientBackend(application)`).
- Регрессия «другие `_vendor/*` отбрасываются» уже есть: `codelab_client_acp/test/unsupported_agent_requests_test.dart`, «an unknown notification gets no reply and is not an error».

**Т3. Причина бюджета** (`acp_client_application.dart`, `sendPrompt`, строки 473–530): ответ `PromptResponse` уже несёт `meta` (`codelab_acp_protocol/lib/src/acp/prompt.dart`, строка 376). Путь итога — `SessionStateMachine.completeTurn(stopReason:)` (`state_machines.dart`, строка 895) → событие `SessionStateEvent.completeTurn` → `PromptTurnStateMachine.complete`; `PromptTurn` (`domain_models.dart`, строка 83, freezed) получает `String? budgetExceeded`, и параметр проходит тем же путём. Значения агента — `BudgetLimit.name` (`steps`, `tokens`, `cost`, `duration`, `deadline`; `codelab_agent_core/lib/src/loop/turn_budget.dart`, проекция — `codelab_agent_acp/lib/src/event_projection.dart`, `turnResponse`) — совпадают с D10. Итог перенесённого хода (`session_info_update` с `_meta.codelab.turnEnded`) клиент не читает вовсе; причина бюджета в нём вне объёма.

**Т4. Модель kit** (`codelab_client_core`):
- `SessionView` объявлен в `lib/src/workspace/workspace_state.dart` (строка 66), а не в `session/`; собирает его `_SessionHandle` (`lib/src/workspace/client_workspace.dart`, строки 1135–1600) в `_sessionFields` из `AcpSession`. План и строки Agents (образец change `add-subagents-and-tasks`) выводятся из `AcpSession` целиком (`planOf`, `subagentRowsOf` с памятью `SubagentRowMemory`, которой владеет handle). Usage — первое состояние kit не из `AcpSession`: handle получает отдельный метод применения снимка, который публикует `revision + 1` только при применённом снимке; `_sessionFields` поле `usage` не трогает.
- Свёртка (`seq`, поколение, `lastTurn` по `turnId`) — чистый класс в `lib/src/usage/` рядом с `UsageDecoder`, без зависимости от `ClientWorkspace`: его использует и тест корпуса (Т7).
- Сброс: `session/load` — в `_SessionHandle.reload` (строка 1504; через `_track` с `_reloading` его вызывает и перезагрузка сессий после `reconnect`); смена соединения — по поколению уведомления (Т2) и по новому `ClientConnectionReady` для сессий, которые новое соединение не загрузило (`detached`). Объявлен ли `usage` — `CodelabExtensions.parse(capabilities.meta).usage` по `_capabilitiesOf` (строка 1019).
- Неизвестная сессия: `_handles` без `sessionId` → снимок отброшен (DEBUG).

**Т5. Наблюдаемость клиента (D14).** В `codelab_client_core/lib` логгера сейчас нет. DEBUG `usage.received {session_id, seq, trigger}` и отброс без `sessionId` пишет маршрут в `codelab_client_acp` (логгер с `connection_generation` там есть; payload — только в трассировке `category=protocol`, которая уже пишет каждое входящее сообщение). `usage.stale`, `usage.decode_failed` и отброс неизвестной сессии пишет kit: `ClientWorkspace` получает необязательный `Logger` (интерфейс `codelab_client_acp`, `domain/logger.dart`; по умолчанию — `StructuredLogLogger`, как у `AcpClientApplication`). Новых зависимостей нет: оба типа экспортирует `codelab_client_acp`. *Альтернатива:* `WorkspaceDiagnostic` — отклонена: это видимая пользователю диагностика, а D14 требует записи журнала.

**Т6. Заметка бюджета** (`codelab_client_core/lib/src/transcript/transcript_projector.dart`): текст строит `_stoppedNoticeText(StopReason?)` (строки 629–636), общий для инкрементальной проекции и эталона `projectTranscript`, поэтому свойство «инкрементальная = с нуля» сохраняется; функция начинает принимать ход (`stopReason` и `budgetExceeded`). Основная спецификация `acp-client-kit`, требование «Инкрементальная проекция транскрипта», задаёт текст `max_turn_requests` безусловно, и отдельное ADDED-требование ему противоречило бы после архивации: дельта переписана в MODIFIED этого требования с прежним текстом и сценариями плюс правило причины бюджета и два сценария. Существующий тест `transcript_projector_test.dart` «max_turn_requests gives its own text» (ход без причины) остаётся зелёным.

**Т7. Фикстуры и клиентский прогон** (`codelab_acp_testing`, `codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart`):
- `conformance:client` — это `fvm dart test packages/dart/codelab_client_acp/test/fixtures` против `AcpClientApplication` (корневой `pubspec.yaml`); `codelab_client_acp` не зависит от `codelab_client_core`, поэтому `SessionView.usage` и текст заметки там не проверить. Разбиение: проверка состояния `acp/prompt-usage-steps` в `_stateChecks` — ход завершён, ядро клиента доставило три снимка (`seq` 1…3, последний `turn`); `acp/prompt-turn-budget-exceeded` (роль `client` уже есть: `roles` не задан, проверка `maxed` — в `_stateChecks`) — причина `tokens`; `acp/prompt-max-turn-requests` — причина `steps`. `SessionView.usage` после `acp/prompt-usage-steps` и заметку бюджета проверяет новый тест `codelab_client_core/test/usage/usage_fixture_test.dart` на `runClientFixture` (как `test/transcript/transcript_projector_test.dart`; `14-golden-fixtures.md` §14.10 допускает фабрику клиента kit); его запускает `fvm dart test` пакета, а не `conformance:client`.
- Сравнение кадров: `_meta` сравнивается частично только на своём уровне, `_meta.codelab` — точно (`lib/src/fixtures/matcher.dart`, `_compareObject` и `_compare`, строки 255–371). Поэтому после добавления `usage` в объявление клиента красными в клиентском прогоне станут все фикстуры с ролью `client`, где кадр `initialize` клиента задан явно с `_meta.codelab`: `acp/initialize-codelab-extensions`, `acp/session-load-interrupted-turn`, `acp/session-new-modes-config`, `acp/set-config-option-model` (у двух последних — внутри `$partial`, но `codelab` всё равно точный). В агентском прогоне их кадры уходят агенту как есть; шагов модели в них нет, поэтому новых кадров `_codelab/session/usage` не появится. Точное ожидание блока клиента есть ещё в `codelab_acp_testing/test/fixtures_load_test.dart` (строки 318–328) — его правит та же задача.
- Handshake клиентского прогона (`lib/src/fixtures/client_conformance.dart`, `_handshake`, строки 466–487) сверяет `clientCapabilities` как `$partial` от `setup.clientCapabilities`, но `_meta.codelab` внутри — точно, а ответ агента — `agentCapabilities: {}` (usage не согласован: в клиентском прогоне `acp/prompt-usage-steps` `support` идёт `unknown` → `reported`). Следствия: `acp/prompt-usage-steps` с `setup.clientCapabilities._meta.codelab: {usage}` в клиентском прогоне красная при любом объявлении клиента; `acp/prompt-subagent-tool-tree` и `acp/session-load-subagent-tool-tree` (роли `agent`, `client`, объявление без `usage`) станут красными с задачей 2.8. Тот же `setup.clientCapabilities` агентский драйвер шлёт агенту буквально (`agent_conformance.dart`, `agentFixtureHandshake`), поэтому `usage` в нём включает снимки в агентском прогоне. Решение пользователя 2026-11-16 — Q15 (б): сверка `_meta.codelab` handshake как подмножества.

**Т8. Пути тестов итерации 2:** 2.1 — существующие `codelab_client_acp/test/application/initialize_codelab_request_test.dart` и `initialize_codelab_extensions_test.dart`; 2.2 — новый `codelab_client_acp/test/application/usage_notification_test.dart` (тесты приложения лежат в `test/application/`); 2.3 — новый `codelab_client_acp/test/application/budget_exceeded_test.dart`; 2.4, 2.5 — новые `codelab_client_core/test/usage/usage_decoder_test.dart`, `session_usage_test.dart` (каталога `test/usage/` ещё нет); 2.6 — новый `codelab_client_core/test/transcript/budget_notice_test.dart`; 2.7 — Т7. У `codelab_client_acp` и `codelab_acp_testing` вложенного `AGENTS.md` нет: действуют корневой и `codelab_client_core/AGENTS.md` (§5 — разбор `_meta.codelab.*` только в `codelab_client_acp` и kit; §3 — kit опирается на отбрасывание поздних событий бэкендом).

### D22. Исправления по двойному ревью итерации 2 (2026-11-16)

Технические решения оркестратора 2026-11-16 по ревью архитектуры и безопасности итерации 2. Новых методов, полей и значений на проводе нет; уточняются наблюдаемость клиента (D14, D21 Т5), свёртка `lastTurn` (D8) и разбор денег (D9).

1. **Записи журнала клиента.** Отбросы получают имена, у записей kit есть корреляция с соединением (§16 `AGENTS.md`):
   - `codelab_client_acp`: DEBUG `usage.received {session_id, seq, trigger}`, где `trigger` — только `step`, `turn` или `compaction`, любое другое значение пишется как `other` (строка агента не попадает в журнал как есть); DEBUG `usage.dropped {reason}` — уведомление без строкового `sessionId`, без payload;
   - kit (`ClientWorkspace`): DEBUG `usage.stale {session_id, seq, last_seq, connection_generation}` — только дубль или опоздание по `seq`; DEBUG `usage.unknown_session {session_id, connection_generation}` — снимок сессии, которой нет в рабочем пространстве (прежняя формулировка «`usage.stale` без `last_seq` для неизвестной сессии» снята); WARNING `usage.decode_failed {session_id, field, reason, connection_generation}` — не чаще раза на сессию и поле.
   Сумм, цен и текста уведомления в записях по-прежнему нет. Документ — `docs/architecture/observability.md`, раздел о `_codelab/session/usage`.
   *Альтернатива:* одна запись `usage.stale` с необязательным `last_seq` для всех отбросов kit — отклонена: по журналу не отличить опоздание от снимка чужой или закрытой сессии.
2. **`lastTurn` привязан к `turnId`.** Каждый снимок с `turnId` заменяет `lastTurn` агрегатом `turn` этого снимка (тот же `turnId` — ход идёт, итог обновляется); снимок без `turnId` (`compaction`) `lastTurn` не меняет; новый `turnId` без разобранного `turn` (поле отсутствует или неверно) — `lastTurn` пуст, а не итог прежнего хода. Для корректного агента (D2: `turn` есть у каждого снимка `step` и `turn`) поведение прежнее; правило убирает показ итога чужого хода под новым `turnId`. Дельта `acp-client-kit`, `12-1-view-model.md` §12.1.5 п. 3.
3. **Предел денег клиента.** Целая часть `cost` — не более 9 цифр (значение не более `999999999.999999`): микроединицы тогда меньше `10^15 < 2^53` и точно представимы целым и на web, где `int` — `double`. Большее значение — цена неизвестна (поле `cost` отсутствует), WARNING `usage.decode_failed` с `reason: wrong_format` (D9). Агент таких сумм не шлёт: его предел — `2^53 − 1` микроединиц (D20 п. 3), а реальные суммы на порядки меньше. *Альтернатива:* `BigInt` — точно при любой длине, но ради недостижимых сумм тянет второй тип денег во всю модель и UI.
4. **`compactionSoon` без переполнения.** Порог `used ≥ 0.9 × compactAt` считается в целых без промежуточных значений больше `2^53` (никакого `used × 10` или `compactAt × 9` на больших числах), поэтому при любых разобранных `used` и `compactAt` результат одинаков на VM и web и не переполняется.

## Risks / Trade-offs

- **R1. Пересечение дельт с `add-subagents-and-tasks`.** Оба change меняют требования `initialize` и «Расширения протокола этапа 4» (`agent-acp-server`) и «Объявление расширений CodeLab при initialize» (`acp-protocol-client`). Дельты этого change написаны поверх текста того change (объединение), поэтому этот change архивируется после него (решение пользователя, Q8 (а)). Сверено 2026-11-15 после влития итерации 2 того change (97e91de2): три MODIFIED-требования пересобраны из его текущего текста — все его строки сохранены дословно, сверху добавлены только ключ `usage`, правило объявления клиента, строка `_codelab/session/usage` в «Расширениях протокола этапа 4» и сценарии с пометкой «(usage)»; правило версии объявления `usage` приведено к D9 (D3). Если тот change снова изменит эти требования до архивации, дельты этого change СЛЕДУЕТ пересобрать тем же способом (задача 0.8).
- **R2. Недосчёт суммаризатора.** Сумма сессии в v1 не включает вызовы суммаризатора (D4, п. 6) и после `add-usage-ledger` может вырасти на их величину. Альтернатива — причина `partial` после каждого сжатия — сделала бы «~» постоянным у длинных сессий без пользы.
- **R3. Субагенты в живых снимках.** До итога хода расход детей не виден; в итоге хода он появляется скачком (D4, п. 3). Панель Agents показывает итог ребёнка отдельно (D24 того change). Неизвестные цены моделей детей ловит эвристика `noPrice` по `subagentUsage` (D6, Q13 (б)); `noUsage` детей адаптер не видит.
- **R4. Эвристика `noUsage`.** Нулевой `input + output` у успешного ответа считается «провайдер не сообщил». Ложное срабатывание невозможно для настоящего ответа модели; scripted-модель без `usage` в фикстурах даёт `noUsage` — это ожидаемо и проверяется фикстурой `acp/prompt-usage-unpriced`.
- **R5. `beforeLoad` почти всегда после перезапуска.** Внешний агент по stdio живёт столько же, сколько соединение, поэтому после перезапуска клиента сумма сессии — «~» до change `add-usage-ledger` (Q7 (а)).
- **R6. Объём трафика.** Одно уведомление на шаг (не на дельту) — порядка десятков на ход; дешевле, чем поток `agent_message_chunk`.
- **R7. Гонки.** Порядок «снимок `turn` → ответ» обеспечивает очередь соединения, а не дисциплина (§13.15); на клиенте `seq` закрывает дубли, опоздания и несколько соединений (D7).
- **R8. Бесконечная цена от встраивающего хоста (вне объёма).** Сторонний `ModelCost` с бесконечной или не числовой ценой, переданный встраивающим хостом мимо конфигурации, ломает запись журнала сессии в ядре (`storage`, кодирование `Usage` в JSON) раньше, чем адаптер успевает отсечь стоимость (D20 п. 3). Конфигурация (`_modelInfo`), фикстуры и `--llm-script` такие цены уже отклоняют (D20 п. 2), поэтому из продукта путь недостижим. Защита в ядре — отдельный change в зоне `codelab_agent_core` по решению пользователя; этот change её не вводит.

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
- **Q8 — (а):** итерация 1 стартует после задач 1.5 и 1.6 change `add-subagents-and-tasks`; архивация — после него (D16, R1). Условие старта выполнено 2026-11-15 (97e91de2).
- **Q9 — (б):** TUI-статус-строка и строка статуса после хода в REPL на `ansi`/`plain`; ветка git — вне change (D12).

Отклонённые варианты и их доводы — в D1 (альтернативы формы), D5, D9, D10.

## Решения пользователя 2026-11-16

Вопросы сверки с кодом (D18):
- **Q10 — (а):** отдельное поле оценщика заполнения `AgentLoopConfig.contextEstimator`, рантайм передаёт его всегда; `estimateTokens`, проверка перед запросом и поведение этапа 2 не меняются; сценарии «Автосжатие выключено» и фикстура `acp/prompt-usage-compaction-off` остаются (`used` и `size` без `compactAt`) (D5, D18 Т2). Отклонены: (б) всегда передавать `estimateTokens` — синтетический `overflow` без сжатия ломает контракт этапа 2; (в) без автосжатия `context` нет вовсе.
- **Q11 — (а):** сценарий «Два соединения одной сессии» заменён сценарием «Сессия перешла к новому соединению»: после `reattach` снимки получает новое соединение, `seq` продолжает счёт моста без сброса (D1, D4, D18 Т5). Отклонено (б) — оставить сценарий до SESM-15.
- **Q12 — (а)** (техническое решение оркестратора): `window` — по текущей модели цикла на момент `StepEnded`; смена модели посреди хода видна со следующего шага (дельта `agent-loop`, D18 Т2). Отклонено (б) — перенос `StepEnded` за `prepareNextStep` меняет порядок событий.
- **Q13 — (б):** эвристика `noPrice` у хода и сессии по `TurnEnded.subagentUsage` с ненулевыми токенами и нулевой стоимостью (D6, R3). Отклонены: (а) принять без «~»; (в) признак цены в ядре — правка ядра ради редкого случая.
- **Q14 — (б):** debug `acp.usage.sent {session_id, seq, trigger}` без сумм и денег (D14, D18 Т9). Отклонены: (а) без записи; (в) `turn.end` по §12 — вне объёма.

Вопрос сверки клиентского слоя (D21):
- **Q15 — (б):** клиентский драйвер фикстур (`codelab_acp_testing/lib/src/fixtures/client_conformance.dart`, `_handshake`) сверяет `_meta.codelab` из `setup.clientCapabilities` как подмножество: каждый указанный ключ — точно, лишние ключи объявления клиента допустимы. Агентский прогон и кадры фикстур не меняются; `acp/prompt-usage-steps` получает роль `client` с `setup.clientCapabilities._meta.codelab` только с `usage`; фикстуры дерева субагентов не правятся. Полное объявление клиента точно проверяют четыре фикстуры с явным кадром `initialize` (`acp/initialize-codelab-extensions`, `acp/session-load-interrupted-turn`, `acp/session-new-modes-config`, `acp/set-config-option-model`) и `initialize_codelab_request_test.dart` (D21 Т7; дельта `acp-golden-fixtures`, сценарий «Объявление клиента в handshake — подмножество»; документ `14-golden-fixtures.md` §14.7, §14.10 — задача 2.7). Отклонены: (а) точное сравнение с полным объявлением в `setup.clientCapabilities` и кадрами usage в фикстурах дерева — связывает фикстуры разных расширений; (в) без роли `client` у `acp/prompt-usage-steps` — расходится с D13.

## Open Questions

Нет.
