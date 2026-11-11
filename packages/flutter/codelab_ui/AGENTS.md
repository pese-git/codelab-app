# AGENTS.md — codelab_ui

Правила этого пакета дополняют корневой `AGENTS.md` для каталога `packages/flutter/codelab_ui`.

Источники:
- корневой `AGENTS.md` §5 (границы пакетов, холст — только reference), §6, §13, §15;
- `docs/architecture/layers-and-dependencies.md`;
- `docs/architecture/proposals/dart-agent-and-clients/` §12.3 (отображение app) и §12.4.9 (настройки);
- design.md changes `redesign-transcript-rows` (строки ленты, D5–D6), `lighten-approval-block` (полоса решения, D3, D5, D6), `add-app-settings-shell` (виджеты настроек), `add-provider-setup-ui` (D19 — виджеты, D24 — отступления от артборда, D27 — риск `Unknown risk`);
- холст `docs/design/claude-design/` — только reference: код и разметка холста не копируются (корневой `AGENTS.md` §5).

## 1. Назначение и границы

* Fluent UI-кит рабочего места. Зависит только от Flutter, `fluent_ui` и того, что уже в `pubspec.yaml` (`flutter_bloc`, `freezed_annotation`, `gpt_markdown`, `val_highlight`). `gpt_markdown` и `val_highlight` импортируются только из `lib/src/rendering/` (правило сторожа, design.md change `add-desktop-markdown`, D2, D10); `material_ui`, `cupertino_ui`, `flutter_svg` и `val_*_flutter` в код пакета не импортируются — вид остаётся Fluent.
* НЕ ДОЛЖЕН импортировать `package:codelab_client_*`, `codelab_acp_*`, `codelab_agent_*`, `codelab_setup`, `codelab_embedded` и `dart:io`. У пакета нет зависимостей от внутренних пакетов в `pubspec.yaml`, поэтому такой импорт не соберётся; отдельного правила сторожа на `packages/flutter/codelab_ui/lib` в `codelab_architecture_tests/test/support/rules.dart` нет — сторож запрещает обратное направление (`package:codelab_ui/` в Dart-пакетах и CLI). Не добавлять внутреннюю зависимость в `pubspec.yaml`.
* Модели ACP и kit-а сюда не приходят: маппер app (`apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`) переводит их в типы кита (`CodeLabTranscriptRow`, `CodeLabToolCallRow`, `CodeLabNoticeRow`, `CodeLabTranscriptApproval`).

## 2. Нет логики

* Виджет не решает, опасно ли действие, не выбирает риск, тон по смыслу данных, текст заметки или исход; не форматирует и не разбирает протокольный текст. Всё это приходит готовым полем: например, `streaming` у `CodeLabAgentTextRow` вычисляет app, решение «один тег Cancelled» тоже принимает app (Q38).
* Политику ссылок и изображений (какую ссылку открыть, какое изображение можно загрузить) принимает app и передаёт через `CodeLabMarkdownScope`; кит только рисует и сообщает о клике (`add-desktop-markdown`, D2).
* Допустима только вёрстка: раскладка, обрезка вспомогательных меток, раскрытие, фокус, клавиши, временное состояние просмотра в `State` (как «Show full command»).

## 3. Слои

* `atomics/` — без составных частей кита: `CodeLabText` с ролями, `CodeLabBadge`, `CodeLabMonospaceBlock`.
* `molecules/` — из атомов: `CodeLabKeyValueList`, `CodeLabStepBreadcrumb`, `CodeLabThoughtBlock`, `CodeLabToolCallSummary`.
* `rendering/` — отрисовка ответа агента как markdown: `CodeLabMarkdown`, `CodeLabMarkdownConfig`, `CodeLabMarkdownScope`, `CodeLabCodeBlock`, счётчики `CodeLabMarkdownStats`. Импортирует только `atomics/`; его импортируют `organisms/`. Единственный слой, где разрешены `gpt_markdown` и `val_highlight`.
* `organisms/` — ленты, плитки, таблицы, панели: `CodeLabTranscriptPanel`, `CodeLabToolCallTile`, `CodeLabApprovalPrompt`, `CodeLabStatusTable`.
* Импорт — только вниз по слоям; экспорт — через барели слоёв (`atomics.dart`, `molecules.dart`, `organisms.dart`) и `lib/codelab_ui.dart`. Новый атом — при втором употреблении (как `CodeLabMonospaceBlock`, D19), не «на вырост» (корневой `AGENTS.md` §13).

## 4. Отдельные виджеты

* **`CodeLabStatusTable`** — таблица «Agent status» и подобных панелей. Колонки и ячейки — готовые строки от вызывающего, действие строки — колбэк; виджет не знает `McpServerState` и не считает «retry in».
* **`CodeLabMonospaceBlock`** — текст как есть, моноширинно (`CodeLabTextRole.mono`), с переносом, рамкой и выделением; не меняет и не разбирает текст. Употребление: ответ `/mcp` в панели «Agent status» (SETUP-11, Q34). Ответ агента в ленте он больше не рисует: огороженный ответ — блок кода `CodeLabCodeBlock` внутри markdown (D11).

* **`CodeLabTerminalPane`** — панель Terminal дока: вкладки с тегом статуса, «+», пустое состояние, `InfoBar` предупреждения и слот `content`. Виджет терминала (рендер `xterm2`) в кит не импортируется — его передаёт app в слот; подпись и тон тега, состояние «нет сессии» и сами вкладки — готовые данные от вызывающего, процессов и логики в ките нет (`add-integrated-terminal`, D3).

## 5. Тоны и риски

* Набор `CodeLabTone`: `neutral`, `accent`, `success`, `warning`, `danger`. Смысл не передаётся только цветом: тег с текстом рядом со значком.
* `CodeLabApprovalRisk` (включая `unknown` → `Unknown risk`, тон `warning`, Q32) и `CodeLabToolCallStatus` — фиксированные пары «подпись — тон» внутри кита; какой риск и статус показать, решает app.
* Тоны исхода одобрения такие же, как у тегов статуса: отмена — `warning`, отказ — `danger`.

## 6. Превью и тесты

* Каждый новый публичный виджет или новое состояние строки получает пример в `*_previews.dart` своего слоя (`codelab_organism_previews.dart`, `codelab_molecule_previews.dart`) на фиктивных данных, без секретов и реальных путей пользователя. Маркер `sk-test-leak-…` в данных превью и тестов не используется как «реальный» ключ.
* Widget-тест на каждый публичный виджет в `packages/flutter/codelab_ui/test/`: ключи `ValueKey`, видимые подписи, тон — поведение, не пиксели.
* Комментарии — по корневому `AGENTS.md` §15 (почему / для чего / как).
