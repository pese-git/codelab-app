## 1. acp_ui — AcpProgressChecklist

- [ ] 1.1 Добавить presentation-enum'ы `AcpPlanEntryStatus`/`AcpPlanEntryPriority` (зеркалят протокольные `PlanEntryStatus`/`PlanEntryPriority`)
- [ ] 1.2 Реализовать `AcpProgressChecklist` organism: список entries, статус-иконки, priority-бейджи, "N of M done" + progress bar
- [ ] 1.3 Реализовать компактный summary-режим (текущий `in_progress`/следующий `pending` entry) с возможностью развернуть в полный список

## 2. Обработка plan updates

- [ ] 2.1 Обработать `SessionUpdate.plan` в `CodeLabShellCubit` — маппинг `List<PlanEntry>` → `List<CodeLabPlanEntry>`
- [ ] 2.2 Добавить `currentPlan: List<CodeLabPlanEntry>?` в `CodeLabShellState`
- [ ] 2.3 Полная замена текущего плана при каждом новом `plan` update (не merge/diff)

## 3. Интеграция в main pane

- [ ] 3.1 Добавить компактную сводку над транскриптом в `WorkbenchMainPane`, видна только если `currentPlan` не пуст
- [ ] 3.2 Скрыть сводку, если все entries `completed` (полный список остаётся доступен)
- [ ] 3.3 Реализовать разворачивание в полный `AcpProgressChecklist`

## 4. Тесты

- [ ] 4.1 Widget-тест: получение `SessionUpdate.plan` рендерит чеклист с верными статусами/приоритетами
- [ ] 4.2 Widget-тест: отсутствие plan update — чеклист и сводка не рендерятся вообще
- [ ] 4.3 Widget-тест: новый `plan` update полностью заменяет предыдущий список
- [ ] 4.4 Widget-тест: сводка скрывается, когда все entries `completed`

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
