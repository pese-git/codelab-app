# agent-execution-env Specification

## Purpose
Окружение исполнения Dart-агента: порт `ExecutionEnv` с ошибками как значениями `Result`, граница рабочей папки `BoundedEnv`, `MemoryExecutionEnv` для тестов и web и `LocalExecutionEnv` пакета `codelab_agent_io` для файловой системы и процессов хоста. Инструменты работают только через этот порт, поэтому ядро остаётся без `dart:io` (`agent-core-architecture` §4).
## Requirements
### Requirement: Порт ExecutionEnv и ошибки как значения
Ядро SHALL обращаться к файлам и процессам только через порт `ExecutionEnv`, который объединяет `FileSystem` (`cwd`, `readText(path, {line, limit})`, `writeText`, `stat`) и `Shell` (`exec(command, ExecOptions)`). Опциональные возможности `DirectoryListing`, `BinaryFiles` и `PathResolver` SHALL проверяться через `is`.

Ожидаемые ошибки SHALL возвращаться значениями `Err(FileError)` и `Err(ExecError)` с кодом из `FileErrorCode` и `ExecErrorCode`, а не исключениями (ENV-1).

Семантика методов:
- пути на входе — абсолютные или относительные `cwd`, на выходе — абсолютные нормализованные;
- `readText` отдаёт строки с номера `line` (с 1), не больше `limit`; невалидный UTF-8 → `notText`; каталог → `isDirectory`;
- `writeText` создаёт недостающих родителей;
- ненулевой код возврата `exec` — это `Ok(ExecResult(exitCode: N))`.

#### Scenario: Ненулевой код — данные, а не ошибка
- **WHEN** команда завершается с кодом 1
- **THEN** `exec` возвращает `Ok` с `exitCode: 1` и выводом команды

#### Scenario: Ожидаемая ошибка не бросает
- **WHEN** `readText` вызывается для несуществующего файла, для каталога и для файла с невалидным UTF-8
- **THEN** возвращаются `Err` с кодами `notFound`, `isDirectory` и `notText`, и ни один вызов не бросает исключение

### Requirement: Граница рабочей папки BoundedEnv
Ни один инструмент НЕ SHALL получать базовый env в обход `BoundedEnv` (ENV-2). `BoundedEnv.wrap(inner, root)` SHALL проверять путь каждой операции по алгоритму §4.4 документа ядра:

1. Путь нормализуется: `~` и `~/` отклоняются, относительный путь приклеивается к `cwd`, `.` и пустые сегменты выбрасываются, `..` снимает сегмент.
2. Если внутренний env реализует `PathResolver`, разрешается самый длинный существующий префикс пути.
3. Путь принимается, только если его **сегменты** начинаются с сегментов корня.
4. Отклонённый путь даёт `Err(FileError(outsideWorkspace, p))` до любого обращения к внутреннему env для этой операции (ENV-3).

Внутреннему env SHALL передаваться нормализованный путь `abs`, а не разрешённый `real`. Для `exec` проверяется `ExecOptions.cwd`, а содержимое команды — нет.

`wrap` SHALL возвращать обёртку, которая реализует опциональную возможность, только если её реализует внутренний env. Путь для `listDir` и `readBytes` SHALL проверяться так же (ENV-4). Записи-ссылки из `listDir`, разрешающиеся вне корня, остаются в списке как `FileType.link`, а последующие операции с ними отклоняются.

#### Scenario: Соседний каталог с общим префиксом
- **WHEN** при корне `/proj` запрашивается `/proj_evil/x`
- **THEN** результат — `outsideWorkspace`, внутренний env не получает ни одного вызова (`bounded_env_test.dart: rejects sibling directory with shared prefix`)

#### Scenario: Таблица §4.4
- **WHEN** при корне `/proj` проверяются `src/a.dart`, `/proj`, `../x`, `src/../../etc/passwd`, `~/.ssh/id_rsa`, `./a//b/./c`
- **THEN** приняты `src/a.dart`, `/proj` и `./a//b/./c` (как `/proj/a/b/c`), остальные отклонены с `outsideWorkspace`

#### Scenario: Пути Windows после приведения
- **WHEN** при корне `/c/proj` (из `C:\proj`) проверяются `/c/proj2/x` и `/c/proj/../proj2/x`
- **THEN** оба пути отклонены с `outsideWorkspace`

#### Scenario: Ссылка наружу и новый файл за ссылкой внутрь
- **WHEN** внутренний env реализует `PathResolver`, `/proj/link` ведёт на `/etc`, а `/proj/docs` — на `/proj/site/docs`
- **THEN** `link/passwd` отклоняется, а `docs/new/file.md` в несуществующем каталоге принимается

#### Scenario: Обёртка не выдумывает возможностей
- **WHEN** `BoundedEnv.wrap` получает env без `DirectoryListing`
- **THEN** результат не реализует `DirectoryListing`; для env с ним — реализует и проверяет путь

### Requirement: MemoryExecutionEnv
`MemoryExecutionEnv` SHALL хранить файлы в памяти по абсолютным POSIX-путям, всегда иметь каталоги `/` и `cwd` и реализовывать `DirectoryListing`. Поведение:
- `writeText` создаёт предков; если предок — файл, результат `notDirectory`;
- `readText` декодирует UTF-8 строго, срез `line`/`limit` идёт по `\n`;
- `listDir` возвращает прямых потомков в лексикографическом порядке;
- `modified` берётся из `Clock` хоста;
- `exec` → `Err(ExecError(shellUnavailable, message: 'shell is not available on this platform'))`.

`PathResolver` НЕ SHALL реализовываться.

#### Scenario: Общий контрактный набор
- **WHEN** контрактный набор `execution_env_contract.dart` (чтение диапазона строк, запись с созданием родителей, `notFound`, `isDirectory`, `notText`) прогоняется на `MemoryExecutionEnv`
- **THEN** все проверки проходят без исключений

### Requirement: LocalExecutionEnv пакета codelab_agent_io
`LocalExecutionEnv` SHALL реализовывать `ExecutionEnv`, `DirectoryListing`, `BinaryFiles` и `PathResolver` поверх `dart:io` и проходить тот же контрактный набор, что `MemoryExecutionEnv`.

`exec` SHALL работать по §4.6 документа ядра:
1. Несуществующий `cwd` → `spawnFailed`.
2. Запуск через `/bin/sh -c` (на Windows `cmd.exe /d /s /c`) с `includeParentEnvironment: false`.
3. `stdin` закрывается сразу.
4. `stdout` и `stderr` читаются в общий кольцевой буфер не больше `outputByteLimit` байт; при переполнении отбрасывается начало и ставится `truncated`; каждый чанк уходит в `onOutput`.
5. Таймаут или отмена завершают дерево процессов: снимок таблицы процессов, `SIGTERM` всем потомкам одним проходом, до 2 с ожидания, `SIGKILL` оставшимся.

Управление SHALL возвращаться не позже чем через 5 с после сигнала (ENV-5).

Окружение процесса SHALL состоять только из базового набора §4.5 и `ExecOptions.env` (ENV-6). Базовый набор:
- `PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL` — значения хоста, если заданы;
- фиксированные `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`.

Пути хоста Windows SHALL приводиться к виду ядра (`C:\proj` ↔ `/c/proj`) функциями `toCorePath` и `toHostPath`.

#### Scenario: Процесс игнорирует SIGTERM
- **WHEN** команда `sh -c 'trap "" TERM; sleep 60'` запущена с таймаутом 1 с
- **THEN** `exec` возвращает `Err(ExecError(timeout))` с хвостом вывода не позже чем через 6 с после запуска (`local_exec_test.dart`)

#### Scenario: Окружение по allowlist
- **WHEN** в тестовом процессе задана переменная `CODELAB_TEST_SECRET`, а команда печатает `env`
- **THEN** вывод не содержит `CODELAB_TEST_SECRET` и содержит `GIT_TERMINAL_PROMPT=0`

#### Scenario: Вывод больше лимита
- **WHEN** команда печатает больше `outputByteLimit` байт
- **THEN** `ExecResult.output` содержит хвост не длиннее лимита, а `truncated` равен `true`

#### Scenario: Интерактивная команда не зависает
- **WHEN** команда читает из `stdin`
- **THEN** она получает EOF и завершается без таймаута

#### Scenario: Отмена убивает внуков
- **WHEN** команда запускает дочерний `sleep 60` в фоне и ждёт его, а токен отменяется
- **THEN** `exec` возвращает `Err(ExecError(aborted))`, и в таблице процессов не остаётся потомков корневого процесса

### Requirement: ListingOverlayEnv
`ListingOverlayEnv(primary, listing)` SHALL реализовывать `ExecutionEnv` и `DirectoryListing`: `listDir` и `stat` берутся у `listing`, остальные операции (`readText`, `writeText`, `exec`) — у `primary`. `stat` локальный, потому что в ACP нет метода stat и каталог через клиента не проверить (design.md, D15). Сессия оборачивает его в `BoundedEnv` целиком, поэтому граница рабочей папки одна для обоих env (§4.7, §10.4 документа ядра; design.md change `add-dart-agent-acp-server`, D5).

Хост ACP-сервера передаёт `listing`, только когда клиент и агент работают на одной машине (stdio). Без него `ls` и `search` выключены с причиной.

#### Scenario: Листинг локально, чтение через клиента
- **WHEN** `ls` и `read` вызываются над `ListingOverlayEnv(fakeClientEnv, memoryEnv)`
- **THEN** `ls` возвращает содержимое `memoryEnv` без запросов к клиенту, а `read` идёт в `fakeClientEnv`

#### Scenario: Граница общая
- **WHEN** `ls` вызывается с путём вне `cwd` сессии над `BoundedEnv(ListingOverlayEnv(...))`
- **THEN** вызов отклоняется `outsideWorkspace` до обращения к `listing`

### Requirement: Корни только для чтения
`BoundedEnv.wrap(inner, root, {readOnlyRoots, readOnlyFs, execInReadOnlyRoots})` SHALL принимать необязательные корни только для чтения, файловую систему для них и признак, что внутренний env исполняет команды на той же машине, что `readOnlyFs` (`agent-core-architecture` §4.4, §17.2.3; design.md change `add-agent-skills`, D5; решения пользователя Q4, Q17, Q23; SKL-9):
1. корни `readOnlyRoots` SHALL нормализоваться и разрешаться `realpath` через `readOnlyFs` один раз при создании обёртки;
2. операции чтения (`readText`, `readBytes`, `stat`, `listDir`) SHALL принимать путь, если его разрешённая форма лежит в `root` **или** в одном из `readOnlyRoots` по правилу сегментов §4.4; путь в `readOnlyRoots` SHALL уходить в `readOnlyFs`, а не во внутренний env;
3. запись, правка и удаление SHALL приниматься только в `root`; путь в `readOnlyRoots` для них — `Err(FileError(outsideWorkspace, p))` до обращения к любому env (ENV-3);
4. `ExecOptions.cwd` в `readOnlyRoots` SHALL приниматься и передаваться внутреннему env, только если `execInReadOnlyRoots == true`; иначе — `Err(FileError(outsideWorkspace, p))` до обращения к env. Содержимое команды, как и прежде, не проверяется (запись командой ловит политика разрешений, PERM-11);
5. без `readOnlyFs` `readOnlyRoots` SHALL игнорироваться: поведение — как у `wrap(inner, root)`;
6. ссылка из корня только для чтения, ведущая за его пределы, SHALL отклоняться так же, как ссылка из `root`.

Обёртка SHALL реализовывать опциональную возможность, только если её реализует внутренний env (ENV-4); для путей в `readOnlyRoots` — только если её реализует и `readOnlyFs`.

В `readOnlyRoots` рантайм SHALL класть только канонические каталоги загруженных навыков, лежащие вне `root` и не содержащие его: каталог навыка внутри рабочей папки остаётся обычной частью `root`, и правку в нём решает PERM-11, а сессия, открытая внутри каталога навыка, правит его как рабочую папку (design.md change `add-agent-skills`, D17). Рантайм SHALL ставить `execInReadOnlyRoots: true`, только если env сессии исполняет команды на машине агента (локальное окружение встроенного агента, `AcpServerConfig.localEnv`); у env клиента ACP (`AcpClientExecutionEnv`) — `false`: клиент ограничивает `cwd` `terminal/create` рабочей папкой сессии (`AGENTS.md` §10), и запрос с `cwd` в каталоге агента он отклонит. Подсказку SHALL давать инструмент `exec` до вызова env: он сравнивает `cwd` с `readOnlyRoots` сессии и при `execInReadOnlyRoots == false` возвращает модели ошибку инструмента с подсказкой запустить скрипт по абсолютному пути с `cwd` рабочей папки (capability `agent-skills`, «Сопутствующие файлы и скрипты навыка»; решение Q23 (а)); `BoundedEnv` при этом остаётся последним рубежом и различать причины `outsideWorkspace` не обязан. Клиенту запрос не отправляется, containment клиента не меняется.

#### Scenario: Чтение и запись в корне только для чтения
- **WHEN** при корне `/proj` и `readOnlyRoots: [/home/u/.codelab/skills/notes]` выполняются `readText` и `writeText` по пути `/home/u/.codelab/skills/notes/ref.md`
- **THEN** чтение возвращает содержимое из `readOnlyFs`, внутренний env вызова не получил; запись — `outsideWorkspace`, ни один env вызова не получил

#### Scenario: Соседи корня только для чтения недоступны
- **WHEN** при тех же корнях читаются `/home/u/.codelab/config.yaml` и `/home/u/.codelab/skills/other/SKILL.md`
- **THEN** оба — `outsideWorkspace`

#### Scenario: cwd команды в каталоге навыка
- **WHEN** `exec` получает `ExecOptions.cwd` `/home/u/.codelab/skills/notes`; в первом варианте `execInReadOnlyRoots: true`, во втором — `false`
- **THEN** в первом варианте (локальное исполнение, решение Q17) команда передана внутреннему env с этим `cwd`; во втором (env клиента ACP) — `outsideWorkspace` до обращения к внутреннему env, `terminal/create` не отправляется

#### Scenario: Ссылка наружу из корня только для чтения
- **WHEN** `/home/u/.codelab/skills/notes/link` ведёт на `/etc`, и читается `link/passwd`
- **THEN** результат — `outsideWorkspace`

#### Scenario: Сессия внутри каталога навыка
- **WHEN** сессия открыта в `/home/u/.codelab/skills/notes/scripts`, а навык `notes` загружен из `/home/u/.codelab/skills/notes`
- **THEN** этот каталог не входит в `readOnlyRoots`, и `writeText('/home/u/.codelab/skills/notes/scripts/a.py', …)` уходит во внутренний env как запись в рабочей папке (критичность правки решает PERM-11)

