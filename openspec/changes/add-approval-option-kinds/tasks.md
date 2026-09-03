## 1. acp_ui — kind на уровне модели

- [x] 1.1 Добавить enum `AcpApprovalOptionKind {allowOnce, allowAlways, rejectOnce, rejectAlways}` в `acp_ui`
- [x] 1.2 Добавить обязательное поле `kind` в `AcpApprovalOption`
- [x] 1.3 Заменить string-heuristics (`_defaultApproveOptionId`/`_defaultRejectOptionId`) в `AcpApprovalOptionGroup` на маппинг по `kind` → фиксированный шорткат
- [x] 1.4 Сохранить `approveOptionId`/`rejectOptionId` как override поверх kind-based дефолта

## 2. Raw input в approval-панели

- [x] 2.1 Добавить collapsible "View raw input" в `AcpApprovalPanel`, свёрнутый по умолчанию
- [x] 2.2 Проверить, покрывает ли `Expander` из `fluent_ui` потребность, прежде чем писать свой collapse-виджет

## 3. Интеграция

- [x] 3.1 Обновить `CodeLabShellCubit._approvalOption` (`shell_cubit.dart:809-819`) — маппинг `PermissionOptionKind` → `AcpApprovalOptionKind`, передача `kind` в `AcpApprovalOption`
- [x] 3.2 Убедиться, что `tone` по-прежнему выводится из `kind` (allow→success, reject→danger), не дублируется как отдельный источник истины

## 4. Тесты

- [x] 4.1 Widget-тест: 4 опции с разными kind получают 4 разных шортката
- [x] 4.2 Widget-тест: опция с label без слов "allow"/"reject" всё равно получает верный шорткат по kind
- [x] 4.3 Widget-тест: raw input свёрнут по умолчанию, раскрывается по клику

## 5. Проверка

- [x] 5.1 `fvm dart run melos run format`
- [x] 5.2 `fvm dart run melos run analyze`
- [x] 5.3 `fvm dart run melos run test`
