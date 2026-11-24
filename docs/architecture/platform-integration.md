# Интеграция с платформой в CodeLab

Документ задаёт правила, по которым клиенты CodeLab (desktop, CLI) и Dart-агент работают с операционной системой: файлами, процессами, окружением, секретами, плагинами Flutter и нативными API.

Цели:

* изолировать API, зависящие от платформы;
* не допускать распространения `dart:io` и плагинов платформы по коду фич;
* сделать интеграцию с desktop тестируемой;
* сохранить переносимость между Windows, macOS и Linux;
* держать под контролем файловую систему, запуск процессов и хранение секретов;
* обеспечить единый жизненный цикл ресурсов платформы.

Общие правила — корневой `AGENTS.md` (§5, §6, §10, §11, §12, §13, §16), [`layers-and-dependencies.md`](layers-and-dependencies.md), [`technology-stack.md`](technology-stack.md), [`permissions.md`](permissions.md), [`concurrency.md`](concurrency.md), [`error-handling.md`](error-handling.md), [`observability.md`](observability.md), [`testing.md`](testing.md). Окружение исполнения агента — [`proposals/agent-core/04-execution-env.md`](proposals/agent-core/04-execution-env.md) (§4.5 — окружение процессов).

Термины:

* **Порт** (semantic port) — узкий интерфейс, через который application-слой просит у платформы одну возможность (`ProjectFolderPicker`, `TerminalProcessRunner`, `ExecutionEnv`) (§4, §79).
* **Адаптер платформы** (platform adapter) — реализация порта на `dart:io`, плагине Flutter или нативном API; единственное место, где эти API видны (§8).
* **Возможность** (capability) — то, что нужно приложению («выбрать папку»), в отличие от её реализации на конкретной ОС (§3).
* **Composition root** — место сборки зависимостей: `apps/codelab_desktop/lib/app/` (Cherrypick), `apps/codelab_cli/lib/src/composition_root.dart`, хост `apps/codelab_agent` (§62).
* **Рабочая папка** (working directory) — `cwd` сессии ACP; корень, которым ограничены пути и процессы агента (§16, §54).
* **Containment** — проверка, что путь или `cwd` не выходит за рабочую папку (§16, §71; корневой `AGENTS.md` §10).
* **`$CODELAB_HOME`** — каталог конфигурации и данных, общий для app, CLI и агента; по умолчанию `~/.codelab` (§12, §28).
* **Процесс-сирота** (orphan process) — дочерний процесс, переживший своего владельца (§23).

Где в коде. Клиент: порты файлов и процессов ACP `fs/*` и `terminal/*` — `TextFileReader`, `TextFileWriter` и лексическая проверка `resolveWithinWorkingDirectory` (`packages/dart/codelab_client_acp/lib/src/domain/fs_access.dart`), `TerminalProcessRunner`, `TerminalProcessHandle`, `TerminalProcessState` (`terminal_access.dart` того же каталога); их адаптеры на `dart:io` — `codelab_client_io`: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider`, `resolveCodelabHome` (`lib/src/platform/`), хранилища `JsonFileProfileStore` и `JsonFileRecentProjectsStore` с атомарной записью `writeBytesAtomically` (`lib/src/stores/`), дерево файлов проекта `IoProjectFiles` (`lib/src/files/`), транспорты `ioTransportResolver` (`lib/src/transport/`). Процесс внешнего агента по stdio запускает и закрывает `StdioAcpTransport` (`package:codelab_acp_transports/io.dart`). Desktop: адаптеры платформы — `apps/codelab_desktop/lib/core/platform/` (`ProjectFolderPicker`, `ThemeFilePicker`, `ExternalLinkOpener`, `LocalFolderOpener`, `OsDropRegion`, `LocalPathKindOf`, `SystemThemeAccentSource`, `AppMenuBridge`, `UserShellLauncher` и `PtyUserShellLauncher`, хранилища настроек `SharedPreferences*`), сборка — `createCodeLabRootScope` и `CodeLabRootLifecycle` (`lib/app/app_scope.dart`), выход из app — `AppExitHandler` (`lib/app/app_exit_handler.dart`); плагины — `file_selector`, `path_provider`, `shared_preferences`, `url_launcher`, `desktop_drop`, `system_theme`, `pty2`; macOS собран без песочницы (`macos/Runner/*.entitlements`: `com.apple.security.app-sandbox` = `false`). CLI: каталог `CodelabHome` и история с правами `0700`/`0600` (`apps/codelab_cli/lib/src/home.dart`), сигналы (`signals.dart`). Агент: порт `ExecutionEnv` с возможностями `DirectoryListing`, `BinaryFiles`, `PathResolver` (`packages/dart/codelab_agent_core/lib/src/env/execution_env.dart`), граница рабочей папки `BoundedEnv` (`bounded_env.dart`, по `realpath`), тестовая `MemoryExecutionEnv`; реализации на `dart:io` — `codelab_agent_io`: `LocalExecutionEnv` (`lib/src/env/`: shell `/bin/sh -c` или `cmd.exe /d /s /c`, окружение по `hostEnvironmentAllowlist`, завершение дерева процессов `terminateTree`, пути ядра POSIX ↔ пути ОС `toCorePath`/`toHostPath`), stdio-серверы MCP `StdioProcessTransport` (`lib/src/mcp/`), `codelabHomeOf`, `ConfigLoader` и `ConfigWatcher` (`lib/src/config/`), хранилище секретов `openSecretStore` с бэкендами `env` и `file` (`lib/src/secrets/`). Встроенного агента клиенту отдаёт `codelab_embedded` (настольный открыватель — `lib/io.dart`). Проверки `Platform.is*` и `Platform.operatingSystem` есть только в адаптерах, хостах и composition root: `codelab_agent_io`, `codelab_client_io` (`IoTerminalProcessRunner`), `codelab_setup/lib/src/io/`, `codelab_embedded/lib/src/io/` и сценарный открыватель `codelab_embedded/lib/src/testing/scripted_opener.dart`, `apps/codelab_agent`, `apps/codelab_cli/lib/src/` (`home.dart`, `signals.dart`, `serve_alias.dart`, `input/io_terminal.dart`), `apps/codelab_desktop/lib/core/platform/` (`PtyUserShellLauncher`, `build_info.dart`), `lib/app/app_scope.dart` desktop (§5). `main.dart` desktop читает только `Platform.environment`.

---

## 1. Основной принцип

Поведение, зависящее от платформы, — забота infrastructure.

Предпочтительная модель:

```text
Application / Feature
        │
        ▼
Platform abstraction
        ▲
        │
Desktop adapter
        │
        ▼
OS / Flutter plugin / dart:io
```

Код фичи НЕ ДОЛЖЕН напрямую зависеть от конкретного плагина платформы, если это не забота только presentation.

---

## 2. Поддерживаемые платформы

Desktop-приложение ДОЛЖНО сохранять возможность работы на поддерживаемых платформах проекта:

* Windows;
* macOS;
* Linux.

Новая зависимость или интеграция с платформой ДОЛЖНА быть проверена на совместимость со всеми обязательными платформами проекта.

Если возможность поддерживается не везде, это ДОЛЖНО быть выражено явно.

В коде терминал пользователя (`PtyUserShellLauncher`) проверен только на macOS; ветки Linux и Windows есть, но не проверены (D12 change `add-integrated-terminal`). Неподдержанную ОС порт выражает явно — `UserShellLauncher.isSupported`.

---

## 3. Возможность платформы

СЛЕДУЕТ различать:

```text
application capability
```

и:

```text
platform implementation
```

Например:

```text
OpenFile
```

— возможность приложения.

А:

```text
Windows file picker
macOS NSOpenPanel
Linux GTK picker
```

— детали реализации.

---

## 4. Абстракция платформы

Абстракция платформы ДОЛЖНА быть узкой и выражать смысл операции.

Предпочтительно (пример иллюстративный; реальный порт выбора папки — `ProjectFolderPicker` в `apps/codelab_desktop/lib/core/platform/project_folder_picker.dart`):

```dart
abstract interface class FilePicker {
  Future<String?> pickFile();
}
```

вместо:

```dart
abstract interface class PlatformService {
  Future<dynamic> execute(String action, Map<String, dynamic> args);
}
```

Обобщённый сервис платформы скрывает ответственность и ухудшает типобезопасность.

---

## 5. `Platform.is*`

Проверки:

```dart
Platform.isWindows
Platform.isMacOS
Platform.isLinux
```

МОЖНО использовать в:

* адаптерах infrastructure;
* bootstrap и composition;
* слое утилит, зависящих от платформы.

НЕ СЛЕДУЕТ использовать их непосредственно в:

* domain;
* переиспользуемом ядре ACP;
* BLoC;
* виджетах фич;

если поведение можно скрыть за абстракцией.

Обозначения клавиш (⌘ или Ctrl, ⌥ или Alt) — не поведение платформы, а соглашение её интерфейса.
Их выбирает только каталог сочетаний кита `CodeLabShortcut` (`packages/flutter/codelab_ui`) по
`defaultTargetPlatform` из `package:flutter/foundation.dart`, а не по `Platform.is*`: значение
подменяется в тестах (`debugDefaultTargetPlatformOverride`) и не требует `dart:io`. Код фичи
берёт готовую подпись из каталога и сам платформу для этого не проверяет (change
`add-app-keyboard-page`, D4).

В коде проверок `Platform.is*` в domain, Cubit и виджетах нет; полный список мест — абзац «Где в коде» выше. Виджеты фич передают `defaultTargetPlatform` в каталог (`compactFor`, `combosFor`) без собственного ветвления.

---

## 6. Условные импорты

Условные импорты (conditional imports) МОЖНО использовать, если реализация действительно различается между платформами.

Например (иллюстративные имена):

```text
platform_window.dart
platform_window_windows.dart
platform_window_macos.dart
platform_window_linux.dart
```

Это предпочтительнее множества проверок `if (Platform...)` во время выполнения в бизнес- и application-коде.

---

## 7. Плагины Flutter

Плагин Flutter СЛЕДУЕТ считать зависимостью infrastructure, если он даёт доступ к:

* файловой системе;
* нативному API окна;
* защищённому хранилищу;
* буферу обмена;
* уведомлениям;
* интеграции с процессами и системой.

API плагина НЕ ДОЛЖЕН автоматически становиться публичным API application-слоя.

---

## 8. Изоляция плагинов

Предпочтительная схема:

```text
Feature
   │
   ▼
App abstraction
   ▲
   │
Plugin adapter
   │
   ▼
Flutter plugin
```

Это позволяет:

* тестировать фичу без плагина;
* заменять плагин;
* изолировать различия платформ;
* уменьшать связанность.

В коде импорт части плагинов desktop ограничен одним файлом-адаптером правилами сторожа (`packages/dart/codelab_architecture_tests/test/support/rules.dart`): `pty2` — `user_shell_launcher.dart`, `system_theme` — `system_accent_source.dart`, `desktop_drop` — `os_drop_region.dart`, `file_selector` и `url_launcher` — адаптеры в `lib/core/platform/`.

### 8а. Нативное меню macOS и канал `codelab/app_menu`

Источник — change [`add-app-appearance-page`](../../openspec/changes/archive/2026-11-20-add-app-appearance-page/design.md), D15а; spec `app-settings` «Открытие настроек из меню macOS».

Главное меню macOS (`apps/codelab_desktop/macos/Runner/Base.lproj/MainMenu.xib`, переводы — `ru.lproj/MainMenu.strings`) обрабатывает `keyEquivalent` своих пунктов раньше Flutter. Поэтому:

* пункт меню с сочетанием, которое app обрабатывает и в Dart, ДОЛЖЕН иметь action; пункт без action молча «съедает» сочетание;
* action пункта, которому нужна логика app, передаёт команду в Dart по каналу `codelab/app_menu` (`AppDelegate`), а не выполняет её нативно. Сейчас канал несёт один метод — `openSettings` (пункт «Preferences…», ⌘,);
* в Dart канал слушает только мост `AppMenuBridge` (`lib/core/platform/app_menu_bridge.dart`). Мост переводит метод в вызов application (`NavigationCubit.openSettings(source: shortcut)`) и не содержит своей логики. Владелец моста — `CodeLabBootstrap`: `attach()` при старте, `dispose()` при закрытии, после чего поздний вызов ничего не делает. Неизвестный метод — `MissingPluginException`;
* проверок `Platform.isMacOS` для меню в Dart нет (§5): на других ОС канал просто не вызывается, сочетания обрабатывает `CallbackShortcuts`.

Новый пункт меню с логикой app добавляет метод в этот же канал, а не новый канал.

---

## 9. Файловая система

Файловая система — забота infrastructure.

Примитивы `File`, `Directory` и другие примитивы `dart:io` СЛЕДУЕТ использовать напрямую только в подходящем слое infrastructure.

НЕ СЛЕДУЕТ использовать их напрямую из виджета или domain.

---

## 10. Абстракция доступа к файлам

Если application-логика работает с файлами, СЛЕДУЕТ использовать абстракцию.

Например (иллюстративный порт; реальные — `TextFileReader` и `TextFileWriter` клиента, `FileSystem` в составе `ExecutionEnv` агента):

```dart
abstract interface class FileStore {
  Future<String> readText(String path);
  Future<void> writeText(String path, String content);
}
```

Конкретный API ДОЛЖЕН соответствовать реальному смыслу задачи.

В коде у клиента порты `TextFileReader`/`TextFileWriter` живут в web-безопасном `codelab_client_acp`, а адаптер `IoTextFileIo` — в `codelab_client_io`, общем для app и CLI; composition root передаёт его в `AcpClientApplication(textFileReader:, textFileWriter:)`. Агент работает с файлами только через `ExecutionEnv` (`agent-core-architecture` §4).

---

## 11. Работа с путями

Пути ДОЛЖНЫ обрабатываться с учётом платформы.

ЗАПРЕЩЕНО полагаться на:

* жёстко заданный разделитель `/`;
* синтаксис дисков, существующий только в Windows;
* пути, склеенные вручную из строк.

СЛЕДУЕТ использовать утверждённый в проекте механизм работы с путями.

В коде клиенты используют `package:path` (`p.join`, `p.normalize`). Ядро агента хранит пути в POSIX-форме независимо от ОС; на Windows `LocalExecutionEnv` и `StdioProcessTransport` переводят их в пути ОС и обратно (`toHostPath`, `toCorePath` в `codelab_agent_io/lib/src/env/host_path.dart`). Ручная склейка через `/` и `Platform.pathSeparator` встречается в `codelab_agent_io` (например, `config_link_containment.dart`, `skill_roots.dart`, `jsonl_session_store.dart`) — внутри адаптеров, с явной веткой Windows.

---

## 12. Каталоги приложения

Для данных, конфигурации и кэша приложения СЛЕДУЕТ использовать каталоги, принятые на платформе.

НЕ СЛЕДУЕТ жёстко задавать:

```text
C:\Users\...
/Users/...
/home/...
```

Приложение ДОЛЖНО получать правильные каталоги через абстракцию или плагин платформы.

В коде каталог журналов app — `getApplicationSupportDirectory()/logs` (`path_provider`, `apps/codelab_desktop/lib/main.dart`); настройки только app — домен `shared_preferences`. Общие данные app, CLI и агента лежат в `$CODELAB_HOME`: значение переменной `CODELAB_HOME` или `<HOME|USERPROFILE>/.codelab` (`resolveCodelabHome` в `codelab_client_io`, `CodelabHome.resolve` в CLI, `codelabHomeOf` в `codelab_agent_io`). Это не каталог, принятый на платформе (на macOS не `~/Library/Application Support`, на Windows не `%APPDATA%`), а один путь от домашней папки на всех ОС: так app, CLI и агент находят одни и те же файлы без плагина (§28).

---

## 13. Временные файлы

Временные файлы ДОЛЖНЫ:

* иметь владельца;
* удаляться после использования, если это возможно;
* не хранить секреты без необходимости;
* создаваться во временном каталоге, принятом в ОС.

В коде временный файл атомарной записи (§14) создаётся рядом с целевым, а не во временном каталоге ОС: `rename` атомарен только в пределах одной файловой системы; при сбое записи он удаляется (`writeBytesAtomically`). Временный каталог ОС — запасной каталог журналов, когда тест собирает scope без `main.dart` (`Directory.systemTemp`, `createCodeLabRootScope`).

---

## 14. Безопасная запись файлов

Для критичных данных СЛЕДУЕТ использовать безопасную стратегию записи.

Например:

```text
write temp
   ↓
flush
   ↓
atomic replace
```

если это нужно для защиты от частичной записи.

В коде так пишутся общие файлы `$CODELAB_HOME` (`writeJsonObject`, `writeBytesAtomically` в `codelab_client_io/lib/src/stores/json_file.dart`: уникальный временный файл рядом, `flush`, `rename`) и выгрузка CSV использования (`UsageCsvSaver`). Файлы рабочей папки пишутся на месте, без временного файла: у клиента — `IoTextFileIo.writeText` (`fs/write_text_file`), у агента — `LocalExecutionEnv.writeText` (с `flush`).

---

## 15. Разрушающие операции

Удаление, перезапись и рекурсивные операции с файловой системой могут быть чувствительны к безопасности.

Если действие инициировано AI-агентом, оно ДОЛЖНО проходить permission policy.

Подробнее:

`docs/architecture/permissions.md`

Политика разрешений здесь — политика агента. Для ACP-методов `fs/*` и `terminal/*` клиент собственного гейта одобрения не вводит, а вместо него ограничивает `path` и `cwd` рабочей папкой сессии (корневой `AGENTS.md` §10, исключение).

---

## 16. Символические ссылки

Для операций с файлами, чувствительных к безопасности, ДОЛЖНЫ учитываться символические ссылки.

Путь:

```text
workspace/file
```

может на деле указывать за пределы рабочей папки.

Слой разрешений и безопасности НЕ ДОЛЖЕН полагаться только на текстовый префикс пути.

В коде по реальным путям проверяют агент (`BoundedEnv`: корень и цель раскрываются `realpath` через `PathResolver`, для несуществующей цели — по самому глубокому существующему предку) и дерево файлов проекта app (`IoProjectFiles`: `resolveSymbolicLinks` корня и цели до открытия файла; остаточный риск — подмена ссылки между проверкой и открытием, TOCTOU). Клиентская проверка ACP `fs/*` и `terminal/*` — `resolveWithinWorkingDirectory` — только лексическая (`p.normalize` и сравнение префикса по сегментам) и ссылки не раскрывает: пакет `codelab_client_acp` без `dart:io`. Это расхождение кода с решением D3 change [`add-acp-fs-client-support`](../../openspec/changes/archive/2026-09-04-add-acp-fs-client-support/design.md) (канонический путь, отказ при выходе по symlink; в Risks — `resolveSymbolicLinksSync` и тесты symlink-escape) и со спецификацией `openspec/specs/acp-fs-client/spec.md` («после канонизации»). Doc-комментарий `resolveWithinWorkingDirectory` называет выход по ссылке принятым остаточным риском, но ни design, ни спецификация такого риска не принимают. Порт `LocalPathKindOf` app определяет вид брошенного пути, следуя по ссылкам (§37а).

---

## 17. Наблюдатели за файлами

Если используются наблюдатели за файловой системой (file watchers), у каждого ДОЛЖНЫ быть:

* владелец;
* жизненный цикл;
* очистка;
* обработка ошибок.

Наблюдатель НЕ ДОЛЖЕН переживать закрытие фичи или рабочего пространства без явной причины.

В коде наблюдатель один — `ConfigWatcher` агента (`codelab_agent_io/lib/src/config/config_watcher.dart`): `Directory.watch` на родителе каждого файла конфига, debounce 300 мс, при сбое потока — опрос; его создаёт `FileConfigSource`, вызывает `start`, а после `runtime.dispose()` — `close`.

---

## 18. Внешние процессы

Запуск внешнего процесса — забота infrastructure.

Например:

```text
agent process
shell command
helper executable
```

У каждого такого процесса ДОЛЖЕН быть явный владелец.

---

## 19. Абстракция процессов

Предпочтительно скрывать API процессов за абстракцией, если его использует application-логика.

Например (иллюстративный порт; реальные — `TerminalProcessRunner` клиента, `Shell.exec` в `ExecutionEnv` агента, `UserShellLauncher` desktop):

```dart
abstract interface class ProcessRunner {
  Future<ProcessResult> run(...);
}
```

Для транспорта ACP может существовать специализированный транспорт процесса вместо общего запускателя — `StdioAcpTransport`.

---

## 20. Владение процессом агента

Если AI-агент запускается как дочерний процесс, слой транспорта и infrastructure ДОЛЖЕН владеть:

* запуском процесса;
* stdin и stdout;
* stderr;
* кодом выхода;
* завершением;
* очисткой.

UI НЕ ДОЛЖЕН напрямую управлять `Process`.

В коде процессом внешнего stdio-агента владеет `StdioAcpTransport`: запуск, чтение stdout и stderr, закрытие с эскалацией EOF → `SIGTERM` → `SIGKILL`; транспорт создаёт `ioTransportResolver` по профилю, закрывает `AcpClientApplication` — при отключении, переподключении и `dispose` (при выходе из desktop — шагом `CodeLabRootLifecycle` с пределом `transportCloseTimeout`, 2 с).

---

## 21. `stdout` и `stderr`

Если ACP работает через stdio:

```text
stdout
    → ACP transport

stderr
    → diagnostics
```

если это соответствует контракту протокола.

НЕ СЛЕДУЕТ смешивать диагностику и поток протокола без явного кадрирования.

В коде `StdioAcpTransport` разбирает stdout как поток ACP, а каждую строку stderr публикует событием `AcpTransportEvent.diagnostic` с `source: 'stderr'`. Бинарь `codelab-agent serve --stdio` пишет журнал в stderr (и по `--log-file` в файл), stdout занят протоколом (§80).

---

## 22. Завершение процесса

СЛЕДУЕТ различать:

```text
graceful shutdown
terminate
force kill
```

Жизненный цикл приложения ДОЛЖЕН определять, когда используется каждый вариант.

В CodeLab: штатное завершение (graceful shutdown) — закрытие stdin (stdio-агент, MCP stdio) или `hangUp` (терминал пользователя); terminate — `SIGTERM`; принудительное (force kill) — `SIGKILL` по истечении срока ожидания владельца (2 с у `terminal/*`, у stdio-агента после `SIGTERM` и у `exec` агента; у терминала пользователя — 2 с при закрытии вкладки и 3 с при выходе из app; у stdio-серверов MCP — EOF → 2 с → `SIGTERM` дереву → 5 с → `SIGKILL` → ожидание кода выхода до 2 с, затем потомкам, пережившим корень, `SIGTERM` → 5 с → `SIGKILL`; `codelab_agent_io/lib/src/mcp/stdio_process_transport.dart`). Ожидание выхода процесса без предела ЗАПРЕЩЕНО (`concurrency.md` §46; change [`add-client-process-shutdown-on-exit`](../../openspec/changes/archive/2026-11-13-add-client-process-shutdown-on-exit/design.md), D3, D4).

---

## 23. Процессы-сироты

При закрытии приложения НЕ ДОЛЖНЫ оставаться дочерние процессы-сироты, если это не намеренное поведение продукта.

Процесс закрытия ДОЛЖЕН включать очистку ресурсов процессов.

Терминал пользователя (панель Terminal, change [`add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D4) закрывает свои shell при выходе из app явно: `SIGHUP`, затем принудительное завершение по таймауту. Страховка на случай краха или убийства app — сам PTY: при закрытии PTY-мастера ядро ОС шлёт `SIGHUP` сеансу shell. При штатном выходе страховка не срабатывает: `pty2` ждёт код выхода каждого shell блокирующим `waitpid` в отдельном isolate, Dart VM при остановке ждёт этот isolate, а shell ждёт закрытия мастера, который живёт вместе с процессом app. Поэтому закрытие при выходе ДОЛЖНО быть явным, без него app зависает (решение пользователя 2026-11-12; D4, D15 п. 9 change). Сиротами остаются только задания, которые пользователь намеренно отвязал (`nohup`, `disown`), — это намеренное поведение пользователя.

Остальные дочерние процессы клиента — ACP `terminal/*`, внешний stdio-агент, процессы `exec` и stdio-серверы MCP встроенного агента — закрываются тем же обработчиком выхода через `CodeLabRootLifecycle.dispose()`, параллельно с терминалом, с общим пределом 5 с (`concurrency.md` §45–§46; change [`add-client-process-shutdown-on-exit`](../../openspec/changes/archive/2026-11-13-add-client-process-shutdown-on-exit/design.md)). Опираться на EOF stdin при смерти app ЗАПРЕЩЕНО: `terminal/*` stdin не читает, команды `exec` и внуки обёрток (`npx`) его не видят. Остаточный риск — потомки `terminal/*` и stdio-агента: сигнал получает только корень (design.md change, Q2), и аварийное завершение app, при котором обработчик не вызывается.

Ещё один принятый риск того же change — MCP-сервер встроенного агента, игнорирующий EOF и `SIGTERM`. Закрытие встроенного агента начинается с `AcpAgentServer.shutdown`: он ждёт завершения ходов до 5 с, затем по очереди закрывает сессии, и каждая (`_Session.close()`) после простоя агента закрывает свои MCP-серверы по цепочке сроков §22; `runtime.dispose()` закрывает только оставшиеся сессии. Вместе это больше общего предела выхода 5 с (`AppExitHandler.exitTimeout`), и такой сервер может остаться сиротой (design.md change, таблица владельцев и Risks «Встроенный агент с зависшим ходом»; смягчение отложено — Q3).

В коде `exec` агента и stdio-серверы MCP завершают всё дерево процессов: `terminateTree` находит потомков по снимку таблицы процессов (`ps`), на Windows — `taskkill /T /F` (`codelab_agent_io/lib/src/env/process_tree.dart`).

---

## 24. Код выхода процесса

Код выхода относится к диагностике infrastructure.

Его можно преобразовать в отказ уровня application, например:

```text
agent process exited unexpectedly
```

UI НЕ ДОЛЖЕН сам анализировать числовые коды выхода.

Код выхода `dart:io` на POSIX для процесса, завершённого сигналом, отрицателен (`-15`, `-9`). Адаптер, который отдаёт статус выхода наружу, переводит его сам. Для ACP `terminal/*` это `exitCode: null` и имя сигнала: схема `TerminalExitStatus` требует `exitCode` ≥ 0. Признак «какой сигнал посылали» статусом выхода не считается: процесс мог выйти сам или обработать `SIGTERM` (change [`add-client-process-shutdown-on-exit`](../../openspec/changes/archive/2026-11-13-add-client-process-shutdown-on-exit/design.md), D14).

В коде перевод для `terminal/*` делает `terminalStateFromExitCode` в `IoTerminalProcessRunner` (имя сигнала, `SIG<n>` для непортируемых номеров); `LocalExecutionEnv` агента отдаёт `ExecResult(exitCode: null, signal: 'SIG<n>')` с номером, а не именем сигнала, и без ветки по платформе: на Windows отрицательный код выхода (NTSTATUS) тоже станет `SIG<n>`, тогда как клиент переводит в сигнал только на POSIX (D14).

---

## 25. Защищённое хранилище

Секреты ДОЛЖНЫ храниться через абстракцию защищённого хранилища.

К секретам относятся:

* токены авторизации;
* API-ключи;
* учётные данные;
* приватные токены.

Обычное локальное хранилище настроек НЕ СЛЕДУЕТ использовать для чувствительных данных.

В коде хранилища ОС (keychain, Credential Manager, libsecret) нет — ни у app, ни у агента. Секреты хранит хранилище агента `openSecretStore` (`codelab_agent_io`): `secrets.backend` `auto` и `env` — переменные `CODELAB_SECRET_*`, `file` — `$CODELAB_HOME/secrets.yaml` открытым текстом с правами `0600` (на Windows `file` недоступен); `shared_preferences` для секретов не используется (§80).

---

## 26. Граница защищённого хранилища

Application-слой ДОЛЖЕН работать со смысловым API.

Например (иллюстративный порт; реальный порт клиента — `ProfileSecrets` в `codelab_client_core/lib/src/connection/profile_secrets.dart`):

```dart
abstract interface class CredentialStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> deleteToken();
}
```

а не напрямую с API конкретного плагина.

В коде `ProfileSecrets` app открывает `openProfileSecrets` в composition root (`apps/codelab_desktop/lib/app/client_profile_secrets.dart`) поверх `ClientSecretAccess` из `codelab_setup/io.dart`; Cubit и виджеты получают готовый порт.

---

## 27. Жизненный цикл секретов

Секреты ДОЛЖНЫ:

* находиться в памяти минимально долго;
* не журналироваться;
* не попадать в сообщения исключений;
* не сохраняться в отладочный дамп без маскирования.

---

## 28. Локальное хранилище настроек

В отличие от защищённого хранилища (§25–27), которое предназначено только
для секретов, обычные нечувствительные локальные данные (например, недавно
открытые проекты, настройки интерфейса), которые переживают перезапуск
приложения, СЛЕДУЕТ хранить через отдельный, столь же узкий порт уровня
application:

```dart
abstract interface class RecentProjectsStore {
  Future<List<RecentProject>> load();
  Future<void> record(String path);
}
```

Правила:

* Application-слой работает со смысловым API (как в §26), а не напрямую с
  `SharedPreferences` или аналогичным плагином.
* Данные одной логической темы (например, недавних проектов) СЛЕДУЕТ хранить
  как один сериализованный документ под одним ключом, а не как россыпь
  отдельных ключей — так проще атомарная замена и будущее версионирование
  формата.
* Локальное хранилище настроек НЕ ДОЛЖНО использоваться для секретов и токенов
  (см. §25) и не заменяет структурное хранилище для больших или реляционных
  данных (см. `docs/architecture/technology-stack.md` §12.2).
* Сбои чтения и записи (например, повреждённое или недоступное хранилище)
  ДОЛЖНЫ деградировать некритично — например, «недавние проекты недоступны в
  этой сессии», а не блокировать работу приложения.
* Где лежат данные, решает тот, кто ими пользуется. Настройки только app
  (раскладка, язык, оформление, снимок рабочего места) — `shared_preferences`
  в `apps/codelab_desktop/lib/core/platform/`. Данные, общие с `codelab`
  (CLI), — JSON-файлы в `$CODELAB_HOME` через хранилища `codelab_client_io`:
  домен `shared_preferences` привязан к идентификатору бандла app, CLI его не
  видит, а при смене идентификатора (задача 9.4 дорожной карты) данные
  пропали бы. Так хранятся профили подключения (`profiles.json`) и недавние
  проекты (`recent_projects.json`).
* Общий файл пишут несколько процессов. Запись — через временный файл и
  атомарное переименование (файл не портится), нечитаемый файл или файл
  незнакомой версии не перезаписывается. Порт не обещает межпроцессной
  сериализации «прочитать — изменить — записать»; если потеря одной записи
  при одновременной записи недопустима для темы, это решается отдельно.

Порт `RecentProjectsStore` появился в `openspec/changes/archive/2026-09-04-add-open-project-picker/design.md`
(Decision 4) с реализацией на `shared_preferences`. Change
`share-recent-projects-store` (design.md, D1–D4) перенёс недавние проекты в
общий с CLI файл `$CODELAB_HOME/recent_projects.json`
(`JsonFileRecentProjectsStore`). Перенос прежнего ключа есть только в
предвыпускных сборках app и удаляется до первого `stable` (D9).

В коде порт `RecentProjectsStore` — `codelab_client_core/lib/src/stores/stores.dart`; перенос прежнего ключа — `MigratingRecentProjectsStore` (`apps/codelab_desktop/lib/core/platform/recent_projects_migration.dart`).

---

## 29. Буфер обмена

Буфер обмена — возможность платформы.

Если буфер обмена нужен для обычного действия пользователя в UI, прямой API Flutter МОЖНО использовать на границе presentation.

Если доступ к буферу обмена инициирует AI-агент или он затрагивает безопасность, СЛЕДУЕТ применять политику разрешений и безопасности.

В коде буфер обмена используется только по клику пользователя, напрямую через `Clipboard.setData` в presentation (например, `about_section.dart`, `project_files_pane.dart`, `protocol_pane.dart` app и кнопка копирования `CodeLabCodeBlock` в `packages/flutter/codelab_ui/lib/src/rendering/codelab_code_block.dart`); агент к буферу обмена доступа не имеет.

---

## 30. Уведомления

Системные уведомления — забота presentation и платформы.

Application-слой МОЖЕТ выражать намерение:

```text
NotifyUser
```

но конкретный плагин уведомлений ДОЛЖЕН оставаться адаптером платформы.

В коде системных уведомлений нет.

---

## 31. Управление окнами

Управление окнами может включать:

* сворачивание;
* разворачивание;
* восстановление;
* закрытие;
* режим «поверх всех окон»;
* собственную строку заголовка.

Эти действия ДОЛЖНЫ быть локализованы в слое app и платформы.

Domain фичи НЕ ДОЛЖЕН зависеть от API окна.

В коде плагина управления окнами нет; окно и его строку заголовка ведёт раннер платформы (`MainFlutterWindow.swift` на macOS).

---

## 32. Перехват закрытия

Desktop-приложение МОЖЕТ перехватывать закрытие из-за:

* несохранённых данных;
* активной сессии ACP;
* работающего процесса агента.

Процесс закрытия ДОЛЖЕН управляться application, а не случайным `dispose`.

В коде запрос выхода от ОС принимает `AppExitHandler` (через `AppLifecycleListener` в `CodeLabBootstrap`) и закрывает `CodeLabRootLifecycle` с пределом 5 с; отмены выхода и вопроса пользователю нет (`concurrency.md` §45–§46).

---

## 33. Сохранение состояния окна

Если сохраняются:

* размер;
* положение;
* развёрнутое состояние;

это забота сохранения на стороне presentation и платформы.

Такое состояние НЕ ДОЛЖНО смешиваться с состоянием сессии ACP.

В коде размер и положение окна app не сохраняет; раскладка дока и снимок рабочего места — отдельные хранилища `shared_preferences` (`SharedPreferencesDockLayoutStore`, `shared_preferences_workspace_snapshot_store.dart`).

---

## 34. Несколько окон

Если в будущем появится несколько окон, зависимости уровня окна ДОЛЖНЫ иметь правильную область жизни (scope).

ЗАПРЕЩЕНО заранее делать все сервисы глобальными синглтонами, если им, возможно, нужна область жизни окна.

---

## 35. Открытие внешнего URL

Открытие внешнего URL — действие платформы.

Если его инициирует пользователь из UI, это забота presentation и платформы.

Если его инициирует агент, может потребоваться разрешение.

В коде URL открывает порт `ExternalLinkOpener` (`url_launcher`) только по клику пользователя; можно ли открыть ссылку, решает чистая функция `isOpenableLink` (`lib/core/platform/link_policy.dart`); она проверяется трижды — в `CodeLabMarkdownScope`, в `CodeLabShellCubit.openExternalLink` и в самом адаптере `ExternalLinkOpener.open`.

---

## 36. Глубокие ссылки

Если приложение поддерживает глубокие ссылки (deep links), разбор ДОЛЖЕН быть отделён от навигации.

Например:

```text
OS deep link
    ↓
parse/validate
    ↓
application intent
    ↓
navigation
```

В коде глубоких ссылок нет.

---

## 37. Перетаскивание

Перетаскивание (drag and drop) — взаимодействие presentation и платформы.

Брошенные файлы СЛЕДУЕТ преобразовывать в нормализованную модель или путь application до дальнейшей обработки.

### 37а. Перетаскивание из ОС в app: `OsDropRegion` и `LocalPathKindOf`

Источник — change [`add-empty-project-screen`](../../openspec/changes/archive/2026-11-22-add-empty-project-screen/design.md), D3, D4; spec `agent-workbench-ui` «Открытие папки перетаскиванием», spec `workspace-architecture` «Плагин перетаскивания из ОС только в адаптере платформы».

Flutter не отдаёт на десктопе события перетаскивания внешних файлов: `DragTarget` и `Draggable` работают только внутри дерева виджетов. Приём из Finder, Проводника и файлового менеджера Linux идёт через плагин `desktop_drop` по схеме §8:

* **адаптер** — `apps/codelab_desktop/lib/core/platform/os_drop_region.dart`, виджет `OsDropRegion({child, onEntered, onExited, onDropped})`. Это единственный файл app, где разрешён `package:desktop_drop/` (правило сторожа в `codelab_architecture_tests/test/support/rules.dart`). Типы плагина за адаптер не выходят. `onDropped` получает `List<String?>`: путь элемента или `null`, если у элемента нет локального пути. Других решений в адаптере нет;
* **порт вида пути** — `apps/codelab_desktop/lib/core/platform/local_path_kind.dart`: `LocalPathKind { directory, file, missing, other }`, `typedef LocalPathKindOf`, реализация `ioLocalPathKind` (`FileSystemEntity.type`, по ссылкам). Ошибку проверки порт возвращает как `other`, а не бросает. Порт живёт в app, а не в `codelab_client_io`: второго потребителя нет (§13 корневого `AGENTS.md`);
* **решение** «можно ли открыть брошенное» принимает application — `SettingsCubit.openDroppedPaths`, а не виджет и не адаптер. Путь — недоверенный вход. Отказ хранится типом (`ProjectDropRejection`), текст строит presentation. Поздний результат асинхронной проверки отбрасывается, если пользователь успел выбрать проект иначе или Cubit закрыт (`concurrency.md`);
* `codelab_ui` от плагина не зависит: организм только рисует состояние зоны;
* путь не канонизируется, как и путь из `file_selector` (§38). Containment обеспечивают агент (`BoundedEnv`, realpath) и клиентская проверка `fs/*`/`terminal/*` (`permissions.md`).

Ограничения платформ, которые документируются, а не обходятся:

* **macOS** — app собран без песочницы (`com.apple.security.app-sandbox` = `false`), поэтому брошенный путь доступен и процессу агента. С песочницей (P-13) брошенный URL дал бы только временный security-scoped доступ процессу app, а не дочернему процессу агента; включение песочницы пересматривает это решение вместе с `file_selector` (§44);
* **Windows** — UIPI: в app, запущенный с повышенными правами, перетаскивание из Проводника не доходит. Кнопка «Open folder…» и Cmd/Ctrl+O остаются (§45);
* **Linux** — приём идёт через GTK (`text/uri-list`), X11 и Wayland — средствами GTK; поведение файловых менеджеров различается (§46).

Следующий потребитель — вложения композера (D-12, `proposals/dart-agent-and-clients/12-3-desktop-display.md` §12.3.6) — переиспользует тот же адаптер, а не добавляет второй.

---

## 38. Нативные диалоги

Нативный диалог выбора файла или системный диалог — деталь реализации.

Application-слой ДОЛЖЕН получать типизированный результат, а не зависеть от API диалога.

В коде диалоги `file_selector` закрыты портами `ProjectFolderPicker`, `ThemeFilePicker`, `ProtocolExportSaver`, `UsageCsvSaver` (`apps/codelab_desktop/lib/core/platform/`); Cubit получает путь или `null` (`pickFolder`) либо типизированный результат сохранения (`ProtocolExportSaveResult`, `UsageCsvSaveResult`).

---

## 39. Ошибки платформы

Исключения, зависящие от платформы, СЛЕДУЕТ преобразовывать в типизированные отказы infrastructure или application.

Например (иллюстративные имена отказов):

```text
PlatformException
    ↓
SecureStorageFailure
```

или:

```text
FileSystemException
    ↓
FileAccessFailure
```

UI НЕ ДОЛЖЕН показывать сырое `PlatformException.toString()`.

В коде `FileSystemException` клиента становится `FsNotFoundFailure` или `FsIoFailure` (`IoTextFileIo`), сбой запуска — `TerminalStartFailure` (`IoTerminalProcessRunner`), ошибки дерева проекта — `ProjectFilesFailure` (`IoProjectFiles`); у агента ожидаемые сбои — значения `FileError` и `ExecError` (ENV-1), недоступное хранилище секретов — `SecretStoreUnavailableException`. Общие правила — [`error-handling.md`](error-handling.md).

---

## 40. Неподдерживаемая возможность платформы

Если возможность недоступна на конкретной платформе, это ДОЛЖНО быть явным состоянием или ошибкой.

НЕ СЛЕДУЕТ делать тихий no-op для критичной операции.

В коде так сделаны терминал пользователя (`UserShellLauncher.isSupported`) и бэкенд секретов `file` на Windows (`SecretStoreUnavailableException` с причиной, а не молчаливая подмена).

---

## 41. Определение возможностей

Предпочтительнее проверять возможность:

```text
supportsTray
supportsSecureStorage
supportsWindowControl
```

чем проверять имя ОС прямо в коде фичи.

---

## 42. Фасад возможностей

Для сложных интеграций с desktop может пригодиться фасад (пример иллюстративный, в коде такого фасада нет):

```dart
abstract interface class DesktopCapabilities {
  bool get supportsTray;
  bool get supportsNotifications;
}
```

Но НЕ СЛЕДУЕТ создавать гигантский фасад для всех API платформы.

---

## 43. Конфигурация

Конфигурация, зависящая от платформы, ДОЛЖНА быть локализована.

Например:

* entitlements;
* plist;
* manifest;
* настройки desktop-раннера.

Такие изменения СЛЕДУЕТ документировать рядом с соответствующей возможностью.

---

## 44. Разрешения macOS

macOS может требовать:

* entitlements;
* разрешений песочницы;
* запросов к пользователю.

Политика безопасности приложения НЕ ДОЛЖНА путать разрешение уровня ОС и разрешение пользователя в ACP.

Это разные слои.

В коде песочница выключена в обеих сборках (`DebugProfile.entitlements` и `Release.entitlements`: `com.apple.security.app-sandbox` = `false`); отладочная сборка дополнительно получает `com.apple.security.cs.allow-jit` и `com.apple.security.network.server`.

---

## 45. Особенности Windows

Поведение, специфичное для Windows, может включать:

* семантику создания процессов;
* нечувствительность путей к регистру;
* расширения исполняемых файлов;
* реестр;
* Credential Manager.

Такой код ДОЛЖЕН быть локализован.

В коде ветки Windows локализованы в адаптерах: `cmd.exe /d /s /c` и `taskkill /T /F` (`LocalExecutionEnv`, `terminateTree`), пути с буквой диска (`toCorePath`/`toHostPath`), нет `SIGTERM` (`apps/codelab_agent/lib/src/serve/signals.dart`, `apps/codelab_cli/lib/src/signals.dart`), нет `chmod` (`apps/codelab_cli/lib/src/home.dart`), бэкенд секретов `file` недоступен. Реестр и Credential Manager не используются.

---

## 46. Особенности Linux

Окружения рабочего стола Linux могут различаться:

* бэкендом уведомлений;
* хранилищем ключей (keyring);
* файловыми диалогами;
* поведением оконного менеджера.

НЕ СЛЕДУЕТ без необходимости предполагать единое окружение рабочего стола Linux.

---

## 47. Кроссплатформенный инвариант

Бизнес- и application-поведение ДОЛЖНО быть максимально одинаковым на всех платформах.

Различия платформ ДОЛЖНЫ влиять только там, где возможность действительно различается.

---

## 48. Ветвление по платформе в тестах

Код, зависящий от платформы, СЛЕДУЕТ тестировать отдельно.

Чистые application-тесты НЕ ДОЛЖНЫ зависеть от ОС раннера CI.

В коде адаптеры принимают платформу швом теста, а не читают её скрыто: `platform` вместо `Platform.operatingSystem` (`openSecretStore`, `ConfigLoader`, `FileSecretStore`), `windows:` у `toCorePath`/`toHostPath`, `isWindows:` у `chooseUserShell`.

---

## 49. Двойники адаптеров платформы

В тестах СЛЕДУЕТ использовать двойники (fakes):

```text
FakeFileStore
FakeCredentialStore
FakeWindowController
FakeProcessRunner
```

Это позволяет тестировать application-логику без настоящих вызовов ОС.

Имена выше иллюстративные. В коде это, например, `FakeTerminalProcessRunner`, `FakeUserShellLauncher`, `FakeExternalLinkOpener`, `FakeLocalFolderOpener`, `FakeThemeFilePicker`, `FakeProfileSecrets`, `FakeProfileStore` и `MemoryExecutionEnv` ядра агента.

---

## 50. Интеграционные тесты

Настоящие интеграции с платформой СЛЕДУЕТ проверять интеграционными тестами там, где это оправдано.

Особенно:

* доступ к файлам;
* защищённое хранилище;
* запуск процессов;
* API окон desktop.

---

## 51. Разрешения и API платформы

Если действие платформы инициировано AI-агентом, архитектура ДОЛЖНА разделять:

```text
agent intent
    ↓
permission policy
    ↓
approved application operation
    ↓
platform adapter
```

Адаптер платформы НЕ ДОЛЖЕН сам решать, разрешено ли действие.

Исключение — ACP-методы `fs/*` и `terminal/*`: шаг политики разрешений принадлежит агенту, клиент своего гейта одобрения не вводит и вместо него проверяет containment рабочей папкой до вызова адаптера (корневой `AGENTS.md` §10).

---

## 52. Выполнение shell-команд

Выполнение shell-команд — возможность высокого риска.

Если оно поддерживается, СЛЕДУЕТ:

* централизовать выполнение;
* применять политику разрешений;
* журналировать метаданные без секретов;
* ограничивать время жизни процесса;
* правильно обрабатывать отмену.

НЕ СЛЕДУЕТ выполнять shell-команду напрямую из BLoC или виджета.

**Исключение: терминал пользователя.** Интерактивный shell панели Terminal десктопа (D-28; change [`add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D8) — действие пользователя, а не агента. Политика разрешений к нему не применяется (`permissions.md` §2, «Терминал пользователя — не действие агента»), рабочая папка его не ограничивает. Остальные требования раздела действуют: запуск централизован в одном порту (`UserShellLauncher`, `lib/core/platform/` app), журнал содержит только метаданные (без ввода, вывода, аргументов и окружения), время жизни процессов ограничено вкладкой и запуском app.

В коде команды агента выполняет только `ExecutionEnv.exec` (`LocalExecutionEnv` или ACP `terminal/*` клиента) после политики разрешений агента, с таймаутом и отменой; клиентский `IoTerminalProcessRunner` запускает команду без shell (`Process.start(command, args)`).

---

## 53. Переменные окружения

Чувствительные переменные окружения НЕ ДОЛЖНЫ попадать в журналы.

При запуске дочернего процесса СЛЕДУЕТ передавать только нужные значения окружения.

НЕ СЛЕДУЕТ автоматически наследовать всё окружение, если это создаёт риск безопасности и продукт этого не требует.

**Исключение: терминал пользователя.** Shell панели Terminal получает окружение процесса app целиком плюс `TERM=xterm-256color` и `COLORTERM=truecolor` и запускается как login shell (`$SHELL -l`) (решение пользователя Q9, change [`add-integrated-terminal`](../../openspec/changes/archive/2026-11-22-add-integrated-terminal/design.md), D5). Продукт этого требует: это собственный shell пользователя, урезанное окружение сломало бы его инструменты, а app из Finder (macOS) получает минимальное окружение, и `PATH` восстанавливает login shell. Окружение по-прежнему не журналируется (§65).

В коде у агента окружение собирается по списку: `exec` (`LocalExecutionEnv`) и stdio-серверы MCP (`StdioProcessTransport`) получают только `hostEnvironmentAllowlist` (`PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL`) плюс явные переменные, с `includeParentEnvironment: false` (`agent-core/04-execution-env.md` §4.5); `exec` получает ещё фиксированные `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`, у MCP их нет. У клиента иначе: `IoTerminalProcessRunner` (ACP `terminal/*`) и `StdioAcpTransport` (внешний stdio-агент) наследуют окружение процесса клиента целиком и добавляют переменные запроса или профиля (`includeParentEnvironment` по умолчанию).

---

## 54. Рабочая папка

Рабочая папка процесса ДОЛЖНА задаваться явно.

НЕ СЛЕДУЕТ полагаться на текущую папку процесса как на неявное рабочее пространство.

В коде app без выбранного проекта `cwd` не подставляет — ни папку процесса, ни домашнюю (`SettingsCubit.projectDirectory`). CLI по умолчанию берёт папку процесса, если `--cwd` не задан (`apps/codelab_cli/lib/src/run.dart`), — обычное соглашение терминальных программ. Бинарь `codelab-agent` читает слой конфигурации проекта от папки процесса (`apps/codelab_agent/lib/src/run.dart`, `agent_host.dart`), а корень сессии получает из `session/new` и ограничивает им инструменты через `BoundedEnv`.

---

## 55. Поиск исполняемого файла

Путь к исполняемому файлу СЛЕДУЕТ разрешать предсказуемо.

НЕ СЛЕДУЕТ вслепую полагаться на `PATH` при запуске процессов, чувствительных к безопасности, если нужна более строгая политика.

В коде профиль stdio хранит путь к агенту так, как его ввёл пользователь, без проверки и без перевода в абсолютный; app, запущенное из меню ОС, не видит `PATH` оболочки, поэтому относительное имя бинаря может не найтись (§80); команды ACP `terminal/*` и stdio-серверов MCP ищутся по `PATH` средствами `Process.start` (MCP — с `runInShell: false`).

---

## 56. Доверие к внешнему исполняемому файлу

Если приложение запускает внешний бинарь агента, СЛЕДУЕТ определить:

* откуда он берётся;
* кто его выбрал;
* нужно ли проверять путь;
* какова модель доверия.

Это вопрос безопасности, а не только деталь транспорта.

---

## 57. Ресурсы приложения

Встроенные ресурсы ДОЛЖНЫ использовать механизм ресурсов, утверждённый во Flutter.

НЕ СЛЕДУЕТ обращаться в рабочей сборке к путям относительно дерева исходников.

---

## 58. Файлы рабочего пространства

Файлы рабочего пространства и проекта отличаются от внутренних файлов приложения.

Политика безопасности ДОЛЖНА различать:

```text
app config
app cache
workspace data
arbitrary filesystem
```

если этого требует поведение продукта.

В коде агент защищает свои файлы конфигурации отдельно от рабочей папки (`AgentConfigPaths` в `codelab_agent_core/lib/src/permissions/agent_config_paths.dart`, его сборка `agentConfigPathsFor` в `codelab_agent_io/lib/src/config/agent_config_paths.dart`; сравнение без учёта регистра на macOS и Windows), а корни навыков вне рабочей папки открывает только для чтения (`BoundedEnv`, `readOnlyRoots`).

---

## 59. Резервное копирование и восстановление

Если приложение пишет важные локальные данные, СЛЕДУЕТ определить:

* атомарность;
* стратегию резервного копирования;
* обработку повреждений;
* миграцию.

Это относится к архитектуре хранения, если она появится.

---

## 60. Имена адаптеров платформы

Адаптеры СЛЕДУЕТ называть по ответственности.

Хорошо (иллюстративные имена):

```text
WindowsWindowController
SecureCredentialStore
StdioAgentTransport
```

Плохо:

```text
PlatformHelper
SystemManager
NativeUtils
```

Реальные имена в коде: `StdioAcpTransport`, `IoTerminalProcessRunner`, `PtyUserShellLauncher`, `SystemThemeAccentSource`, `JsonFileRecentProjectsStore`.

---

## 61. Не создавать `PlatformService`

Обобщённый `PlatformService` с десятками несвязанных методов обычно нарушает принцип единственной ответственности (SRP).

Лучше несколько узких портов и адаптеров.

---

## 62. Внедрение зависимостей

Конкретные адаптеры платформы создаются в composition root через Cherrypick.

Например (иллюстративные пары «порт → адаптер»):

```text
WindowController
    → FluentWindowController

CredentialStore
    → NativeCredentialStore
```

Код application зависит от абстракции.

В коде модули Cherrypick собирает `createCodeLabRootScope` (`apps/codelab_desktop/lib/app/app_scope.dart`); адаптеры по умолчанию подставляются там же и подменяются в тестах параметрами (`createCodeLabRootScope(userShellLauncher:, externalLinkOpener:, themeFilePicker:, …)`). CLI и бинарь агента собирают зависимости вручную, без Cherrypick.

---

## 63. Область жизни ресурсов платформы

У ресурсов платформы ДОЛЖЕН быть подходящий жизненный цикл:

```text
application-scoped
workspace-scoped
session-scoped
window-scoped
operation-scoped
```

НЕ СЛЕДУЕТ по умолчанию делать все адаптеры платформы синглтонами.

---

## 64. Hot restart и отладка

Жизненный цикл Flutter при разработке может отличаться от рабочей сборки.

НЕ СЛЕДУЕТ строить корректность на допущениях о hot reload и hot restart.

Процесс агента и подписки ДОЛЖНЫ правильно переживать жизненный цикл разработки либо явно перезапускаться.

---

## 65. Наблюдаемость

Интеграция с платформой ДОЛЖНА журналировать:

* тип операции;
* успех или отказ;
* относящиеся к операции корреляционные идентификаторы;
* недоступность возможности платформы.

Журналировать чувствительный payload ЗАПРЕЩЕНО.

Подробнее — [`observability.md`](observability.md).

---

## 66. Производительность

Ввод-вывод платформы НЕ ДОЛЖЕН блокировать отрисовку.

Большие обходы файловой системы, разбор вывода процессов и хеширование ДОЛЖНЫ быть вынесены с пути, критичного для отрисовки.

В коде известное исключение — `pty2`: адаптер терминала пользователя пока вызывает его на UI isolate, перенос в фоновый isolate отложен до после 1.0 (`technology-stack.md` §20д).

---

## 67. Большие операции с файловой системой

Для больших обходов каталогов СЛЕДУЕТ рассмотреть:

* потоковую обработку;
* пакетную обработку;
* isolate;
* отмену;
* прогресс.

Загружать всё дерево файловой системы в память без необходимости ЗАПРЕЩЕНО.

---

## 68. Кодировка файлов

Операции с текстовыми файлами ДОЛЖНЫ явно учитывать кодировку, если это важно.

НЕ СЛЕДУЕТ считать произвольный внешний файл UTF-8, если смысл продукта требует иного.

В коде оба пути читают UTF-8: клиент — `File.readAsString` (`IoTextFileIo`; не-UTF-8 даёт `FsIoFailure`), агент — строгим декодированием (`LocalExecutionEnv.readText`; не-UTF-8 даёт `FileError(notText)`). Вывод процессов декодируется как UTF-8 с `allowMalformed: true` — и у клиента (`IoTerminalProcessRunner.output`), и у `exec` агента.

---

## 69. Переводы строк

В Windows, macOS и Linux могут быть разные соглашения о переводах строк.

НЕ СЛЕДУЕТ нормализовать переводы строк без требования продукта.

В коде агент сохраняет переводы строк при чтении диапазона (`readText(line:, limit:)` — строки вместе с их окончаниями). Клиентский `IoTextFileIo.readText` с `line` или `limit` читает строки через `readAsLines` и склеивает их `\n`: `\r\n` становится `\n`, завершающий перевод строки теряется. Без `line` и `limit` файл возвращается как есть.

---

## 70. Чувствительность к регистру

Чувствительность файловой системы к регистру различается между платформами.

Логика идентичности путей ДОЛЖНА учитывать это, если она влияет на корректность или безопасность.

В коде регистр учитывает защита файлов конфигурации агента (`caseInsensitive` на macOS и Windows, `agent_config_paths.dart`); проверки рабочей папки (`BoundedEnv`, `resolveWithinWorkingDirectory`) сравнивают пути с учётом регистра.

---

## 71. Сравнение путей

Для сравнения путей, чувствительного к безопасности, ЗАПРЕЩЕНО использовать простое:

```dart
path.startsWith(root)
```

без нормализации и канонизации.

В коде нормализацию делают все проверки рабочей папки и сравнивают по границе сегмента; канонизацию по `realpath` — `BoundedEnv` и `IoProjectFiles`, а клиентский `resolveWithinWorkingDirectory` — только нормализацию, вопреки D3 `add-acp-fs-client-support` и спецификации `acp-fs-client` (§16).

---

## 72. Сетевая граница

Если интеграция с desktop включает сетевой доступ вне транспорта ACP, он ДОЛЖЕН быть отдельной заботой infrastructure.

НЕ СЛЕДУЕТ прятать сетевой запрос внутри адаптера платформы, если это не возможность, зависящая от платформы.

---

## 73. Нативный FFI

Если используется FFI, его СЛЕДУЕТ изолировать в отдельном адаптере или пакете.

Код application НЕ ДОЛЖЕН напрямую работать с указателями и нативным жизненным циклом.

В коде собственного FFI нет; нативный PTY приходит плагином `pty2` и виден только адаптеру `PtyUserShellLauncher` за портом `UserShellLauncher` (правило сторожа).

---

## 74. Жизненный цикл FFI

Нативные ресурсы ДОЛЖНЫ иметь явную очистку.

СЛЕДУЕТ документировать владение:

```text
allocate
use
dispose
```

---

## 75. Канал платформы

Если используется собственный канал платформы (platform channel), его API ДОЛЖЕН быть типизированным и узким.

НЕ СЛЕДУЕТ делать обобщённый канал:

```text
invokeMethod("doAnything", map)
```

если можно определить конкретный контракт.

В коде собственных каналов два. В рабочей сборке — только `codelab/app_menu` с единственным методом `openSettings` (§8а). В отладочной сборке macOS есть ещё `codelab/e2e_window` с методом `setContentSize` для e2e-тестов (`MainFlutterWindow.swift`, `#if DEBUG`; `integration_test/flutter_test_config.dart`); в release его нет.

---

## 76. Нормализация ошибок

Слой платформы ДОЛЖЕН приводить ошибки конкретной реализации к понятным типизированным отказам.

Это позволяет application-слою оставаться кроссплатформенным.

---

## 77. Контрольный список перед интеграцией с платформой

Перед добавлением функциональности, зависящей от платформы, агент ОБЯЗАН определить:

1. Это забота presentation или infrastructure?
2. Нужна ли абстракция?
3. Поддерживается ли возможность на всех целевых платформах?
4. Как выглядит поведение при отсутствии поддержки?
5. Нужна ли политика разрешений?
6. Кто владеет жизненным циклом ресурса?
7. Нужны ли очистка и `dispose`?
8. Может ли операция пережить владельца?
9. Какие секреты и данные участвуют?
10. Какие тесты нужны?
11. Нужен ли ADR?
12. Не протекает ли API плагина в application или domain?

---

## 78. Главные инварианты

### PLATFORM-001 — API платформы изолированы

Детали ОС и плагинов не распространяются по коду application.

### PLATFORM-002 — Границы чистого Dart сохраняются

`codelab_acp_protocol`, `codelab_client_acp` и другие пакеты на чистом Dart не получают зависимость от Flutter или платформы без архитектурного решения.

### PLATFORM-003 — Побочные действия агента проходят политику разрешений

Действия агента с файлами, процессами и сетью не обходят границу безопасности.

### PLATFORM-004 — У ресурсов платформы есть владелец

Процесс, наблюдатель, подписка и нативный дескриптор имеют жизненный цикл и очистку.

### PLATFORM-005 — Неподдерживаемая возможность явна

Тихий no-op не используется для критичных операций.

### PLATFORM-006 — UI не владеет infrastructure

Виджеты не создают адаптеры процессов, файловой системы и нативных API напрямую.

---

## 79. Основная модель

Предпочтительная архитектура:

```text
Feature / Application
        │
        ▼
Semantic Port
        ▲
        │
Platform Adapter
        │
        ▼
Flutter Plugin / dart:io / OS API
```

Если фича напрямую знает о конкретном desktop-плагине, правилах путей платформы и ветвлении по ОС, границу СЛЕДУЕТ пересмотреть.

---

## 80. Агент CodeLab: встроенный в процесс app и `codelab-agent` как процесс

Агент CodeLab запускается двумя способами. Клиент выбирает профиль подключения; ACP-контракт у обоих одинаков (`acp-boundary.md`, раздел 49).

| | Встроенный агент | `codelab-agent` как процесс |
|---|---|---|
| Где работает | в процессе клиента (app или `codelab`), в его isolate, пара `InProcessAcpLink` вместо сокета и пайпа | отдельный процесс: `codelab-agent serve --stdio` или `--ws` |
| Кто владеет | `codelab_embedded` (хост ядра); клиент получает `EmbeddedAgent` и закрывает его при выходе | процесс запускает клиент по профилю stdio (раздел 20) или внешний клиент вроде Zed; для `--ws` — тот, кто запустил |
| Профиль по умолчанию | да: app без выбора и `codelab` без `--agent` | нет: выбирается явно |
| Файлы и команды | сам агент через `AcpServerConfig.localEnv` (профили `embedded-app-desktop`, `embedded-cli`); `fs/*` и `terminal/*` клиенту не уходят | через `fs/*` и `terminal/*` клиента (или локальный листинг по stdio); так редактор видит несохранённые буферы |
| Конфиг и состояние | `$CODELAB_HOME` (по умолчанию `~/.codelab`): `config.yaml`, сессии, секреты | то же, плюс `CODELAB_*` и флаги запуска |
| Журналы | в `Logger` клиента; диагностика по разделу 65 | stderr процесса, при желании `--log-file`; stdout занят протоколом (раздел 21) |
| Остановка | `dispose` встроенного агента: активные ходы отменяются, журнал дописывается | EOF stdin — код `0`, `SIGINT` — `130`, `SIGTERM` — `143`; ход отменяется, журнал дописывается |

Правила платформенной границы для встроенного агента:

* Файловая система, процессы, хранилище секретов и MCP-серверы — infrastructure: их реализуют `codelab_agent_io` и настольный открыватель `codelab_embedded/io.dart`, а не код приложения или ядро. Основной барель `codelab_embedded` остаётся web-безопасным; `io.dart` импортирует только composition root клиента (`AGENTS.md` §5).
* Containment путей инструментов обеспечивает `BoundedEnv` рабочей папки сессии, а не клиентские проверки платформы. Платформенные ветки (`Platform.is*`) в агенте не распространяются: различия скрыты за портами ядра.
* Хранилище секретов агента — `env` (по умолчанию) или явный `file`; хранилищ ОС (keychain) в этой версии нет. Секреты приложения и секреты агента не смешиваются (раздел 25–26). **Расходится с кодом:** app и CLI хранят свои секреты в хранилище агента (см. абзац «В коде» в конце раздела).
* Встроенный агент НЕ ДОЛЖЕН блокировать UI isolate: ходы и вывод инструментов идут асинхронно; тяжёлые процессы — дочерние процессы инструмента `exec`, а не вычисления в isolate app. Долгая работа по-прежнему отменяется через `session/cancel`.
* Бинарь `codelab-agent` собирается отдельно (`fvm dart run melos run build:agent`) и не входит в сборку app. Приложение, запущенное из меню, не видит `PATH` оболочки, поэтому профиль stdio хранит абсолютный путь к бинарю (раздел 55). **Расходится с кодом:** путь хранится так, как его ввёл пользователь, абсолютность не проверяется и не обеспечивается.
* Отказ встроенного агента — типизированная ошибка открытия (`EmbeddedAgentConfigException` для невалидного конфига) до сетевых вызовов; падение зоны агента закрывает его и сообщается клиенту как сбой соединения, а не необработанное исключение приложения.

В коде app и CLI хранят токены профилей и ключи провайдеров в том же хранилище секретов агента (`ClientSecretAccess` из `codelab_setup/io.dart`, бэкенд по `secrets.backend` пользовательского `config.yaml`): отдельного хранилища секретов у app нет, ключи провайдеров, которые клиент записывает, читает агент. На Windows бэкенд `file` недоступен, остаётся `env`.
