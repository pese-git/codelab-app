Задачи идут парами «тест → реализация» (TDD: `CLAUDE.md`, раздел «Процесс», и ближайший `AGENTS.md` пакета задачи): сначала красный тест, потом код. В скобках — требование спецификации этого change и сценарий, либо решение design.md. Красный тест коммитится отдельно до кода, но коммит делается только по просьбе пользователя.

Задачи перенесены из change `add-file-preview-and-tree` при разделении 2026-11-23 с прежними номерами. Решения пользователя 2026-11-11 (Q1–Q19) и решения D1–D14 — в design.md того change; ссылки «D8», «Q4» ниже ведут туда.

Метки исполнителей:
- `[client]` — `packages/dart/codelab_client_core`, `packages/dart/codelab_client_io`;
- `[desktop]` — `packages/flutter/codelab_ui`, `apps/codelab_desktop`, правило сторожа (`codelab_architecture_tests`) для `features/project_files`.

`apps/codelab_cli`, пакеты агента и ACP не меняются.

Проверки каждой итерации — только затронутое (`AGENTS.md` §21):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm dart analyze` и `fvm dart test` в `codelab_client_core` и `codelab_client_io`; при изменении публичного API kit (итерация 5) — ещё `apps/codelab_cli`;
- `fvm flutter analyze` и `fvm flutter test` в `codelab_ui` и `apps/codelab_desktop`;
- `melos run guard` — при правке правил сторожа;
- для `openspec/` — `openspec validate add-file-tree-ignore-watch-follow --strict`.

## 3. Итерация 3 — `.gitignore`

- [ ] 3.1 `[client]` Красный: `packages/dart/codelab_client_core/test/files/gitignore_matcher_test.dart` — таблица правил: `#`, `!`, якорь `/` в начале и конце, `*`, `?`, `**`, классы `[…]`, `\#`, `\!`, порядок файлов `IgnoreStack` (требование «Игнорируемые записи по `.gitignore`», сценарий «Отрицание правила»). Источник семантики — документация git; сторонний код не копируется (AGENTS.md §5).
- [ ] 3.2 `[client]` Реализация `GitIgnoreMatcher` и `IgnoreStack`.
- [ ] 3.3 `[client]` Красный: `io_project_files_test.dart` — `list` с `IgnoreStack`: поле `ignored`, загрузка `.gitignore` папки и `.git/info/exclude`, файл правил больше 256 КиБ пропускается. Реализация в `IoProjectFiles`.
- [ ] 3.4 `[desktop]` Красный: `project_files_pane_test.dart` — сценарии «`build/` скрыт по `.gitignore`» и «Одно значение на панель и «General»», переключатель `file-tree-show-ignored` и его сохранение в `codelab.file_browser.show_ignored`. Реализация: порт `FileBrowserPreferences` в `lib/core/platform/` (`load` не бросает, сбой — `false`; образец — `AppLanguagePreferences`), владелец значения — `ShowIgnoredFilesCubit` в root scope (образец — `AppLanguageCubit`), `ProjectFilesCubit` получает поток значения, переключатель панели вызывает `set` владельца. Строка «Show ignored files» страницы «General» пишет то же значение через того же владельца (задачи 3.5–3.6, D14); второго ключа и порта нет.
- [ ] 3.5 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/general_page_test.dart` и `test/features/project_files/project_files_pane_test.dart` — spec app-settings «Показ игнорируемых файлов на странице «General»», сценарий «Одна настройка на две точки»: переключение на «General» меняет `ShowIgnoredFilesCubit`, переключатель `file-tree-show-ignored` открытой панели и приглушённую `build`; «Порядок блоков» требования «Страница «General»: состав и порядок» — `settings-general-show-ignored` после `settings-general-reopen-last-project`; без привязки `ProjectFiles` строки нет; `expectNoStaleLanguage` на `ru`. Перенесено из `add-app-general-page`, задача 4.1 (D14).
- [ ] 3.6 `[desktop]` Реализация 3.5: строка `settings-general-show-ignored` в блоке «Startup and files» поверх `ShowIgnoredFilesCubit` (задача 3.4), ARB `en` и `ru`; строка о владельце в разделе «Страница «General»» `apps/codelab_desktop/AGENTS.md`; раздел страницы «General» в `apps/codelab_desktop/doc/user-guide.md` через `docs-writer`. 3.5 зелёный, `l10n:check` зелёный. Перенесено из `add-app-general-page`, задача 4.2 (D14).

## 4. Итерация 4 — наблюдение

- [ ] 4.1 `[client]` Красный: `io_project_files_test.dart` — `watch` папки выдаёт событие при создании файла и прекращает при отмене подписки. Реализация `IoProjectFiles.watch` (D11).
- [ ] 4.2 `[desktop]` Красный: `project_files_cubit_test.dart`. Требование «Наблюдение за раскрытыми папками», сценарии «Новый файл без Refresh» и «Сворачивание отменяет подписку». Проверяет:
  - склейку 200 мс (fake async);
  - лимит 256;
  - строку «Changes are not tracked» при ошибке;
  - отмену подписок при смене корня и `close()`;
  - пересборку правил при изменении `.gitignore`.
- [ ] 4.3 `[desktop]` Реализация в `ProjectFilesCubit` и `ProjectFilesPane`.

## 5. Итерация 5 — «Open file» и Following

- [ ] 5.1 `[client]` Красный: `packages/dart/codelab_client_core/test/transcript/` — `ToolCallView.locations` с `line`, замена при `tool_call_update`, равенство инкрементальной проекции и проекции с нуля. Требование «Места вызова с номером строки», сценарии «Место со строкой», «Место без строки».
- [ ] 5.2 `[client]` Реализация `ToolLocationView` и поля `locations`; `build_runner`; анализ и тесты `apps/codelab_cli` (публичный API kit).
- [ ] 5.3 `[desktop]` Красный: `project_files_pane_test.dart` и тест маппера строки ленты — требование ««Open file» из строки вызова инструмента», сценарии «Открытие у строки», «Место вне корня»; ключ `tool-row-open-file-<toolCallId>`; ссылка наружу не даёт действия.
- [ ] 5.4 `[desktop]` Реализация: действие строки вызова в `codelab_ui` (только колбэк), маппер и `ProjectFilesCubit.openLocation` (раскрыть, выбрать, прочитать, `line`).
- [ ] 5.5 `[desktop]` Красный: `project_files_cubit_test.dart` — требование «Following за местами хода», сценарии «Следование во время хода», «Чужая сессия не уводит просмотр», «Ручной выбор выключает Following»; вне хода места игнорируются; по умолчанию выключен, не сохраняется.
- [ ] 5.6 `[desktop]` Реализация переключателя `file-preview-following` и подписки Cubit на места сессии в фокусе (D8). Владелец подписки — Cubit; отмена при `close()`.

## 6. Завершение

- [ ] 6.1 `[desktop]` Строка D-13 в `agent-parity-goals.md` — выполнено, со ссылками на тесты; экран 03 в `delivery-roadmap.md` §10.1.
- [ ] 6.2 Проверки затронутого (§21) по каждой итерации, `openspec validate add-file-tree-ignore-watch-follow --strict`. Полный `melos run check` — только по просьбе пользователя.
- [ ] 6.3 Архивирование change — только по просьбе пользователя, после merge итераций 3–5 и после архивирования `add-file-preview-and-tree`.
