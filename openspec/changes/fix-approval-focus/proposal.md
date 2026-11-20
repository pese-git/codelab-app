## Why

Полоса решения ожидающего одобрения (`CodeLabApprovalPrompt`) и группа вариантов (`CodeLabApprovalOptionGroup`) оборачивают себя в `Focus(autofocus: true)`, пока одобрение активно (`shortcutsEnabled`). Сочетания одобрения привязаны к поддереву полосы:
- Cmd/Ctrl+Enter — `allow_once`;
- Cmd/Ctrl+Alt+Enter — `allow_always`;
- Cmd/Ctrl+Backspace — `reject_once`;
- Cmd/Ctrl+Alt+Backspace — `reject_always`.

`autofocus` срабатывает, только когда в области фокуса никого нет. Отсюда две проблемы.

1. **Поведение недетерминировано.** Обычно фокус держат рабочее место (`CodeLabWorkbenchShortcuts`, `Focus(autofocus: true)`; `_workbenchScope.requestFocus()` после возврата из настроек) и композер. Тогда фокус на полосу не переходит, и сочетания работают только после Tab до её кнопок. Руководство пользователя так и пишет: «фокус сам в карточку не переходит». Но если фокус потерян, он переходит.
2. **Случайное одобрение** (приоритет 1, `AGENTS.md` §2, §10). Фокус теряется после клика по пустой ленте или закрытия палитры. Если одобрение появится в этот момент, `autofocus` отдаст фокус полосе. Тогда Cmd/Ctrl+Enter, набранный «вслепую» для отправки промпта, выберет `allow_once`. Решение не было осознанным и не относилось к вызову, который пользователь видел. Риск вынесен отдельной задачей из ревью безопасности change `add-app-keyboard-page` (вердикт SAFE).

При реализации найден связанный дефект видимости (приоритет 1). Проекция транскрипта клиентского ядра (`transcript_projector.dart`, `_approvalFor`) показывает в строке вызова **первое** одобрение этого `toolCallId`, даже уже решённое. Второй `session/request_permission` для того же вызова есть в `SessionView.pendingApprovals` и в InfoBar настроек, но не виден в ленте: ответить на него в app нельзя, а переход к одобрению не находит его полосу. Для вызова без `tool_call` действует то же правило «первый побеждает» (`_unannouncedApprovalItems`). Спецификации повторного запроса для одного вызова нет ни в `acp-client-kit`, ни в `agent-workbench-ui`.

Сейчас нет и детерминированного пути к одобрению с клавиатуры. Tab проходит через шапку, сайдбар и строки ленты, а признак «одобрение в фокусе» в спецификации и на странице «Keyboard» смешивает два понятия:
- модельный признак `PendingApprovalView.focused` — самое раннее ожидающее одобрение хода (`embed-approval-in-thread`, Decision 6);
- клавиатурный фокус Flutter.

## What Changes

- **Одобрение не забирает фокус.** `autofocus` у полосы решения и у `CodeLabApprovalOptionGroup` убирается. Клавиатурный фокус попадает в полосу только явным действием пользователя: Tab или новое сочетание «Go to approval» (design.md, D1, D2).
- **Новое сочетание Cmd/Ctrl+Shift+A — «Go to approval»** (design.md, D3). Работает на рабочем месте, когда у активной сессии есть активное одобрение. Сочетание прокручивает ленту к полосе этого одобрения и ставит фокус клавиатуры на саму полосу, а не на кнопку. Отсюда работают четыре сочетания одобрения. Enter и Space на полосе ничего не выбирают, Tab ведёт к её кнопкам. Без активного одобрения сочетание ничего не делает. Прокрутка переиспользует механизм «Go to approval» панели Agents (`TranscriptViewCubit.requestShow`), но теперь запрос показа ещё и ставит фокус.
- **Видимый фокус и подсказка** (design.md, D4):
  - полоса с клавиатурным фокусом показывает рамку фокуса;
  - программа чтения с экрана читает её как ожидающее одобрение с подписью сочетаний словами;
  - у активного одобрения, пока фокус вне полосы, видна подсказка `Press ⇧⌘A to answer from the keyboard` (`Ctrl+Shift+A` на Windows и Linux). Подсказки вариантов на кнопках остаются. Итерация 7 эту подсказку убирает (D4, п. 6; D14).
- **Фокус после ухода одобрения** (design.md, D5). Полоса с фокусом исчезает, когда пользователь ответил, ход отменён или запрос снят. Тогда фокус SHALL переходить в композер активной сессии, а если его нет — на рабочее место. Следующее ожидающее одобрение фокус сам НЕ SHALL получать. Фокус полосы привязан к своему запросу и не переходит к другому запросу в том же месте ленты.
- **Cmd/Ctrl+Enter вне полосы** описан явно, поведение не меняется (design.md, D6):
  - в композере — отправка, при ожидающем одобрении сообщение уходит в очередь;
  - на рабочем месте, в сайдбаре, в доке и в дереве Files — ничего.
- **Каталог `CodeLabShortcut` и страница «Keyboard»** (design.md, D7):
  - новая запись `goToApproval`, группа Approvals, первая строка группы;
  - на странице 20 строк вместо 19;
  - тексты ARB `en`/`ru`: действие `Go to approval` — «Перейти к одобрению» (термин глоссария), место `Workbench, while an approval is pending` — «Рабочее место, пока ждёт одобрение»;
  - место четырёх строк одобрения уточнено: `Pending approval in focus, …` → `Pending approval with keyboard focus, when the agent offers this option` (`settingsKeyboardWhereApproval`, метка `security`; вычитывает пользователь).
- **Ожидающее одобрение видно в строке своего вызова** (design.md, D13; `[client]`). Ядро выбирает одобрение элемента вызова так: самое раннее ожидающее этого `toolCallId`, иначе последнее решённое. `pendingApprovals`, `focused`, `childApprovals` и ответ не меняются. Исправление действует и в CLI: он читает тот же транскрипт.
- **Глобальные сочетания ответа** (решение пользователя 2026-11-20, по образцу Zed; design.md D14, D15). Ответ с любого места рабочего места, включая поле композера, без фокуса в полосе, самому раннему ожидающему одобрению активной сессии:
  - macOS: ⌘Y — `allow_once`, ⌥⌘Y — `allow_always`, ⌥⌘Z — `reject_once`, ⌥⇧⌘Z — `reject_always`; Windows и Linux: Alt+Shift+Y, Alt+Shift+Q, Alt+Shift+X, Alt+Shift+W. Ctrl+Z, Ctrl+Shift+Z и ⌘Z, ⇧⌘Z остаются правкой текста, Ctrl+Y не отвечает;
  - меры безопасности: невидимый запрос первое нажатие только показывает; запрос, активный меньше 500 мс, не отвечает; автоповтор не отвечает; не из настроек, диалогов, палитры и терминала; только при `Connected` и не `detached`; ответ — id запроса и вариант по `kind` в момент нажатия;
  - журнал `workbench.approval_answer` (`source: button | shortcut`) и `workbench.approval_shortcut_skipped`;
  - прежние локальные клавиши полосы (Cmd/Ctrl+Enter, +Alt, Cmd/Ctrl+Backspace, +Alt) и подсказка перехода `Press ⇧⌘A to answer from the keyboard` убираются; Cmd/Ctrl+Enter — только отправка; «Go to approval» остаётся для чтения запроса и выбора охвата;
  - каталог `CodeLabShortcut` получает клавиши по платформе; на странице «Keyboard» 20 строк: новые клавиши у `allow-once`, `allow-always`, `reject-once`, `reject-always` и новое место.
- **Документы** (design.md, D10):
  - `12-3-desktop-display.md`: A9 и A13, шаг 3, DSK-18 — обновлены при подготовке change;
  - руководство пользователя desktop, `AGENTS.md` и `README.md` кита, `AGENTS.md` app и глоссарий — задачи `docs-writer`.

## Не входит

- **Сочетания на любом одобрении, а не только на самом раннем.** Правило «сочетания действуют только у самого раннего ожидающего одобрения хода» (`embed-approval-in-thread`, Decision 6) не меняется. Tab до более позднего одобрения даёт его кнопки, но не сочетания.
- **Переход к одобрению другой сессии.** Сочетание работает в активной сессии. Фоновые сессии с одобрением по-прежнему видны в сайдбаре, а из настроек — в InfoBar `settings-pending-approval`.
- **Фокус по «Go to approval» панели Agents и по «Back to session» InfoBar настроек.** Обе кнопки ведут себя как раньше (design.md, D8):
  - «Go to approval» панели Agents ведёт и к одобрениям, которые не самые ранние, а у них сочетаний нет;
  - «Back to session» восстанавливает прежний фокус (spec app-settings «Рабочее место недоступно с клавиатуры из настроек»).
- **Изменения ACP и кода CLI.** Протокол, `PendingApprovalView.focused` и `apps/codelab_cli` не меняются. В `codelab_client_core` меняется только выбор одобрения элемента вызова (D13).

## Зависимость от `add-app-keyboard-page`

Каталог `CodeLabShortcut`, страница «Keyboard» и требования app-settings «Страница «Keyboard»: …» вводит активный change `add-app-keyboard-page`. Ветка этого change сделана от его ветки. Требования ещё не перенесены в `openspec/specs/app-settings`. Поэтому:
- MODIFIED-дельта app-settings этого change опирается на текст `add-app-keyboard-page/specs/app-settings/spec.md`;
- `add-app-keyboard-page` SHALL архивироваться раньше этого change (задача 6.4);
- если порядок нарушится, архивация этого change упадёт на MODIFIED-требовании без базы, и это заметно сразу.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`:
  - ADDED «Одобрение получает клавиатурный фокус только по действию пользователя»;
  - ADDED «Переход к ожидающему одобрению с клавиатуры»;
  - ADDED «Фокус после ухода одобрения»;
  - ADDED «Ответ на одобрение сочетанием с любого места рабочего места»;
  - MODIFIED «Approval options are rendered and bound to shortcuts by kind» — сочетания у всех четырёх видов по платформе;
  - MODIFIED «Approval card inside the tool call row» — подсказки и сочетания ответа действуют с любого места рабочего места; полоса не берёт фокус сама; сценарии «Shortcut of an always option», «Shortcut hints of the always scope».
- `acp-client-kit` — ADDED «Одобрение в элементе вызова транскрипта» (повторный запрос того же вызова).
- `app-settings` — MODIFIED (из `add-app-keyboard-page`): «Страница «Keyboard»: строки таблицы» (строка `go-to-approval`, клавиши ответа, 20 строк), «Страница «Keyboard»: обозначения клавиш» (подсказки ответа по платформам), «Сочетания app и страница «Keyboard» не расходятся» (исключение для клавиш по платформе, сценарий «Отправка и одобрение на разных клавишах»).

## Impact

- **Код** (`[desktop]`, `[client]`):
  - `packages/flutter/codelab_ui`:
    - `atomics/codelab_shortcuts.dart` — запись `goToApproval`;
    - `organisms/codelab_approval_prompt.dart` — без `autofocus`, фокусируемая полоса с рамкой и семантикой, подсказка перехода;
    - `molecules/codelab_approval_option_group.dart` — без `autofocus`;
    - `organisms/codelab_workbench_shortcuts.dart` — `onGoToApproval`;
    - `organisms/codelab_transcript_panel.dart` — запрос показа с фокусом, ключ полосы по запросу;
    - ARB кита — подсказка и подпись полосы;
    - тесты, превью, `README.md`, `AGENTS.md`.
  - `packages/dart/codelab_client_core` (`[client]`): `transcript_projector.dart` — выбор одобрения элемента вызова (`_approvalFor`, `_unannouncedApprovalItems`), тесты.
  - `apps/codelab_desktop`:
    - `TranscriptViewCubit.requestShow` с признаком фокуса;
    - цель перехода — активное одобрение активной сессии;
    - привязка в `workbench_shell.dart`;
    - возврат фокуса в композер;
    - тексты страницы «Keyboard» в ARB `en`/`ru`;
    - тесты.
- **Зависимости и граф:** публичный API `codelab_client_core` не меняется. Новых пакетов, зависимостей и рёбер нет. Граф `README.md`, `desktopAllowlist` и allowlist ядра (PKG-2) не меняются. Правило `rules.dart` не нужно.
- **ACP:** без изменений. `session/request_permission` отвечается тем же `optionId` по тем же вариантам. Меняется только то, когда клавиши до полосы доходят.
- **Данные пользователя:** ничего не читается и не пишется.
- **Безопасность:** убирается путь к ответу через `autofocus`. Ответ сочетанием без фокуса — решение пользователя 2026-11-20 с компенсирующими мерами (видимость, задержка 500 мс, без автоповтора, журнал источника; design.md D14). Permission flow, привязка решения к своему вызову и правило «самое раннее одобрение» сохраняются.
