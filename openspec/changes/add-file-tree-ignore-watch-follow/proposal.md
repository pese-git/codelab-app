## Why

Панель Files (строка D-13 матрицы целей) влита в `develop` в объёме итераций 0–2 change `add-file-preview-and-tree`: ленивое дерево рабочей папки в границах realpath, просмотр только для чтения, предупреждение для файлов с секретами, «Refresh». Итерации 3–5 этого change не начаты, поэтому его нельзя было архивировать, а в `openspec/specs/` не было спецификации `workspace-file-browser`, хотя feature `project_files` уже работает. Разделение 2026-11-23 оставляет в `add-file-preview-and-tree` только влитый объём, а итерации 3–5 переносит сюда.

## What Changes

- **Игнорируемые записи** (итерация 3; design.md change `add-file-preview-and-tree`, Q4): правила `.gitignore` каждой папки на пути и `.git/info/exclude` корня; переключатель «Show ignored files» на панели и строка `settings-general-show-ignored` на странице «General» — одна настройка `codelab.file_browser.show_ignored`, один владелец `ShowIgnoredFilesCubit` (D14).
- **Наблюдение за раскрытыми папками** (итерация 4; Q9, D11): без рекурсии, склейка 200 мс, не больше 256 папок, отмена при сворачивании.
- **«Open file» из строки вызова инструмента и Following** (итерация 5; Q6, Q7, D8); в kit — места вызова с номером строки `ToolCallView.locations`.
- Номера задач сохранены (3.1–3.6, 4.1–4.3, 5.1–5.6, 6.1–6.2); 6.3 — архивирование этого change.
- **BREAKING**: нет. ACP не меняется: `ToolCallLocation` уже несёт `path` и `line`.

## Не входит

- Всё, что уже влито и описано в `add-file-preview-and-tree`: панель, граница рабочей папки, ленивое перечисление, просмотр, секреты, док.
- Остальные пункты «Не входит» `add-file-preview-and-tree` (редактирование, поиск, git-статусы, markdown-превью, «Insert as mention», CLI, web и телефон).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `workspace-file-browser`: ADDED «Игнорируемые записи по `.gitignore`», «Наблюдение за раскрытыми папками», ««Open file» из строки вызова инструмента», «Following за местами хода».
- `acp-client-kit`: ADDED «Места вызова с номером строки».
- `app-settings`: MODIFIED «Страница «General»: состав и порядок» — строка «Show ignored files»; ADDED «Показ игнорируемых файлов на странице «General»».

## Impact

- `packages/dart/codelab_client_core` (`[client]`): `GitIgnoreMatcher`, `IgnoreStack` в `lib/src/files/`; член `watch` порта `ProjectFiles` (D2 `add-file-preview-and-tree`); `ToolLocationView` и `ToolCallView.locations` — публичный API kit, поэтому проверяется и `apps/codelab_cli`.
- `packages/dart/codelab_client_io` (`[client]`): `IoProjectFiles` — `list` с `IgnoreStack`, `watch`.
- `packages/flutter/codelab_ui` (`[desktop]`): переключатели `file-tree-show-ignored` и `file-preview-following`, действие «Open file» строки вызова (только колбэк).
- `apps/codelab_desktop` (`[desktop]`): `FileBrowserPreferences`, `ShowIgnoredFilesCubit`, наблюдение и Following в `ProjectFilesCubit`, строка «General», ARB `en` и `ru`.
- Новых пакетов, зависимостей и правил сторожа нет; граф в `README.md` не меняется.
- Документы: `agent-parity-goals.md` D-13 и `delivery-roadmap.md` §10.1 (экран 03) — задача 6.1; `apps/codelab_desktop/AGENTS.md` и `doc/user-guide.md` — задача 3.6.
