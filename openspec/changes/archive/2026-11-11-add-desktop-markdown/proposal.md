## Why

Лента desktop показывает ответ агента сырым текстом: на smoke 2026-10-30 видны `**`, обратные кавычки и строки ```` ``` ```` (SMK-07, P2, [#177](https://github.com/pese-git/codelab-app/issues/177); сводка — `docs/backlog/smoke-2026-10-30.md`). Тот же дефект повторно замечен на регрессе с LM Studio 2026-11-06 и на smoke macOS 2026-11-09 (`delivery-roadmap.md` §10.4, строка «Markdown в сообщениях агента»). Длинные ответы со списками, таблицами и кодом читать тяжело. Схема ACP рекомендует клиенту рисовать текстовый блок как markdown (`docs/protocols/acp/protocol/17-Schema.md`, `ContentBlock` → `text`: «Clients SHOULD render this text as Markdown»), а desktop этого не делает.

Цель матрицы — строка Should **D-06** «Markdown в транскрипте»: ответы агента отображаются как markdown с подсветкой кода; критерий — widget-тест `packages/flutter/codelab_ui/test/acp_markdown_test.dart` (`agent-parity-goals.md` §3.9). Строка входит в группу 7 «Отображение ответа» плана 1.0 (`delivery-roadmap.md` §6.1).

Принятый план (`dart-agent-and-clients` §12.1.4, §12.3) предлагал свой инкрементальный разбор в `codelab_client_core`, свою отрисовку и `re_highlight`. После прототипа пользователь 2026-11-11 выбрал пакет `gpt_markdown` 1.4.1 для разбора и стриминга в desktop, а для CLI — отдельный change со своим разбором (design.md, «Решения пользователя 2026-11-11»). Этот change оформляет выбор, его условия безопасности и правку принятых разделов.

## What Changes

- **Отрисовка ответа агента пакетом `gpt_markdown`** (`agent-workbench-ui`, ADDED «Markdown в ответе агента»; MODIFIED «Transcript reads as a conversation»):
  - обёртка `CodeLabMarkdown` в `codelab_ui/lib/src/rendering/` без Material-предка, со своими builder'ами (код, флажок задачи, ссылка, изображение) и темой из `FluentTheme`;
  - тема и builder'ы создаются один раз и переиспользуются, иначе пакет перестраивает все закрытые блоки;
  - HTML не разбирается (`html: false`), LaTeX — только `\(…\)` и `\[…\]`, `$` — обычный символ.
- **Блок кода** (ADDED «Блок кода в ответе агента»): подпись языка вне выделения, кнопка «Copy» с исходным кодом, подсветка движком `val_highlight` за нашим интерфейсом, своя палитра из ролей `FluentTheme` с контрастом ≥ 4,5:1, пороги синхронной и фоновой токенизации.
- **Стриминг** (ADDED «Стриминг markdown без перестройки закрытых блоков»): закрытый блок строится один раз (DSK-3), незакрытая ограда — моноширинно без подсветки (DSK-6).
- **Ссылки** (ADDED «Ссылки в ответе агента»): активны только `http`, `https`, `mailto`; клик открывает адрес сразу через порт `ExternalLinkOpener` на `url_launcher`, полный адрес — в подсказке; прочие схемы — обычный текст.
- **Изображения** (ADDED «Изображения в ответе агента»): по умолчанию не загружаются — заглушка с хостом и кнопкой «Show image»; загрузка только по клику и только `https`. Уточняет VIEW-12 и DSK-7: «не загружать без явного действия пользователя».
- **Ответ одним огороженным блоком** (MODIFIED «Ответ агента одним огороженным блоком»): общий блок кода с подписью и «Copy»; сценарий блока мыслей уточняется (MODIFIED «Model thoughts in a collapsible block»: мысли по-прежнему без разметки).
- **Зависимости:** `gpt_markdown` в `codelab_ui` (с ним приходят ещё 11 пакетов: `material_ui`, `cupertino_ui`, `flutter_svg`, `vector_graphics`, `vector_graphics_codec`, `vector_graphics_compiler`, `path_parsing`, `val_highlight`, `val_highlight_flutter`, `val_latex`, `val_latex_flutter`; лицензии BSD-3-Clause и MIT; шрифты JetBrains Mono и Latin Modern); `val_highlight` — прямая зависимость `codelab_ui`; `url_launcher` в `apps/codelab_desktop`. Правила сторожа ограничивают импорт `gpt_markdown`, `val_highlight` и `url_launcher` одним каталогом и запрещают `material_ui` и `cupertino_ui` в нашем коде.
- **BREAKING (UI, внутреннее):** `CodeLabAgentTextRow.preformatted` заменяется флагом `streaming`; превью и widget-тесты переходят на новую модель.

## Не входит

- **Разбор markdown в `codelab_client_core`** и поле `AgentTextItem.markdown`: ядро клиента не меняется, `AgentTextItem` остаётся текстом (VIEW-11 сохраняется).
- **Markdown в CLI (U-10)** — отдельный change `add-cli-markdown` со своим разбором. Вывод `raw`, headless и pipe не меняется.
- **Diff правок (D-07, U-11)**, изменения блока мыслей (D-08 сделан), usage (D-09), вложения (D-12), поиск (D-17).
- **Кнопка «Copy reply»**, выделение через несколько строк ленты, сворачивание длинного блока кода, диалог полного просмотра большого кода.
- **Разметка промпта пользователя и мыслей модели** — показываются как есть.
- **Изменения ACP:** новых методов, полей, `_meta` и `_codelab/*` нет; change выполняет SHOULD схемы для ответа агента, конкретный диалект markdown ACP не задаёт.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui` — новые требования «Markdown в ответе агента», «Блок кода в ответе агента», «Стриминг markdown без перестройки закрытых блоков», «Ссылки в ответе агента», «Изображения в ответе агента»; изменены «Transcript reads as a conversation», «Model thoughts in a collapsible block», «Ответ агента одним огороженным блоком».

## Impact

- **`packages/flutter/codelab_ui`** (`[desktop]`): `lib/src/rendering/` — `CodeLabMarkdown`, конфигурация пакета, `CodeLabCodeHighlighter`, `CodeLabCodeTheme`; строка `CodeLabAgentTextRow(id, text, streaming)`; превью и `test/acp_markdown_test.dart`; зависимости `gpt_markdown`, `val_highlight`; нижняя граница `environment` — Dart 3.12 и Flutter 3.44 (требование `gpt_markdown`; FVM — 3.47.0); вложенный `AGENTS.md` (§1–§4).
- **`apps/codelab_desktop`** (`[desktop]`): маппер ответа и политика ссылок и изображений в `features/workbench/application/`; порт `ExternalLinkOpener` в `lib/core/platform/`, привязка в `app_scope.dart`, `CodeLabShellCubit.openExternalLink`; показ изображений в `TranscriptViewCubit`; зависимость `url_launcher`.
- **`packages/dart/codelab_architecture_tests`** (`[protocol]`): правила сторожа (D10 design.md).
- **`packages/dart/codelab_client_core`, `apps/codelab_cli`:** без изменений.
- **Документы:** `dart-agent-and-clients` §12.1 (`12-1-view-model.md`: markdown-модель — для CLI, VIEW-3 и VIEW-12) и §12.3 (`12-3-desktop-display.md`: §12.3.2, A2–A4, DSK-2, DSK-3, DSK-5, DSK-7, §12.3.6, §12.3.7); `technology-stack.md`; `11-assumptions-and-open-questions.md`; `delivery-roadmap.md` (§4.5, §10.4); `agent-parity-goals.md` (D-06); `docs/backlog/smoke-2026-10-30.md`; `THIRD_PARTY_NOTICES.md` (шрифты).
- **Граф пакетов в `README.md`** не меняется: новых связей между внутренними пакетами нет.
