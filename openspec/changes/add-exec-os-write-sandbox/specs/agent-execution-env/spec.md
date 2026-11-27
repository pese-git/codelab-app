## ADDED Requirements

### Requirement: Защита записи exec на уровне ОС
Порт `ExecutionEnv` SHALL нести защиту записи для `exec` (design.md change `add-exec-os-write-sandbox`, D3).

Состав порта:
- `ExecOptions.writeProtection: ExecWriteProtection?` — абсолютные пути ядра (POSIX), каждый защищается поддеревом; `copyWith` SHALL сохранять поле;
- `ExecResult.writeProtected` — защита была применена к процессу;
- код `ExecErrorCode.sandboxFailed` — защиту применить не удалось, команда не запускалась;
- опциональная возможность `ExecSandboxShell` с `execSandbox: ExecSandboxStatus`: `ExecSandboxActive(mechanism)` или `ExecSandboxUnavailable(reason)`. Возможность проверяется через `is`.

Правила:
- Env со статусом `ExecSandboxActive`, получивший непустой `writeProtection`, SHALL либо запустить процесс под защитой (`writeProtected: true`), либо вернуть `Err(ExecError(sandboxFailed))`, не запуская команду (fail closed).
- С `writeProtection == null` команда SHALL запускаться без защиты.
- `BoundedEnv` и `ListingOverlayEnv` SHALL реализовывать `ExecSandboxShell` всегда и отдавать статус внутреннего env (у `ListingOverlayEnv` — `primary`). Если внутренний env возможности не реализует, они SHALL отдавать `ExecSandboxUnavailable('environment has no OS sandbox')`.
- `BoundedEnv` SHALL передавать `writeProtection` внутреннему env без изменений.
- `MemoryExecutionEnv` и `AcpClientExecutionEnv` НЕ SHALL реализовывать `ExecSandboxShell`.
- Ядро НЕ SHALL знать механизм ОС: в `codelab_agent_core` нет `dart:io`, `Platform` и имён механизмов, кроме непрозрачной строки `mechanism` (PKG-1).

#### Scenario: Обёртка пробрасывает статус и защиту
- **WHEN** `BoundedEnv.wrap` оборачивает фейковый env со статусом `ExecSandboxActive('fake')`, а `exec` вызывается с `writeProtection` из двух путей и `cwd` внутри корня
- **THEN** обёртка отдаёт `ExecSandboxActive('fake')`, внутренний env получает те же два пути, а `ExecResult.writeProtected` приходит от внутреннего env (`bounded_env_test.dart`)

#### Scenario: Env без возможности
- **WHEN** `BoundedEnv.wrap` оборачивает `MemoryExecutionEnv`, а `ListingOverlayEnv` — фейковый клиентский env без `ExecSandboxShell`
- **THEN** обе обёртки отдают `ExecSandboxUnavailable('environment has no OS sandbox')`

#### Scenario: copyWith сохраняет защиту
- **WHEN** `ExecOptions` с `writeProtection` копируется через `copyWith(cwd: …)`
- **THEN** у копии тот же `writeProtection`

### Requirement: Песочница sandbox-exec в LocalExecutionEnv на macOS
`codelab_agent_io` SHALL обнаруживать механизм ОС функцией `detectExecSandbox()` — единственным местом с проверкой платформы (`AGENTS.md` §11). `LocalExecutionEnv` SHALL получать механизм конструктором (`sandbox:`) и реализовывать `ExecSandboxShell` со статусом механизма. Без параметра механизм — `NoOsWriteSandbox('not configured')`. На Linux и Windows `detectExecSandbox()` SHALL давать `NoOsWriteSandbox` с причиной `not implemented on <os>` (design.md, D6).

**Проба.** На macOS `detectExecSandbox()` SHALL выполнять функциональную пробу во временном каталоге:
1. `/usr/bin/sandbox-exec` существует;
2. запись внутрь защищённого пробного каталога отклонена, файл не создан;
3. запись вне его разрешена.

Любой другой исход SHALL давать `NoOsWriteSandbox` с причиной; в причине — первая строка stderr, без путей пользователя (D5).

**Запуск.** С `MacSandboxExec` и непустым `writeProtection` `exec` SHALL запускать `/usr/bin/sandbox-exec -p <профиль> -D W0=… -D A0=… <shell> -c <command>`. Окружение, `cwd`, буфер, таймаут и отмена SHALL оставаться прежними (§4.6, ENV-5, ENV-6).

**Профиль** SHALL собираться только из постоянных фрагментов и ссылок `(param "Wi")`/`(param "Ai")`. Строки путей SHALL передаваться только как значения `-D` и НЕ SHALL попадать в текст профиля. Правила:
- `(allow default)`;
- `(deny file-write* (subpath (param "Wi")) …)` для каждого защищаемого пути;
- `(deny file-write-create file-write-unlink (literal (param "Ai")) …)` для каждого каталога-предка защищаемых путей вплоть до `/`, кроме самих защищаемых путей.

**Формы путей.** Для каждого пути SHALL передаваться две формы: лексическая и каноническая. Каноническая — `realpath` самого глубокого существующего предка плюс остаток. Формы пересчитываются при каждом вызове. Предки SHALL браться от обеих форм. Дубликаты SHALL убираться, порядок SHALL быть стабильным.

**Ошибки.** Путь, который нельзя передать параметром (содержит NUL или пуст), отсутствие `sandbox-exec` и ошибка `Process.start` SHALL давать `Err(ExecError(sandboxFailed, message))` без запуска команды.

#### Scenario: Текст профиля не зависит от путей
- **WHEN** профиль строится для путей `/w/a`, `/w/we"ird) (allow file-write*`, `/w/x\y;z`, пути с переводом строки и `/w/юникод`
- **THEN** текст профиля совпадает с эталоном для того же числа путей и предков, а каждый путь присутствует только в значении `-D` (`exec_sandbox_test.dart`)

#### Scenario: Каноническая форма и предки
- **WHEN** на macOS защищается `/tmp/<t>/proj/.codelab`, а `.codelab` не существует
- **THEN** параметры `W` содержат `/tmp/<t>/proj/.codelab` и `/private/tmp/<t>/proj/.codelab`, параметры `A` — `/private/tmp/<t>/proj`, `/private/tmp/<t>`, `/private/tmp`, `/private` и `/` и лексические предки, без дубликатов

#### Scenario: Запись в защищаемые пути отклоняется ОС
- **WHEN** на macOS с активной песочницей в проекте `<t>/proj` с `.codelab/config.yaml` и защитой `<t>/proj/.codelab`, `<t>/proj/.agents/skills` выполняются `echo x > .codelab/config.yaml`, `echo x >> .codelab/new.yaml`, `rm .codelab/config.yaml`, `chmod 777 .codelab/config.yaml`, `mkdir -p .agents/skills/x`, `mv .codelab ../x`, `cd .. && mv proj proj2`, `ln .codelab/config.yaml ../other/hl` и запись через ранее созданную символическую ссылку `../other/sl` на `.codelab/config.yaml`
- **THEN** каждая команда завершается ненулевым кодом с `Operation not permitted` в выводе, содержимое и расположение `.codelab` и `proj` не изменились, `ExecResult.writeProtected` — `true` (`local_exec_sandbox_test.dart`, `@TestOn('mac-os')`)

#### Scenario: Несуществующий каталог конфигурации нельзя создать
- **WHEN** в проекте без `.codelab` с защитой `<t>/proj/.codelab` выполняются `mkdir .codelab`, `mkdir .CODELAB` (том без учёта регистра) и `mkdir x && echo y > x/config.yaml && mv x .codelab`
- **THEN** ни `.codelab`, ни `.CODELAB` не создаются, а `x` остаётся на месте

#### Scenario: Остальное разрешено
- **WHEN** под той же песочницей выполняются `cat .codelab/config.yaml`, `echo ok > out.txt`, `touch .`, `mkdir build` и запись во временный каталог
- **THEN** все команды завершаются с кодом 0

#### Scenario: Потомки и фоновые процессы наследуют защиту
- **WHEN** команда запускает `(sleep 0.3; echo y > .codelab/g) &` и сразу завершается
- **THEN** после завершения фонового процесса файла `.codelab/g` нет

#### Scenario: Сбой запуска песочницы — команда не исполняется
- **WHEN** `MacSandboxExec` настроен на несуществующий путь `sandbox-exec`, а команда — `touch <t>/marker`
- **THEN** `exec` возвращает `Err(ExecError(sandboxFailed))`, файла `<t>/marker` нет

#### Scenario: Проба внутри чужой песочницы
- **WHEN** `detectExecSandbox()` выполняется в процессе, уже запущенном под `sandbox-exec`
- **THEN** результат — `NoOsWriteSandbox` с причиной из stderr `sandbox_apply`, и `LocalExecutionEnv` отдаёт `ExecSandboxUnavailable`

#### Scenario: Отмена под песочницей
- **WHEN** под песочницей команда запускает фоновый `sleep 60` и ждёт его, а токен отменяется
- **THEN** `exec` возвращает `Err(ExecError(aborted))` не позже чем через 5 с, потомков корневого процесса в таблице процессов нет (ENV-5)

#### Scenario: Linux и Windows без механизма
- **WHEN** `detectExecSandbox()` выполняется на Linux или Windows
- **THEN** результат — `NoOsWriteSandbox` с причиной `not implemented on linux` или `not implemented on windows`, а `exec` с `writeProtection` запускает команду без песочницы, `writeProtected` — `false`
