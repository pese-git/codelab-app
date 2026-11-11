Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2): сначала красный тест, потом код. В скобках — требование спецификации этого change и сценарий, либо решение design.md. Красный тест коммитится отдельно до кода, но коммит делается только по просьбе пользователя.

Решения пользователя 2026-11-11 (Q1–Q16) — в design.md.

Метки исполнителей:
- `[client]` — `packages/dart/codelab_client_core`, `packages/dart/codelab_client_io`;
- `[desktop]` — `packages/flutter/codelab_ui`, `apps/codelab_desktop`, правило сторожа (`codelab_architecture_tests`) для `features/project_files`.

`apps/codelab_cli`, пакеты агента и ACP не меняются.

Проверки каждой итерации — только затронутое (`AGENTS.md` §21):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm dart analyze` и `fvm dart test` в `codelab_client_core` и `codelab_client_io`; при изменении публичного API kit (итерация 5) — ещё `apps/codelab_cli`;
- `fvm flutter analyze` и `fvm flutter test` в `codelab_ui` и `apps/codelab_desktop`;
- `melos run guard` — при правке правил сторожа;
- для `openspec/` — `openspec validate add-file-preview-and-tree --strict`.

## 0. Документы и change

- [x] 0.1 Переписать proposal, design, specs и tasks по `dart-agent-and-clients` §12.6.8 и решениям пользователя 2026-11-11.
- [x] 0.2 `dart-agent-and-clients/12-6-cli-desktop-extras.md`:
  - §12.6.1 — D-13 «в доке»;
  - §12.6.8 — панель дока вместо вкладки сайдбара; имена `CodeLab*`; корень без сессии; WebSocket и web; Q3 (предупреждение вместо скрытия); v1 без `.gitignore` и наблюдения; «Open file» и Following; «Insert as mention» после D-12; ключи и файлы тестов; без `codelab.sidebar.tab`;
  - §12.6.15 — UX-15;
  - §12.6.17 — пп. 9, 10, 12, 14.
- [x] 0.3 `12-3-desktop-display.md` §12.3.2 — строки `ProjectFilesCubit`, `CodeLabFileTree`/`CodeLabFilePreview`, `ProjectFilesPane`; ключи тестов. `12-4-first-run-and-settings.md` §12.4.9 — без `codelab.sidebar.tab`.
- [x] 0.4 `agent-parity-goals.md`, строка D-13 (док, критерий, ссылка на change); `delivery-roadmap.md` §10.1, строки 03 и 29.

## 1. Итерация 1 — контракт kit и адаптер

- [x] 1.1 `[client]` Красный: `packages/dart/codelab_client_core/test/files/project_files_rules_test.dart`. Покрывает требование `acp-client-kit` «Чтение папки проекта в границах рабочей папки», сценарии «Выход из корня через `..`», «Двоичный файл по содержимому, а не по расширению», «Имя файла с секретами», «Место вызова через другой путь к той же папке». Таблицы для:
  - `normalizeRelativePath`: `\0`, абсолютный путь, `..`, `./`, `a//b`, пустой путь = корень;
  - `classifyPreview`: граница 8 КиБ, `maxBytes`, неверный UTF-8;
  - `isMaybeSecretFileName`;
  - `relativeToRoot`;
  - сортировки записей.
- [x] 1.2 `[client]` Реализация `lib/src/files/` (`project_files.dart`, `project_files_rules.dart`) и экспорт из бареля; строка о `lib/src/files/` (`ProjectFiles` и правила) в `packages/dart/codelab_client_core/AGENTS.md` §1. Без `dart:io` и новых зависимостей (D1, D2, D4, D5); doc-комментарии по AGENTS.md §15.
- [x] 1.3 `[client]` Красный: `packages/dart/codelab_client_io/test/files/io_project_files_test.dart` на временной папке. Покрывает требование `acp-client-kit` «IO-адаптеры клиента», сценарии «Символическая ссылка наружу», «Большой файл читается не целиком», и `workspace-file-browser` «Граница рабочей папки браузера». Проверяет:
  - `canonicalRoot` через ссылку;
  - ссылку внутри корня (`docs` → `doc`);
  - ссылку наружу (`symlinkOutside`, `read` → `outsideRoot`);
  - битую ссылку (`other`);
  - `../` → `invalidPath`;
  - `notFound`;
  - `.git` нет в перечислении;
  - 5001 запись → 5000 и `omitted: 1`;
  - двоичный и большой файл.
- [x] 1.4 `[client]` Реализация `lib/src/files/io_project_files.dart` (D3): проверка realpath до открытия, `path` для склейки. Экспорт из бареля `codelab_client_io`; строка `IoProjectFiles` в `packages/dart/codelab_client_io/AGENTS.md` §1.
- [x] 1.5 `[client]` По ревью итерации 1 — каждая правка парой «красный тест → код»:
  - **Q15:** `isMaybeSecretFileName` без учёта регистра (сценарий `acp-client-kit` «Имя секрета без учёта регистра»);
  - **Q16:** несуществующая цель проверяется по realpath ближайшего существующего предка (сценарий «Несуществующий файл за ссылкой наружу» → `outsideRoot`; внутри корня — `notFound`);
  - **шов чтения** `IoProjectFiles(openRange:)`: адаптер просит ровно `[0, maxBytes + 1)`, `openFileRange` уважает `end` (сценарий «Большой файл читается не целиком»);
  - **лексическая проверка** `resolveLexicallyInsideRoot` до обращения к диску за целью; на Windows сегмент с `\` или `:` → `invalidPath` (D3, п. 1; тест через `p.Context(style: windows)`, без приёмки на Windows);
  - **тесты границы:** цепочка `a -> b -> outside`, ссылка `../outside`, цикл ссылок (`read` → `unreadable`, в списке `other`), `\0` на уровне адаптера, FIFO (`list` → `other`, `read` → `unreadable` без зависания);
  - **`_kindOf`:** не обычный файл (FIFO, сокет, устройство) → `other` (сценарий «FIFO в перечислении»);
  - **`relativeToRoot`:** пустая база пропускается, предусловие в doc;
  - **симметрия ошибок:** `list` файла и `read` папки → `unreadable` (сценарий «Перечисление файла и чтение папки»; D3, п. 4);
  - **`\0` в корне:** `invalidPath` до обращения к диску (`dart:io` обрезает путь по `\0`; D3, п. 4);
  - doc-комментарии полей моделей, строка `lib/src/files/` в `packages/dart/codelab_client_core/AGENTS.md` §1.
  - **второй круг ревью:**
    - Q16 по любой ошибке разрешения (ENOTDIR, EACCES, ELOOP, нет файла), не только по отсутствию цели;
    - путь проходится от корня без перехода по ссылкам; битая ссылка наружу и ссылка на существующую цель вне корня дают одинаковый `outsideRoot` (сценарии «Битая и рабочая ссылки наружу неразличимы», «Ошибка разрешения за ссылкой наружу», «Ошибка разрешения внутри корня»);
    - лексическая проверка и склейка объединены в адаптере (`resolveLexicallyInsideRoot`), Windows-правило — только там, kit платформенно-независим (сценарий «Windows-сегмент отклоняется адаптером»; D3, п. 1);
    - страховочная ветка `ArgumentError` удалена, `\0` → `invalidPath` до обращения к диску (D3, п. 4).
  - **третий круг ревью:** Q16 для цепочки ссылок с битым концом (`a -> b -> /outside/missing` и `a -> b -> /outside/existing` → одинаково `outsideRoot`, лимит 40 переходов); восстановление прав в EACCES-тесте.

## 2. Итерация 2 — панель Files v1

- [ ] 2.1 `[desktop]` Красный: правило сторожа «`dart:io` запрещён в `apps/codelab_desktop/lib/features/project_files/`» в `codelab_architecture_tests/test/support/rules.dart` и тест правила на примере импорта (D10). Реализация — само правило; `melos run guard` зелёный.
- [ ] 2.2 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_file_tree_test.dart`. Требования «Ленивое перечисление папок», сценарии «Большая папка», «`.git` скрыт, скрытые файлы видны», и «Граница рабочей папки браузера», сценарий «Ссылка наружу видна, но не открывается». Проверяет:
  - отрисовку строк по `CodeLabFileTreeRowData` (отступ по глубине, значки папки, файла и ↗);
  - 10 000 строк — построены только видимые и запас;
  - клавиши ↑/↓/→/←/Enter и колбэки;
  - строку ↗ без колбэка раскрытия;
  - строку «… N more»;
  - строку ошибки папки;
  - ключи `file-tree-row-<relativePath>`.
- [ ] 2.3 `[desktop]` Реализация `CodeLabFileTree` (`ListView.builder`, высота строки 24) и `CodeLabFileTreeRowData` в `organisms/` и `models/`; превью в `codelab_organism_previews.dart`.
- [ ] 2.4 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_file_preview_test.dart`. Требования «Просмотр файла только для чтения» (сценарии «Текстовый файл», «Двоичный файл», «Слишком большой файл») и «Предупреждение для файлов с секретами». Проверяет:
  - номера строк;
  - подсветку строки и прокрутку к ней (вход `line`, для итерации 5);
  - отсутствие редактируемого поля;
  - состояния `loading`, `binary`, `tooLarge`, `failed`;
  - `InfoBar` `file-preview-secret-warning` при флаге `maybeSecret`;
  - ключ `file-preview`.
- [ ] 2.5 `[desktop]` Реализация `CodeLabFilePreview`: моноширинно, без подсветки до `add-desktop-markdown`, D4; превью организма.
- [ ] 2.5a `[desktop]` Красный: `codelab_file_preview_test.dart` — строка относительного пути `file-preview-path` и кнопка `file-preview-copy-path` вызывает колбэк с `relativePath`; `project_files_pane_test.dart` — сценарий «Copy path копирует относительный путь» (буфер — ровно `lib/src/a.dart`, без корня и содержимого; Q14, D13).
- [ ] 2.5b `[desktop]` Реализация: строка пути и «Copy path» в `CodeLabFilePreview` (только колбэк), `Clipboard.setData` в `ProjectFilesPane`.
- [ ] 2.6 `[desktop]` Красный: `apps/codelab_desktop/test/features/project_files/project_files_cubit_test.dart` на фальшивом `ProjectFiles`. Требования «Панель Files в доке инструментов» (сценарии «Корень без сессии», «Смена сессии в фокусе»), «Ленивое перечисление папок» (сценарии «Раскрытие папки читает один уровень», «Refresh показывает новый файл»), «Просмотр файла только для чтения» (сценарий «Поздний результат чтения») и D6. Проверяет:
  - автомат `noFolder → loading → ready`, `unavailable`;
  - раскрытие — ровно один `list`;
  - поздние `list` и `read` после смены файла или корня отбрасываются;
  - Refresh не дублируется;
  - раскрытые папки сохраняются по корню при возврате к сессии.
- [ ] 2.7 `[desktop]` Реализация `ProjectTreeState` и `ProjectFilesCubit` в `features/project_files/application/`; чистая функция построения строк — отдельно, с тестом.
- [ ] 2.8 `[desktop]` Красный: `apps/codelab_desktop/test/features/workbench/application/session_folder_is_local_test.dart` — embedded и stdio дают `true`, webSocket — `false` (требование «Панель Files в доке инструментов», сценарий «Нет панели для WebSocket-агента»; D7, D9). Реализация `sessionFolderIsLocal` в `features/workbench/application/`.
- [ ] 2.9 `[desktop]` Красный: `apps/codelab_desktop/test/features/project_files/project_files_pane_test.dart`. Требования «Панель Files в доке инструментов» (сценарии «Открытие панели для встроенного агента», «Повторное сочетание закрывает панель», «Нет панели для WebSocket-агента»), «Предупреждение для файлов с секретами» (сценарий «Открытие `.env`»: журнал и диагностика без маркера) и `agent-workbench-ui` «Tool dock with closable pane tabs» (сценарий «Unavailable pane is hidden but kept in the layout»). Проверяет:
  - переключатель `tool-toggle-files`, Cmd/Ctrl+Shift+E, пункт палитры «Files»;
  - сайдбар на месте;
  - без привязки `ProjectFiles` панели нет.
- [ ] 2.10 `[desktop]` Реализация:
  - `ProjectFilesPane` (дерево сверху, просмотр снизу, «Refresh»);
  - вычисляемые доступные панели в `workbench_shell.dart`;
  - привязка `IoProjectFiles` в `lib/app/app_scope.dart`;
  - сочетание и `HostCommand` палитры;
  - события `project_files.*` без содержимого (D5);
  - раздел о feature в `apps/codelab_desktop/AGENTS.md`.

## 3. Итерация 3 — `.gitignore`

- [ ] 3.1 `[client]` Красный: `packages/dart/codelab_client_core/test/files/gitignore_matcher_test.dart` — таблица правил: `#`, `!`, якорь `/` в начале и конце, `*`, `?`, `**`, классы `[…]`, `\#`, `\!`, порядок файлов `IgnoreStack` (требование «Игнорируемые записи по `.gitignore`», сценарий «Отрицание правила»). Источник семантики — документация git; сторонний код не копируется (AGENTS.md §5).
- [ ] 3.2 `[client]` Реализация `GitIgnoreMatcher` и `IgnoreStack`.
- [ ] 3.3 `[client]` Красный: `io_project_files_test.dart` — `list` с `IgnoreStack`: поле `ignored`, загрузка `.gitignore` папки и `.git/info/exclude`, файл правил больше 256 КиБ пропускается. Реализация в `IoProjectFiles`.
- [ ] 3.4 `[desktop]` Красный: `project_files_pane_test.dart` — сценарий «`build/` скрыт по `.gitignore`», переключатель `file-tree-show-ignored` и его сохранение в `codelab.file_browser.show_ignored`. Реализация в Cubit, панели и порте настроек app.

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
- [ ] 6.2 Проверки затронутого (§21) по каждой итерации, `openspec validate add-file-preview-and-tree --strict`. Полный `melos run check` — только по просьбе пользователя.
