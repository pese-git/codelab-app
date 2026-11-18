# Backlog: суммаризатор без usage не даёт `noUsage`, ревью 2026-11-17

Находка реализации change `fix-discarded-compaction-usage` (адаптер ACP, задачи 2.1–2.2; ветка
`feature/fix-discarded-compaction-usage`). Ревью архитектуры проверило её по коду. Решение пользователя
2026-11-17 (Q7 (а) того change) — принять текущее поведение и закрыть расхождение отдельным change. В design.md
change это риск R8.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| REV-2 | P2 | bug | agent, protocol | Вызов суммаризатора с нулевым usage не даёт `noUsage` в протоколе и `usage.json`, хотя D4 `add-usage-ledger` это обещает | да | [#353](https://github.com/pese-git/codelab-app/issues/353) |

## Карточки

### REV-2. Суммаризатор с нулевым usage не даёт `noUsage` (P2)

**Где:**
- `packages/dart/codelab_agent_acp/lib/src/usage_accounting.dart`: `summarizerEnded` пропускает нулевой usage, а
  проекция ответа журнала ставит суммаризатору только `noPrice`;
- `packages/dart/codelab_agent_core/lib/src/usage/usage_ledger.dart`: свёртка ставит группе `summaries` только
  `noPrice`;
- фикстура `packages/dart/codelab_acp_testing/fixtures/acp/compact-usage-context.json` (суммаризатор без
  usage): в ней зафиксировано, что `partial` нет.

**Факт:**
- D4 change `add-usage-ledger` («`noUsage` суммаризатора», ревью итерации 1) требует причину `noUsage` в
  `summaries` и `total` для вызова (суммы запросов прохода), у которого все счётчики нулевые. Тогда в строках
  `Summaries` и `Total` появляется «~».
- В коде этого нет ни для записанного сжатия, ни для отброшенного (запись `codelab.compaction_discarded`).
  Живой снимок `_codelab/session/usage`, засев на `session/load`, ответ `_codelab/session/usage/ledger` и
  `usage.json` причины `noUsage` не несут.
- Текст `/usage` при этом ставит «~» по правилу шага (`summaryApprox` в
  `codelab_agent_core/lib/src/usage/usage_report_text.dart`). Поэтому `/usage` и клиентская строка статуса
  расходятся.

**Почему важно:** провайдер не прислал usage суммаризатора, а клиент показывает сумму сессии точной, без «~».
Это тот класс ошибок, который закрывают `add-usage-extension` и `add-usage-ledger`: сумма занижена без пометки
о неполноте.

**Что сделать (OpenSpec change):**
- `noUsage` для вызова суммаризатора с нулевыми `input`, `output`, `cacheRead`, `cacheWrite` (инвариант
  `noUsage` — D26 change `add-usage-extension`). Это касается и записанного, и отброшенного прохода.
- Правку согласовать во всех местах:
  - живая сумма (`summarizerEnded`);
  - свёртка ядра;
  - проекция ответа журнала;
  - засев на `session/load`.
- Инвариант «засев = `total`» должен сохраниться.
- Обновить фикстуру `acp/compact-usage-context`.
- Решить и вынести пользователю вопрос: писать ли `partial` суммаризатора в `usage.json`. Это формат файла,
  версия 1.
- Связано: R3 change `add-usage-ledger` — отмена и сбой суммаризатора тоже оставляют сумму неполной без «~».
  Возможно, их стоит закрыть одним change «неполный учёт суммаризатора».
