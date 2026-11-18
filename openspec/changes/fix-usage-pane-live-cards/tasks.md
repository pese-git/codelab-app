Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала пишутся красные тесты. Их коммитят отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках указаны требование и сценарий спецификации, решение design.md или вопрос.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`;
- `[client]` — `codelab_client_core` (и проверки `apps/codelab_cli`, который читает `UsageTotals`);
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`;
- `[protocol]` — задач нет: провод, фикстуры и проекция адаптера не меняются (design.md, D9).

Итерации и PR в `develop` (design.md, D11): итерации 1 и 2 — одним PR, итерация 3 — своим:
- 0 — документы;
- 1 — карточки и строка журнала (SMK-42, SMK-44, SMK-45);
- 2 — время бюджета (SMK-43, Q3, Q4);
- 3 — закрытие.

Решения пользователя 2026-11-18 по Q1–Q6 — все по рекомендации (design.md, «Решения пользователя 2026-11-18»): SMK-44 и SMK-45 входят в change, правка ядра (Q3 (а)) — тоже.

Зависимости: 1 ← 0 (выполнено 2026-11-18); 2 ← 0 (выполнено); 3 ← 1, 2. Итерации 1 и 2 независимы.

Проверки — только затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` изменённого пакета. При правке публичного API (`UsageTotals`, `SessionView`, `ApprovalWaitMeter`) — ещё и пакетов-потребителей: `apps/codelab_cli`, `apps/codelab_desktop`, `codelab_agent_acp`, `codelab_embedded`;
- `fvm dart test` / `fvm flutter test` изменённого пакета и потребителей изменённых элементов;
- `fvm dart run melos run web-compile` — при правке `codelab_client_core` и `codelab_agent_core`;
- `fvm dart run melos run conformance:client` — при правке разбора usage в kit (итерация 1);
- `fvm dart run melos run test:e2e:cli:dart-agent` — при правке `codelab_client_core`, через который работает CLI (итерации 1 и 2);
- `guard` не нужен: импорты, `pubspec.yaml` и `rules.dart` не меняются. Если исполнитель всё же добавит импорт между пакетами — `fvm dart run melos run guard`;
- `test:e2e:app:*` — только в `release/*`.

## 0. Документы (итерация 0)

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D11, причины с файлом и строкой, вопросы Q1–Q6), дельты `agent-workbench-ui`, `acp-client-kit`, `agent-loop`, `tasks.md`; `openspec validate fix-usage-pane-live-cards --strict`.
- [x] 0.2 Ответы пользователя на Q1–Q6 — в design.md (раздел «Решения пользователя 2026-11-…»), в D и в дельты. Ответ не по рекомендации меняет дельту:
  - Q1 (а) или (б) — правило источника карточек и сценарии «Карточки после ответа журнала», «Журнал отстал после сбоя»;
  - Q2 (а) — формула Time, сценарии «Одобрение не откатывает время» и «Два одобрения одновременно», требование kit (только `requestedAt`);
  - Q3 (б) или (в) — дельта `agent-loop` снимается;
  - Q4 (б) или (в) — фильтр корня в kit и сценарий «Одобрение субагента»;
  - Q5, Q6 — строки и сценарии «Журнал пересобран после хода», «Пустая сессия».
  
  `openspec validate fix-usage-pane-live-cards --strict`.

  *Итог 2026-11-18:* все ответы — по рекомендации (Q1 (в), Q2 (б), Q3 (а), Q4 (а), Q5 (а), Q6 (а)); раздел «Решения пользователя 2026-11-18» в design.md, D помечены «решение пользователя Qn», Open Questions — «Нет». Дельты `agent-workbench-ui`, `acp-client-kit`, `agent-loop` сверены с ответами — правок не потребовалось. Proposal обновлён (SMK-44 и SMK-45 в объёме).
- [x] 0.3 `[desktop]` `dart-agent-and-clients/12-3-desktop-display.md`, A17:
  - п. 1 — ключ кэша данных панели: список ожиданий одобрений корня вместо признака (D5);
  - п. 3 — источник карточек по `seq` (D1), Turns · steps из `session.turns` (D2), Cost `no usage yet` (D8), строка состояния `stale`/`missing` и подсказка (D7);
  - п. 6 — Time между снимками без ожиданий корня, тик при `cancelling`, одобрение потомка тик не останавливает (D4);
  - строки таблицы «Как проверить» — по именам тестов при реализации итераций 1 и 2.

  *Итог:* заголовок A17 — ссылка на change и решения 2026-11-18; п. 1 — ключ кэша по `approvalWaits`; п. 3 — строка состояния `stale`/`missing`, правило источника карточек, Cost `no usage yet`, Turns по `session.turns` и R1; п. 6 — «живой» бюджет, формула Time с объединением ожиданий корня, `cancelling`, одобрение потомка, условие тика. Строки таблицы тестов — при реализации.
- [x] 0.4 `[client]` `dart-agent-and-clients/12-1-view-model.md` §12.1.5 — `UsageTotals.turns` (D2), ожидания одобрений корня в `SessionView` и правило часов (D3); §12.1.10 — тесты задач 1.1 и 2.3.

  *Итог:* п. 3 — `UsageTotals.turns`; п. 3b — время между снимками ссылается на п. 3c; новый п. 3c — `SessionView.approvalWaits` (источник, только корень, `resolvedAt`, равенство по значению, часы). §12.1.10 — при реализации задач 1.1 и 2.3.
- [x] 0.5 `[agent]` `agent-core/05-agent-loop.md` §5.2 (абзац о `maxDuration` и ожидании одобрения): пересекающиеся ожидания вычитаются один раз (D6, Q3 (а)). Ожидание потомка время корня не останавливает — так и записать (Q4 (а)).

  *Итог:* абзац «Бюджет хода» — объединение ожиданий, открытие и закрытие ожидания в политике, ожидание потомка не входит в счётчик корня. Кроме того, `delivery-roadmap.md` §6.2 п. 1 и таблица changes: следующим взят `fix-usage-pane-live-cards`, `add-session-deadline` отложен решением пользователя 2026-11-18.

## 1. Карточки и строка журнала (итерация 1)

- [ ] 1.1 `[client]` Красные тесты kit, `codelab_client_core/test/usage/` (файл по образцу `usage_decoder_test.dart`):
  - `session.turns` 3 → `UsageTotals.turns` 3; строка `"3"` и `-1` → `null` и одно предупреждение `usage.decode_failed` с `field: session.turns`, снимок применён; без поля и у агрегата `turn` → `null` (acp-client-kit «Usage сессии», сценарий «Число ходов сессии»; D2);
  - `UsageLedgerView.turnCount` и `total` журнала после перехода на общий разбор прежние (тесты `usage_ledger_decoder_test.dart` зелёные без правки ожиданий, кроме нового поля `total.turns`).
- [x] 1.2 `[client]` Реализация: `UsageTotals.turns` (`usage_models.dart`, `build_runner` для freezed), разбор в `parseUsageTotals` (`usage_parsing.dart`), барель. Ожидания существующих тестов kit и `apps/codelab_cli`, которые сравнивают `UsageTotals` целиком, получают `turns`. Проверки: `web-compile`, `conformance:client`, `fvm dart test` в `apps/codelab_cli`, `test:e2e:cli:dart-agent`.
- [ ] 1.3 `[desktop]` Красные тесты:
  1. `apps/codelab_desktop/test/features/usage/application/usage_pane_data_test.dart`, источник карточек (agent-workbench-ui «Панель Usage», сценарии «Карточки во время хода», «Карточки после ответа журнала», «Журнал отстал после сбоя», «Агент без журнала»; D1, D2):
     - `ledger.seq ≥ usage.lastSeq` → `total` журнала, `<` → `usage.session`;
     - без `usage.session` → журнал;
     - `loading(previous)` и `failed(previous)` с отставшим журналом → снимки;
     - Turns · steps из снимка с `turns` — `2 · 5` и среднее, без `turns` — только шаги;
     - в одной карточке числа одного агрегата;
  2. тот же файл, Cost пустой сессии (сценарий «Пустая сессия»; D8, Q6 (а)): `—` и `no usage yet`, без тона, `price unknown` и `$0.00` нет. При нулевых шагах с причиной `noUsage` или с ненулевыми токенами — прежнее правило;
  3. тот же файл, строка состояния (сценарии «Журнал пересобран после хода», «Rebuild from log»; D7, Q5 (а)): `stale` и `missing` → `Ledger: up to date · N records` и подсказка `refreshed from the session journal (<reason>)`; `invalid`, `explicit`, незнакомая причина → `rebuilt from journal (<reason>) · N records` без подсказки;
  4. `packages/flutter/codelab_ui/test/codelab_usage_pane_test.dart`: подсказка строки состояния — `Tooltip` из данных; без подсказки `Tooltip` нет.
- [x] 1.4 `[desktop]` Реализация:
  1. `features/usage/application/usage_pane_data.dart`: выбор агрегата карточек (D1), Turns · steps по `turns` (D2);
  2. там же: Cost пустой сессии (D8);
  3. там же: `_statusLineOf` и поле подсказки в `UsagePaneData` (D7); `codelab_ui` — необязательная подсказка строки состояния в `CodeLabUsagePane` (`escapeForDisplay`, как у остальных подсказок), превью; маппер `presentation/usage_pane_view.dart`;
  4. `apps/codelab_desktop/AGENTS.md`, раздел «Панель Usage» — источник карточек и строка состояния. Документация `README.md`, `doc/`, `docs/user/` — через `docs-writer` по стандарту `codelab-docs`, если описанное там меняется (руководство пользователя — карточки и строка журнала).
  
  Проверки: `fvm flutter analyze` и `fvm flutter test` в `apps/codelab_desktop` и `packages/flutter/codelab_ui`.

## 2. Время бюджета (итерация 2)

- [ ] 2.1 `[agent]` Красные тесты `codelab_agent_core` (по образцу `test/loop/turn_budget_progress_test.dart`, `FakeClock`):
  - два одобрения параллельной группы по 60 с одновременно, шаг 61 с → `StepEnded.budget.active` 1 с, а не отрицательное значение (agent-loop «Бюджет хода», сценарий «Параллельные одобрения вычитаются один раз»; D6, Q3 (а));
  - одно ожидание — прежнее значение (сценарий «Ожидание одобрения не тратит время хода»);
  - ожидание потомка не входит в счётчик корня (Q4 (а), поведение не меняется);
  - модульные тесты счётчика: пересекающиеся, вложенные и последовательные ожидания, `reset()`, отмена ожидания (закрытие в `finally`).
- [x] 2.2 `[agent]` Реализация: `ApprovalWaitMeter` — объединение ожиданий (`tools/agent_tool.dart`), пара «начать — закончить» в `permissions/policy.dart` вместо `add`. Барель; allowlist PKG-2 не меняется. Проверки: `web-compile`, `fvm dart test` в `codelab_agent_core`, `fvm dart analyze` в `codelab_agent_acp` и `codelab_embedded`.
- [ ] 2.3 `[client]` Красные тесты kit, `codelab_client_core/test/` (рядом с тестами `pendingApprovals`), — acp-client-kit «Ожидания одобрений корня хода», все сценарии; D3:
  - метки `requestedAt` и `resolvedAt` равны меткам домена, порядок по `requestedAt`;
  - ожидающее — `resolvedAt == null`;
  - запрос потомка не входит, а в `pendingApprovals` есть;
  - новый ход — пусто;
  - отмена хода и потеря соединения закрывают интервал;
  - решённое без `resolvedAt` не входит;
  - равенство по значению между ревизиями без изменения одобрений.
- [x] 2.4 `[client]` Реализация: вид ожиданий (freezed) и поле `SessionView`, проекция из `AcpSession` рядом с `pendingApprovalViews` (`transcript_projector.dart`) на общем разборе `subagentRequester`; барель; `build_runner`. Проверки: `web-compile`, `test:e2e:cli:dart-agent`.
- [ ] 2.5 `[desktop]` Красные тесты (agent-workbench-ui «Бюджет хода в панели Usage»; D4, D5):
  - `test/features/usage/application/usage_budget_test.dart`, Time на момент `now`:
    - сценарии «Время идёт между шагами», «Одобрение не откатывает время» (`0:05` стоит, после ответа `0:08`), «Два одобрения одновременно» (`0:04`), «Одобрение субагента» (`3:05`, тик), «Отмена хода» (`3:07`), «Начало нового хода»;
    - ожидание, начатое до `receivedAt`, учитывается только после него;
    - насыщение около 2⁶³ − 1, отрицательная разность — ноль;
    - признак тика: нет при ожидающем одобрении корня, есть при одобрении потомка и при `cancelling`;
  - тот же файл, группа `ActiveSessionCubit`: ответ на одобрение без новой ревизии `usage` меняет данные блока; фрагменты ответа при неизменных ожиданиях данных панели не пересчитывают (D5);
  - `test/features/usage/presentation/usage_budget_tick_test.dart`:
    - запрос одобрения корня останавливает тик, а значение Time не уменьшается;
    - ответ возобновляет тик без прыжка;
    - одобрение потомка тик не останавливает;
    - `cancelling` тикает до снимка `turn`.
    
    Часы виджета — от `receivedAt` kit со сдвигом (D9 change `add-desktop-usage-pane`, «Тик»). Метки одобрений берутся из `SessionView` теста.
- [x] 2.6 `[desktop]` Реализация: `features/usage/application/usage_budget.dart` — интервалы и признак «живой» в `UsageBudgetData`, формула в `usageBudgetRowsAt`, признак тика (D4); `ActiveSessionCubit._usageOf` — ключ кэша по списку ожиданий (D5); `apps/codelab_desktop/AGENTS.md` («Блок Turn budget и тик»). Проверки: `fvm flutter analyze`, `fvm flutter test` в `apps/codelab_desktop`.
- [x] 2.7 `[desktop]` `integration_test/usage_pane_flow_test.dart` (приёмка `release/*`): сверить ожидания с D1 (scripted-агент без журнала уже показывает живые карточки; Dart-агент и встроенный после хода — журнал). Правка — только если ожидания меняются. В `feature/*` — только `fvm flutter analyze` (AGENTS.md §21).

## 3. Закрытие (итерация 3)

- [ ] 3.1 Ручная проверка на отладочной сборке desktop (macOS), как задача 4.1 change `add-desktop-usage-pane`:
  - встроенный агент, модель с ценами (OpenRouter `openai/gpt-4o-mini`), `budget.max_cost` и `budget.max_duration` в изолированном `CODELAB_HOME`;
  - ключ провайдера — только переменной окружения.
  
  Сценарии:
  - новая сессия без ходов: Cost `—` и `no usage yet` (SMK-45);
  - ход: карточки Input, Output, Cost совпадают со строкой статуса во время хода, после хода — с таблицей `Per turn` (SMK-42);
  - строка журнала после хода — `Ledger: up to date · N records`, подсказка с причиной; «Rebuild from log» — `(explicit)` (SMK-44);
  - ход с одобрением: Time стоит, пока одобрение ждёт, не откатывается и после ответа не прыгает вперёд (SMK-43);
  - ход с двумя одобрениями одной группы (например, `write` и `execute` в одном ответе) — время один раз;
  - отмена хода во время шага — Time не откатывается.
  
  Ключ провайдера не попадает в журналы приложения, файлы сессии и CSV (`sk-or-` — 0). Итог — в design.md (раздел «Итог ручной проверки»).
- [ ] 3.2 Сверка документов с кодом (задачи 0.3–0.5), строки таблиц тестов A17 и §12.1.10. Бэклог `docs/backlog/smoke-2026-11-18-desktop-usage-pane.md`: SMK-42…SMK-45 — «Закрыто change `fix-usage-pane-live-cards`» (или иной статус по ответам Q5, Q6). Новые наблюдения ручной проверки — карточками бэклога.

## Definition of Done

- Ответы на Q1–Q6 записаны в design.md, дельты им соответствуют, `openspec validate fix-usage-pane-live-cards --strict` проходит.
- Все сценарии дельт `agent-workbench-ui`, `acp-client-kit`, `agent-loop` покрыты тестами; каждый тест сначала был красным.
- Проверки §21 затронутого выполнены и перечислены в описании PR. Явно указано, что полный `melos run check` не запускался (если не запускался).
- Документы архитектуры (A17, §12.1.5, §5.2) и `apps/codelab_desktop/AGENTS.md` совпадают с кодом. Документация пакетов и пользователя обновлена через `docs-writer`, если описанное менялось.
- Ручная проверка 3.1 выполнена, итог в design.md, статусы бэклога обновлены.
- Провод ACP и фикстуры не менялись. Allowlist ядра (PKG-2), граф `README.md` и правила сторожа не менялись.
