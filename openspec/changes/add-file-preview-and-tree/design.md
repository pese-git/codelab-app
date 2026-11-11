## Context

**Что есть сейчас (develop 5e6e1254):**

| Что | Где | Состояние |
|---|---|---|
| Док панелей инструментов | `LayoutCubit` (`apps/codelab_desktop/lib/features/workbench/application/layout_cubit.dart`), `CodeLabToolDock`, `DockLayoutStore` (`codelab.dock.*`) | есть (change `redesign-workbench-shell`, D5); разбиения `lower` нет |
| `ToolPane.files`, `ToolPane.terminal` | `codelab_ui/lib/src/molecules/codelab_tool_pane.dart` | значения есть, app их не предлагает: `_availablePanes = [plan, protocol]` |
| Сохранённая раскладка | `workbench_shell.dart` | показывает только панели из `_availablePanes`, сохранённую раскладку не трогает |
| Чтение файлов клиентом | `IoTextFileIo` (`codelab_client_io`) для ACP `fs/*` | граница только лексическая (`resolveWithinWorkingDirectory`, `codelab_client_acp/lib/src/domain/fs_access.dart`): выход через symlink принят как остаточный риск |
| Места вызова | ACP `ToolCallLocation { path, line? }` (`08-Tool Calls.md` «Following the Agent») | в kit `ToolCallView.paths` — только пути, `line` теряется |
| Папка сессии и проекта | `SessionView.cwd`, `WorkspaceState.projectDirectory`, `WorkspaceState.profile` | есть |
| Подсветка и markdown | change `add-desktop-markdown` (`CodeLabCodeHighlighter`, `CodeLabMarkdown`) | в работе, не слит |
| Терминал | change `add-integrated-terminal` | не начат, документы устарели (см. D9) |

**Источник дизайна** — `dart-agent-and-clients` §12.6.8 (D-13), §12.3 A13 (шаг 0 — док; шаг 6 — панель без данных не предлагается). Change реализует его с решениями пользователя 2026-11-11 и приводит документ к ним (задачи группы 0).

**Граница с ACP.** Браузер — чтение клиента, а не ACP `fs/*` и не инструмент агента. Одобрения он не требует (AGENTS.md §10 охраняет действия агента). Граница рабочей папки при этом обязательна и строже, чем у `fs/*`: realpath, проверка до чтения. Методов, полей и `_meta` ACP change не вводит. «Open file» и Following опираются только на стандартные `locations` с `path` (абсолютный) и `line`; диапазона строк ACP не определяет, и клиент его не выдумывает (AGENTS.md §3.4).

## Goals / Non-Goals

**Goals:**
- Панель Files: ленивое дерево и просмотр только для чтения в границах папки сессии (UX-15, UX-16).
- Строгая граница по realpath; ссылки наружу видны, но не открываются.
- Один порт `ProjectFiles` в kit и одна реализация `IoProjectFiles` в `codelab_client_io`. Политика (что считать двоичным, слишком большим, похожим на секрет) — в kit.
- Панель есть только там, где папка сессии на этой машине.
- Следующие итерации — правила `.gitignore`, наблюдение, «Open file» у строки вызова, Following — без перестройки v1.

**Non-Goals:** см. proposal.md, «Не входит».

## Решения пользователя 2026-11-11

| № | Вопрос | Решение |
|---|---|---|
| Q1 | Сроки (D-13 — Could, M5) | делаем сейчас, в фоне, не блокируя 1.0 |
| Q2 | Символическая ссылка наружу | строка с ↗, не раскрывается и не открывается; проверка по realpath до чтения (§12.6.8, шаг 2) |
| Q3 | Файлы с секретами (`.env*`, `*.pem`, `*.key`, `id_*`) | показываются как есть, с предупреждением в просмотре; правило имён — одно место в kit (то же, что `maybeSecret` §12.1.7); содержимое никогда не попадает в логи и диагностику. Рекомендация архитектора (содержимое за кликом «Show contents») отклонена |
| Q4 | Фильтр шумных записей | в v1 скрыт только `.git`; `.gitignore` и `.git/info/exclude` с «Show ignored files» — следующей итерацией |
| Q5 | Что показывает просмотр в v1 | текст с номерами строк, пометки binary и too large (лимиты §12.6.8); markdown — через `CodeLabMarkdown` после `add-desktop-markdown`; картинки — позже; HTML — только исходником |
| Q6 | Действие у строки вызова | «Open file» — файл с диска в Files у строки `line`; превью вывода инструмента не делается, пометки «from tool call» нет |
| Q7 | Following | отдельной итерацией после «Open file»; работает только во время хода сессии в фокусе; по умолчанию выключен |
| Q8 | WebSocket-агент | панель Files не предлагается для любых WebSocket-профилей |
| Q9 | Обновление при изменении файлов | v1 — кнопка «Refresh»; наблюдение (§12.6.8, шаг 6: без рекурсии, склейка 200 мс, до 256 папок) — отдельной итерацией |
| Q10 | Web и устройства без локальной папки | панель не предлагается; «Import from Files» — этап 10; встроенный агент на desktop — как stdio |
| Q11 | CLI | не делается; правила `.gitignore` в kit позже переиспользует дополнение путей CLI |
| Q12 | «Insert as mention» | отложено до D-12 |
| Q13 | Корень без сессии | дерево папки выбранного проекта (`WorkspaceState.projectDirectory`) |
| Q15 | Регистр в правиле имён секретов | без учёта регистра: `.ENV`, `Server.PEM`, `ID_RSA` получают предупреждение (ревью итерации 1) |
| Q16 | Цель, которая не разрешается, за ссылкой наружу | существование и доступность файла вне корня не различаются. Если цель не разрешается (любая ошибка разрешения: нет файла, ENOTDIR, EACCES, ELOOP), путь проходится от корня по сегментам без перехода по ссылкам: ссылка, чей realpath не разрешается или разрешается вне корня, либо ближайший разрешимый предок вне корня → `outsideRoot`; иначе — исходная ошибка (`notFound`, `unreadable`) (ревью итерации 1, второй круг) |
| Q14 | «Copy path» и строка пути из артборда | входят в итерацию 2 (панель v1): над просмотром — относительный путь файла от корня; «Copy path» копирует в буфер обмена этот относительный путь, не содержимое |

## Decisions

### D1. Пакеты и слои

| Компонент | Пакет / путь | Слой |
|---|---|---|
| `ProjectFiles` (порт), `ProjectEntry`, `ProjectEntryKind`, `DirectoryListing`, `FilePreview` (`TextPreview`, `BinaryPreview`, `TooLargePreview`), `ProjectFilesFailure` | `codelab_client_core/lib/src/files/` | чистый Dart, web-безопасно |
| `normalizeRelativePath`, `classifyPreview`, `isMaybeSecretFileName`, `relativeToRoot` | `codelab_client_core/lib/src/files/` | чистые функции — политика kit |
| `GitIgnoreMatcher`, `IgnoreStack` (итерация 3) | `codelab_client_core/lib/src/files/` | чистый Dart |
| `IoProjectFiles` | `codelab_client_io/lib/src/files/` | `dart:io`: realpath, перечисление, чтение, позже `watch` |
| `ProjectTreeState`, `ProjectFilesCubit` | `apps/codelab_desktop/lib/features/project_files/application/` | application |
| `sessionFolderIsLocal` | `apps/codelab_desktop/lib/features/workbench/application/` | application (D9) |
| `CodeLabFileTree`, `CodeLabFileTreeRowData`, `CodeLabFilePreview` | `codelab_ui/lib/src/organisms/`, `models/` | ui_kit, без логики |
| `ProjectFilesPane` | `apps/codelab_desktop/lib/features/project_files/presentation/` | presentation |

Почему не `apps/codelab_desktop/lib/core/platform/` (прежний вариант change): `dart:io`-адаптеры клиента живут в `codelab_client_io`, а правила — в kit (корневой AGENTS.md §5; вложенные AGENTS.md обоих пакетов). Тогда правила проверяются на Dart VM без Flutter, а будущий web или мобильный хост подставит другую реализацию порта.

Почему Cubit дерева в app, а не в kit: раскрытые папки и выбор — UI-состояние окна. CLI дерево не рисует (Q11), значит, второй потребитель отсутствует. Чистую часть — плоский список строк по раскрытым папкам — Cubit строит функцией, которая тестируется отдельно.

Альтернатива — `ProjectFiles` целиком в app — отклонена: §12.6.8 и AGENTS.md §5 требуют общих адаптеров, а правила `.gitignore` нужны CLI.

**Зависимости.** Allowlist-ы не меняются. В `codelab_client_core` нет `package:path`, поэтому `normalizeRelativePath` работает по сегментам POSIX-пути, без него. Склейку с путями ОС делает `IoProjectFiles` через `path`, который уже есть в allowlist `codelab_client_io`. Граф `README.md` не меняется.

### D2. Контракт `ProjectFiles`

```dart
// packages/dart/codelab_client_core/lib/src/files/project_files.dart
abstract interface class ProjectFiles {
  Future<String> canonicalRoot(String folder);                  // realpath(folder)
  Future<DirectoryListing> list(String root, String relativeDir,
      {int maxEntries = 5000});                                 // итерация 3: + IgnoreStack
  Future<FilePreview> read(String root, String relativePath,
      {int maxBytes = 1 << 20});
  // итерация 4: Stream<String> watch(String root, String relativeDir);
}
```

- `ProjectEntry(relativePath, name, kind, size?)`. `kind` — `file | directory | symlinkOutside | other`; `ignored` добавляется в итерации 3. В `relativePath` — POSIX-разделители, путь от корня.
- `DirectoryListing(relativeDir, entries, omitted)`. Сначала папки, затем файлы, по имени без учёта регистра. `.git` в перечислении нет никогда.
- `ProjectFilesFailure(kind, relativePath)` с видами `outsideRoot | notFound | unreadable | invalidPath`. Это типизированная ошибка (`error-handling.md`), её текст не содержит содержимого файла.
- Члены будущих итераций в коде не появляются раньше своей итерации (AGENTS.md client_core §2: «заглушек нет»).

### D3. Граница рабочей папки (Q2)

1. **Лексически, до обращения к диску.**
   - Kit, платформенно-независимо: `normalizeRelativePath` даёт `invalidPath` для `\0`, абсолютного POSIX-пути и `..`, поднимающегося выше корня; `..` внутри пути вычисляется (`a/../b` → `b`). Функцию вызывают и Cubit, и `IoProjectFiles`.
   - Адаптер `IoProjectFiles`: лексическая проверка выполняется вместе со склейкой `root/rel` в стиле путей текущей ОС (`resolveLexicallyInsideRoot`). На Windows сегменты с `\` или `:` (буква диска, альтернативные потоки NTFS) дают `invalidPath`. Kit этого правила не знает: оно зависит от платформы.
   - Первая версия проверена только на POSIX (macOS, Linux); Windows-правило задано и проверено тестом со стилем путей Windows, но приёмки на Windows нет.
2. **`IoProjectFiles`, по realpath.** Для каждой операции считается `realpath(root/rel)` (`resolveSymbolicLinks`); результат должен быть равен `root` или начинаться с `root + separator`, иначе `outsideRoot`. Проверка выполняется до открытия файла или перечисления папки.
3. **Цель не разрешается (Q16).** Если `realpath(root/rel)` даёт любую ошибку разрешения (нет файла, ENOTDIR, EACCES, ELOOP), путь проходится от корня по сегментам без перехода по ссылкам:
   - ссылка, чей realpath не разрешается или разрешается вне корня → `outsideRoot`;
   - ближайший разрешимый предок вне корня → `outsideRoot`;
   - иначе — исходная ошибка: `notFound` или `unreadable`.

   Битая ссылка на цель вне корня и ссылка на существующую цель вне корня дают один и тот же `outsideRoot`. Так ответ не раскрывает, существует ли и доступен ли файл вне корня.
4. **Виды ошибок симметричны.** `list` файла и `read` папки дают `unreadable`, а не `ArgumentError` или исключение `dart:io`. `\0` в корне или в относительном пути даёт `invalidPath` до обращения к диску: `dart:io` на macOS молча обрезает путь по `\0` и открыл бы другой путь.
5. **Ссылка наружу** перечисляется как `symlinkOutside` (↗): не раскрывается, не открывается, «Open file» к ней не ведёт. Битая ссылка, FIFO, сокет и устройство — `other`: не раскрываются и не открываются.
6. **Лексическая проверка `fs/*` не переиспользуется.** Она не разрешает ссылок и ради браузера не меняется: граница `fs/*` — отдельное решение (`add-acp-fs-client-support`, Decision 3).

Альтернатива — общая функция границы для `fs/*` и браузера — отклонена: `codelab_client_acp` не должен получить `dart:io`, а ужесточение `fs/*` меняет поведение ACP-клиента и требует своего change.

### D4. Классификация просмотра и лимиты (Q5)

`IoProjectFiles.read` читает не больше `maxBytes + 1` байт и передаёт байты и размер в `classifyPreview` kit:
- NUL в первых 8 КиБ → `BinaryPreview(size)`, текст «Binary file (N KB)»;
- размер больше `maxBytes` (1 МиБ) → `TooLargePreview(size)`, текст «File too large to preview (N MB)»;
- иначе `TextPreview(text)`, UTF-8 с заменой неверных байт.

Номера строк рисует `CodeLabFilePreview`, строки виртуализированы. До слияния `add-desktop-markdown` текст моноширинный без цвета. Подсветка и markdown появятся потом через `CodeLabCodeHighlighter` и `CodeLabMarkdown` с их порогами, без своего движка. Расширение файла на классификацию не влияет.

### D5. Файлы с секретами (Q3)

- `isMaybeSecretFileName(name)` в kit — одно правило для браузера и будущего `PromptContentBuilder` (D-12, `maybeSecret` §12.1.7). Шаблоны `.env*`, `*.pem`, `*.key`, `id_*` сравниваются с именем файла без учёта регистра (Q15): `.ENV`, `Server.PEM` и `ID_RSA` тоже получают предупреждение. На macOS и Windows файловая система обычно нечувствительна к регистру, и `.ENV` — тот же файл.
- Совпадение даёт в просмотре `InfoBar` уровня `warning` «This file may contain secrets.» (ключ `file-preview-secret-warning`), а содержимое показывается как есть.
- **Инвариант:** текст просмотра не попадает в логи, диагностику, события и снимок рабочего места. События `project_files.*` несут только `session_id`, операцию и вид сбоя; относительный путь — только на уровне debug. Тест проверяет журнал после открытия `.env`.

### D6. Состояние `ProjectFilesCubit`

```dart
final class ProjectTreeState {
  final ProjectTreeStatus status;  // noFolder | unavailable(reason) | loading | ready
  final String? root;              // realpath папки
  final Set<String> expanded;      // relativeDir
  final List<CodeLabFileTreeRowData> rows;
  final String? selected;
  final FilePreviewState preview;  // none | loading(path) | shown(path, preview, line?) | failed(path, kind)
}
```

- **Корень.** Папка сессии в фокусе (`SessionView.cwd`), без сессии — `WorkspaceState.projectDirectory` (Q13). Ни того, ни другого — `noFolder`. Папки нет на диске — `unavailable`: «The project folder does not exist.».
- Раскрытые папки и выбор хранятся по корню в памяти Cubit, не в `shared_preferences`: это UI-состояние окна. Набор открытых панелей по-прежнему сохраняет `LayoutCubit`.
- **Поздние результаты** (AGENTS.md §9, §12). Каждый `list` и `read` получает номер запроса. Результат применяется, только если номер текущий для этой папки или файла и корень не сменился. Иначе он отбрасывается без изменения состояния.
- Сворачивание папки не отменяет `list` в полёте: результат отбросится по номеру. Ошибка `list` — строка ошибки под папкой. Ошибка `read` — `failed(path, kind)`.
- **Refresh** (Q9) перечитывает раскрытые папки и выбранный файл: одна операция на папку, повторное нажатие во время обновления игнорируется.

Альтернатива — набор флагов `isLoading`/`hasError` — отклонена (AGENTS.md §8).

### D7. Доступность панели и док

- Панель Files предлагается, если в scope есть привязка `ProjectFiles` и `sessionFolderIsLocal(profile)` истинно. Предикат истинен для `ConnectionProfile.embedded` и `.stdio` и ложен для `.webSocket` (Q8, Q10). Профиль — текущий профиль окна (`WindowConnectionState.profile`).
- `_availablePanes` в `workbench_shell.dart` становится вычисляемым списком.
- Недоступная панель не показывается и не имеет переключателя, но остаётся в `LayoutState.openPanes` и в `codelab.dock.*`. После возвращения к локальному профилю она снова видна. Так раскладка пользователя не теряется при временной смене подключения. Это общее правило дока: требование `agent-workbench-ui` переписывается обобщённо, и терминальный change добавит только свои сценарии.
- Cmd/Ctrl+Shift+E — переключатель Files (A13, шаг 3). Пункт «Files» в группе «Go to» палитры через `HostCommand` вызывает тот же `LayoutCubit.togglePane`.
- Разбиение дока не вводится: «дерево сверху, просмотр снизу» — разметка внутри `ProjectFilesPane`.

### D8. «Open file» и Following (итерация 5; Q6, Q7)

- **Kit.** `ToolCallView` получает `locations: List<ToolLocationView(path, line?)>` в порядке прихода. `paths` остаётся: его используют `ToolRowFormatter` и CLI. Проекция с нуля и инкрементальная совпадают. Это аддитивное изменение публичного API kit (требование `acp-client-kit` «Места вызова с номером строки»).
- **Относительный путь.** `relativeToRoot(absolute, sessionCwd, root)` (kit) снимает префикс `sessionCwd` или канонического `root`: на macOS `/tmp` и `/private/tmp` — одна папка. Путь вне обоих — действия нет. Окончательную проверку делает `IoProjectFiles` (D3).
- **«Open file»** у строки вызова с местом внутри корня, только при доступной панели. Действие открывает и активирует Files, раскрывает папки до файла, выбирает его и прокручивает просмотр к `line`; строка подсвечивается. Ключ — `tool-row-open-file-<toolCallId>`.
- **Following** — переключатель в шапке панели (`file-preview-following`), по умолчанию выключен, в `shared_preferences` не сохраняется.
  - Пока он включён и в сессии в фокусе идёт ход, каждое новое место (новый `tool_call` или `tool_call_update` с изменившимися `locations`) открывает файл так же, как «Open file».
  - Вне хода и для других сессий места игнорируются.
  - Ручной выбор файла в дереве выключает Following, как в Zed.
  - Смена фокуса сессии Following не включает и не выключает: следующий ход новой сессии ведёт уже её места.
- Альтернатива «превью вывода инструмента» отклонена пользователем (Q6). Вывод — фрагмент в формате агента: у Dart-агента `read` с `offset` и `limit`, у сторонних агентов формат неизвестен.

### D9. Согласование с `add-integrated-terminal`

Файлы терминального change здесь не меняются: его ведут в другом worktree. Договорённости:
1. **Папка панели** — папка сессии в фокусе, как у Files (A13, шаг 0).
2. **Предикат «папка сессии на этой машине»** — одна функция `sessionFolderIsLocal` в `apps/codelab_desktop/lib/features/workbench/application/`. Вводит её этот change, терминальный change использует её же (A16, шаг 6: нет панели для web и удалённой папки).
3. **Требование дока** этот change переписывает обобщённо (D7). Терминальный change добавляет только свои сценарии (Terminal toggle, Cmd/Ctrl+`).
4. **Разбиение дока** (`lower`) не вводит ни один из двух changes.
5. **Сочетания** не пересекаются: Cmd/Ctrl+Shift+E — Files, Cmd/Ctrl+` — Terminal.
6. **Открытый пункт терминального change:** A13 (шаг 0) говорит «Files и Terminal открываются в папке сессии», а A16 (шаг 3) и D-28 — «в рабочей папке активного профиля на момент создания». Его design.md ещё ссылается на `state.stdioCwd`, `core/platform/TerminalProcessFactory`, `AcpTerminalPanel` и нижнюю строку. Противоречие должен снять терминальный change; рекомендация — папка сессии в фокусе.

### D10. Сторож

Новое правило в `codelab_architecture_tests/test/support/rules.dart`: `apps/codelab_desktop/lib/features/project_files/` не импортирует `dart:io`, по образцу `features/settings/presentation` (SETUP-9). `codelab_client_core/lib/src/files/` уже покрыт правилом `webUnsafe` пакета, `codelab_client_io` — своим. Пакетов и рёбер графа change не добавляет.

### D11. Наблюдение (итерация 4; Q9)

По §12.6.8, шаг 6:
- на каждую раскрытую папку — `Directory(path).watch()` без рекурсии;
- события склеиваются за 200 мс и вызывают повторный `list` этой папки;
- не больше 256 наблюдаемых папок, дальше — только «Refresh»;
- ошибка наблюдения — строка «Changes are not tracked».

Владелец подписок — `ProjectFilesCubit`: отмена при сворачивании, смене корня и `close()` (AGENTS.md §9). При итерации 3 изменение `.gitignore` пересобирает правила поддерева.

### D12. Тесты

| Уровень | Где | Что |
|---|---|---|
| kit | `codelab_client_core/test/files/` | `normalizeRelativePath`, `classifyPreview`, `isMaybeSecretFileName`, `relativeToRoot`, сортировка; позже таблица `.gitignore` |
| IO | `codelab_client_io/test/files/io_project_files_test.dart` | временная папка: ссылка наружу, `../`, `.git`, лимит 5000, binary, too large, позже `watch` |
| ui_kit | `codelab_ui/test/codelab_file_tree_test.dart`, `codelab_file_preview_test.dart` | отрисовка, клавиатура, виртуализация, состояния |
| app | `apps/codelab_desktop/test/features/project_files/project_files_cubit_test.dart`, `project_files_pane_test.dart` | автомат, поздние результаты, доступность, Refresh, «Open file», Following — на фальшивом `ProjectFiles` |

Widget-тесты не трогают настоящую файловую систему: она зависает в fake-async зоне (`apps/codelab_desktop/AGENTS.md`, «Тесты»).

### D13. Отступления от артборда `docs/design/claude-design/Files.dc.html`

Совпадает с артбордом:
- док справа: дерево сверху, просмотр снизу;
- строка ↗ «outside, not opened»;
- пометки «Binary file (24 KB)», «File too large to preview (3 MB)», «Changes are not tracked · Refresh»;
- «Show ignored files» (итерация 3);
- подпись «Panes follow the focused session».

Отступления:
- **Git-статус `M` у файла** — не входит (Non-Goals).
- **«Insert as mention»** — после D-12 (Q12).
- **«Copy path» и строка пути** — входят (Q14), но показывают относительный путь от корня, а не путь с именем проекта: это тот же `relativePath`, что в дереве. Буфер обмена — `Clipboard.setData` в presentation (Flutter services), без нового порта: копируется только строка пути.
- **Состояние «The session folder is not on this computer.»** не нужно: для WebSocket панель не предлагается (Q8). Вместо него — «The project folder does not exist.» для пропавшей локальной папки.
- **Подпись «.gitignore respected · .git never shown»** — в v1 только «.git never shown», с итерацией 3 — полностью.

Артборд не правится этим change.

## Risks / Trade-offs

- **[TOCTOU по символическим ссылкам]** Между проверкой realpath и открытием файла ссылку могут подменить. Дескриптор в Dart нельзя проверить на realpath. → Окно узкое, читаем только на чтение, лимит размера; остаточный риск принят и записан здесь. Агент и так может прочитать любой файл своими инструментами в пределах своей политики.
- **[Поздние результаты]** `list` или `read` после смены файла, сессии или корня могут перетереть актуальное состояние. → Номер запроса и корень в ключе (D6), тест на каждую гонку.
- **[Секреты на экране]** Q3 показывает содержимое `.env` как есть. → Предупреждение в просмотре; инвариант «не в логах и диагностике» с тестом (D5).
- **[Ложная локальность]** У stdio-агента в контейнере или по ssh папка может отличаться от локальной с тем же путём. → Принято: stdio-агент по определению видит ту же файловую систему, что клиент, в обычном сценарии. WebSocket исключён целиком (Q8).
- **[Большие папки]** Лимит 5000 записей на папку и виртуализация дерева. Перечисление асинхронное и не блокирует UI-изолят.
- **[Огромная папка в адаптере — принято]** `IoProjectFiles.list` перечисляет папку целиком, чтобы отсортировать записи и посчитать `omitted`. На миллионе записей это стоит памяти и времени адаптера, хотя UI защищён лимитом 5000. Предохранитель (остановка перечисления по числу записей или по времени) не делается: такие папки в рабочих проектах редки, а ранняя остановка ломает сортировку и счёт `omitted`. Риск принят по ревью итерации 1.
- **[Параллельный терминальный change]** Оба меняют требование дока и `_availablePanes`. → Этот change идёт первым и вводит обобщённое правило и предикат (D9). Терминальный change при архивировании перебазирует свою дельту.
- **[Зависимость от `add-desktop-markdown`]** До слияния нет подсветки и markdown. → Принято (Q5); превью работает без них.

## Migration Plan

Миграции данных нет. Новый ключ `shared_preferences` не вводится до итерации 3 (`codelab.file_browser.show_ignored`). Ключ `codelab.sidebar.tab` из прежней редакции §12.6.8 не вводится: сайдбар остаётся списком сессий.

## Open Questions

- Для терминального change: папка вкладки — сессия в фокусе или активный профиль (D9, п. 6).
- Markdown-превью после `add-desktop-markdown`: задача этого change (если тот change сольётся до итерации 5) или отдельный маленький change — решает оркестратор по факту слияния.
