## Why

Ядро Dart-агента уже считает usage и стоимость каждого шага (`Usage`, `UsageCost`, `calculateCost`, `StepEnded`, `TurnEnded.usage`; `agent-core-architecture` §2.12, §12.6), но клиенту их не передаёт: в вендоренной спецификации ACP (`docs/protocols/acp/protocol/`) нет ни поля, ни вида обновления для usage, а придумывать их запрещено (`AGENTS.md` §3.4). Поэтому строка статуса рабочего места и статус-строка CLI не показывают ни токены, ни стоимость, ни заполнение контекста (VIEW-6, DSK-11 сейчас выполняются тривиально: данных нет никогда). Причину остановки хода по бюджету (`_meta.codelab.budgetExceeded`, C-13) агент уже отправляет, а клиент её не читает: пользователь видит «The turn reached the limit of model requests» даже тогда, когда ход остановил лимит стоимости.

Change вводит расширение CodeLab для usage — первый из четырёх changes панели Usage (экран 17; пул 1.x, `delivery-roadmap.md` §4.6, §6.2 п. 1; цели L-11, U-13, D-09; инварианты DSK-11, VIEW-6). Открытый вопрос `agent-core/16-non-mvp-and-open-questions.md` §16.3 «Передача usage и стоимости клиенту» закрывается этим change.

## What Changes

Решения пользователя 2026-11-13 по Q1–Q9 внесены (design.md, «Решения пользователя 2026-11-13»). Расширение следует правилам `docs/protocols/acp/protocol/15-Extensibility.md` (design.md, D17): свой метод с префиксом `_`, объявление в `_meta` capability-объектов, никаких новых корневых полей и видов `sessionUpdate`.

- **Новое расширение ACP (агент → клиент): уведомление `_codelab/session/usage`** (D1, D2). Агент шлёт его после каждого шага модели, в конце хода (до ответа на `session/prompt`, ACP-3) и после сжатия контекста. Параметры — снимок с накопленными значениями: шаг, ход и сессия (токены `input`, `output`, `cacheRead`, `cacheWrite`, необязательный `reasoning`; стоимость десятичной строкой с валютой; число шагов и ходов; причины неполноты `partial`), заполнение контекста (`used`, `size` и порог автосжатия `compactAt`, если автосжатие включено) и монотонный `seq` сессии для идемпотентности.
- **Объявление** — ключ `usage: {"version": 1}` в схеме `_meta.codelab` при `initialize` (D9 change `add-subagents-and-tasks`): клиент CodeLab объявляет, что понимает уведомление, агент отвечает тем же ключом и только тогда шлёт `_codelab/session/usage` этому соединению (D3). Сторонний клиент (Zed) и фикстуры без объявления ничего нового не получают.
- **Ядро:** `StepEnded` получает заполнение контекста после шага (оценка с якорем на usage шага, `estimateContextTokens`, и окно `effectiveContextWindow`), чтобы адаптер не считал токены сам (D5).
- **`codelab_agent_acp`:** проекция `StepEnded`, `TurnEnded`, `ContextCompacted` в `_codelab/session/usage`; агрегаты хода и сессии на сессию сервера, общие для всех подключённых соединений (D4, D6).
- **Клиент:** `codelab_client_acp` объявляет `usage`, принимает `_codelab/session/usage` и отдаёт его ядру клиента; `codelab_client_core` разбирает уведомление терпимо (`UsageDecoder`) и публикует `SessionView.usage` (`UsageView`): последний ход, сессия, контекст, деньги в целых микроединицах, «~» для неполных сумм, «неизвестно» вместо нулей (D7, D8).
- **Причина остановки по бюджету:** клиент читает `_meta.codelab.budgetExceeded` ответа `session/prompt`; заметка хода называет лимит (`budget exceeded: cost`) (D10).
- **Desktop:** строка статуса под композером — модель · режим · контекст · токены хода · стоимость хода и сессии; «usage: —» с подсказкой для агента без расширения; тон контекста по порогам 80/95 %, подпись `compaction soon` при `used ≥ 0.9 × compactAt` (D11).
- **CLI:** TUI-статус-строка получает сегменты `ctx N%`, `↑…k ↓…`, `$…` в порядке и с правилами отбрасывания §12.2.6; строка статуса после хода в REPL на `ansi`/`plain` (D12).
- **Фикстуры:** новые golden-фикстуры с `extensions: ["usage"]`; фикстура объявлений `acp/initialize-codelab-extensions` получает ключ `usage` (D13).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-acp-server`: блок объявлений `initialize` с ключом `usage`; список разрешённых расширений с `_codelab/session/usage`; новое требование «Уведомление `_codelab/session/usage`».
- `agent-loop`: `StepEnded` несёт заполнение контекста после шага.
- `acp-protocol-client`: объявление `usage` в `clientCapabilities._meta.codelab`; приём `_codelab/session/usage`; причина остановки по бюджету в итоге хода.
- `acp-client-kit`: `SessionView.usage` и правила свёртки; заметка остановки по бюджету с названием лимита.
- `agent-workbench-ui`: строка статуса сессии под композером.
- `codelab-tui`: сегменты usage в статус-строке TUI.
- `codelab-cli`: строка статуса после хода в REPL.
- `acp-golden-fixtures`: фикстуры расширения usage.

## Не входит

- **`add-usage-ledger`** — журнал usage сессии `usage.json` (L-29, `agent-core` §12.6.1), команда `/usage [rebuild]`, полная сумма сессии после `session/load` (снимает причину `beforeLoad`, D6), учёт вызовов суммаризатора в сумме сессии.
- **`add-desktop-usage-pane`** — сама панель Usage в доке (экран 17, D-09 полностью): карточки, ходы и шаги, модели, экспорт CSV, клик по строке статуса, живой прогресс бюджета хода C-13 (поля лимитов в `_codelab/session/usage` — тем change).
- **`add-session-deadline`** — дедлайн сессии C-15, `/timer`, значение `deadline` в `budgetExceeded` и его показ.
- Хронология хода D-22 (панель Timeline): уведомление уже несёт шаг (`step`), но панель и границы шагов в ленте — отдельным change.
- Чтение чужого `usage_update` (Claude Code и другие агенты): его нет в вендоренной спецификации ACP, поэтому его нельзя трактовать без обновления `docs/protocols/acp/` отдельным change (вариант (в) Q1 отклонён). Незнакомый вид `session/update` по-прежнему пропускается (`acp-protocol-client`, «Незнакомый вид обновления пропускается»).
- Ветка git в статус-строке (часть U-13, `GitBranchProbe`), ключи `status_line.after_turn` и `status_line.segments`, поле `usage` событий `stream-json` (§12.5) — отдельно (решение Q9 (б)).
- Обнуляемые (`null`) `cacheRead`/`cacheWrite` в ядре: «~» в v1 ставится только по причинам D6 (решение Q2 (а)).
- Стоимость в валюте, отличной от USD: цены каталога моделей — доллары (`UsageCost`), валюта на проводе нужна для будущего.
- Изменение формата журнала сессии и модели `Usage` ядра.

## Impact

- `packages/dart/codelab_agent_core`: `loop/agent_events.dart` (`StepEnded`), `loop/agent_loop.dart`, тесты цикла.
- `packages/dart/codelab_agent_acp`: проекция событий, объявление в `initialize`, агрегаты usage сессии, тесты; `AGENTS.md` не меняется.
- `packages/dart/codelab_acp_testing`: новые фикстуры, правка `acp/initialize-codelab-extensions`, режим usage scripted-агента для e2e.
- `packages/dart/codelab_client_acp`: `clientCapabilities._meta.codelab.usage`, маршрут `_codelab/session/usage`, `budgetExceeded` в итоге хода.
- `packages/dart/codelab_client_core`: `lib/src/usage/` (`UsageDecoder`, `UsageView`, свёртка), `SessionView.usage`, заметка остановки по бюджету в `transcript_projector.dart`; барель; `AGENTS.md` (перечень назначения).
- `packages/flutter/codelab_ui`: виджет строки статуса сессии.
- `apps/codelab_desktop`: маппер и Cubit активной сессии, разметка под композером, widget-тесты, `integration_test/usage_display_flow_test.dart` (приёмка `release/*`).
- `apps/codelab_cli`: `tui/core/status_line.dart`, строка статуса REPL после хода, PTY-e2e `cli/status-line-usage`.
- Документы: `agent-core/13-acp-adapter.md` (§13.2, §13.7, §13.12, §13.16), `12-observability-and-errors.md` §12.6, `16-non-mvp-and-open-questions.md` §16.3, `dart-agent-and-clients/12-1-view-model.md` §12.1.1, §12.1.5, §12.1.10, `12-2-cli-display-and-input.md` §12.2.6, `12-3-desktop-display.md` A7, `delivery-roadmap.md` §4.6, §6.2, `agent-parity-goals.md` (L-11, U-13, D-09 — имена фикстур и тестов).
- Новых пакетов, зависимостей, рёбер графа и правил сторожа нет; allowlist ядра (PKG-2) не меняется.
- Зависимость: схема объявлений D9 и её первая реализация — итерация 1 change `add-subagents-and-tasks` (задачи 1.5, 1.6); итерация 1 стартует после них, архивация — после того change (решение Q8 (а)).
