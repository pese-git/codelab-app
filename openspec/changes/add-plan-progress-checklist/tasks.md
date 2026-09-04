## 1. acp_ui — AcpActivityBar (docked shell)

- [x] 1.1 Реализовать `AcpActivityBar` organism: docked-контейнер (верхние скруглённые углы, без нижней границы/отступа), список секций, разделённых горизонтальной линией
- [x] 1.2 Секция — заголовок (кликабельный целиком, разворачивает/сворачивает тело секции) + опциональное тело; контейнер скрыт полностью, если список секций пуст
- [x] 1.3 Спроектировать API секции так, чтобы регистрация новой секции (будущие Edited files/Queue) не требовала правок самого `AcpActivityBar` (см. `design.md` Non-Goals — сами эти секции не реализуются)

## 2. acp_ui — AcpProgressChecklist (содержимое секции Plan)

- [x] 2.1 Добавить presentation-enum'ы `AcpPlanEntryStatus`/`AcpPlanEntryPriority` (зеркалят протокольные `PlanEntryStatus`/`PlanEntryPriority`)
- [x] 2.2 Реализовать заголовок секции: если есть `in_progress` entry и секция свёрнута — `"Current: <текст>"` (`TextOverflow.ellipsis`, см. `design.md`) + `"N left"` (если остались `pending`); иначе — `"Plan"` + `"N Tasks"`/`"N/M"`
- [x] 2.3 Кнопка "✕ Clear" в заголовке секции — вызывает `dismissPlan()`, не разворачивая/не сворачивая секцию (нативная изоляция вложенного `AcpIconButton` от внешнего `Button` — без ручного `stopPropagation`)
- [x] 2.4 Реализовать тело секции: список entries с фиксированной максимальной высотой (128px — уменьшено с исходных 160px после того, как e2e на реальных системных шрифтах поймал 2px overflow при недостаточном запасе) и внутренним скроллом, статус-иконки, priority-бейджи, без прогресс-бара

## 3. Обработка plan updates

- [x] 3.1 Обработать `SessionUpdate.plan` в `CodeLabShellCubit` — маппинг `List<PlanEntry>` → `List<AcpPlanEntry>` (без промежуточного `CodeLabPlanEntry`, см. `design.md`)
- [x] 3.2 Добавить `currentPlan: List<AcpPlanEntry>?` в `CodeLabShellState`
- [x] 3.3 Полная замена текущего плана при каждом новом `plan` update (не merge/diff) — последний `PlanUpdate` по всем `turns` сессии побеждает
- [x] 3.4 Добавить `dismissPlan()` в `CodeLabShellCubit` — очищает `currentPlan` (`null`), не отправляет ничего агенту

## 4. Интеграция в main pane

- [x] 4.1 Вставить `AcpActivityBar` между транскриптом и композером в `WorkbenchMainPane` (не над транскриптом), видна только если есть хотя бы одна активная секция (Plan — если `currentPlan` не пуст)
- [x] 4.2 Скрыть секцию Plan полностью, если все entries `completed` (не показывать "All Done" — см. `design.md`); полный список остаётся доступен, пока секция видна
- [x] 4.3 Разворачивание/сворачивание секции по клику на всю строку заголовка (уже реализовано в `AcpActivityBar`, task 1.2 — здесь просто подключение)

## 5. Тесты

- [x] 5.1 Widget-тест: получение `SessionUpdate.plan` рендерит чеклист с верными статусами/приоритетами (acp_ui — заголовок/список; app — маппинг в `currentPlan`)
- [x] 5.2 Widget-тест: отсутствие plan update — `AcpActivityBar` не рендерится вообще (acp_ui — пустой список секций; app — `currentPlan == null`)
- [x] 5.3 Widget-тест: новый `plan` update полностью заменяет предыдущий список (app, через реальный prompt turn)
- [x] 5.4 Widget-тест: секция скрывается, когда все entries `completed` (`WorkbenchMainPane`, app)
- [x] 5.5 Widget-тест: заголовок секции показывает `"Current: X"` + `"N left"` при наличии `in_progress`, и `"Plan" + "N Tasks"/"N/M"` иначе (acp_ui)
- [x] 5.6 Widget-тест: `dismissPlan()` очищает `currentPlan` и скрывает секцию; последующий `plan` update показывает её заново (app, через реальный prompt turn)
- [x] 5.7 Widget-тест: развёрнутый список с числом entries больше видимой области — скроллится внутри себя, не растягивая `AcpActivityBar` (acp_ui)
- [x] 5.8 E2e (`integration_test/plan_progress_checklist_flow_test.dart`): реальный stdio-агент (`CodelabCompatibleStdioAgentMode.withPlan`) шлёт `plan` updates за настоящий prompt turn — сводка/разворачивание/dismiss/repopulate/скрытие при завершении проверены сквозь реальный процесс, не через фейки

## 6. Проверка

- [x] 6.1 `fvm dart run melos run format`
- [x] 6.2 `fvm dart run melos run analyze`
- [x] 6.3 `fvm dart run melos run test` (acp_testing/acp_transports/acp_ui/codelab_app — все зелёные)
- [x] 6.4 `fvm flutter test integration_test/plan_progress_checklist_flow_test.dart -d macos --dart-define=CODELAB_E2E_DART=../../.fvm/flutter_sdk/bin/dart` (реальный stdio-агент, `melos run test:e2e:app:plan-checklist`)
