## 1. codelab_ui: полоса решения

- [x] 1.1 Вынести выбор варианта по `PermissionOptionKind` и привязку сочетаний из `CodeLabApprovalOptionGroup` в `CodeLabApprovalShortcuts` (design D2); поведение группы не меняется, её тесты зелёные
- [x] 1.2 `CodeLabApprovalPrompt` как полоса решения (design D3): «Allow» и «Reject» без заливки со значками, выбор охвата «Only this time» / «Always» справа; кнопка отвечает вариантом по таблице решения и охвата; охват по умолчанию, пункты охвата по наличию вариантов, недоступная кнопка с подсказкой; под «Always» — подписи вариантов агента; охват — локальное состояние; подсказка сочетания по варианту текущего охвата
- [x] 1.3 Сочетания всех четырёх видов привязаны в `CodeLabApprovalPrompt` и работают без открытия меню и при любом охвате, пока `shortcutsEnabled` (design D2)
- [x] 1.4 «View raw input» — кнопка-значок в полосе, раскрывает сырой ввод над полосой; причина — приглушённой строкой над полосой (design D8)
- [x] 1.5 `CodeLabTranscriptApprovalPending` без `title`/`question` и `cwd`; ключи `CodeLabApprovalPrompt.allowKey`, `rejectKey`, `scopeKey` вместо ключей вариантов на кнопках (design D3, D4, D7)

## 2. codelab_ui: шапка строки при ожидании

- [x] 2.1 `CodeLabToolCallTile`: при ожидании деталь — `pending.command`, если есть, до трёх строк с переносом; «Show full command» снимает ограничение, состояние — в `State` строки (design D5)
- [x] 2.2 Тег риска вместо тега статуса при ожидании; подписи и тоны риска — в файле полосы (design D6)
- [x] 2.3 Убрать выделение ждущей строки: `CodeLabExpanderCard.highlighted` и акцентную полосу (design D6)
- [x] 2.4 Тело строки при ожидании — `CodeLabApprovalPrompt` внизу строки под тонкой линией, без отдельной карточки и без повтора команды
- [x] 2.5 Удалить `CodeLabApprovalPanel`, `CodeLabApprovalOptionsLayout` и превью панели; превью полосы решения (design D1)

## 3. codelab_desktop: маппер

- [x] 3.1 Маппер не выбирает заголовок или вопрос по виду вызова (`approvalTitleOf` уходит) и не передаёт папку сессии (design D4, D7)

## 4. Тесты

- [x] 4.1 Widget-тесты полосы по сценариям спецификации: «Command decision bar», «Allow once by default», «Always is an explicit scope», «A scope without an option for a decision», «Shortcut of an always option»; полоса в одну строку в колонке 720 px и в узкой колонке без переполнения
- [x] 4.2 Widget-тесты шапки: «Command awaiting approval» (тег риска, без «Awaiting approval»), «Long command is never cut before the decision», команда 400 символов без пробелов не выходит за строку
- [x] 4.3 `ui_mappers_test`: у ожидающего одобрения нет заголовка и папки сессии
- [x] 4.4 Перенести проверки в `codelab_transcript_test`, `codelab_organisms_test`, `codelab_molecules_test` и `integration_test/permission_flow_test.dart` на кнопки полосы и выбор охвата (e2e на устройстве в `feature/*` не запускается, AGENTS.md §21)

## 5. Проверка

- [x] 5.1 `fvm exec melos run check` зелёный
- [x] 5.2 Ручная проверка в приложении с тестовым агентом (`chat-demo.json`): одобрение `echo running tests` — шапка с командой и тегом Shell, полоса «Allow · Reject · Only this time», выбор «Always», кнопки отвечают нужным вариантом; снимок до и после. Сочетания из композера — вне change (design, Open Questions)
