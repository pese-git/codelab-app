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

