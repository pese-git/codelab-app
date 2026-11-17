Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала одной задачей пишутся красные тесты. Их коммитят отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках — сценарий спецификации, решение design.md, критерий матрицы или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`;
- `[protocol]` — `codelab_agent_acp`, `codelab_acp_protocol`, `codelab_acp_testing` (фикстуры, scripted-агент);
- `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`.

Итерации — каждая отдельным PR в `develop` (design.md, D14):
- 0 — документы;
- 1 — ядро и io;
- 2 — протокол;
- 3 — клиент.

Решения пользователя 2026-11-17 по Q1–Q9 — все (а) (design.md, «Решения пользователя 2026-11-17»).

Зависимости: 1 ← 0 (выполнено 2026-11-17); 2 ← 1; 3 ← 2. Change архивируется после `add-usage-extension` (design.md, R1).

Проверки каждой задачи — только для затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке `codelab_agent_core`, `codelab_client_core`, `codelab_client_acp`;
- `fvm dart run melos run protocol-conformance`, `conformance:agent`, `conformance:client`, `conformance:embedded` — при правке фикстур, проекции и kit;
- `fvm dart run melos run prompts:check` — при правке промпта суммаризатора (не ожидается);
- `fvm dart run melos run test:e2e:cli:dart-agent` — при правке `apps/codelab_cli` и клиентского слоя.

## 0. Документы (итерация 0)

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D14, вопросы Q1–Q9), дельты `agent-sessions`, `agent-compaction`, `agent-slash-commands`, `agent-acp-server`, `acp-protocol-client`, `acp-client-kit`, `acp-golden-fixtures`; `openspec validate add-usage-ledger --strict`.
- [x] 0.2 Сверка дельт с change `add-usage-extension` (design.md, R1). Проверить, что требования `agent-acp-server` «initialize», «Расширения протокола этапа 4», «Уведомление `_codelab/session/usage`» и `acp-client-kit` «Usage сессии» пересобраны из его текущего текста и все его строки сохранены, кроме правок этого change. Правки: ключ `usageLedger`, `trigger: "load"`, засев вместо `beforeLoad`, суммаризатор в сумме, сброс usage в начале загрузки, ожидание снимка до регистрации сессии. Повторить перед архивацией, если тот change снова изменит эти требования. *Итог 2026-11-17:* скриптовая сверка строк — все непустые строки четырёх требований есть в дельтах, кроме девяти, расширенных правками этого change (перечислены выше).
- [x] 0.3 Ответы пользователя на Q1–Q9 — в design.md (раздел «Решения пользователя 2026-11-17») и в дельты. *Итог:* все ответы — (а), совпадают с рекомендациями; пометки «по рекомендации» в D заменены на «решение пользователя», Open Questions — «Нет».
- [x] 0.4 `[agent]` Документы ядра по принятым ответам:
  - `agent-core/12-observability-and-errors.md`: §12.6 — суммаризатор в сумме сессии вместо «до change `add-usage-ledger`»; `TurnEnded.usage` без суммаризатора — поправить строку про `compactionUsage` (D4); §12.6.1 — свёртка по записям, правило хода, `loop_note`, `toolCallIds`, `turns`, `source` без `bytes`, `byBranch` и `inherited` отложены, `noPrice` по каталогу, текст `/usage` (D1–D3, D5); OBS-10 — «функция записей журнала»; §12.9 — тесты задач 1.1–1.4;
  - `08-sessions.md` §8.2.4 — `details.usage` у `compaction` с этапа change; §8.9 — `usage.json` больше не «после MVP»;
  - `09-compaction.md` — `Summarizer` с usage, `ContextCompacted.usage`;
  - `05-agent-loop.md` — `ContextCompacted` без usage в ходе;
  - `10-core-assembly-and-profiles.md` — порт `UsageLedgerStore` в `AgentCoreServices`.
- [x] 0.5 `[protocol]` `agent-core/13-acp-adapter.md`:
  - §13.2 — ключ `usageLedger`;
  - §13.4 — `usage` в списке после `status` и отметка «реализовано»;
  - §13.5 — снимок `load` после ответа и засев;
  - §13.7 — строка `ContextCompacted` (суммаризатор в сумме);
  - §13.12 — строки ключа `usageLedger`, метода `_codelab/session/usage/ledger` и повода `load` со ссылкой на change и пометкой о соответствии «Custom Requests» `15-Extensibility.md`; строка `beforeLoad` — «агент CodeLab не ставит»;
  - §13.13 — диаграмма `session/load` со снимком после ответа;
  - §13.16 — фикстуры D11 вместо `acp/usage-and-redact-commands` для `/usage`;
  - `14-golden-fixtures.md` — метка `usageLedger`.
- [x] 0.6 `[client]` `dart-agent-and-clients/12-1-view-model.md` §12.1.5:
  - п. 3 — полная сумма после загрузки, сброс в начале загрузки, ожидание снимка до регистрации сессии;
  - новый пункт — `SessionView.usageLedger`, `refreshUsageLedger`, правило «kit не сливает журнал со снимками»;
  - §12.1.10 — тесты задач 3.1–3.4.
  
  `12-3-desktop-display.md` A7: строка «после загрузки — `beforeLoad`» → полная сумма у агента CodeLab; панель Usage берёт данные из `SessionView.usageLedger` (ссылка для change `add-desktop-usage-pane`).
- [x] 0.7 `delivery-roadmap.md` §4.6, §6.2 п. 1 — второй change открыт, что закрывает; `agent-parity-goals.md`:
  - L-29: «Как в ACP» — `/usage` и `_codelab/session/usage/ledger`; критерий `core/usage-ledger-rebuild-deterministic` (`usage_ledger_test.dart`, `usage_ledger_store_test.dart`), фикстуры `acp/slash-usage`, `acp/usage-ledger-request`;
  - D-09: панель — `add-desktop-usage-pane` поверх `SessionView.usageLedger`.
  
  Строки матрицы закрытыми не отмечаются: реализации ещё нет.

## 1. Ядро и io (итерация 1)

### 1a. Красные тесты

- [x] 1.1 `[agent]` `codelab_agent_core/test/usage/usage_ledger_test.dart` (новый) — свёртка на снимках, собранных вручную (`SessionSnapshot` из записей):
  - два хода — ходы и шаги, `toolCallIds`, номера шагов с 0;
  - `steer` не открывает ход, `loop_note` — не шаг;
  - `noUsage` у ответа без usage, но не у `error`; шаг только с кэш-токенами — без `noUsage`;
  - ход без шагов не входит;
  - подпись хода — 64 руны, у `command` — исходный текст;
  - завершённый `subagent` — в ходе и сессии, не в моделях; незавершённый и не последний по `subagentId` — нет;
  - `compaction` с `details.usage` — `summaries`;
  - модели по алфавиту;
  - сериализация дважды побайтово равна (`core/usage-ledger-rebuild-deterministic`, OBS-10);
  - журнал без шагов;
  - в сериализации нет текстов ответов и аргументов.
  
  Отчёт: модели без цен по каталогу сессии; модель, которой нет в каталоге, — без цены (agent-sessions «Журнал usage сессии»; D1, D2, Q4, Q9). Красный.
- [x] 1.2 `[agent]` `codelab_agent_core/test/usage/usage_ledger_report_test.dart` (новый, на фейковом `UsageLedgerStore` в памяти):
  - файл отсутствует — `missing`, записан;
  - повтор — `upToDate` без записи;
  - дописанная запись — `stale`; битый JSON и `version: 2` — `invalid`; `rebuild` — `explicit`;
  - сбой `write` — `notSaved` и warning `usage.ledger.write_failed`;
  - без порта — `inMemory` без обращений;
  - два одновременных вызова — одна запись;
  - `rebuild` во время обычного — одна операция после неё;
  - закрытие сессии ждёт запись;
  - лог `usage.ledger.rebuild` с `reason`, `records`, `duration_ms`.
  
  (agent-sessions «Файл usage.json и порт UsageLedgerStore»; D3). Красный.
- [x] 1.3 `[agent]` `codelab_agent_core/test/compaction/compaction_usage_test.dart` (новый, на `ScriptedStreamFunction`):
  - `/compact` — `details.usage` и модель в записи, `ContextCompacted.usage` и модель;
  - два прохода сжатия — два события;
  - аварийное сжатие посреди хода — `TurnEnded.usage` без суммаризатора;
  - реплей старой записи без `details.usage` — `usage == null`.
  
  Существующие тесты `Summarizer` правятся под новый тип результата (agent-compaction «Usage суммаризатора»; D4, Q6). Красный.
- [x] 1.4 `[agent]` `codelab_agent_core/test/commands/usage_command_test.dart` (новый):
  - `/usage` после двух ходов — текст D5 построчно;
  - повтор — `up to date`; `/usage rebuild`;
  - модель без цен — `cost unknown`, частичная цена — `~$`, `noUsage` — `input ~`;
  - `Subagents` и `Summaries` при ненулевых счётчиках;
  - пустая сессия — `Session usage: no model requests yet`;
  - `/usage now` — `Usage: /usage [rebuild]`;
  - без порта — `rebuilt in memory`;
  - отмена до ответа — `cancelled` без сообщения;
  - журнал без записей команды.
  
  `builtin_commands_test` и тест списка команд: `usage` после `status` (agent-slash-commands «Команда /usage», «Список команд сессии»; D5, Q7). Красный.
- [x] 1.5 `[agent]` `codelab_agent_io/test/session/usage_ledger_store_test.dart` (новый, во временном каталоге): запись в `<журнал без .jsonl>/usage.json` через `.tmp` и `rename`; чтение отсутствующего — `null`; удалённый файл восстанавливается побайтово тем же; каталог без прав на запись — типизированная ошибка без падения процесса; путь не выходит за `sessions/` (agent-sessions «Удалённый файл восстанавливается»; D3, D13). Красный.
- [x] 1.6 `[protocol]` Фикстура `acp/slash-usage` (роль `agent`, метки `usage`, `usageLedger`), конструкция по `acp/slash-help`; ожидание текста `/usage`. Красная в `conformance:agent`. *Сверка с кодом итерации 1:* список команд строит ядро, поэтому в этой итерации уже правлены 7 фикстур с явным списком (`available-commands-no-tools`, `prompt-template-command`, `skill-command-listed`, `skill-invoke`, `skill-tool-load`, `slash-help`, `slash-mcp-list`) и текст `/help` в `slash-help` и `slash-mode-plan` (D11, R9).

### 1b. Реализация

- [x] 1.7 `[agent]` `codelab_agent_core/lib/src/usage/`:
  - свёртка `buildUsageLedger` (D1), модель журнала и сериализация формата v1 (D3);
  - отчёт с моделями без цены по `AgentSession.models` (D2);
  - порт `UsageLedgerStore` в `host/services.dart` (необязательный);
  - операция `AgentSession.usageLedger({rebuild})` и вариант в памяти для засева;
  - одна операция с записью на сессию; закрытие сессии ждёт запись;
  - барель; doc-комментарии по-русски со ссылками на D1–D3, OBS-10.
  
  Тесты 1.1, 1.2 зелёные; `web-compile`, `guard`.
- [x] 1.8 `[agent]` `Summarizer` с результатом (текст, usage, модель); реализация рантайма берёт usage и модель из `AssistantMessage`; `compact` пишет `details.usage`; `ContextCompacted` получает `usage` и модель; реплей — `null` без `details.usage` (D4). Тест 1.3 зелёный; существующие тесты сжатия и агентские фикстуры `acp/slash-compact`, `acp/compact-usage-context` без изменений кадров.
- [x] 1.9 `[agent]` `/usage [rebuild]` в `commands/builtin_commands.dart`: объявление §13.4, место после `status`, текст D5 с правилами Q7. Тест 1.4 зелёный.
- [x] 1.10 `[agent]` `codelab_agent_io`: реализация `UsageLedgerStore` по каталогу сессии `JsonlSessionStore` (§8.9); `apps/codelab_agent` (`agent_host.dart`: `serve` и сценарный режим `--llm-script` — при `--sessions-dir`, на том же `JsonlSessionStore`, что журнал; без `--sessions-dir` сессии в памяти и `/usage` — `rebuilt in memory`; так `test-scenario` проигрывает `acp/slash-usage` против бинаря — сверка с кодом итерации 1) и настольный открыватель `codelab_embedded/lib/io.dart` передают порт в `AgentCoreServices`; сценарный открыватель — только с файловым журналом `sessionsDir` (сверка с кодом итерации 1); основной барель `codelab_embedded` порт не получает (`inMemory`). Тест 1.5 зелёный; `guard`, `web-compile` (барель `codelab_embedded`).
- [x] 1.11 `[protocol]` `conformance:agent` для `acp/slash-usage` зелёный. Агентская фабрика `codelab_agent_acp/test/conformance_test.dart` передаёт настоящий порт во временном каталоге; `acp/slash-usage` ждёт `Ledger: rebuilt from journal` (D11).

## 2. Протокол (итерация 2)

### 2a. Красные тесты

- [ ] 2.1 `[protocol]` `codelab_agent_acp/test/initialize_test.dart` (существующий): `usageLedger: {"version": 1}` в блоке при любом `clientCapabilities._meta.codelab`; ключ `usageLedger` от клиента ни на что не влияет; без `_meta.codelab` — блока нет (agent-acp-server «initialize»: «(usageLedger)»; D7). Красный.
- [ ] 2.2 `[protocol]` `codelab_agent_acp/test/usage_ledger_request_test.dart` (новый, на `test/support/server_harness.dart`):
  - форма результата D6 после хода с двумя шагами и `read`;
  - `seq` — последний снимок; `total` равен `session` последнего снимка;
  - `rebuild` — `explicit`; незнакомая сессия — `-32002`; неверный тип `rebuild` — `-32602`;
  - запрос во время хода — `running: true`, ход не меняется; `session/cancel` запрос не отменяет;
  - модель без цен — без `cost`, `noPrice`;
  - сбой записи — `notSaved`; исключение свёртки — `-32603` с `usageLedgerFailed`;
  - лог `acp.usage.ledger` без токенов и денег;
  - стандартные типы без новых полей.
  
  (agent-acp-server «Запрос `_codelab/session/usage/ledger`»; D6). Красный.
- [ ] 2.3 `[protocol]` `codelab_agent_acp/test/usage_ledger_seed_test.dart` (новый):
  - засев на `session/load` журнала с тремя ходами, субагентом и сжатием с usage суммаризатора — `session` снимка `load` равен `total` ответа журнала по токенам, стоимости, `turns`, `steps`, `partial`; `beforeLoad` нет;
  - следующий ход прибавляется;
  - `reattach` — без пересева, снимок `load` с очередным `seq`;
  - журнал без шагов — снимка `load` нет;
  - соединение без `usage` — снимков нет;
  - снимок `load` после ответа `session/load` и после всех кадров реплея;
  - `/compact` в живой сессии — суммаризатор в `session` снимка `compaction`, `turn` следующего хода его не содержит;
  - лог `acp.usage.seeded`.
  
  Тест `usage_projection_test.dart`: ожидание `beforeLoad` заменяется полной суммой; сценарий «Сессия перешла к новому соединению» — снимок `load` с `seq` 4, ход с `seq` 5 (agent-acp-server «Полная сумма сессии после session/load», «Уведомление»: «Сессия после загрузки», «Загрузка сессии без шагов», «Суммаризатор в сумме сессии»; D4, D8). Красный.
- [ ] 2.4 `[protocol]` Замер R4: `codelab_agent_acp/test/usage_ledger_size_test.dart` (новый, тег `slow`, входит в `check`) на синтетическом журнале 1 000 ходов × 40 шагов. Время построения и кодирования ответа и размер JSON печатаются в вывод теста; тест падает при размере больше 16 МБ или времени больше 5 с на CI. Если порог не проходит, работа останавливается: вопрос о пагинации (Q8 (б)) возвращается к пользователю до итерации 3. Красный до 2.6.
- [ ] 2.5 `[protocol]` Фикстуры D11 с ролью `agent`: `acp/usage-ledger-request` (роль `client` — в 3.5), `acp/usage-ledger-rebuild`, `acp/session-load-usage-full` (вместо удаляемой `acp/session-load-usage-partial`), `acp/compact-usage-summary`. В `acp/initialize-codelab-extensions` — `usageLedger` в ответе агента (`a2c`). Фабрика агентского прогона даёт порт во временном каталоге и сценарный ответ суммаризатора с usage (D11). Красные в `conformance:agent`.

### 2b. Реализация

- [ ] 2.6 `[protocol]` `codelab_agent_acp`:
  - ключ `usageLedger` в `_codelabExtensions` (`agent_server.dart`);
  - ветка `_codelab/session/usage/ledger` в `_onRequest`: поиск `_bridge`, разбор параметров, `AgentSession.usageLedger`;
  - проекция отчёта в результат D6 — микродоллары и причины общей функцией с `UsageAccounting` (D2), `seq` моста;
  - лог `acp.usage.ledger`; doc-комментарии по-русски со ссылкой на D6, D17 change `add-usage-extension`.
  
  Тесты 2.1, 2.2, 2.4 зелёные.
- [ ] 2.7 `[protocol]` Засев `UsageAccounting` отчётом в памяти при создании моста веткой `session/load` вместо `markLoadedFromJournal`. Снимок `trigger: "load"` через `Reply.after` после ответа `session/load`, в том числе при `reattach`: только объявившим `usage` и только при ненулевых шагах. Слагаемое суммаризатора по `ContextCompacted.usage` (не в ход). `noPrice` суммаризатора по каталогу. Лог `acp.usage.seeded`. `UsagePartial.beforeLoad` остаётся в перечислении, но мостом CodeLab не ставится. Тест 2.3 зелёный.
- [ ] 2.8 `[protocol]` `codelab_acp_testing` (сужено по сверке с кодом итерации 1: списки команд уже правлены в 1.6, R9). Scripted-агент `codelab_compatible_stdio_agent.dart` в режиме `with_usage` шлёт снимок `load` после ответа `session/load` — для e2e клиентов в 3.6, 3.7. Фикстуры 2.5 и `acp/slash-usage` зелёные в `conformance:agent`, `conformance:embedded`; `protocol-conformance`; `test:e2e:cli:dart-agent`.

## 3. Клиент (итерация 3)

### 3a. Красные тесты

- [ ] 3.1 `[client]` `codelab_client_acp/test/application/usage_ledger_request_test.dart` (новый, на `FakeAcpTransport`):
  - `CodelabExtensions.usageLedger` только при целом `version: 1`;
  - запрос с `rebuild` и без него — кадр, сырой результат и поколение;
  - без ключа — отказ без кадра;
  - `-32601` и `-32002` — типизированный сбой с кодом;
  - клиент не объявляет `usageLedger` (`initialize_codelab_request_test.dart` не меняется).
  
  (acp-protocol-client «Запрос журнала usage»; D7, D9). Красный.
- [ ] 3.2 `[client]` `codelab_client_core/test/usage/usage_ledger_decoder_test.dart` (новый):
  - форма D6; деньги в микроединицах, валюта, незнакомые причины;
  - без `sessionId`, `seq` или `total.tokens` — отказ; ход или шаг без обязательных полей пропущен;
  - неверный тип необязательного поля — поля нет, одно предупреждение на сессию и поле;
  - `toolCallIds` сохранены; исключений нет;
  - общий разбор агрегата с `UsageDecoder` — существующие `usage_decoder_test.dart` зелёные.
  
  (acp-client-kit «Журнал usage сессии в клиенте»; D10). Красный.
- [ ] 3.3 `[client]` `codelab_client_core/test/usage/session_usage_ledger_test.dart` (новый, на `ClientWorkspace` с `AcpClientBackend` и `FakeAcpTransport`):
  - `unavailable` без ключа; `idle` → `loading` → `loaded`;
  - слияние вызовов с `rebuild`;
  - ответ после переподключения отброшен с `usage.ledger.stale`; ответ после `session/load` той же сессии отброшен;
  - `failed` с кодом и предыдущим журналом;
  - сброс в `idle` при переподключении и `session/load`.
  
  (acp-client-kit «Журнал usage сессии в клиенте»: все сценарии). Красный.
- [ ] 3.4 `[client]` `codelab_client_core/test/usage/session_usage_test.dart` (существующий) — снимок `load`:
  - повторная загрузка открытой сессии, снимок обработан раньше обновления сессии по ответу — сумма не стёрта;
  - первая загрузка сессии из списка — снимок ждёт регистрации;
  - сбой загрузки — снимок отброшен с `usage.unknown_session`;
  - `UsageTrigger.load` не меняет `lastTurn`.
  
  (acp-client-kit «Usage сессии»: «Снимок load после загрузки», «Снимок load до регистрации сессии», «Загрузка сорвалась»; D10). Красный.
- [ ] 3.5 `[protocol]` Роль `client` фикстуры `acp/usage-ledger-request`: проверка состояния в `codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` (запрос ушёл с теми же параметрами) и в `codelab_client_core/test/usage/usage_fixture_test.dart` (`usageLedger` — `loaded`, один ход, два шага) (acp-golden-fixtures «Клиентский прогон журнала»). Красная в `conformance:client`.
- [ ] 3.6 `[desktop]` `apps/codelab_desktop/test/features/workbench/application/usage_status_mapper_test.dart` (существующий): после загрузки сессии со снимком `load` строка статуса до первого хода — `— · session $X` без «~» (D23 Т9 п. 3 change `add-usage-extension`; D8). Красный до 3.8 только если маппер требует правки; иначе тест — регрессионный и зелёный сразу, это фиксируется в PR.
- [ ] 3.7 `[client]` `apps/codelab_cli`: PTY-e2e `--continue` со scripted-агентом в режиме `with_usage` — строка REPL после первого хода без `~` от `beforeLoad` (`test/e2e/status_line_usage_test.dart`, существующий; D8). Регрессионный, как 3.6.

### 3b. Реализация

- [ ] 3.8 `[client]` `codelab_client_acp`: признак `usageLedger` в `CodelabExtensions` (`domain/codelab_extensions.dart`); метод запроса журнала в `AcpClientApplication` через `_sendRequest` с поколением соединения и типизированным сбоем. Тест 3.1 зелёный; `web-compile`.
- [ ] 3.9 `[client]` `codelab_client_core`, `lib/src/usage/`:
  - общий разбор агрегата из `UsageDecoder`;
  - `UsageLedgerDecoder`, модель журнала и состояние (freezed), `SessionView.usageLedger`;
  - `AgentBackend` с операцией запроса и реализация в `AcpClientBackend`;
  - `ClientWorkspace.refreshUsageLedger` со слиянием и защитой поколений;
  - `UsageTrigger.load`; сброс usage в начале загрузки; ожидание снимка до регистрации сессии;
  - барель; `codelab_client_core/AGENTS.md` §5 — строка про журнал usage;
  - `build_runner`.
  
  Тесты 3.2–3.5 зелёные; `web-compile`, `conformance:client`.
- [ ] 3.10 `[desktop]`, `[client]` Правки маппера desktop и статус-строки CLI, если 3.6 или 3.7 красные; иначе — без кода. `test:e2e:cli:dart-agent`.

## 4. Закрытие

- [ ] 4.1 Ручная проверка в отладочной сборке macOS и CLI со встроенным агентом и реальным провайдером, изолированный `CODELAB_HOME`:
  - два хода, перезапуск, загрузка — сумма без «~» до первого хода;
  - `/usage`, `/usage rebuild`; удалённый `usage.json` восстановлен;
  - `/compact` — сумма выросла на суммаризатор;
  - в выводе и журналах нет ключа провайдера.
  
  Итог — в design.md.
- [ ] 4.2 `agent-parity-goals.md`: L-29 закрыт (тесты и фикстуры); `delivery-roadmap.md` — change влит, следующий `add-desktop-usage-pane`. Сверка документов архитектуры с кодом.
