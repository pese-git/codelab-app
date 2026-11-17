## Why

Change `fix-compaction-estimate-and-no-gain` (в `develop`) ввёл CMP-10: проход сжатия, после которого согласованная оценка контекста не меньше оценки до него, не применяется. Компактор возвращает `NothingToCompact('no reduction')` (или `Compacted` прошлого прохода), запись `compaction` не пишет, `ContextCompacted` не эмитит и пишет только лог `compaction.skipped`. Но суммаризатор к этому моменту уже вызван, и запрос к модели оплачен.

Change `add-usage-ledger` (PR #346, ещё не влит) учитывает usage суммаризатора только через запись `compaction` (`details.usage`) и событие `ContextCompacted.usage` (его D4). У отброшенного прохода нет ни того, ни другого. Поэтому оплаченный вызов не попадает:
1. в сумму сессии — `UsageAccounting` в `codelab_agent_acp` (D4 того change);
2. в журнал usage — `buildUsageLedger`, `usage.json`, `/usage`, ответ `_codelab/session/usage/ledger` (D1, D3, D6);
3. в причины неполноты: сумма занижена без «~».

Засев суммы на `session/load` (D8) берёт числа из той же свёртки, поэтому после загрузки вызов тоже не виден. Это риск R11 change `add-usage-ledger`, принятый до отдельного change (решение пользователя 2026-11-17). Типичный случай — ручная проверка D16 того change: `/compact` с `keep_recent_tokens: 100`, резюме длиннее региона. После CMP-10 пользователь получает `Nothing to compact.`, а потраченные деньги нигде не показываются.

## What Changes

Решения пользователя 2026-11-17 по Q1–Q5 внесены (design.md, «Решения пользователя 2026-11-17»): все вопросы — вариант (а), рекомендованный. После сверки с `develop` — Q6 (а): запись учёта и при исходе `stale` (design.md, D11).

- **Ядро: служебная запись учёта отброшенного прохода** (D1, Q1 (а), Q6 (а)). Когда проход отброшен по CMP-10 или его запись не легла по CMP-12 (`stale`), компактор дописывает в журнал запись `custom` с `customType: "codelab.compaction_discarded"`. В её `data` лежат `usage` и `summaryModel` (те же имена и форма, что в `compaction.details`), а также `trigger`, `pass`, `reason`, `tokensBefore`, `tokensAfter`. Текста резюме в записи нет. В контекст модели запись не входит (`custom` — «прочее» в `buildLlmContext`, §8.7). Транскрипт и проекция не меняются, исход прохода прежний. Старое ядро прочтёт такую запись по правилу `custom` (§8.2.4) и проигнорирует. Нового типа записи нет, разбор журнала не меняется.
- **Ядро: событие** `CompactionDiscarded` (D2) — новая ветка `AgentEvent`. Несёт `usage`, `model`, `trigger`, `pass`, `tokensBefore`. Эмитится после записи учёта. Реплей его не даёт: после загрузки сумму даёт засев.
- **Ядро: свёртка журнала** (D3, Q2 (а)). `buildUsageLedger` считает запись `codelab.compaction_discarded` с `data.usage` вызовом суммаризатора: `summaries.count`, `summaries.usage`, `summaries.models`, `summaryCalls`, итог сессии. Новое необязательное поле `summaries.discarded` — число отброшенных вызовов. Правила цены и `noUsage` — как у вызова из записи `compaction` (D2, D4 change `add-usage-ledger`). `usage.json` остаётся версии 1, ключ `discarded` пишется только при ненулевом значении (Q3 (а)).
- **`/usage`** (D4). Строка `Summaries: <count> (<n> discarded), <usage>`; часть в скобках — только при ненулевом `discarded`.
- **Адаптер ACP** (D5, Q2 (а), Q4 (а)):
  - на `CompactionDiscarded` usage вызова входит в сумму сессии по тому же правилу, что `ContextCompacted.usage`;
  - соединения, объявившие `usage`, получают снимок `_codelab/session/usage` с новым поводом `trigger: "compactionDiscarded"`; заполнение контекста в нём — `tokensBefore` прохода, то есть заполнение не изменилось;
  - ответ `_codelab/session/usage/ledger` получает `summaries.discarded`;
  - засев на `session/load` берёт вызов из свёртки, поэтому инвариант «засев = `total`» (D8 change `add-usage-ledger`) сохраняется по построению.
- **Наблюдаемость** (D6). Лог `compaction.skipped` с `reason: "no reduction"` получает поля `summary_model` и `usage_record_id`. Токенов и денег в логе нет, как в `compaction.done`.
- **Фикстура** `acp/compact-no-gain-usage` (D7) — агентский и клиентский прогон.

## Не входит

- **R3 change `add-usage-ledger`**: сбой суммаризатора (`CompactionFailed`) и отмена после ответа модели. Записи учёта у них нет, как и сейчас. Форма записи с `reason` допускает расширение отдельным change (решение пользователя Q5 (а)).
- Повторные отброшенные проходы `afterTurn`: если оценка снова выше порога, каждый ход может платить за вызов суммаризатора без выигрыша. Change только делает их видимыми (`discarded`). Как ограничить такие проходы, решит отдельная задача компактора (R4).
- Usage суммаризатора в журналах субагентов: журналы детей свёртка не читает (D1 п. 5 change `add-usage-ledger`).
- Разбор `summaries.discarded` в модели клиента (`UsageLedgerView`): декодер клиента терпимый и незнакомое поле пропускает. Поле понадобится панели — change `add-desktop-usage-pane`.
- Изменение ответа `/compact` (`Nothing to compact.`), промптов сжатия и порога выигрыша.
- Стандартные типы ACP: новых методов, полей и значений `sessionUpdate` нет (`AGENTS.md` §3.4). Меняется только собственное расширение CodeLab `_codelab/session/usage*`, по его правилам совместимости (D17 change `add-usage-extension`, D6 change `add-usage-ledger`).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

Все дельты — ADDED: требования, которые уточняются, вводят ещё не архивированные changes (design.md, D8).
- `agent-compaction`: запись учёта и событие отброшенного прохода.
- `agent-sessions`: отброшенные вызовы в журнале usage и в `usage.json`.
- `agent-slash-commands`: отброшенные вызовы в строке `Summaries` команды `/usage`.
- `agent-acp-server`: сумма сессии, снимок `compactionDiscarded`, `summaries.discarded` в ответе журнала.
- `acp-golden-fixtures`: фикстура `acp/compact-no-gain-usage`.

## Impact

- `packages/dart/codelab_agent_core`:
  - `compaction/compactor.dart` — запись учёта, событие, поля лога;
  - `loop/agent_events.dart` — `CompactionDiscarded`;
  - `usage/usage_ledger.dart` — свёртка, `discarded`, сериализация `usage.json`;
  - `usage/usage_report_text.dart` — строка `Summaries`;
  - барель — экспорт события.
- `packages/dart/codelab_agent_acp`:
  - `session_bridge.dart` — обработка события, снимок;
  - `usage_accounting.dart` — снимок `compactionDiscarded`, `summaries.discarded` в ответе;
  - `event_projection.dart` — новая ветка исчерпывающего `switch`, кадров ACP нет.
- `packages/dart/codelab_acp_testing` — фикстура `acp/compact-no-gain-usage`.
- `packages/dart/codelab_client_core`, `codelab_client_acp`, `apps/*` — без изменений кода. Тесты подтверждают, что клиент v1 принимает новый повод и новое поле.
- Документы после перебазирования на `develop` с `add-usage-ledger`:
  - `agent-core/08-sessions.md` §8.2.4 — известный `customType`;
  - `09-compaction.md` §9.8 — шаг «нет выигрыша»;
  - `05-agent-loop.md` — каталог событий;
  - `12-observability-and-errors.md` — §12.6.1 и каталог логов `compaction`;
  - `13-acp-adapter.md` — §13.12, таблица проекции событий.
- Новых пакетов, зависимостей, рёбер графа и правил сторожа нет. Allowlist ядра (PKG-2) не меняется.
- **Зависимости.** Change опирается на `fix-compaction-estimate-and-no-gain`, `add-usage-ledger` (PR #346 влит), `anchor-context-estimate-after-compaction` и `fix-config-change-during-background-compaction` (SES-16, CMP-12). Все в `develop`, не архивированы. Сверка с кодом — design.md, D11. Архивируется после них (D8).
