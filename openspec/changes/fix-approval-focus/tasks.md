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
- [ ] 5.4 `[desktop]` Проверка фактов документов 5.1–5.3 (`architecture-reviewer`), исправления.

## 6. Проверки и PR

- [ ] 6.1 `[desktop]` Проверки затронутого (`AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm flutter analyze` в `packages/flutter/codelab_ui` и `apps/codelab_desktop`;
  - `fvm flutter test` обоих пакетов;
  - `melos run l10n:check`;
  - `fvm flutter analyze` для `apps/codelab_desktop/integration_test` (только компиляция, `feature/*`);
  - для 3а: `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_client_core` и `apps/codelab_cli`, `melos run web-compile`, `melos run conformance:client`, `melos run test:e2e:cli:dart-agent`;
  - `openspec validate fix-approval-focus --strict`;
  - если правились опубликованные на сайте документы и установлен Node — `cd site && npm ci && npm run verify`.
- [ ] 6.2 `[desktop]` Ручная проверка app:
  - на macOS — появление одобрения после клика по пустой ленте, затем ⌘⏎: ответа нет; ⇧⌘A и ⌘⏎: ответ; VoiceOver на полосе;
  - на Windows — Ctrl+Shift+A не переключает раскладку и доходит до app (D3, Risks). При конфликте — решение по Q1 до PR.
- [ ] 6.3 `[desktop]` Двойное ревью (`architecture-reviewer`, `acp-safety-reviewer`): ни одного пути к ответу на `session/request_permission` без явного действия пользователя.
- [ ] 6.4 `[desktop]` Архивация — только после архивации `add-app-keyboard-page`: MODIFIED-дельта app-settings опирается на его требования (proposal, «Зависимость»).
- [ ] 6.5 `[desktop]` PR в `develop`. В описании:
  - какие проверки запускались локально, и что полный `melos run check` не запускался;
  - изменение поведения: одобрение больше не берёт фокус само, новый переход Cmd/Ctrl+Shift+A;
  - исправление ядра: повторный `session/request_permission` того же вызова виден в строке вызова (D13), затрагивает и CLI;
  - зависимость от `add-app-keyboard-page`.
- [ ] 6.6 `[desktop]` `[client]` Исправления по двойному ревью (без CRITICAL и HIGH):
  - пересборка ленты одним `emit` после ответа (`ActiveSessionCubit.respondToApproval`), D4, п. 4;
  - фокус с выключенной кнопки полосы переходит на узел самой полосы (`didUpdateWidget`), не покидая её; сценарий «Кнопка с фокусом выключается», D4, п. 4;
  - запрос показа несёт `approvalId`, лента фокусирует только полосу с ключом `CodeLabApprovalPrompt.keyFor(sessionId, approvalId)`; ключ включает id сессии; повторное нажатие при фокусе в цели ничего не меняет, D4, пп. 2, 4;
  - узел, которому Flutter отдал фокус, внутри другой полосы — перевод в композер или на рабочее место сразу, в микротаске; сценарий «Flutter вернул фокус на кнопку другого одобрения», D5;
  - одна транзитивная функция порядка «самое раннее ожидающее» для строки вызова и признака `focused` (`codelab_client_core`, `[client]`), D13;
  - документация: убран «клик» как способ поставить фокус (кнопка Fluent `HoverButton` фокус по клику не берёт); уточнены подсказки и «только у самого раннего одобрения».
