## Why

Два предыдущих usage-changes дали клиенту данные, но desktop показывает из них только строку статуса под композером. Change `add-usage-extension` ввёл живые снимки `_codelab/session/usage` и строку статуса. Change `add-usage-ledger` ввёл историю сессии по ходам, шагам и моделям: запрос `_codelab/session/usage/ledger`, `SessionView.usageLedger` и `ClientWorkspace.refreshUsageLedger`. Панели, которая показывает эту историю, нет. Пользователь не видит, какой ход и какой шаг потратили деньги, не может выгрузить расход и не видит, сколько осталось до лимита бюджета хода (C-13), пока ход идёт. Агент знает лимиты `budget.*`, но клиенту их не передаёт: при остановке приходит только причина `budgetExceeded` (D10 change `add-usage-extension`).

Change — третий из четырёх usage-changes (`delivery-roadmap.md` §4.6, §6.2 п. 1): `add-usage-extension` → `add-usage-ledger` → **`add-desktop-usage-pane`** → `add-session-deadline`. Он закрывает D-09 полностью (экран 17, артборд «17 Usage pane») и показ бюджета C-13 в клиенте.

## What Changes

Решения пользователя 2026-11-17 по Q1–Q10 — все вариант (а) (design.md, «Решения пользователя 2026-11-17»).

- **Панель Usage в доке desktop** (D1, Q1). Панель `ToolPane.usage` в доке инструментов рядом с Files, Plan и Agents. Панель показывает данные сессии в фокусе:
  - шапка «This session» с кнопками «Rebuild from log» и «Export CSV»;
  - карточки Input (cache read · write), Output (reasoning), Cost («~» и причина) и Turns · steps (среднее число шагов на ход);
  - блок «Turn budget» (C-13);
  - таблица «Per turn» с раскрытием хода до шагов;
  - таблица «Per model».
  
  Источник — `SessionView.usageLedger` (журнал агента) и `SessionView.usage` (живые снимки). App ничего не суммирует сам. Неизвестное показывается как «—», а не как ноль (DSK-11, VIEW-6).
- **Обновление журнала** (D3, Q4). Журнал запрашивается при показе панели и после каждого снимка `turn`, `load` или `compaction`, если `seq` журнала отстал от `usage.lastSeq`. «Rebuild from log» вызывает `refreshUsageLedger(rebuild: true)` (Q3).
- **Подписи шагов** (D4, Q6). Шаг подписывается по транскрипту клиента: `toolCallIds` шага сопоставляются со строками вызовов ленты, подпись — правило `ToolRowFormatter`.
- **Экспорт CSV** (D5, Q2). Одна таблица в формате RFC 4180 сохраняется в файл, который пользователь выбирает в системном диалоге (`file_selector`, уже в зависимостях). В таблице точные числа: токены целыми, деньги десятичной строкой из микроединиц, неизвестное — пустой ячейкой. Ячейки защищены от формульной инъекции.
- **Клик по строке статуса** (D6). Клик открывает панель Usage и делает её активной. В change `add-usage-extension` строка была некликабельной.
- **Прогресс бюджета хода C-13** (D7–D9, Q5). Предлагается новое необязательное поле `budget` в параметрах `_codelab/session/usage` версии 1, без смены версии: правило совместимости D2 change `add-usage-extension` прямо предусматривает лимиты бюджета для панели. В поле — лимиты хода и израсходованное по тому же правилу, по которому цикл проверяет бюджет. Источник — ядро: `StepEnded` и `TurnEnded` несут прогресс бюджета, адаптер проецирует его в снимки `step` и `turn`. Клиент разбирает поле в `UsageView.budget`, панель рисует полосы Tokens, Cost, Time (и Steps — Q5). Время между шагами досчитывает таймер панели.
- **Агент без журнала** (D10, Q7). Без `usageLedger` панель строится по живым снимкам: карточки есть, таблиц, CSV и «Rebuild» нет. Без `usage` и без `usageLedger` панель не предлагается, а строка статуса остаётся «usage: —» без перехода.
- **Палитра.** Пункт «Usage» открывает панель, пока она доступна. Имя команды хоста не совпадает с агентской `/usage` (D11).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`: новое требование «Панель Usage»; строка статуса становится кликабельной (MODIFIED «Строка статуса сессии под композером» из change `add-usage-extension`).
- `agent-loop`: прогресс бюджета хода в `StepEnded` и `TurnEnded`.
- `agent-acp-server`: поле `budget` в уведомлении `_codelab/session/usage`.
- `acp-client-kit`: `UsageView.budget` и правила его свёртки; точная печать денег для экспорта.
- `acp-golden-fixtures`: фикстура бюджета в usage.

## Не входит

- **`add-session-deadline`** — дедлайн сессии C-15, `/timer`, блок «Session deadline» артборда (кнопки «Extend 30 min», «Change…», «Turn off»), значение `deadline` в `budgetExceeded` и его показ.
- Пометка `fallback` у модели в «Per model»: в журнале её нет (D2 change `add-usage-ledger` считает модели по ответившей модели шага). Нужна новая строка в форме журнала, это отдельный change.
- Панель Timeline (D-22, A14) и переход от шага панели к строке ленты.
- Usage в CLI и TUI сверх `/usage` агента, в том числе экспорт CSV из CLI.
- Изменение формы запроса `_codelab/session/usage/ledger`, пагинация журнала (R4 change `add-usage-ledger`) и ветки (`byBranch`).
- Настройка лимитов бюджета из app: лимиты по-прежнему задаёт конфигурация агента (`budget.*`, `15-configuration.md`).
- Бюджеты субагентов: показывается только бюджет хода корневой сессии.
- Чужой `usage_update` и стоимость не в USD — как в предыдущих changes.

## Impact

- `packages/flutter/codelab_ui`: организм панели Usage (карточки, полосы бюджета, таблица ходов с раскрытием, таблица моделей; без логики), `onTap` у `CodeLabSessionStatusBar`, ключи тестов.
- `apps/codelab_desktop`: feature `lib/features/usage/` (`application/` — данные панели, правило обновления журнала, CSV; `presentation/` — слот дока); `ActiveSessionCubit` и фасад `CodeLabShellCubit` — данные панели, доступность, `showUsagePane`; `workbench_shell.dart` — слот `ToolPane.usage`; палитра; порт сохранения файла в `lib/core/platform/`; widget-тесты; `integration_test/usage_pane_flow_test.dart` (приёмка `release/*`).
- `packages/dart/codelab_client_core`: `UsageView.budget`, разбор `budget` в `UsageDecoder`, точная печать денег (`usage_format.dart`); барель.
- `packages/dart/codelab_agent_core`: прогресс бюджета в `StepEnded` и `TurnEnded` (`loop/agent_loop.dart`, `loop/agent_events.dart`, `loop/turn_budget.dart`).
- `packages/dart/codelab_agent_acp`: поле `budget` в проекции `_codelab/session/usage`.
- `packages/dart/codelab_acp_testing`: фикстура `acp/prompt-usage-budget`, режим бюджета scripted-агента для e2e app.
- `packages/dart/codelab_client_acp`, `codelab_acp_protocol`: без изменений.
- Документы: `dart-agent-and-clients/12-3-desktop-display.md` (A7, A13, новый раздел о панели Usage, тесты), `12-1-view-model.md` §12.1.5, `agent-core/05-agent-loop.md` §5.2, `13-acp-adapter.md` §13.12, `agent-parity-goals.md` (D-09, C-13), `delivery-roadmap.md` §4.6, §6.2.
- Новых пакетов, внешних зависимостей, рёбер графа в `README.md` и правил сторожа нет; allowlist ядра (PKG-2) не меняется.
- Зависимость: changes `add-usage-extension` и `add-usage-ledger` влиты в `develop`, но не архивированы. Дельта `agent-workbench-ui` пересобрана из текста `add-usage-extension`, поэтому этот change архивируется после них (design.md, R1).
