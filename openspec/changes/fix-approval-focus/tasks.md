## Исполнители

- `[desktop]` — `packages/flutter/codelab_ui`, `apps/codelab_desktop`;
- `[client]` — `packages/dart/codelab_client_core`: только выбор одобрения элемента вызова (итерация 3а, design.md D13);
- `[protocol]`, `[agent]` — задач нет: ACP, ядро агента и код CLI не меняются (design.md, D11).

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2):
- красный тест — отдельная задача и отдельный коммит до кода; коммит — только по просьбе пользователя;
- задача реализации ссылается на свой красный тест;
- красный тест может опираться на заглушки сигнатур без поведения: запись каталога, параметр `onGoToApproval`, признак `focusApproval`.

Прежние тесты, которые полагались на `autofocus` полосы, получают явный шаг фокуса: Tab до кнопки или переход. Ожидаемый результат сценария не меняется (design.md, Risks).

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` пакета;
- тесты пакета;
- `melos run l10n:check` — при правке ARB.

`guard` не нужен. `web-compile`, `conformance:client` и `test:e2e:cli:dart-agent` — только для итерации 3а (design.md, D11).

## 0. Документы (выполнено при подготовке change)

- [x] 0.1 `[desktop]` `docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md`:
  - A9 — фокус одобрения: без `autofocus`, сочетания при фокусе в полосе активного одобрения, переход Cmd/Ctrl+Shift+A, возврат фокуса в композер (D1–D5);
  - A13, шаг 3 — сочетание Cmd/Ctrl+Shift+A (D3).

## 1. Итерация 1 — одобрение не берёт фокус само (безопасность)

- [x] 1.1 `[desktop]` Красный, кит: `packages/flutter/codelab_ui/test/codelab_approval_focus_test.dart` (D1; spec agent-workbench-ui «Одобрение получает клавиатурный фокус только по действию пользователя»). Для `CodeLabApprovalPrompt` с `shortcutsEnabled: true` и для `CodeLabApprovalOptionGroup` проверяет:
  - после `pump` при пустом фокусе `primaryFocus` не внутри полосы;
  - Cmd/Ctrl+Enter, Cmd/Ctrl+Alt+Enter, Cmd/Ctrl+Backspace и Cmd/Ctrl+Alt+Backspace, каждое в вариантах `control` и `meta`, не вызывают `onOptionSelected`;
  - перестроение полосы с новыми вариантами не переносит фокус;
  - после Tab до кнопки «Allow» те же сочетания выбирают свои варианты;
  - у полосы с `shortcutsEnabled: false` (не самое раннее одобрение) после Tab до кнопки сочетания ничего не выбирают, а Enter на кнопке выбирает её вариант.

  Прежние сценарии одобрения в `codelab_molecules_test.dart`, `codelab_organisms_test.dart` и `codelab_shortcut_bindings_test.dart` получают явный шаг фокуса.
- [x] 1.2 `[desktop]` Реализация 1.1: убрать `autofocus` в `organisms/codelab_approval_prompt.dart` и `molecules/codelab_approval_option_group.dart`. Doc-комментарии обоих виджетов и `CodeLabApprovalShortcuts` объясняют, почему полоса не берёт фокус сама (D1, D2; `AGENTS.md` §15). 1.1 и прежние тесты кита зелёные.
- [x] 1.3 `[desktop]` Красный, app: `apps/codelab_desktop/test/features/workbench/presentation/approval_focus_test.dart`. Дерево `CodeLabApp` с фейковым транспортом, ответ на `session/request_permission` наблюдается на проводе. Сценарии:
  - agent-workbench-ui «Одобрение появилось без фокуса — Cmd/Ctrl+Enter не отвечает»;
  - «Одобрение появилось без фокуса — остальные сочетания одобрения не отвечают»;
  - «Одобрение появилось после закрытия палитры»;
  - «Фокус в композере не уходит к одобрению»;
  - «Фокус в дереве Files или в сайдбаре»;
  - «Tab до кнопки не самого раннего одобрения»;
  - MODIFIED «Approval card inside the tool call row»: «Shortcut without keyboard focus in the bar».

  Прежние тесты app с нажатием сочетаний одобрения получают явный шаг фокуса, сценарии не ослабляются:
  - `workbench_shell_test.dart`;
  - `widget_test.dart`;
  - `settings_pending_approval_test.dart`;
  - `keyboard_bindings_test.dart` — «Отправка и одобрение на одной клавише».
- [x] 1.4 `[desktop]` Реализация 1.3. Код app не должен меняться: поведение даёт 1.2. Если тест красный из-за чужого `autofocus` или из-за того, что фокус по ошибке оказывается в полосе, исправить там и описать причину в комментарии. 1.3 зелёный.

## 2. Итерация 2 — переход «Go to approval»

- [x] 2.1 `[desktop]` Красный, кит (D3, D4; spec «Переход к ожидающему одобрению с клавиатуры»):
  - `codelab_shortcuts_test.dart`:
    - 20 записей, `go-to-approval` — первая в группе `approvals`;
    - активаторы `control` и `meta` с `shift`;
    - `capsFor`: `⇧ ⌘ A` и `Ctrl Shift A`;
    - `compactFor`: `⇧⌘A` и `Ctrl+Shift+A`;
    - `spokenFor`: `Shift+Cmd+A` и `Ctrl+Shift+A`.
  - `codelab_shortcut_bindings_test.dart`: сценарий сторожа 2 для `goToApproval` — `CodeLabWorkbenchShortcuts.onGoToApproval`, оба активатора; число записей 20.
  - `codelab_approval_focus_test.dart`:
    - `requestFocus` узла полосы ставит фокус на полосу, а не на кнопку;
    - у узла `skipTraversal`: Tab с элемента перед полосой ведёт к «Allow»;
    - Enter и Space на полосе не вызывают `onOptionSelected`;
    - рамка фокуса видна, пока фокус на полосе или внутри неё, и не видна без фокуса;
    - семантика: `Awaiting approval` и подсказка `<название варианта>: Cmd+Enter` на macOS;
    - подпись `Press ⇧⌘A to answer from the keyboard` (macOS) и `Press Ctrl+Shift+A to answer from the keyboard` (Linux) есть у активного одобрения без фокуса и пропадает с фокусом; у неактивного её нет; на `ru` — перевод;
    - смена ключа (новый id запроса) даёт полосу без фокуса.
  - `codelab_transcript_show_request_test.dart` (новая группа):
    - запрос показа с `focusApproval: true` прокручивает к цели и ставит фокус на её полосу, в том числе на блок под строкой `agent`;
    - запрос без признака фокус не меняет;
    - цель не построилась или запрос устарел — фокус прежний, `onShowRequestDone` вызван;
    - перемонтированная лента запрос не повторяет.
- [x] 2.2 `[desktop]` Реализация 2.1 в ките:
  - `CodeLabShortcut.goToApproval`;
  - `CodeLabWorkbenchShortcuts.onGoToApproval`;
  - в `CodeLabApprovalPrompt`:
    - `FocusNode` полосы в `State` с `skipTraversal`;
    - рамка цветами `FluentTheme`;
    - `Semantics`;
    - подпись `codeLabApprovalGoToHint`;
  - `CodeLabTranscriptShowRequest.focusApproval` и поиск полосы в построенной цели;
  - ключ полосы по `targetId` в `CodeLabToolCallTile`;
  - `codeLabApprovalGoToHint` в `codelab_ui_en.arb` и `codelab_ui_ru.arb` с меткой `security`;
  - превью полосы с фокусом и с подсказкой, `codelab_previews_test.dart`;
  - doc-комментарии (`AGENTS.md` §15).

  2.1 и `l10n:check` зелёные.
- [x] 2.3 `[desktop]` Красный, app (D4; spec «Переход к ожидающему одобрению с клавиатуры», все сценарии):
  - `agents_pane_state_test.dart` (или новый `transcript_view_cubit_test.dart` рядом): `requestShow(focusApproval: true)` кладёт признак в запрос; `dropShowRequestOutside` гасит его при смене сессии;
  - тест выбора цели (`apps/codelab_desktop/test/features/workbench/application/`):
    - самое раннее ожидающее одобрение активной сессии;
    - одобрение субагента — `rowId` строки `agent` корня;
    - нет цели, если ожидающего одобрения нет, соединение не `Connected` или сессия `detached`;
  - `approval_focus_test.dart`:
    - «Пользователь с клавиатуры доходит до одобрения и отвечает»;
    - «Переход и остальные сочетания»;
    - «Enter на полосе ничего не выбирает»;
    - «С клавиатуры через Tab»;
    - «Несколько одобрений — переход к самому раннему»;
    - «Одобрение субагента»;
    - «Ожидающего одобрения нет»;
    - «Цель ушла до фокуса»;
    - «Из настроек сочетание не действует»;
    - «Палитра команд открыта»;
    - «Подсказка перехода на macOS и Linux»;
    - «Чтение с экрана»;
    - риск design.md «Активное одобрение сменилось при фокусе в полосе»: Tab на полосу `B`, `A` решена кнопкой — сочетания на `B` начинают действовать, фокус не переходит.
- [x] 2.4 `[desktop]` Реализация 2.3 в app:
  - выбор цели в application (`features/workbench/application/`), без логики в `build`;
  - `TranscriptViewCubit.requestShow(focusApproval:)`;
  - `onGoToApproval` в `workbench_shell.dart`, передаётся всегда (D4, п. 1);
  - пока открыта палитра команд, сочетание ничего не делает;
  - `ActiveSessionCubit.respondToApproval` пересобирает ленту одним `emit` со снятием `isRespondingToApproval` (D4, п. 4).

  2.3 зелёный; `workbench_shell_test.dart`, `settings_pending_approval_test.dart` и тесты панели Agents зелёные без изменения сценариев.

## 3. Итерация 3 — фокус после ухода полосы

- [x] 3.1 `[desktop]` Красный (D5; spec «Фокус после ухода одобрения»):
  - кит, `codelab_approval_focus_test.dart` и `codelab_transcript_show_request_test.dart`: полоса с фокусом при `dispose` и при смене ключа вызывает `onApprovalFocusReleased` один раз; полоса без фокуса — ни разу;
  - app, `approval_focus_test.dart`:
    - «Ответ клавишами возвращает фокус в композер»;
    - «Отмена хода при фокусе в полосе»;
    - «Новый запрос того же вызова»;
    - переключение сессии при фокусе в полосе — фокус в композере новой сессии;
    - пользователь кликнул в дерево Files в том же кадре, что и ответ, — фокус в дереве, а не в композере;
  - app, модульный тест функции выбора цели возврата фокуса (`apps/codelab_desktop/test/features/workbench/application/approval_focus_return_test.dart`; D5): композер включён и фокус свободен — композер; композер выключен — рабочее место; фокус уже занят — не трогать. Ветка «композер выключен» проверяется здесь, а не в дереве app: `isPromptEnabled` в `shell_cubit.dart` всегда `true`.

  Сценарий «Новый запрос того же вызова» станет зелёным только после 3.4.
- [x] 3.2 `[desktop]` Реализация 3.1:
  - `onApprovalFocusReleased` в `CodeLabApprovalPrompt` и ленте;
  - параметр `textFocusNode` у `CodeLabPromptComposer`; узел принадлежит `State` рабочего места app и освобождается в `dispose`;
  - функция выбора цели возврата фокуса в `features/workbench/application/` (D5); виджет в следующем кадре только исполняет её результат (§12).

  3.1 зелёный (сценарий «Новый запрос того же вызова» — после 3.4), прежние тесты композера зелёные.

## 3а. Итерация 3а — ожидающее одобрение видно в строке своего вызова (`[client]`)

- [x] 3.3 `[client]` Красный: `packages/dart/codelab_client_core/test/transcript/approval_in_row_test.dart` (design.md D13; spec acp-client-kit «Одобрение в элементе вызова транскрипта», все сценарии):
  - «Повторный запрос после ответа»;
  - «После ответа на повторный запрос»;
  - «Повторный запрос вызова без `tool_call`»;
  - «Два ожидающих запроса одного вызова»;
  - «Один запрос — без изменений»;
  - инвариант: для каждого `PendingApprovalView` с `focused == true` корня в `pendingApprovals` есть элемент вызова транскрипта с этим одобрением; `childApprovals` строки `agent` не изменились.
- [x] 3.4 `[client]` Реализация 3.3: правило выбора в `transcript_projector.dart` — `_approvalFor` и `_unannouncedApprovalItems` (одно правило, один элемент на `toolCallId`); doc-комментарии (`AGENTS.md` §15). 3.3 зелёный; прежние тесты `codelab_client_core` и `apps/codelab_cli` зелёные без изменения сценариев; `web-compile`, `conformance:client`, `test:e2e:cli:dart-agent` зелёные.

## 4. Итерация 4 — страница «Keyboard» и тексты

- [x] 4.1 `[desktop]` Красный, app (D7; spec app-settings MODIFIED «Страница «Keyboard»: строки таблицы»):
  - `keyboard_page_test.dart`:
    - «Полный список на Linux» — 20 строк;
    - новые «Строка «Go to approval»» и «Поиск строки перехода»;
    - прочие проверки числа строк — 20;
  - `keyboard_shortcut_search_test.dart`: 20 записей; `ctrl shift a`, `⇧⌘A`, `Shift+Cmd+A` находят только `go-to-approval`;
  - `keyboard_page_l10n_test.dart`: 20 строк; русские тексты строки `go-to-approval` и нового места строк одобрения;
  - `test/support/keyboard_rows.dart`: эталон 20 строк по спецификации.
- [x] 4.2 `[desktop]` Реализация 4.1:
  - `settingsKeyboardActionGoToApproval`, `settingsKeyboardWhereApprovalPending` и новый текст `settingsKeyboardWhereApproval` в `app_en.arb` и `app_ru.arb`, метка `security` в `@description`;
  - ветки `goToApproval` в `keyboardShortcutActionOf`, `keyboardShortcutWhereOf`, `keyboardShortcutGroupOf`.

  4.1, `keyboard_bindings_test.dart`, сторожа 1 и 2 и `l10n:check` зелёные.
- [x] 4.3 `[desktop]` Вычитка пользователем русских текстов с меткой `security` (Q4): тексты 4.2 и `codeLabApprovalGoToHint` из 2.2. Правки — в ARB и в глоссарий одним PR.

## 5. Итерация 5 — документация (`docs-writer`, стандарт `.claude/skills/codelab-docs/SKILL.md`)

- [x] 5.1 `[desktop]` `docs/architecture/l10n-glossary.md` (D7, итог 4.3; правило §7 глоссария — термин в том же PR, что и сообщение):
  - «Страница «Keyboard»» — строки `Go to approval`, `Workbench, while an approval is pending`, `Pending approval with keyboard focus, when the agent offers this option`;
  - «Одобрение» — `Press {shortcut} to answer from the keyboard`.
- [x] 5.2 `[desktop]` `apps/codelab_desktop/doc/user-guide.md`:
  - раздел про одобрения: таблица сочетаний дополнена ⇧⌘A / Ctrl+Shift+A «перейти к одобрению»; абзац «Сочетания работают, когда фокус внутри карточки…» переписан — переход, рамка фокуса, Enter на полосе ничего не выбирает, подсказка, возврат фокуса в композер, следующее одобрение фокус не получает;
  - раздел «Сочетания клавиш» — строка «Go to approval» в группе Approvals и новое место строк одобрения.
- [x] 5.3 `[desktop]` Правила пакетов:
  - `packages/flutter/codelab_ui/AGENTS.md` §4: виджеты одобрения не берут фокус сами (`autofocus` запрещён), ключ полосы — id запроса, `onGoToApproval`, `focusApproval`, `onApprovalFocusReleased`;
  - `packages/flutter/codelab_ui/README.md`: раздел про одобрение — фокус и переход;
  - `apps/codelab_desktop/AGENTS.md`: цель перехода выбирает application по признаку `focused` модели; возврат фокуса в композер с проверкой свободного фокуса.
- [x] 5.4 `[desktop]` Проверка фактов документов 5.1–5.3 (`architecture-reviewer`), исправления.

## 6. Проверки и PR

- [x] 6.1 `[desktop]` Проверки затронутого (`AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm flutter analyze` в `packages/flutter/codelab_ui` и `apps/codelab_desktop`;
  - `fvm flutter test` обоих пакетов;
  - `melos run l10n:check`;
  - `fvm flutter analyze` для `apps/codelab_desktop/integration_test` (только компиляция, `feature/*`);
  - для 3а: `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_client_core` и `apps/codelab_cli`, `melos run web-compile`, `melos run conformance:client`, `melos run test:e2e:cli:dart-agent`;
  - `openspec validate fix-approval-focus --strict`;
  - если правились опубликованные на сайте документы и установлен Node — `cd site && npm ci && npm run verify`.
- [ ] 6.2 `[desktop]` Ручная проверка app:
  - на macOS — появление одобрения после клика по пустой ленте, затем ⌘⏎: ответа нет; ⇧⌘A и ⌘⏎: ответ; VoiceOver на полосе; — пройдено пользователем 2026-11-20 (debug-сборка ветки);
  - на Windows — Ctrl+Shift+A не переключает раскладку и доходит до app (D3, Risks). При конфликте — решение по Q1 до PR. — не проверялось.
- [x] 6.3 `[desktop]` Двойное ревью (`architecture-reviewer`, `acp-safety-reviewer`): ни одного пути к ответу на `session/request_permission` без явного действия пользователя.
- [ ] 6.4 `[desktop]` Архивация — только после архивации `add-app-keyboard-page`: MODIFIED-дельта app-settings опирается на его требования (proposal, «Зависимость»).
- [ ] 6.5 `[desktop]` PR в `develop`. В описании:
  - какие проверки запускались локально, и что полный `melos run check` не запускался;
  - изменение поведения: одобрение больше не берёт фокус само, новый переход Cmd/Ctrl+Shift+A;
  - исправление ядра: повторный `session/request_permission` того же вызова виден в строке вызова (D13), затрагивает и CLI;
  - зависимость от `add-app-keyboard-page`.
- [x] 6.6 `[desktop]` `[client]` Исправления по двойному ревью (без CRITICAL и HIGH):
  - пересборка ленты одним `emit` после ответа (`ActiveSessionCubit.respondToApproval`), D4, п. 4;
  - фокус с выключенной кнопки полосы переходит на узел самой полосы (`didUpdateWidget`), не покидая её; сценарий «Кнопка с фокусом выключается», D4, п. 4;
  - запрос показа несёт `approvalId`, лента фокусирует только полосу с ключом `CodeLabApprovalPrompt.keyFor(sessionId, approvalId)`; ключ включает id сессии; повторное нажатие при фокусе в цели ничего не меняет, D4, пп. 2, 4;
  - узел, которому Flutter отдал фокус, внутри другой полосы — перевод в композер или на рабочее место сразу, в микротаске; сценарий «Flutter вернул фокус на кнопку другого одобрения», D5;
  - одна транзитивная функция порядка «самое раннее ожидающее» для строки вызова и признака `focused` (`codelab_client_core`, `[client]`), D13;
  - документация: убран «клик» как способ поставить фокус (кнопка Fluent `HoverButton` фокус по клику не берёт); уточнены подсказки и «только у самого раннего одобрения».

## 7. Итерация 7 — глобальные сочетания ответа (решение пользователя 2026-11-20; design.md D14, D15)

Сначала красные тесты, затем реализация. Прежние сценарии, которые нажимали ⌘⏎, ⌥⌘⏎, ⌘⌫ или ⌥⌘⌫ в полосе, переписываются под новые требования, а не удаляются: их ожидание теперь — «ответа нет» (spec agent-workbench-ui «Одобрение получает клавиатурный фокус только по действию пользователя», сценарий «Прежние клавиши одобрения не отвечают и при фокусе в полосе»).

- [x] 7.0 `[desktop]` `docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md`: A9 (сочетания ответа, локальных клавиш нет), A11 (Cmd/Ctrl+Enter больше не одобряет), DSK-18 (решение пользователя 2026-11-20) — обновлены при подготовке итерации.
- [x] 7.1 `[desktop]` Красный, кит (D15; spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места», «Approval options are rendered and bound to shortcuts by kind»; app-settings «Страница «Keyboard»: обозначения клавиш»):
  - `codelab_shortcuts_test.dart`: 20 записей; `allowOnce`, `allowAlways`, `rejectOnce`, `rejectAlways` с комбинациями по платформе; `capsFor`/`compactFor`/`spokenFor` — `⌘ Y`, `⌥⌘Y`, `Option+Cmd+Z`, `⌥ ⇧ ⌘ Z` на macOS и `Alt Shift Y`, `Alt+Shift+Q`, `Alt+Shift+X`, `Alt+Shift+W` на Linux; ⇧⌘Z и ⌘Z не привязаны; `searchNotations` содержит комбинации обеих платформ; на macOS активатор только `meta` (без Ctrl+Y), на Linux — только Alt+Shift;
  - `codelab_shortcut_bindings_test.dart`: сценарии сторожа 2 для записей ответа через `CodeLabWorkbenchShortcuts.onAnswerApproval` при платформе macOS и Linux; чужие клавиши (Ctrl+Y и Cmd+Y на Linux, Ctrl+Y на macOS) не вызывают колбэк; автоповтор не вызывает;
  - `codelab_approval_focus_test.dart`: в полосе ⌘⏎, ⌥⌘⏎, ⌘⌫, ⌥⌘⌫ ничего не выбирают; подсказки кнопок активного одобрения — клавиши ответа, включая `⌥⇧⌘Z` у «Reject» при охвате «Always»; подписи `codeLabApprovalGoToHint` нет; семантика `Allow once: Cmd+Y`;
  - `codelab_transcript_show_request_test.dart` (или новый файл ленты): лента сообщает видимость полосы по `keyFor(sessionId, approvalId)` — построена и целиком в области прокрутки; вне области и при открытой выдвижной панели — не видна.
- [x] 7.2 `[desktop]` Реализация 7.1 в ките: комбинации по платформе в каталоге (D15), `onAnswerApproval` в `CodeLabWorkbenchShortcuts` (`includeRepeats: false`), локальные привязки полосы и `CodeLabApprovalOptionGroup` убраны (`CodeLabApprovalShortcuts` даёт только подсказки и вариант по `kind`), запрос видимости полосы у ленты, удаление `codeLabApprovalGoToHint` из ARB кита, превью, doc-комментарии (`AGENTS.md` §15). 7.1, прежние тесты кита и `l10n:check` зелёные.
- [x] 7.3 `[desktop]` Красный, app, application: `apps/codelab_desktop/test/features/workbench/application/approval_shortcut_decision_test.dart` — чистая функция решения по нажатию (D14) с внедряемыми часами:
  - нет цели, соединение не `Connected`, сессия `detached` — `no_target`, ответа нет;
  - нет варианта этого `kind`, неизвестный `kind` — `no_option`;
  - полоса не видна — показать без ответа (`not_visible`);
  - цель активна меньше 500 мс — показать без ответа (`settling`); ровно 500 мс и больше — ответ;
  - отсчёт начинается заново, когда активным становится другой id; ответ несёт id запроса и `optionId` цели в момент нажатия.
- [x] 7.4 `[desktop]` Красный, app, дерево `CodeLabApp` (`approval_focus_test.dart`, новый `approval_shortcuts_test.dart`): все сценарии требования «Ответ на одобрение сочетанием с любого места рабочего места», включая журнал `workbench.approval_answer` и `workbench.approval_shortcut_skipped` без сырых аргументов и команды, терминал пользователя и Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z в композере на Windows (Ctrl+Y ничего не меняет, повтор — Ctrl+Shift+Z); переписанные сценарии требований «Одобрение получает клавиатурный фокус…», «Переход к ожидающему одобрению с клавиатуры» (ответ ⌥⌘Z после перехода, `reject_always` кнопкой после выбора охвата, подсказки кнопок, чтение с экрана), «Фокус после ухода одобрения» (ответ ⌘Y, «Flutter вернул фокус на кнопку другого одобрения» с Enter), MODIFIED «Approval card inside the tool call row» («Shortcut of an always option», «Shortcut hints of the always scope»), сценарии «Отклонить всегда» и «Отмена и повтор правки на macOS не отвечают».
- [x] 7.5 `[desktop]` Реализация 7.3 и 7.4 в app:
  - функция решения в `features/workbench/application/`, учёт момента активации цели (часы — параметр, как в `WorkbenchUsagePane`);
  - `onAnswerApproval` в `workbench_shell.dart`; показ полосы — `TranscriptViewCubit.requestShow` без фокуса;
  - ответ — тот же путь, что у кнопки (`respondToApproval`) с источником `shortcut`; события журнала;
  - терминал пользователя поглощает клавиши ответа, они не всплывают до рабочего места.

  7.3, 7.4 и прежние тесты app зелёные.
- [x] 7.6 `[desktop]` Красный, страница «Keyboard» (spec app-settings MODIFIED «…строки таблицы», «…обозначения клавиш», «Сочетания app и страница «Keyboard» не расходятся»):
  - `keyboard_page_test.dart`: 20 строк, клавиши четырёх строк ответа для macOS и Windows (`reject-always` — `⌥ ⇧ ⌘ Z` и `Alt Shift W`), место `Workbench, earliest pending approval, if it offers this option`;
  - `keyboard_shortcut_search_test.dart`: `alt shift y` на macOS находит только `allow-once`;
  - `keyboard_page_l10n_test.dart`: русские тексты нового места;
  - `keyboard_bindings_test.dart`: сценарий «Отправка и одобрение на разных клавишах»;
  - `test/support/keyboard_rows.dart`: эталон 20 строк.
- [x] 7.7 `[desktop]` Реализация 7.6: `settingsKeyboardWhereApprovalAnywhere` в `app_en.arb` и `app_ru.arb` с меткой `security`; удаление `settingsKeyboardWhereApproval` (`settingsKeyboardActionRejectAlways` остаётся); ветки `switch` в `keyboard_page.dart`. 7.6, сторожа 1 и 2 и `l10n:check` зелёные.
- [x] 7.8 `[desktop]` Вычитка пользователем русского текста с меткой `security` (Q7): текст принят как есть (решение пользователя 2026-11-20).
- [x] 7.9 `[desktop]` `docs-writer`: `apps/codelab_desktop/doc/user-guide.md` — таблица сочетаний одобрения (⌘Y, ⌥⌘Y, ⌥⌘Z, ⌥⇧⌘Z; Alt+Shift+Y, Q, X, W), где они действуют, первое нажатие показывает невидимый запрос, задержка 500 мс после появления, ⌘⏎ — только отправка, «Go to approval» — для чтения и охвата; раздел «Сочетания клавиш».
- [x] 7.10 `[desktop]` `docs-writer`: `docs/architecture/l10n-glossary.md` — новое место строк ответа; удалить `Pending approval with keyboard focus, …` и `Press {shortcut} to answer from the keyboard`.
- [x] 7.11 `[desktop]` `docs-writer`: `packages/flutter/codelab_ui/AGENTS.md` и `README.md` (клавиши по платформе в каталоге, у полосы нет локальных клавиш, видимость полосы у ленты); `apps/codelab_desktop/AGENTS.md` (решение по нажатию в application, задержка, журнал источника).
- [x] 7.12 `[desktop]` Проверка фактов документов 7.9–7.11 (`architecture-reviewer`), исправления.
- [ ] 7.13 `[desktop]` Проверки затронутого (`AGENTS.md` §21): format, `fvm flutter analyze` и `fvm flutter test` в `packages/flutter/codelab_ui` и `apps/codelab_desktop`, `melos run l10n:check`, компиляция `integration_test`, `openspec validate fix-approval-focus --strict`. Ручная проверка: macOS — ⌘Y из композера, ⌘Z/⇧⌘Z правят текст и не отвечают; Windows — Alt+Shift+Y не переключает раскладку, Ctrl+Y не отвечает, Ctrl+Shift+Z повторяет правку; Linux — Alt+Shift+Q и Alt+Shift+W не перехватывает оконный менеджер; Windows и Linux — смена раскладки Alt+Shift с немедленным набором «н» или «й» не отвечает, заранее зажатые Alt и Shift (дольше 150 мс) отвечают; Alt+Shift+Tab в другое окно, отпустить модификаторы там, вернуться и набрать «y» в композере — ответа нет; видимость при окне за краем монитора и при всплывающей подсказке над полосой (design.md, Risks, «Допущение видимости»); macOS — ⌥⇧⌘Z не занят системой; набор через IME в композере не отвечает на запрос (D14, Risks; при конфликте — вопрос пользователю до PR).
  - Проверки затронутого — пройдены (format, analyze, тесты кита +764 и app +3291, `l10n_check`, сторож, `integration_test`, validate, сайт на Node 26.4.0).
  - Ручная проверка macOS, 2026-11-20 (debug-сборка ветки, проверял агент через управление экраном): ⌘Y из композера отвечает «Allow once»; ⌘⏎ при ожидающем одобрении ставит сообщение в очередь, на запрос не отвечает; ⌘Z и ⇧⌘Z в композере не отвечают; удержание ⌘Y даёт один ответ; невидимая полоса — первое ⌘Y и первое ⌥⌘Z только прокручивают и подсвечивают, второе сразу (≈150 мс) не отвечает, через секунду отвечает (⌥⌘Z — Reject); при открытой палитре и на экране настроек ⌘Y не отвечает (InfoBar «Агент ждёт вашего одобрения» остаётся); страница «Клавиатура» — 20 строк, клавиши ⌘Y, ⌥⌘Y, ⌥⌘Z, ⌥⇧⌘Z и новое место; ⇧⌘A ставит рамку фокуса на полосу, Enter и Пробел на ней ничего не выбирают.
  - Повторная ручная проверка macOS на `c6d36bda` (после слияния develop), 2026-11-20: ⌘Y из композера с черновиком отвечает, черновик цел; ⌘⏎ ставит в очередь; при открытой палитре, на экране настроек, в диалоге «Добавить профиль подключения» и в терминале ⌘Y не отвечает; поиск страницы «Клавиатура» `alt shift y` находит только «Разрешить только сейчас», `⌘Y` — «Разрешить только сейчас» и «Всегда разрешать»; после «Назад» из настроек ⌘K открывает палитру без клика; ⇧⌘A — рамка, Enter и Пробел не отвечают, затем ⌥⌘Z отклоняет. Журнал: `workbench.approval_answer` (`kind`, `request_id`, `tool_call_id`) и `workbench.approval_shortcut_skipped` (`not_visible`, затем `settling`) — без аргументов инструмента. Замечено: сразу после прокрутки колесом полоса, видимая на экране, один раз посчитана `not_visible` (вероятно, полоса прокрутки поверх угла полосы перехватывает hit-test) — ложный отказ в безопасную сторону, первое нажатие только показывает.
  - Не проверено вручную: ⌥⌘Y и ⌥⇧⌘Z (постоянные решения), «запрос моложе 500 мс» по таймингу, два одобрения сразу, диалоги и терминал, поиск на странице «Клавиатура», VoiceOver, ⌥⇧⌘Z занятость системой; Windows и Linux целиком.
  - Найдено вне scope: после возврата из настроек стрелкой «Назад» клавиатурный фокус не возвращается на рабочее место — не работают ни ⌘K, ни ⌘Y до клика (безопасная сторона для одобрений; дефект возврата фокуса `add-app-settings-shell`, `codelab_app_widget.dart`). Исправлено в этом PR по решению пользователя: сохранённый узел восстанавливается только внутри рабочего места (не сайдбар и не хозяин сочетаний), иначе фокус — в композер (spec app-settings); тест `settings_focus_return_test.dart`; на macOS после «Назад» ⌘K и набор текста работают без клика.
- [x] 7.14 `[desktop]` Повторное двойное ревью (`architecture-reviewer`, `acp-safety-reviewer`; итог: APPROVED, SAFE): ответ сочетанием только активному, видимому и не только что появившемуся одобрению; нет пути ответа из настроек, диалогов, палитры и терминала; журнал без сырых данных.
- [x] 7.15 `[desktop]` Описание PR #376: глобальные сочетания ответа и их клавиши по платформам; убраны локальные ⌘⏎/⌥⌘⏎/⌘⌫/⌥⌘⌫ и подсказка перехода; четыре сочетания, включая `reject_always` ⌥⇧⌘Z / Alt+Shift+W; какие проверки запускались, полный `melos run check` не запускался.
- [x] 7.16 `[desktop]` Исправления по ревью итерации 7 (без CRITICAL и HIGH; закоммичены в b825210c и следующем коммите):
  - Windows и Linux: Alt+Shift+буква отвечает, только если Alt и Shift зажаты не меньше 150 мс до буквы; отказ — `modifiers_not_held`; сценарии «Буква наложилась на смену раскладки», «Заранее зажатые модификаторы отвечают» (решение пользователя 2026-11-20, четвёртое; D14, п. 4);
  - отсчёт 500 мс заново после показа невидимой полосы; сценарий «Нажатие сразу после показа не отвечает» (D14, п. 2; MEDIUM безопасности);
  - встроенный диалог корня диска (`_RootSessionDialog`, `pendingRootSession`) — сочетания ответа не действуют, как в палитре (D14, «Где действуют»);
  - нажатие, пока ответ в полёте, журналируется с `reason: answer_in_flight`; сценарий «Нажатие, пока ответ в полёте» (D14, п. 5; D9);
  - источник ответа — тип `ApprovalAnswerSource`, а не строка (D9);
  - design: риски итераций 1–6, снятые итерацией 7, и ссылки на удалённый тест и подсказку перехода переписаны; риск «Допущение видимости» (hit-test, окно за краем монитора);
  - `12-3-desktop-display.md` A9 и `12-6-cli-desktop-extras.md` (Cmd/Ctrl+Enter — отправка) обновлены при подготовке задачи;
  - код: часы в тестах через `CodeLabShellParts` вместо реального ожидания 600 мс; `searchNotations` по платформам; удаление мёртвых параметров `CodeLabApprovalOptionGroup`; описания ARB строк ответа (`@description`, метка `security`); doc-комментарии по `AGENTS.md` §15.

## 8. Итерация 8 — раскладка ввода: исследовано и отменено (design.md D16; решения пользователя 2026-11-20, пятое и шестое)

D16 реализован (8.1–8.5) и отменён шестым решением пользователя: на настоящей macOS Flutter уже отдаёт латинскую логическую клавишу при русской раскладке, исходный сбой — артефакт инструмента управления экраном, а правило D16 добавляло риск на латинских раскладках с диакритикой.

- [x] 8.1 `[desktop]` Красные тесты кита при русской раскладке. После отката защитными оставлены AZERTY по напечатанной букве, кириллица без модификатора и кириллическая логическая клавиша при зажатом ⌘ (не совпадает: сравнивается только логическая клавиша); латинская логическая клавиша при русской раскладке покрыта обычными тестами каталога и проверена вручную (8.6). Тесты физической позиции US удалены вместе с D16.
- [x] 8.2 `[desktop]` Откат реализации D16 в каталоге кита: `CodeLabLayoutActivator` и таблица физических позиций убраны, `CodeLabKeyCombo.accepts` и активаторы снова сравнивают логическую клавишу (`add-app-keyboard-page`, D3). Защитные тесты 8.1 и 8.3, сторожа 1 и 2 и прежние тесты кита и app зелёные.
- [x] 8.3 `[desktop]` Тесты app при русской раскладке — оставлены защитными в части, которая не опирается на физическую позицию (spec agent-workbench-ui «Сочетания app не зависят от раскладки ввода»).
- [x] 8.4 `[desktop]` Реализация в app — не потребовалась.
- [x] 8.5 `[desktop]` `docs-writer`: откатить правки 8.5 о правиле D16 в `packages/flutter/codelab_ui/AGENTS.md` и `README.md`; в `apps/codelab_desktop/doc/user-guide.md` оставить «сочетания работают при любой раскладке, на кейкапах — латинские клавиши» с оговоркой, что Windows и Linux проверяются вручную.
- [x] 8.6 `[desktop]` Ручная проверка macOS с русской раскладкой, 2026-11-20 (настоящая клавиатура, пользователь), без D16: ⌘K (клавиша «Л») открывает палитру, ⌘Y (клавиша «Н») отвечает на запрос — журнал `workbench.approval_answer kind: allow_once, source: shortcut`. Это подтверждает, что сочетания работают при русской раскладке силами Flutter. Управление экраном для такой проверки непригодно: при русской раскладке оно шлёт физическую клавишу A. Windows и Linux не проверены — остаются в ручной проверке перед выпуском.
- [x] 8.7 `[desktop]` Двойное ревью отката и 8.10 (`architecture-reviewer`, `acp-safety-reviewer`): физических клавиш в каталоге нет, сочетания ответа сравнивают логическую клавишу. Исправления по ревью: вернуть app-тест «кириллица без модификаторов в композере не отвечает» (удалён откатом); тест кита — кириллическая логическая клавиша при зажатом ⌘ не совпадает; тест 8.10 проверяет, куда встал фокус, и что фокус композера не трогается; `approval_shortcut_skipped` с `reason: palette_open` / `root_dialog`. Остаточный риск (ревью безопасности, LOW): на Linux AltGr+Shift+буква может считаться Alt+Shift — проверить вручную перед выпуском вместе с Alt+Shift.
- [x] 8.8 `[desktop]` Описание PR #376: D16 исследован и отменён; сочетания при русской раскладке на macOS проверены вручную.
- [x] 8.9 `[desktop]` По ревью архитектуры (MAJOR): диагностика ложного `not_visible` — поле `visibility_detail` в `workbench.approval_shortcut_skipped` и публичное API кита `CodeLabApprovalVisibility.check` / `CodeLabApprovalVisibilityResult` (design.md D9); защитный тест полосы прокрутки. Закоммичено в a333a4cd и fc797a49. Причина ложного `not_visible` пока не найдена.
- [x] 8.10 `[desktop]` Сочетания рабочего места при фокусе на самом скоупе `Workbench` (клик по ленте): ⌘K и ⌘Y молчали, журнал пуст. Слушатель скоупа переводит фокус на узел-хозяин сочетаний (design.md D14 «Где действуют»); красный тест — 17c77e58, исправление — dd13e718. Ручная проверка macOS, 2026-11-20 (пользователь): после клика по ленте ⌘K открывает палитру, ⌘Y отвечает на запрос.
