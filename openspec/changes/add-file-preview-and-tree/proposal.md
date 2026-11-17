## Why

В CodeLab нельзя посмотреть файлы проекта, не уходя из приложения. В строке вызова инструмента (`Read lib/a.dart:10-29`) виден только путь, а в панели Files дока инструментов справа пока ничего нет: в `ToolPane` значение `files` есть, но app предлагает только Plan и Protocol (`apps/codelab_desktop/lib/features/workbench/presentation/workbench_shell.dart`, `_availablePanes`).

Это строка матрицы целей **D-13** «Файловый браузер проекта» (`agent-parity-goals.md` §3.9, Could, этап 9+, веха M5; экран 03 `delivery-roadmap.md` §10.1). Принятый дизайн — `dart-agent-and-clients` §12.6.8 и §12.3 A13. Пользователь 2026-11-11 решил делать её сейчас, в фоне, не блокируя 1.0 (design.md, Q1).

Раньше этот change (2026-08) предлагал свой reader в `apps/codelab_desktop/lib/core/platform/`, вкладку сайдбара, превью вывода инструмента и подсветку «диапазона» из `ToolCallLocation`. Код и документы с тех пор ушли вперёд: появились общий клиентский слой `codelab_client_core` и адаптеры `codelab_client_io`, док панелей (`LayoutCubit`, change `redesign-workbench-shell`), переименования ADR-0002. Кроме того, в ACP у `ToolCallLocation` есть только `path` и `line` — диапазона нет. Change переписан по §12.6.8 и решениям пользователя 2026-11-11.

## What Changes

- **Панель Files в доке инструментов** (`workspace-file-browser`, ADDED):
  - дерево папки сессии в фокусе, без сессии — папки выбранного проекта (Q13);
  - сверху дерево, снизу просмотр только для чтения внутри одной панели;
  - вход — переключатель в app bar, Cmd/Ctrl+Shift+E, пункт палитры.
- **Где панель есть.** Только для локальной папки: встроенный агент и stdio-профиль. Для WebSocket-профилей, в web и на устройствах без локальной папки панель не предлагается (Q8, Q10).
- **Граница рабочей папки по realpath, до чтения** (Q2):
  - символическая ссылка наружу — строка с ↗, не раскрывается и не открывается;
  - путь с `\0`, абсолютный или с `..` отклоняется.
- **Ленивое перечисление:**
  - читаются только корень и раскрытые папки, до 5000 записей на папку, сверх лимита — «… N more»;
  - `.git` скрыт всегда, остальные скрытые записи видны;
  - в v1 обновление только кнопкой «Refresh» (Q4, Q9).
- **Просмотр только для чтения** (Q5):
  - текст с номерами строк;
  - пометки «Binary file» и «File too large to preview» (лимиты §12.6.8);
  - для файлов с именами `.env*`, `*.pem`, `*.key`, `id_*` — показ как есть с предупреждением; содержимое не попадает в логи и диагностику (Q3).
  - над просмотром — относительный путь файла от корня и «Copy path», который копирует только этот путь (Q14).
- **Следующие итерации того же change:**
  - правила `.gitignore` и `.git/info/exclude` с переключателем «Show ignored files» (Q4);
  - наблюдение за раскрытыми папками (Q9);
  - «Open file» из строки вызова инструмента: файл с диска в Files у строки `line` (Q6);
  - режим Following: только во время хода сессии в фокусе, выключен по умолчанию (Q7).
- **Общий клиентский слой** (`acp-client-kit`, ADDED и MODIFIED):
  - порт `ProjectFiles`, модели и чистые правила (проверка относительного пути, классификация превью, имена файлов с секретами) — в `codelab_client_core`;
  - `IoProjectFiles` — в `codelab_client_io`;
  - места вызова с номером строки `ToolCallView.locations`.
- **Док** (`agent-workbench-ui`, MODIFIED «Tool dock with closable pane tabs»): доступность панели определяет её предикат; панель без данных не предлагается; недоступная панель скрывается, но остаётся в сохранённой раскладке.
- **Документы:** §12.6.8, §12.3 (таблица компонентов), §12.4.9, `agent-parity-goals.md` D-13 и `delivery-roadmap.md` §10.1 приводятся к доку и к решениям пользователя.
- **BREAKING:** нет. ACP не меняется.

## Не входит

- Редактирование файлов в CodeLab; поиск по файлам; git-статусы в дереве.
- Превью вывода инструмента и пометка «from tool call» (Q6). Правки агента покажет панель Diff (D-07), это отдельный change.
- Markdown-превью через `CodeLabMarkdown` и подсветка через `CodeLabCodeHighlighter`: только после слияния change `add-desktop-markdown`, отдельной задачей или change. До этого превью моноширинное без цвета. Картинки — позже; HTML показывается только исходником (Q5).
- «Insert as mention» — после D-12, вложений в app (Q12).
- CLI (Q11). Правила `.gitignore` в kit позже переиспользует дополнение путей CLI (§12.2.8).
- «Import from Files…» и панель на телефоне и в web — этап 10 (§12.8, Q10).
- Вертикальное разбиение дока (`ToolDockState.lower`).
- Панель Terminal — change `add-integrated-terminal`. Здесь только общие правила дока и предикат локальной папки (design.md D9).

## Capabilities

### New Capabilities

- `workspace-file-browser`: панель Files дока — ленивое дерево рабочей папки в её границах, просмотр файла только для чтения, обновление, игнорируемые записи, наблюдение, «Open file» из вызова инструмента и Following.

### Modified Capabilities

- `agent-workbench-ui`: требование «Tool dock with closable pane tabs» — доступность панели по её предикату вместо перечня панелей одного change.
- `acp-client-kit`:
  - ADDED «Чтение папки проекта в границах рабочей папки» — порт и чистые правила kit;
  - ADDED «Места вызова с номером строки»;
  - MODIFIED «IO-адаптеры клиента» — `IoProjectFiles`.

## Impact

- `packages/dart/codelab_client_core` (`[client]`): `lib/src/files/` — `ProjectFiles`, `ProjectEntry`, `DirectoryListing`, `FilePreview`, `ProjectFilesFailure`, `normalizeRelativePath`, `classifyPreview`, `isMaybeSecretFileName`; позже `GitIgnoreMatcher`, `IgnoreStack`; `ToolCallView.locations` и проекция. Новых зависимостей нет.
- `packages/dart/codelab_client_io` (`[client]`): `lib/src/files/io_project_files.dart`. Новых зависимостей нет.
- `packages/flutter/codelab_ui` (`[desktop]`): `CodeLabFileTree`, `CodeLabFileTreeRowData`, `CodeLabFilePreview`, превью организмов; действие «Open file» строки вызова.
- `apps/codelab_desktop` (`[desktop]`):
  - `lib/features/project_files/{application,presentation}` — `ProjectFilesCubit`, `ProjectTreeState`, `ProjectFilesPane`;
  - `sessionFolderIsLocal` в `features/workbench/application/`;
  - вычисляемые доступные панели в `workbench_shell.dart`;
  - привязка `ProjectFiles` в `lib/app/app_scope.dart`;
  - Cmd/Ctrl+Shift+E, пункт палитры.
- `packages/dart/codelab_architecture_tests` (`[desktop]`): правило «`dart:io` запрещён в `apps/codelab_desktop/lib/features/project_files/`».
- Граф пакетов в `README.md` не меняется: app уже зависит от `codelab_client_core` и `codelab_client_io`.
- Документы: `12-6-cli-desktop-extras.md` §12.6.8, §12.6.15 (UX-15, UX-16), §12.6.17; `12-3-desktop-display.md` §12.3.2; `12-4-first-run-and-settings.md` §12.4.9; `agent-parity-goals.md` D-13; `delivery-roadmap.md` §10.1.
