Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Красные тесты пишутся одной задачей и коммитятся отдельно, до кода, — только по явной просьбе пользователя. В скобках — сценарий спецификации, решение design.md или инвариант.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`;
- `[protocol]` — `codelab_agent_acp`, `codelab_acp_testing`;
- `[client]` — `codelab_client_core` (только тесты).

Задач `[desktop]` нет.

**Старт реализации** — только после трёх условий (design.md, R1, D10):
1. ответы пользователя на Q1–Q5 (получены 2026-11-17, все (а));
2. слияние PR #346 (`add-usage-ledger`) в `develop`;
3. перебазирование ветки `feature/fix-discarded-compaction-usage` на `develop`.

Порядок: 0.2а → 0.3 → 0.4 → 1.1 → 1.2 → 1.3 → 2.1 → 2.2 → 3.1 → 4 → 5. Одна ветка, один PR в `develop`.

Проверки — только затронутое (корневой `AGENTS.md` §21); полный `melos run check` — по просьбе пользователя.

## 0. Документы

- [x] 0.1 OpenSpec change: `proposal.md`, `design.md` (D1–D10, Q1–Q5), дельты `agent-compaction`, `agent-sessions`, `agent-slash-commands`, `agent-acp-server`, `acp-golden-fixtures`; `openspec validate fix-discarded-compaction-usage --strict`.
- [x] 0.2 Ответы пользователя на Q1–Q5 — в design.md (раздел «Решения пользователя 2026-11-17») и в дельты; пометки «до решения пользователя» заменены на «решение пользователя Qn». *Итог 2026-11-17:* все ответы — (а), совпадают с рекомендациями.
- [ ] 0.2а После перебазирования на `develop` с `add-usage-ledger` сверить D1–D5 с влитым кодом: `SummaryResult`, `ContextCompacted.usage`, `buildUsageLedger`, `UsageLedgerGroup`, `UsageAccounting.summarizerEnded`, `compactionSnapshot`. Расхождения — в design.md до красных тестов (R1).
- [ ] 0.3 `[agent]` Документы ядра по принятым ответам (архитектор; «сначала документ»):
  - `agent-core/08-sessions.md` §8.2.4 — строка `custom`: известный `customType` `codelab.compaction_discarded` с полями `data` (D1), рядом с `codelab.cwd_changed`;
  - `09-compaction.md` §9.8 — шаг «нет выигрыша»: запись учёта, `CompactionDiscarded`, поля лога; §9.9 — CMP-10 «кроме записи учёта»; §9.11 — тесты задачи 1.1;
  - `05-agent-loop.md` — каталог событий: `CompactionDiscarded` (D2);
  - `12-observability-and-errors.md` — §12.3, каталог `compaction`: поля `usage_record_id`, `summary_model` у `compaction.skipped` (D6); §12.6.1 — шаг 2c свёртки, ключ `summaries.discarded`, строка `Summaries` (D3, D4).
- [ ] 0.4 `[protocol]` `agent-core/13-acp-adapter.md`:
  - таблица проекции событий — `CompactionDiscarded`: кадров `session/update` нет, снимок `compactionDiscarded`;
  - §13.12 — повод `compactionDiscarded`, `summaries.discarded` в ответе журнала (D5).

## 1. Ядро (`codelab_agent_core`)

- [ ] 1.1 `[agent]` Красные тесты (дельты `agent-compaction`, `agent-sessions`, `agent-slash-commands`; D1–D4, D6):
  - `test/compaction/compactor_test.dart`:
    - «/compact без выигрыша записывает учёт»: резюме `'x' * 20000` с usage `{input: 764, output: 171}` и моделью. Ожидается одна запись `custom` `codelab.compaction_discarded` с полями `data` по D1 и без `summary`; сообщения `buildLlmContext` до и после равны; `CompactionDiscarded` с теми же usage и моделью; `ContextCompacted` нет; лог `compaction.skipped` с `usage_record_id` и `summary_model`;
    - «Второй проход без выигрыша»: запись `compaction`, затем запись учёта с `pass: 2`; по одному `ContextCompacted` и `CompactionDiscarded`;
    - «Нет точки среза», «Сбой и отмена»: записи учёта и события нет;
    - «Запись учёта в регионе следующего сжатия»: после записи учёта следующий `compact` даёт ту же точку среза и тот же `SummaryRequest.region`, что без неё.
  - `test/runtime/builtin_slash_commands_test.dart`, «/compact без выигрыша»: ответ `Nothing to compact.`, в журнале одна запись учёта, `TurnEnded.usage` без суммаризатора.
  - `test/compaction/overflow_then_compact_test.dart`, «Аварийное сжатие без выигрыша»: запись учёта с `trigger: "overflow"`, `TurnEnded(failed)`, `TurnEnded.usage` без суммаризатора.
  - `test/session/` (реплей): журнал с записью учёта — реплей без `CompactionDiscarded`; читатель сохраняет запись как `CustomRecord`, проекция та же («Старое ядро читает новую запись»: проверить, что старый путь разбора `custom` не меняется).
  - `test/usage/usage_ledger_test.dart`: «Отброшенный вызов в свёртке», «Записанный и отброшенный проходы», «Цена отброшенного вызова» (через отчёт и каталог), «Запись неверной формы»; детерминизм сериализации с `discarded`.
  - `test/usage/usage_report_text_test.dart` (или рядом с тестом текста `/usage`): «/usage после /compact без выигрыша», «Без отброшенных вызовов».
- [ ] 1.2 `[agent]` Характеризационная правка тестов change `fix-compaction-estimate-and-no-gain`, которые проверяют неизменный журнал при проходе без выигрыша (design.md, R2; исключение (а) TDD ядра): `compactor_test.dart` «Резюме длиннее региона», «Второй проход без выигрыша», «Навыки не выбрасываются ради выигрыша», `builtin_slash_commands_test.dart` «/compact без выигрыша», `overflow_then_compact_test.dart` «Аварийное сжатие без выигрыша». Ожидание «журнал не изменился» заменяется на «единственная новая запись — учёт D1; записей `compaction` нет; проекция и транскрипт те же». Каждая правка — с комментарием-ссылкой на D1 этого change.
- [ ] 1.3 `[agent]` Реализация 1.1–1.2:
  - `lib/src/loop/agent_events.dart`: `CompactionDiscarded` с doc-комментарием (почему, для чего, как; D2); экспорт в барели;
  - `lib/src/compaction/compactor.dart`: на ветке `after >= before` — `writer.append` записи `CustomRecord` (D1), затем `emit(CompactionDiscarded(...))`, затем лог `compaction.skipped` с `usage_record_id`, `summary_model`; doc-комментарии `compact` и `NothingToCompact` обновить;
  - исчерпывающие `switch` по `AgentEvent` в ядре (`session_writer.dart` и др.) — ветка без действия;
  - `lib/src/usage/usage_ledger.dart`: разбор записи учёта в `buildUsageLedger`, `UsageLedgerGroup.discarded`, ключ `discarded` в сериализации `usage.json` (D3);
  - `lib/src/usage/usage_report_text.dart`: строка `Summaries` (D4);
  - константа `customType` — одна, в ядре, рядом с компактором или свёрткой; без дублирования строки.

## 2. Адаптер ACP и фикстура

- [ ] 2.1 `[protocol]` Красные тесты (дельта `agent-acp-server`; D5):
  - `packages/dart/codelab_agent_acp/test/usage_bridge_test.dart`:
    - «/compact без выигрыша в живой сумме»: снимок `compactionDiscarded` с суммой, прежними `turns`/`steps`, `context.used` = `tokensBefore`, без `turnId`/`step`/`turn`;
    - «Клиент без объявления»: кадров нет;
    - при нулевом usage — `noUsage`;
    - модель без цен — `noPrice`;
    - «Записанное сжатие без изменений»;
  - `usage_projection_test.dart`, «Сумма после session/load»: засев включает отброшенный вызов; `session` снимка `load` равен `total` ответа журнала;
  - тест ответа журнала: `summaries.discarded` при ненулевом значении и его отсутствие при нуле;
  - фикстура `packages/dart/codelab_acp_testing` `acp/compact-no-gain-usage` по D7 (красная до 2.2 в `conformance:agent`).
- [ ] 2.2 `[protocol]` Реализация 2.1:
  - `session_bridge.dart`: ветка `CompactionDiscarded` — `summarizerEnded` и `_sendUsage('compactionDiscarded', …)`;
  - `usage_accounting.dart`: построитель снимка (общий с `compactionSnapshot` по `used`, повод — параметр) и `discarded` в `summaries` ответа журнала;
  - `event_projection.dart`: ветка `CompactionDiscarded() => const []`.

## 3. Клиент

- [ ] 3.1 `[client]` Тесты совместимости без кода (D5, R7):
  - `packages/dart/codelab_client_core/test/usage/` — снимок `trigger: "compactionDiscarded"` разбирается как `UsageTrigger.unknown`, обновляет `session` и `context` и не трогает `lastTurn`;
  - ответ журнала с `summaries.discarded` разбирается без предупреждения `usage.ledger.decode_failed`, `summaries.count` и токены — из ответа.
  
  Если тест красный, остановиться и вернуть вопрос архитектору: правка клиента в этот change не входит.

## 4. Проверки

- [ ] 4.1 `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_agent_acp`, `codelab_client_core` (только тесты 3.1).
- [ ] 4.2 `fvm dart run melos run conformance:agent`: новая фикстура и существующие фикстуры сжатия без правок (сценарий «Корпус не меняется»). `fvm dart run melos run protocol-conformance` — корпус фикстур.
- [ ] 4.3 `fvm dart run melos run web-compile` (изменён `codelab_agent_core`); `fvm dart run melos run test:e2e:cli:dart-agent` (изменён агент, через который работает CLI).
- [ ] 4.4 Ручная проверка (по образцу D16 change `add-usage-ledger`): CLI REPL, встроенный агент, модель с ценами, `compaction.keep_recent_tokens: 100`, `/compact` без выигрыша. Ожидается: строка статуса растёт на стоимость вызова сразу; `/usage` — `Summaries: 1 (1 discarded), …`; после перезапуска с `--continue` сумма та же, без «~». Ключа провайдера нет ни в журнале, ни в `usage.json`.
- [ ] 4.5 `openspec validate fix-discarded-compaction-usage --strict`.

## 5. Закрытие

- [ ] 5.1 Сверка документов 0.3–0.4 с кодом: имена события, полей записи и лога, текст `/usage`.
- [ ] 5.2 Подготовка к архивации (design.md, D8). Порядок: `fix-compaction-estimate-and-no-gain` → `add-usage-ledger` → этот change. Если к этому моменту уточняемые требования уже в `openspec/specs/`, ADDED-требования перевести в MODIFIED:
  - `agent-compaction` «Сжатие без выигрыша не применяется» — убрать «журнал не меняется» для отброшенного прохода;
  - «Журнал usage сессии»;
  - «Команда /usage»;
  - «Уведомление `_codelab/session/usage`» — новый повод в списке.
  
  Так основная спецификация не будет противоречить себе. `openspec validate --strict` после правки.
