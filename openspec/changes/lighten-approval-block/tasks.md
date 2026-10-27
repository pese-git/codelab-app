## 1. codelab_ui: строка решения

- [ ] 1.1 Вынести выбор варианта по `PermissionOptionKind` и привязку сочетаний из `CodeLabApprovalOptionGroup` в переиспользуемую функцию (design D2); поведение группы не меняется, её тесты зелёные
- [ ] 1.2 `CodeLabApprovalPrompt`: вопрос, главная кнопка `allow_once` (или первый `allow_*`), обычная кнопка `reject_once` (или первый `reject_*`), `DropDownButton` «More options» с остальными вариантами, разделителем и «View raw input» (design D3); подсказки сочетаний на кнопках и пунктах; причина приглушённой строкой; сырой ввод раскрывается по пункту меню
- [ ] 1.3 Сочетания всех четырёх видов привязаны в `CodeLabApprovalPrompt` и работают без открытия меню, пока `shortcutsEnabled` (design D2)
- [ ] 1.4 `CodeLabTranscriptApprovalPending`: `title` → `question`, поле `cwd` удалить (design D4, D7)

## 2. codelab_ui: шапка строки при ожидании

- [ ] 2.1 `CodeLabToolCallTile`: при ожидании деталь — `pending.command`, если есть, до трёх строк с переносом; «Show full command» снимает ограничение, состояние — в `State` строки (design D5)
- [ ] 2.2 Тег риска вместо тега статуса при ожидании; тоны и подписи риска переезжают из `CodeLabApprovalPanel` (design D6)
- [ ] 2.3 `CodeLabExpanderCard.highlighted` — акцентная полоса 2 px у ведущего края вместо рамки вокруг (design D6)
- [ ] 2.4 Тело строки при ожидании — `CodeLabApprovalPrompt` без отдельной карточки и без повтора команды
- [ ] 2.5 Удалить `CodeLabApprovalPanel`, `CodeLabApprovalOptionsLayout` и превью панели; превью ленты с ожиданием — на новой строке решения (design D1)

## 3. codelab_desktop: маппер

- [ ] 3.1 `approvalTitleOf` → `approvalQuestionOf` по таблице спецификации; маппер не передаёт папку сессии (design D4, D7)

## 4. Тесты

- [ ] 4.1 Widget-тесты `codelab_ui`: сценарии «Command approval prompt», «Always options live in the menu», «Shortcut of a menu option», «Decision leaves a tag»; одна строка решения в колонке 720 px без переноса кнопок
- [ ] 4.2 Widget-тесты шапки: «Command awaiting approval» (тег риска, полоса, без «Awaiting approval»), «Long command is never cut before the decision», команда 400 символов без пробелов не выходит за строку
- [ ] 4.3 `ui_mappers_test`: вопрос по каждому виду из таблицы, папка сессии не передаётся
- [ ] 4.4 Перенести проверки «Awaiting approval» и «Run a command?» в `codelab_transcript_test`, `codelab_organisms_test`, `codelab_molecules_test` и `integration_test/permission_flow_test.dart` (e2e на устройстве в `feature/*` не запускается, AGENTS.md §21)

## 5. Проверка

- [ ] 5.1 `fvm exec melos run check` зелёный
- [ ] 5.2 Ручная проверка в приложении с тестовым агентом (`chat-demo.json`): одобрение `echo running tests` — шапка с командой и тегом Shell, одна строка решения, меню, ⌘⏎ и ⌥⌘⏎ работают; снимок до и после
