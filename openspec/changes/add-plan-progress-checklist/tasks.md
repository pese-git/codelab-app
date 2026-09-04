## 1. acp_ui — AcpActivityBar (docked shell)

- [ ] 1.1 Реализовать `AcpActivityBar` organism: docked-контейнер (верхние скруглённые углы, без нижней границы/отступа), список секций, разделённых горизонтальной линией
- [ ] 1.2 Секция — заголовок (кликабельный целиком, разворачивает/сворачивает тело секции) + опциональное тело; контейнер скрыт полностью, если список секций пуст
- [ ] 1.3 Спроектировать API секции так, чтобы регистрация новой секции (будущие Edited files/Queue) не требовала правок самого `AcpActivityBar` (см. `design.md` Non-Goals — сами эти секции не реализуются)

## 2. acp_ui — AcpProgressChecklist (содержимое секции Plan)

- [ ] 2.1 Добавить presentation-enum'ы `AcpPlanEntryStatus`/`AcpPlanEntryPriority` (зеркалят протокольные `PlanEntryStatus`/`PlanEntryPriority`)
- [ ] 2.2 Реализовать заголовок секции: если есть `in_progress` entry и секция свёрнута — `"Current: <текст>"` (обрезка через fade) + `"N left"` (если остались `pending`); иначе — `"Plan"` + `"N Tasks"`/`"N/M"`
- [ ] 2.3 Кнопка "✕ Clear" в заголовке секции — вызывает `dismissPlan()`, не разворачивая/не сворачивая секцию (`stopPropagation` относительно клика по заголовку)
- [ ] 2.4 Реализовать тело секции: список entries с фиксированной максимальной высотой и внутренним скроллом, статус-иконки, priority-бейджи, без прогресс-бара

## 3. Обработка plan updates

- [ ] 3.1 Обработать `SessionUpdate.plan` в `CodeLabShellCubit` — маппинг `List<PlanEntry>` → `List<CodeLabPlanEntry>`
- [ ] 3.2 Добавить `currentPlan: List<CodeLabPlanEntry>?` в `CodeLabShellState`
- [ ] 3.3 Полная замена текущего плана при каждом новом `plan` update (не merge/diff)
- [ ] 3.4 Добавить `dismissPlan()` в `CodeLabShellCubit` — очищает `currentPlan` (`null`), не отправляет ничего агенту

## 4. Интеграция в main pane

- [ ] 4.1 Вставить `AcpActivityBar` между транскриптом и композером в `WorkbenchMainPane` (не над транскриптом), видна только если есть хотя бы одна активная секция (Plan — если `currentPlan` не пуст)
- [ ] 4.2 Скрыть секцию Plan полностью, если все entries `completed` (не показывать "All Done" — см. `design.md`); полный список остаётся доступен, пока секция видна
- [ ] 4.3 Разворачивание/сворачивание секции по клику на всю строку заголовка

## 5. Тесты

- [ ] 5.1 Widget-тест: получение `SessionUpdate.plan` рендерит чеклист с верными статусами/приоритетами
- [ ] 5.2 Widget-тест: отсутствие plan update — `AcpActivityBar` не рендерится вообще
- [ ] 5.3 Widget-тест: новый `plan` update полностью заменяет предыдущий список
- [ ] 5.4 Widget-тест: секция скрывается, когда все entries `completed`
- [ ] 5.5 Widget-тест: заголовок секции показывает `"Current: X"` + `"N left"` при наличии `in_progress`, и `"Plan" + "N Tasks"/"N/M"` иначе
- [ ] 5.6 Widget-тест: `dismissPlan()` очищает `currentPlan` и скрывает секцию; последующий `plan` update показывает её заново
- [ ] 5.7 Widget-тест: развёрнутый список с числом entries больше видимой области — скроллится внутри себя, не растягивая `AcpActivityBar`

## 6. Проверка

- [ ] 6.1 `fvm dart run melos run format`
- [ ] 6.2 `fvm dart run melos run analyze`
- [ ] 6.3 `fvm dart run melos run test`
