Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала одной задачей пишутся красные тесты. Их коммитят отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках — сценарий спецификации, решение design.md, критерий матрицы или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`;
- `[protocol]` — `codelab_agent_acp`, `codelab_acp_protocol`, `codelab_acp_testing` (фикстуры, scripted-агент);
- `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`, правило сторожа desktop.

Итерации — каждая отдельным PR в `develop` (design.md, D15):
- 0 — документы;
- 1 — панель без бюджета;
- 2 — бюджет в агенте;
- 3 — бюджет в клиенте и панели;
- 4 — закрытие.

Решения пользователя 2026-11-17 по Q1–Q10 — все (а) (design.md, «Решения пользователя 2026-11-17»).

Зависимости: 1 ← 0 (выполнено 2026-11-17); 2 ← 0 (выполнено); 3 ← 1, 2; 4 ← 3. Итерации 1 и 2 независимы. Change архивируется после `add-usage-extension` и `add-usage-ledger` (design.md, R1).

Проверки каждой задачи — только для затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов, `pubspec.yaml` и `rules.dart`;
- `fvm dart run melos run web-compile` — при правке `codelab_agent_core`, `codelab_client_core`;
- `fvm dart run melos run protocol-conformance`, `conformance:agent`, `conformance:client`, `conformance:embedded` — при правке фикстур, проекции и kit;
- `fvm dart run melos run test:e2e:cli:dart-agent` — при правке клиентского слоя, через который работает CLI (итерация 3);
- `test:e2e:app:*` — только в `release/*`.

## 0. Документы (итерация 0)

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D15, вопросы Q1–Q10), дельты `agent-workbench-ui`, `agent-loop`, `agent-acp-server`, `acp-client-kit`, `acp-golden-fixtures`, `tasks.md`; `openspec validate add-desktop-usage-pane --strict`.
- [x] 0.2 Ответы пользователя на Q1–Q10 — в design.md (раздел «Решения пользователя …»), в D и в дельты. Сверка MODIFIED «Строка статуса сессии под композером» с текущим текстом change `add-usage-extension` (R1): все строки сохранены, кроме абзаца о клике. Повторить перед архивацией, если тот change снова изменит требование. *Итог 2026-11-17:* все ответы — (а), совпадают с рекомендациями; D-решения помечены «решение пользователя Qn (а)», дельты без правок, Open Questions — «Нет»; MODIFIED собран скриптом из текста `add-usage-extension`.
- [x] 0.3 `[desktop]` `dart-agent-and-clients/12-3-desktop-display.md`:
  - A7 — клик по строке статуса (D6);
  - A13 — Usage в `_availablePanesOf` и предикат (D1, D10), пункт палитры (D11);
  - новый раздел «Панель Usage» (A17 или следующий свободный номер): состав (D2), обновление журнала (D3), подписи шагов (D4), CSV (D5), бюджет (D9), отступления от артборда (Q9), ключи тестов;
  - таблица тестов — задачи 1.x и 3.x;
  - `app:usage_pane_flow_test.dart` в списке приёмки `release/*`.
  
  *Итог:* A7 (клик), A13 шаг 6 (предикат Usage), новый раздел A17 «Панель Usage» (п. 1–8), запись `app:usage_pane_flow_test.dart` с модульными тестами в «Как проверить»; строки таблицы тестов по именам тестов — при реализации итераций 1 и 3.
- [x] 0.4 `[client]` `dart-agent-and-clients/12-1-view-model.md` §12.1.5: новый пункт — `UsageView.budget` и правила свёртки (D9); п. 4b — `formatUsageMoneyExact` (D5); п. 3a — кто и когда обновляет журнал (ссылка на D3); §12.1.10 — тесты задач 1.2 и 3.2.
- [x] 0.5 `[agent]` `[protocol]` Документы ядра и адаптера:
  - `agent-core/05-agent-loop.md` §5.2 — прогресс бюджета в `StepEnded` и `TurnEnded` (D8);
  - `13-acp-adapter.md` §13.12 — поле `budget` в `_codelab/session/usage` со ссылкой на правило совместимости D2 change `add-usage-extension` и `15-Extensibility.md`; §13.16 — фикстура `acp/prompt-usage-budget`;
  - `14-golden-fixtures.md` — фикстура в перечне.
- [x] 0.6 `agent-parity-goals.md`: D-09 — панель (`add-desktop-usage-pane`, критерии задач 1.x); C-13 — показ прогресса в клиенте и фикстура `acp/prompt-usage-budget`. `delivery-roadmap.md` §4.6, §6.2 п. 1, таблица changes — третий change открыт. Строки матрицы закрытыми не отмечаются: реализации ещё нет.

## 1. Панель без бюджета (итерация 1)

- [ ] 1.1 `[desktop]` Красный тест сторожа: каталог `apps/codelab_desktop/lib/features/usage/application/` без `package:flutter/` и `dart:io` (design.md, D12); правило в `packages/dart/codelab_architecture_tests/test/support/rules.dart` вместе с каталогом. Проверка: `melos run guard`.
- [ ] 1.2 `[client]` Красные тесты `formatUsageMoneyExact` в `codelab_client_core/test/usage/usage_format_test.dart`: `2.26`, `0.000041`, `0`, `999999999.999999`, обратимость через разбор `cost` (acp-client-kit «Точная запись суммы usage», сценарий «Обратимость»; D5).
- [ ] 1.3 `[client]` Реализация `formatUsageMoneyExact` в `usage_format.dart`, экспорт барелем; `web-compile`.
- [ ] 1.4 `[desktop]` Красные тесты application панели (`apps/codelab_desktop/test/features/usage/application/`):
  - `usage_pane_data_test.dart` — `usagePaneDataOf`: карточки из журнала и из живых снимков, Input по Q8, среднее шагов в целых, ходы от нового к старому, `running`, «—» у строки без usage и без цены, строки `Subagents` и `Summaries` (agent-workbench-ui «Панель Usage», сценарии «Панель с журналом», «Неизвестная цена и ход без usage», «Неполная стоимость сессии», «Агент без журнала»; D2, D10);
  - `usage_step_label_test.dart` — подписи `Read lib/…`, ` +N`, `reply`, `N tool calls` (сценарии требования «Подпись шага в панели Usage»; D4);
  - `ledger_refresh_test.dart` — правило D3: показ, `seq`, занятая сессия, `failed` без автоповтора, один автоматический запрос на значение `lastSeq` (сценарии «Журнал после хода», «Журнал не догоняет снимки», «Сбой загрузки журнала»);
  - `usage_csv_test.dart` — заголовок, порядок строк, точные числа, пустые ячейки, кавычки, CRLF, префикс `'` (сценарии требования «Экспорт usage в CSV»; D5);
  - доступность `usageAvailable` по таблице D10 (сценарий «Агент без usage»).
- [ ] 1.5 `[desktop]` Реализация feature `lib/features/usage/application/`: `UsagePaneData`, `usagePaneDataOf`, подписи шагов, `ledgerRefreshNeeded`, `buildUsageCsv`. В `ActiveSessionCubit` — данные панели в `_onView` (одна подписка, D1), флаг «панель показана» и вызов `refreshUsageLedger` по правилу D3. В фасаде `CodeLabShellCubit` — `usageAvailable`, `usagePaneShown`, `refreshUsageLedger`, `rebuildUsageLedger`, `exportUsageCsv`, `openUsagePane`. События `usage_pane.refresh` и `usage_pane.export` (D13).
- [ ] 1.6 `[desktop]` Красные widget-тесты:
  - `packages/flutter/codelab_ui/test/codelab_usage_pane_test.dart` — карточки, таблица с раскрытием, модели, состояния (индикатор, заметка сбоя с `Retry`, заметка «без журнала»), ключи `usage-*`; тон и тексты приходят из данных;
  - `codelab_session_status_bar_test.dart` — `onTap`: клик, Enter, Space, курсор; без `onTap` строка некликабельна (R9);
  - `apps/codelab_desktop/test/features/usage/presentation/usage_pane_test.dart` — слот дока: открытие вызывает один запрос журнала, `Rebuild from log` — запрос с `rebuild: true`, клик по строке статуса открывает и активирует Usage и не закрывает при повторе, пункт палитры `Usage` (`/usage-pane`) рядом с командой агента `/usage`, панель без usage не предлагается и остаётся в раскладке (agent-workbench-ui «Строка статуса сессии под композером», сценарии «Клик открывает панель Usage», «Строка без данных некликабельна»; «Панель Usage», сценарии «Rebuild from log», «Агент без usage», «Смена сессии в фокусе»);
  - экспорт на двойнике порта сохранения: сохранено, отказ (`cancelled`, без заметки), сбой (`Couldn't save the file.`) (сценарий «Отказ в диалоге»).
- [ ] 1.7 `[desktop]` Реализация `codelab_ui`: организм `CodeLabUsagePane` и модели строк (без логики, `codelab_ui/AGENTS.md`), `onTap` у `CodeLabSessionStatusBar`, превью виджетов по образцу пакета. Реализация desktop:
  - `WorkbenchUsagePane` в `features/usage/presentation/` с сигналом показа;
  - слот `ToolPane.usage` и предикат в `CodeLabShell._availablePanesOf`;
  - пункт палитры (`_usageAction`) и построитель набора пунктов хоста (D11);
  - порт `UsageCsvSaver` в `lib/core/platform/` на `file_selector` и его привязка в `app_scope.dart`;
  - шов тестов `CodeLabTestBinding(usageCsvSaver:)`.
- [ ] 1.8 `[desktop]` `apps/codelab_desktop/AGENTS.md` — раздел «Панель Usage»: слои, владелец подписки и правила обновления, порт сохранения, события, правило сторожа. Документация пакета и приложения (`README.md`, `doc/`, `docs/user/`) — через `docs-writer` по стандарту `codelab-docs`, если описанное там меняется.

## 2. Бюджет в агенте (итерация 2)

- [ ] 2.1 `[agent]` Красные тесты `codelab_agent_core/test/loop/turn_budget_progress_test.dart`: прогресс в `StepEnded` и `TurnEnded` — шаги, токены `input + output` с потомками без кэша, стоимость `null` у модели без цен, время без ожидания gate по `FakeClock`, совпадение с решением остановки (agent-loop «Прогресс бюджета хода в событиях шага и хода», все сценарии; D8; C-13).
- [ ] 2.2 `[agent]` Реализация: `BudgetProgress` (имя — исполнителю) в `loop/turn_budget.dart`, одна функция прогресса и проверки в `AgentLoop`, поле в `StepEnded` и `TurnEnded` (`loop/agent_events.dart`); барель; `web-compile`; allowlist PKG-2 не меняется.
- [ ] 2.3 `[protocol]` Красные тесты `codelab_agent_acp/test/usage_budget_projection_test.dart` и фикстура `acp/prompt-usage-budget` (роль `agent`): поле только при `max_tokens`, `max_cost` или `max_duration`; состав; `cost.limit` из `max_cost`; `cost` без `used` на модели без цен и `currency` при `budget.cost`; нет поля в `compaction` и `load`; существующие usage-фикстуры не меняются (agent-acp-server «Бюджет хода в уведомлении `_codelab/session/usage`», все сценарии; acp-golden-fixtures «Фикстура бюджета хода в usage», сценарии «Агентский прогон», «Существующие фикстуры»; D7).
- [ ] 2.4 `[protocol]` Реализация проекции `budget` в `codelab_agent_acp` (снимки `step` и `turn`); бюджет в режиме usage scripted-агента `codelab_acp_testing` для приёмки app (по образцу `withUsage`, D13 change `add-usage-extension`). Проверки: `protocol-conformance`, `conformance:agent`, `conformance:embedded`.

## 3. Бюджет в клиенте и панели (итерация 3)

- [ ] 3.1 `[client]` Красные тесты `codelab_client_core/test/usage/usage_budget_test.dart` и клиентская роль `acp/prompt-usage-budget`: разбор `budget`, подполя и `field: budget.<подполе>` в `usage.decode_failed`, свёртка по `turnId`, `receivedAt` по часам рабочего пространства, сброс при переподключении и загрузке (acp-client-kit «Бюджет хода в usage сессии», все сценарии; acp-golden-fixtures, сценарий «Клиентский прогон»; D9).
- [ ] 3.2 `[client]` Реализация `UsageView.budget` (`TurnBudgetView`), разбор в `UsageDecoder`, свёртка в `UsageFold`; барель; `codelab_client_core/AGENTS.md` §5 (перечень назначения), если меняется; `web-compile`, `conformance:client`, `test:e2e:cli:dart-agent`.
- [ ] 3.3 `[desktop]` Красные тесты блока «Turn budget»:
  - маппер — строки по присутствующим лимитам, `This turn` и `Last turn`, тон 80 % и 100 %, больше 100 %, `— / $0.50` и `not checked: price unknown`, `m:ss` и `h:mm:ss`, подсказка Tokens (R2);
  - виджет — тик раз в секунду только при показанной панели, `running`, отсутствии одобрений и наличии `duration`; таймер отменяется при скрытии;
  
  (agent-workbench-ui «Бюджет хода в панели Usage», все сценарии; D9).
- [ ] 3.4 `[desktop]` Реализация блока в `CodeLabUsagePane` (`codelab_ui`, полосы и подписи из данных) и в маппере и виджете desktop; часы виджета внедряются тестами, как у `WorkbenchAgentsPane`.
- [ ] 3.5 `[desktop]` Интеграционный тест `apps/codelab_desktop/integration_test/usage_pane_flow_test.dart` (приёмка `release/*`; в скрипт `test:e2e:app:usage` рядом с `usage_display_flow_test.dart`): scripted-агент с usage, журналом и бюджетом — открытие панели кликом по строке статуса, раскрытие хода, «Rebuild from log», «Turn budget» во время хода, экспорт CSV во временный каталог через шов порта. В ветке `feature/*` не запускается (AGENTS.md §21).

## 4. Закрытие (итерация 4)

- [ ] 4.1 Ручная проверка на отладочной сборке desktop (macOS) со встроенным агентом и моделью с ценами, `budget.max_cost` и `budget.max_duration` в изолированном `CODELAB_HOME`:
  - панель по клику на строку статуса;
  - журнал после хода;
  - подписи шагов;
  - CSV в табличном редакторе (точные числа, нет формул);
  - «Turn budget» во время хода и после остановки `budget exceeded: cost`;
  - агент без журнала (внешний профиль).
  
  Итог — в design.md (раздел «Итог ручной проверки»). Ключ провайдера нигде не попадает в файлы и вывод.
- [ ] 4.2 Сверка документов с кодом (задачи 0.3–0.6); `agent-parity-goals.md` — D-09 и C-13 закрыты со ссылками на тесты; `delivery-roadmap.md` — следующий change `add-session-deadline`.
