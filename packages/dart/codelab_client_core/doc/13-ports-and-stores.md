# Порты и хранилища

Слой чистый и ничего не читает с диска сам. Всё внешнее он описывает портами — интерфейсами, которые реализуют `codelab_client_io` и composition root хоста. Глава собирает порты в одну таблицу и разбирает те, что не вошли в другие главы: хранилища профилей и недавних проектов, чтение папки проекта, каталог тем.

## Таблица портов

| Порт | Что делает | Реализации |
|---|---|---|
| `AgentBackend` | источник данных слоя: соединение, сессии, кадры | `AcpClientBackend` (в слое, поверх `AcpClientApplication`) |
| `TransportResolver` | профиль → `AcpTransport` | `ConfigTransportResolver` (в слое, принимает фабрики); `ioTransportResolver` в `codelab_client_io` собирает его с настоящими stdio и WebSocket; `EmbeddedTransportResolver` в composition root app и CLI открывает встроенного агента |
| `SecretSource` | ссылка на токен → значение | `ProfileSecretSource` (общий для app и CLI), `InMemorySecretSource` |
| `ProfileSecrets` | хранилище секретов профилей | реализации composition root: `_ClientProfileSecrets` в `apps/codelab_cli/lib/src/run.dart`, `client_profile_secrets.dart` и `ReopenableProfileSecrets` в `apps/codelab_desktop/lib/app/` |
| `ProfileStore` | профили подключения | `JsonFileProfileStore` (`codelab_client_io`, файл `profiles.json` в `CODELAB_HOME`); в app при недоступном файле — `UnavailableProfileStore` |
| `RecentProjectsStore` | недавние проекты | `JsonFileRecentProjectsStore` (`codelab_client_io`); в app — `MigratingRecentProjectsStore` над ним (одноразовый перенос ключа `shared_preferences`), при недопустимом `CODELAB_HOME` — `UnavailableRecentProjectsStore` |
| `WorkspaceSnapshotStore` | снимок рабочего пространства | `SharedPreferencesWorkspaceSnapshotStore` в app; `InMemoryWorkspaceSnapshotStore` в слое — для тестов |
| `ProjectFiles` | чтение папки проекта | `IoProjectFiles` (`codelab_client_io`) |
| `ThemeLibrary` | каталог пользовательских тем | `IoThemeLibrary` (`codelab_client_io`); `InMemoryThemeLibrary` в слое — для тестов |

Правило границы: порт объявляется в слое, реализация на `dart:io` — в `codelab_client_io`, реализация на Flutter-плагине — в app. `codelab_client_io` политики не содержит (`codelab_client_io/AGENTS.md`); политика — чистые функции слоя. Подробнее о пакете — [`codelab_client_io`](../../codelab_client_io/doc/README.md).

Двойники для тестов создаются так же, как реализации: см. [главу 14](14-testing.md) и [рецепт](15-extending.md#рецепт-хранилище-профилей-в-памяти).

## Профили и недавние проекты

`ProfileStore` (`lib/src/stores/stores.dart`):

- `load()` возвращает профили в порядке хранения и ничего не прячет — в том числе прежнюю запись `default`, которую потребитель отделяет через `usableStoredProfiles` ([глава 12](12-profiles-and-secrets.md));
- `save(profile)` заменяет профиль с тем же `id` на месте или добавляет новый в конец; реализация отклоняет зарезервированный id (`reservedProfileIds`) `ArgumentError`;
- `remove(id)` удаляет профиль без проверки резерва и возвращает `true`, если он был (так удаляется и запись `default`);
- встроенный профиль не сохраняется: он выбирается словом `embedded`, а не записью.

Файл общий: `$CODELAB_HOME/profiles.json` читают и app, и CLI, поэтому оба видят одни профили.

`RecentProjectsStore` — `load()` и `record(path)`. Правило «последний открытый — первым, не больше `recentProjectsLimit` (10)» общее для app и CLI и лежит в слое как `mergeRecentProjects(a, b)`: одна запись на путь (точное сравнение строк) с наибольшим `lastOpenedAt`, порядок по времени по убыванию, при равенстве — порядок появления, затем первые десять. Входы не меняются; повторное слияние результата ничего не меняет (идемпотентность). Правило в слое, потому что `codelab_client_io` политики не содержит, а функция без `dart:io` держит слой web-безопасным.

Реальный прогон слияния двух списков с общим путём `/a`:

```text
[/b 2026-11-25T00:00:00.000Z, /a 2026-11-24T00:00:00.000Z]
```

Побеждает запись `/a` с большим `lastOpenedAt`; `/b` — самая свежая. Файл — `$CODELAB_HOME/recent_projects.json` (`JsonFileRecentProjectsStore`). Тест — `test/stores/merge_recent_projects_test.dart`.

## Чтение папки проекта: `ProjectFiles`

Браузер файлов — чтение клиента, а не ACP-методы `fs/*`. Граница корня здесь строже лексической: realpath. Порт объявлен в слое, потому что `dart:io` слою запрещён, а реализация — `IoProjectFiles`.

Порт (`lib/src/files/project_files.dart`):

| Метод | Что делает |
|---|---|
| `canonicalRoot(folder)` | realpath папки; `notFound`, если её нет |
| `list(root, relativeDir, {maxEntries = 5000})` | один уровень папки как `DirectoryListing(relativeDir, entries, omitted)` |
| `read(root, relativePath, {maxBytes = 1 << 20})` | просмотр файла; читается не больше `maxBytes + 1` байт |

`FilePreview` — закрытая иерархия: `TextPreview(text)`, `BinaryPreview(size)`, `TooLargePreview(size)`. Ошибка — `ProjectFilesFailure(kind, relativePath)` с видами `outsideRoot`, `notFound`, `unreadable`, `invalidPath`; в `toString()` путь не попадает, потому что он может раскрыть структуру проекта. `ProjectEntry` — `relativePath`, `name`, `kind` (`file`, `directory`, `symlinkOutside`, `other`), `size`; ссылка с целью вне корня показывается, но не раскрывается и не открывается.

Политику «что показать» держат **чистые правила слоя** (`project_files_rules.dart`) — реализация только читает:

| Функция | Правило |
|---|---|
| `normalizeRelativePath(path)` | приводит путь к виду «POSIX от корня без `.` и `//`»; `..` выше корня, `\0` и абсолютный путь — `invalidPath` |
| `classifyPreview(head, size:, maxBytes:)` | NUL в первых 8 КиБ — `BinaryPreview`; иначе `size > maxBytes` — `TooLargePreview`; иначе `TextPreview` (UTF-8, неверные байты заменяются). Расширение файла не учитывается |
| `isMaybeSecretFileName(name)` | `.env*`, `*.pem`, `*.key`, `id_*`, без учёта регистра: такой файл показывается с предупреждением |
| `relativeToRoot(abs, sessionCwd:, root:)` | абсолютный путь места вызова → путь от корня браузера или `null` |
| `sortProjectEntries(entries)` | папки, затем остальное, по имени без учёта регистра; детерминированно |

Реальный прогон:

```text
normalizeRelativePath('a/./b/../c')                 -> a/c
normalizeRelativePath('../etc')                     -> ProjectFilesFailure(invalidPath)
relativeToRoot('/work/app/lib/a.dart', sessionCwd: '/work/app', root: '/private/work/app')
                                                    -> lib/a.dart
isMaybeSecretFileName('.env.local')                 -> true
```

Две линии границы: лексическая (`normalizeRelativePath`, до обращения к диску) и realpath в реализации порта. Содержимое файла НЕ ДОЛЖНО попадать в логи, диагностику и снимок. Тест — `test/files/project_files_rules_test.dart`; спецификация — [`workspace-file-browser`](../../../../openspec/specs/workspace-file-browser/spec.md).

## Темы: `ThemeFile` и `ThemeLibrary`

Формат пользовательской темы `$CODELAB_HOME/themes/<имя>.json` общий для app и CLI. Слой разбирает файл чистой функцией и объявляет порт каталога; файлов не читает.

`ThemeFile.parse(fileName, text)` (или `parseBytes`) возвращает `ThemeLoaded(theme, warnings, unsetRoles)` либо `ThemeRejected(issue)`. Разбор **нестрогий**: предупреждения не отменяют тему, ошибки отменяют. «Строгость» решает потребитель: app применяет тему с предупреждениями, CLI считает любую проблему ошибкой.

Результат языконезависим: `ThemeIssue(code, line, column, key, value, hint)` — код (`ThemeIssueCode`), позиция (строка и колонка с 1, UTF-16) и аргументы, без английской строки. Текст строит клиент: app — по ARB, CLI — своими строками. Коды до `terminalColor` включительно — предупреждения (`isWarning`): `unknownKey`, `duplicateKey`, `terminalColor`; остальные отклоняют тему: `tooLarge`, `notUtf8`, `invalidJson`, `notAnObject`, `missingName`, `invalidName`, `nameMismatch`, `reservedName`, `invalidExtends`, `invalidValue`.

Форматные правила: размер не больше `themeFileMaxBytes` (64 КиБ); имя — `[a-z0-9-]{1,32}` (`isValidThemeName`) и совпадает с именем файла; имена `auto`, `dark`, `light`, `high-contrast`, `mono` зарезервированы за встроенными темами; `extends` — `light`, `dark` или `high-contrast` (`ThemeBase`); роли — закрытый набор `ThemeRole` (`colors.*` и `colors.code.*`); значения цвета — `ThemeColorValue`: `Rgb` (`#rrggbb`), `DefaultColor`, `AnsiColor`, `IndexedColor` (`256:<n>`). Терминальные цвета app не применяет и сообщает предупреждением `terminalColor`.

Реальный разбор файла с опечаткой в ключе и вторым файлом с неверным значением:

```text
loaded acme base=light accent=Rgb(0x3366ff)
warning: ThemeIssue(unknownKey 6:5 key=acent value=null hint=accent)
rejected: ThemeIssue(invalidValue 1:39 key=accent value=null hint=null)
```

Подсказка `hint` — ближайший ключ области на расстоянии Левенштейна не больше 2.

`ThemeLibrary` — порт каталога: `list()` → `List<ThemeEntry>`, `read(name)`, `import(...)` → `ThemeImportResult` (`ThemeImportImported`, `Replaced`, `Unchanged`, `NeedsReplace`, `Invalid`, `SourceChanged`, `Failed`). `ThemeEntry` несёт либо `text`, либо `ThemeReadError` (`tooLarge`, `notUtf8`, `unreadable`): сбой одного файла не ломает перечисление. Каталог, который нельзя перечислить, — `ThemeCatalogException(ThemeCatalogFailure)` (`notADirectory`, `unreadable`); пути и текст ОС в исключение не кладутся, потому что они попадают в журнал. Применять роли к виджетам слой не умеет и не должен: это дело app. Реализация `IoThemeLibrary` — в `codelab_client_io`; контракт проверяет `test/themes/theme_library_contract_test.dart` на `InMemoryThemeLibrary`. Спецификация — [`client-themes`](../../../../openspec/specs/client-themes/spec.md).

Сквозной разбор настроек клиента и агента: [настройки на клиенте](settings-on-client.md), [алгоритм настроек агента](../../codelab_agent_core/doc/algorithms/settings.md).
