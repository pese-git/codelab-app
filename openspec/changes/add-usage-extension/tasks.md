Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала одной задачей пишутся красные тесты — они коммитятся отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках — сценарий спецификации, решение design.md, критерий матрицы или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent`;
- `[protocol]` — `codelab_agent_acp`, `codelab_acp_protocol`, `codelab_acp_testing` (фикстуры, scripted-агент);
- `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`.

Итерации — каждая отдельным PR в `develop` (design.md, D16):
- 0 — документы;
- 1 — протокол и агент;
- 2 — клиентский слой;
- 3 — desktop и CLI.

Решения пользователя 2026-11-13 по Q1–Q9 внесены (design.md, «Решения пользователя 2026-11-13»).

Зависимости: 1 ← 0 и задачи 1.5, 1.6 change `add-subagents-and-tasks` (схема D9 в коде; Q8 (а)); 2 ← 1; 3 ← 2. Change архивируется после `add-subagents-and-tasks` (design.md, R1).

Проверки каждой задачи — только для затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке `codelab_agent_core`, `codelab_client_core`, `codelab_client_acp`;
- `fvm dart run melos run protocol-conformance`, `conformance:agent`, `conformance:client`, `conformance:embedded` — при правке фикстур, проекции и kit;
- `fvm dart run melos run test:e2e:cli:dart-agent` — при правке `apps/codelab_cli` и клиентского слоя.

Тесты — на Dart VM и widget-тесты. Интеграционные `integration_test/*` app в `feature/*` только компилируются (`fvm flutter analyze`), на устройстве их запускает `release/<version>` (AGENTS.md §21).

## 0. Документы (итерация 0)

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D17, вопросы Q1–Q9), дельты `agent-acp-server`, `agent-loop`, `acp-protocol-client`, `acp-client-kit`, `acp-golden-fixtures`, `agent-workbench-ui`, `codelab-tui`, `codelab-cli`; `openspec validate add-usage-extension --strict`.
- [x] 0.2 Временные пометки (до решений пользователя; заменены задачами 0.4–0.7) в `agent-core/13-acp-adapter.md` §13.12, `16-non-mvp-and-open-questions.md` §16.3, `12-observability-and-errors.md` §12.6, `dart-agent-and-clients/12-1-view-model.md` §12.1.5, `delivery-roadmap.md` §4.6.
- [x] 0.3 Ответы пользователя 2026-11-13 на Q1–Q9 внесены в design.md (раздел «Решения пользователя 2026-11-13», D1, D2, D5, D11, D12, новый D17 «Соответствие правилам расширения ACP») и в дельты: имя метода `_codelab/session/usage`; Q3 (б) — `compactAt` и `compaction soon` (`agent-acp-server`, `agent-loop`, `acp-client-kit`, `agent-workbench-ui`, фикстура `acp/prompt-usage-compaction-off`); Q9 (б) — требование `codelab-cli` безусловно; сценарии «Стандартные типы без новых полей», «Запрос без новых корневых полей».
- [x] 0.4 `[protocol]` `agent-core/13-acp-adapter.md` по принятой форме: §13.2 — ключ `usage` в схеме объявлений; §13.7 — строки `StepEnded`, `TurnEnded`, `ContextCompacted` (→ `_codelab/session/usage`, ACP-6); §13.12 — строки ключа `usage` и уведомления `_codelab/session/usage` со ссылкой на change вместо строки-заглушки и пометка о соответствии `15-Extensibility.md` (D17); §13.13 — снимок `turn` перед ответом на диаграмме хода; §13.16 — фикстуры D13. `16-non-mvp-and-open-questions.md` §16.3 → строка в §16.2 (решение принято, реализация — итерации 1–3). `12-observability-and-errors.md` §12.6 — абзац «В ACP usage не передаётся» заменить ссылкой на §13.12 и D4 (суммаризатор вне суммы до `add-usage-ledger`).
- [x] 0.5 `[client]` `dart-agent-and-clients/12-1-view-model.md`: §12.1.1 — `UsageView` по D8 (без `SessionStatusBar` и `StatusBarProjector`, `UsageDecoder` без интерфейса); §12.1.5 п. 2–4 — форма D2, свёртка по `seq` без суммирования на клиенте; §12.1.10 — тесты. `12-2-cli-display-and-input.md` §12.2.6 — порядок отбрасывания с профилем (D12), `~` префиксом, отступление от артборда CliStatus. `agent-core/05-agent-loop.md` — `StepEnded` с заполнением контекста (D5).
- [x] 0.6 `[desktop]` `dart-agent-and-clients/12-3-desktop-display.md` A7: имя `CodeLabSessionStatusBar`, состояния `unknown`/`awaiting`/`reported`, `price unknown`, некликабельная строка в v1, `compaction soon` по `compactAt` (Q3 (б)); DSK-11 — ссылка на change; перечень тестов D-09 — без `skip` после итерации 3.
- [x] 0.7 `delivery-roadmap.md` §4.6, §6.2 п. 1 — первый change из четырёх и следующие (`add-usage-ledger`, `add-desktop-usage-pane`, `add-session-deadline`); `agent-parity-goals.md` — L-11 (`acp/prompt-usage-steps` вместо `acp/prompt-usage-meta`; «Как в ACP» — `_codelab/session/usage`), U-13 (что закрывается без ветки git, Q9), D-09 (строка статуса; панель — следующий change), строка L-11 в разделе «Открытые вопросы» — форма выбрана change `add-usage-extension`. Строки матрицы закрытыми не отмечаются: реализации ещё нет.

## 1. Протокол и агент (итерация 1)

### 1a. Красные тесты

- [ ] 1.1 `[agent]` `codelab_agent_core/test/loop/agent_loop_context_fill_test.dart`: шаг с `read` → `StepEnded` несёт `used` по правилу якоря и `window` с `contextWindowCap`; `compactAt` — порог автосжатия, при выключенном сжатии `null`; без `estimateTokens` — `null`; транскрипт и бюджет не меняются (agent-loop «Заполнение контекста после шага»; D5). Красный.
- [ ] 1.2 `[protocol]` `codelab_agent_acp/test/initialize_extensions_test.dart` (или существующий тест блока D9): ключ `usage` в ответе при любом `clientCapabilities._meta.codelab`; без `_meta` — ответ прежний; объявление клиента сохраняется на соединение (agent-acp-server «initialize»: «Клиент CodeLab объявил расширения», «Субагенты выключены», «Ответ codelab-app»). Красный.
- [ ] 1.3 `[protocol]` `codelab_agent_acp/test/usage_projection_test.dart` на `InProcessAcpLink`, `ScriptedStreamFunction`, `FakeClock`: два шага с ценами — `seq` 1…3, суммы, `cost` строкой из микроединиц; модель без цен и ответ без usage — `noUsage`, `noPrice`, без `cost`/`currency`; отмена посреди `exec` — снимок `turn` перед `cancelled`; сбой провайдера — снимок `turn` перед `-32603`; ход `/usage` — без уведомлений; соединение без объявления — без уведомлений; два соединения — одинаковые `seq`; `/compact` — `compaction` без `turnId`; `session/load` журнала с ответами модели — снимков до хода нет, затем `beforeLoad`; выключенное автосжатие — без `compactAt`; кадры без новых корневых полей («Стандартные типы без новых полей») (agent-acp-server «Уведомление `_codelab/session/usage`», все сценарии; D4, D6, D7, D9). Красный.
- [ ] 1.4 `[protocol]` Тест исчерпывающей проекции (ACP-6) — `StepEnded`, `TurnEnded`, `ContextCompacted` помечены «→ `_codelab/session/usage`» в таблице теста. Красный.
- [ ] 1.5 `[protocol]` Фикстуры D13 с ролью `agent`: `acp/prompt-usage-steps`, `acp/prompt-usage-unpriced`, `acp/prompt-usage-cancelled`, `acp/compact-usage-context`, `acp/prompt-usage-compaction-off`, `acp/session-load-usage-partial`; правка `acp/initialize-codelab-extensions` (`usage` в обоих блоках) (acp-golden-fixtures «Фикстуры расширения usage»: «Расширение не объявлено», «Агентский прогон во всех режимах»). Красные в `conformance:agent`.

### 1b. Реализация

- [ ] 1.6 `[agent]` `StepEnded` с заполнением контекста: тип в `loop/agent_events.dart`, вычисление в `agent_loop.dart` через `AgentLoopConfig.estimateTokens` и `effectiveContextWindow`; барель; doc-комментарии по-русски со ссылкой на D5. Тест 1.1 зелёный; `web-compile`, `guard`.
- [ ] 1.7 `[protocol]` `codelab_agent_acp`: ключ `usage` в блоке `agentCapabilities._meta.codelab`; флаг объявления клиента на соединение (2 строки к механизму D9). Тест 1.2 зелёный.
- [ ] 1.8 `[protocol]` `codelab_agent_acp`: агрегаты usage на сессию сервера (шаг, ход, сессия, `seq`, причины, микроединицы, `beforeLoad` по реплею) и проекция `StepEnded`/`TurnEnded`/`ContextCompacted` в `_codelab/session/usage` через ту же `OutboundQueue`, только объявившим соединениям; снимок `turn` — до ответа на `session/prompt` при любом итоге (D4, D6, D7, D9). Тесты 1.3, 1.4, 1.5 зелёные; `conformance:agent`, `conformance:embedded`, `web-compile`.
- [ ] 1.9 `[agent]` `apps/codelab_agent`: тест бинаря `agent_host_test.dart` — `usage` в объявлении и по `--stdio`, и по `--ws` (Q6 (а)). Регрессионный: правка хоста не ожидается.

## 2. Клиентский слой (итерация 2)

### 2a. Красные тесты

- [ ] 2.1 `[client]` `codelab_client_acp/test/initialize_codelab_extensions_test.dart` (существующий тест D9 или новый): `usage` в `clientCapabilities._meta.codelab`; согласованный `usage` из ответа агента; терпимость к `usage: true` и `{"version": "1"}` (acp-protocol-client «Объявление расширений CodeLab при initialize»: «Запрос initialize клиента CodeLab», «Агент объявил usage», «Будущая версия расширения»). Красный.
- [ ] 2.2 `[client]` `codelab_client_acp/test/usage_notification_routing_test.dart` на `FakeAcpTransport`: снимок во время хода и после ответа не меняет статус хода; без `sessionId` — отброшен; уведомление старого поколения помечено им; другие `_vendor/*` по-прежнему отбрасываются (acp-protocol-client «Приём уведомления `_codelab/session/usage`»). Красный.
- [ ] 2.3 `[client]` `codelab_client_acp/test/budget_exceeded_test.dart`: `cost`, незнакомое `energy`, без `_meta`, `budgetExceeded` при `end_turn` игнорируется (acp-protocol-client «Причина остановки по бюджету»). Красный.
- [ ] 2.4 `[client]` `codelab_client_core/test/usage/usage_decoder_test.dart`: форма D2; неизвестные поля и причины игнорируются; неверный тип необязательного поля — поле отсутствует и одно предупреждение; неверные обязательные — снимок отброшен; строки денег `"0"`, `"0.000001"`, `"12.5"` → микроединицы, `"1e-3"`, `"-1"`, `"0.0000001"` → нет стоимости; `cost` без `currency` (acp-client-kit «Usage сессии»: «Неверный тип поля», «Причины неполноты», «Деньги без накопления ошибки»; D8, D9). Красный.
- [ ] 2.5 `[client]` `codelab_client_core/test/usage/session_usage_test.dart`: `unknown`/`awaiting`/`reported`; два хода; `seq` 3, 5, 4, 5; сброс при переподключении и `session/load`; неизвестная сессия; `compactionSoon` по `compactAt` («Скорое сжатие»); одна ревизия `SessionView` на снимок (acp-client-kit «Usage сессии»: «Агент без расширения», «Два хода», «Дубль и опоздание», «Переподключение»; VIEW-6). Красный.
- [ ] 2.6 `[client]` `codelab_client_core/test/transcript/budget_notice_test.dart`: заметки `The turn stopped: budget exceeded: cost.` и прежний текст без причины и с `energy` (acp-client-kit «Заметка остановки по бюджету»). Красный.
- [ ] 2.7 `[protocol]` Клиентская роль фикстур: `acp/prompt-usage-steps` (проверка `SessionView.usage` после хода), `acp/prompt-turn-budget-exceeded` (заметка), клиентские фикстуры с `initialize` — `usage` в объявлении (acp-golden-fixtures «Клиентский прогон», «Причина бюджета у клиента»). Красные в `conformance:client`.

### 2b. Реализация

- [ ] 2.8 `[client]` `codelab_client_acp`: `usage` в объявлении и согласованных возможностях; маршрут `_codelab/session/usage` с поколением соединения; `budgetExceeded` в итоге `PromptTurn` (freezed, `build_runner`). Тесты 2.1–2.3 зелёные.
- [ ] 2.9 `[client]` `codelab_client_core`: `lib/src/usage/` (`UsageDecoder`, `UsageView`, `UsageTotals`, `TokenCounts`, `Money`, `UsagePartial`, `ContextFillView`), `SessionView.usage`, проводка через `AgentBackend`/`AcpClientBackend`, свёртка по `seq`, логи D14; заметка бюджета в `transcript_projector.dart`; барель; `AGENTS.md` пакета — usage в перечне назначения. Тесты 2.4–2.7 зелёные; `conformance:client`, `web-compile`.

## 3. Desktop и CLI (итерация 3)

### 3a. Красные тесты

- [ ] 3.1 `[desktop]` `codelab_ui/test/.../codelab_session_status_bar_test.dart`: подписи и тон из данных; `usage: —` с подсказкой; `—` с `price unknown`; индикатор при ожидании; нет `0` при неизвестном (DSK-11; agent-workbench-ui «Строка статуса сессии под композером»). Красный.
- [ ] 3.2 `[desktop]` `apps/codelab_desktop/test/.../usage_status_mapper_test.dart`: `SessionView.usage` → данные строки: вход `input + cacheRead + cacheWrite`, `~` по причинам, деньги из микроединиц (`0.0041` → `$0.0041`, `1.2` → `$1.20`), контекст 85 % → `warning`, 96 % → `danger`, без `size` — скрыт; `compaction soon` только при `compactionSoon` (agent-workbench-ui: «Два хода», «Контекст близко к пределу», «Неполная сумма после загрузки», «Цена неизвестна»). Красный.
- [ ] 3.3 `[desktop]` Widget-тест рабочего места: строка статуса под композером активной сессии с ключами `status-bar-usage`, `status-bar-cost`, `status-bar-context`; агент без расширения — `usage: —` («Агент без расширения»). Красный.
- [ ] 3.4 `[client]` `apps/codelab_cli/test/tui/status_line_test.dart`: сегменты, `~`, порядок отбрасывания при 120/60/40/25, без usage — нет `ctx`, `↑`, `$`, `0`; цвет порогов в `render` (codelab-tui «Строка подсказок и статус-строка TUI»: все сценарии). Красный.
- [ ] 3.5 `[protocol]` `codelab_acp_testing`: режим scripted-агента, который объявляет `usage` и шлёт снимки по сценарию (для e2e app и CLI, §12.3 «Scripted-агент»); тест режима. Красный.
- [ ] 3.6 `[client]` PTY-e2e `apps/codelab_cli/test/e2e/status_line_usage_test.dart` (`cli/status-line-usage`, U-13): `--ui tui` против scripted-агента с usage — `ctx 9%`, `↑…k ↓…`, `$0.04`; без usage — нет сегментов и `0`; тот же тест с `CODELAB_E2E_AGENT=dart` и сценарием `--llm-script` с ценами модели. Красный.
- [ ] 3.7 `[client]` `apps/codelab_cli/test/repl/after_turn_status_test.dart`: строка после хода на `ansi` (приглушённо) и `plain`; нет на `raw` и в headless; без usage — только режим и модель (codelab-cli «Строка статуса после хода в REPL»). Красный.
- [ ] 3.8 `[desktop]` `apps/codelab_desktop/integration_test/usage_display_flow_test.dart` (D-09): агент без расширения — `usage: —`; scripted-агент с usage двух ходов — ход и сессия, подсказка с пятью счётчиками, контекст 85 % в `warning`. Приёмка `release/*`: в `feature/*` только `fvm flutter analyze`. Скрипт `test:e2e:app:usage` в корневом `pubspec.yaml`.

### 3b. Реализация

- [ ] 3.9 `[protocol]` Режим usage scripted-агента. Тест 3.5 зелёный.
- [ ] 3.10 `[desktop]` `CodeLabSessionStatusBar` в `codelab_ui` (превью в каталоге компонентов), маппер и разметка под композером в `apps/codelab_desktop`; doc-комментарии по-русски со ссылкой на D11. Тесты 3.1–3.3 зелёные; `fvm flutter analyze` для 3.8.
- [ ] 3.11 `[client]` `status_line.dart` и `StatusInfo`: сегменты контекста, токенов, стоимости, порядок отбрасывания, цвет в `render`. Тесты 3.4 и 3.6 зелёные; `test:e2e:cli:dart-agent`.
- [ ] 3.12 `[client]` строка статуса после хода в REPL. Тест 3.7 зелёный.

## 4. Завершение

- [ ] 4.1 `[desktop]` Ручная проверка на macOS (debug): встроенный агент с моделью с ценами и без цен; отмена хода; `/compact`; перезапуск app и загрузка сессии — `~`. Итог — в design.md.
- [ ] 4.2 Документы и код не расходятся (`packages/dart/codelab_agent_core/AGENTS.md` §3, п. «е»): §13, §12.1, §12.2.6, §12.3 A7, матрица; `openspec validate add-usage-extension --strict`.
