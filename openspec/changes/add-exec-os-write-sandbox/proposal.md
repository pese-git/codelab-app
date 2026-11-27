## Why

PERM-11 запрещает модели без человека править конфигурацию агента: проектный `.codelab/**`, `~/.codelab` и `$CODELAB_HOME`, корни навыков (`.agents/skills`, `.codelab/skills` и другие, `AgentConfigScope`). Для `write`/`edit` это надёжно: цель канонизирует `BoundedEnv`, а пишет сам процесс агента. Для `exec` защита — только текстовая эвристика: `shell_lexer.dart`, `critical_patterns.dart`, `agent_config_rules.dart` (`agent-core/07-permissions.md` §7.6.1).

Каждое ревью безопасности находило новые обходы этой эвристики:
- смена каталога через `cd -`, `popd`, неудачный `cd` (change `harden-exec-cwd-tracking`);
- динамические команды и подстановки: `${HOME:-x}`, путь в переменной, `$(…)`;
- переменные-команды: `GIT_EDITOR`, `PAGER`, `LESSOPEN`;
- запись из программ: `python -c`, скрипт из файла, `sed 'w …'`, `awk '{print > …}'`, `echo … | sh`.

Это предел текстового разбора: строка команды не определяет, куда процесс в итоге пишет. Пользователь согласился, что надёжный слой — запрет записи на уровне ОС: процессы, которые запускает `exec`, физически не могут писать в защищаемые пути. Решения пользователя в соседних changes (Q34, Q37, Q47 change `add-agent-skills`) — fail closed и разрешённые списки. Этот change следует им.

Эксперимент на macOS 27.0.1 (design.md, «Context») подтвердил, что `sandbox-exec` с профилем `(allow default)` и `(deny file-write* …)` закрывает все перечисленные классы обходов. Запрет держится для дочерних и фоновых процессов, symlink, hardlink, `rename` предка и несуществующих путей.

## What Changes

- **Второй рубеж PERM-11 для `exec`.** Текстовая проверка остаётся первым рубежом: ранний понятный отказ, вопрос человеку, fallback. Поверх неё процесс команды запускается под запретом записи на уровне ОС. Запрет действует на защищаемые пути сессии и на каталоги-предки: их нельзя создать, удалить или переименовать.
- **Порт ядра** (`codelab_agent_core`, чистый Dart):
  - поле `ExecOptions.writeProtection` (`ExecWriteProtection` — список защищаемых путей);
  - опциональная возможность `ExecSandboxShell` со статусом `ExecSandboxStatus`; `BoundedEnv` и `ListingOverlayEnv` пробрасывают её от внутреннего env;
  - признак `ExecResult.writeProtected`;
  - код ошибки `ExecErrorCode.sandboxFailed`.
- **Сессионный `ExecWriteGuard`** (ядро) строит защиту на каждый вызов `exec` из того же `AgentConfigPaths` сессии, что у политики, плюс `<корень сессии>/.codelab` и `<корень сессии>/.agents/skills` целиком. Одобрение человеком критической команды с меткой `write to agent configuration` снимает защиту ровно для этого `toolCallId` (PERM-4). В `autopilot` защита не снимается никогда.
- **macOS** (`codelab_agent_io`): `LocalExecutionEnv` запускает команду через `/usr/bin/sandbox-exec`. Профиль постоянный, пути передаются параметрами `-D`, а не текстом SBPL: инъекция в профиль через имя пути невозможна. Каждый путь берётся в двух формах — лексической и канонической (`/tmp` → `/private/tmp`). Механизм проверяется пробой при сборке хоста. Сбой запуска песочницы — fail closed: команда не выполняется.
- **Linux и Windows** в этом change — без механизма ОС, статус `unavailable` и прежняя текстовая эвристика. Обоснование и варианты для Linux (`bwrap`, landlock, FFI) — design.md, D6; решение — вопрос Q1.
- **Ключ `permissions.exec_sandbox: auto | required | off`.** По умолчанию `auto`. Проектный слой может только ужесточать значение. Ключ требует перезапуска. В режиме `required` без механизма политика отклоняет `exec` до вопроса.
- **Наблюдаемость.** События журнала `exec.sandbox.status` (при открытии сессии), `exec.sandbox.lifted`, `exec.sandbox.failed`. Строка `Exec sandbox: …` в `config check`. Заметка модели, если процесс получил отказ записи под песочницей.

## Не входит

- ACP: ни методов, ни полей, ни состояний. Защита — поведение агента, клиенту она не передаётся.
- **Терминал клиента ACP** (`AcpClientExecutionEnv` → `terminal/create` → `IoTerminalProcessRunner` пакета `codelab_client_io`). В ACP нет поля для защищаемых путей, придумывать его нельзя (`AGENTS.md` §3.4). Клиент может быть на другой машине, а его терминал обслуживает и внешних агентов. Сессии с таким env получают статус `unavailable` (design.md, D14).
- Linux (`bwrap`) и Windows — отдельный change после ответа на Q1.
- MCP-серверы stdio, LSP-серверы и пользовательские хуки. Их команды задаёт доверенная конфигурация, а не модель.
- Защита от делегирования записи демонам вне дерева процессов: `osascript`, `open`, `launchctl`, `docker run -v`, `ssh localhost`, `cron`. Это известный предел (design.md, D12).
- Ослабление текстовой эвристики при активной песочнице. Обе проверки работают всегда (D1).
- Изменение `write`/`edit` и правил §7.6.1 для них.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-execution-env` — ADDED «Защита записи exec на уровне ОС», ADDED «Песочница sandbox-exec в LocalExecutionEnv на macOS».
- `agent-permissions` — ADDED «Второй рубеж PERM-11 для exec на уровне ОС».
- `agent-configuration` — ADDED «Ключ permissions.exec_sandbox», ADDED «config check показывает защиту exec на уровне ОС».

## Impact

- `codelab_agent_core` `[agent]`:
  - `lib/src/env/execution_env.dart` — порт;
  - `bounded_env.dart`, `listing_overlay_env.dart`, `memory_env.dart` — проброс и статус;
  - новый `lib/src/permissions/exec_write_guard.dart`;
  - `policy.dart` — режим `required`, отметка одобрения;
  - `tools/builtin/exec.dart` — защита, заметка, ошибка;
  - `runtime/agent_runtime.dart` — guard на сессию, событие статуса;
  - схема конфигурации и `SettingsRegistry`.

  Зависимости не меняются (PKG-2), `dart:io` не появляется (PKG-1), пакет остаётся web-безопасным.
- `codelab_agent_io` `[agent]`:
  - новый `lib/src/env/exec_sandbox.dart` (`MacSandboxExec`, `detectExecSandbox`);
  - `local_execution_env.dart` — запуск через песочницу;
  - `cli/config_commands.dart` — строка `config check`.
- `codelab_embedded`, `apps/codelab_agent` `[agent]` — composition root передаёт обнаруженную песочницу в `LocalExecutionEnv`.
- `codelab_client_*`, `apps/codelab_cli`, `apps/codelab_desktop` не меняются: `config check` CLI идёт через `codelab_setup` → `ConfigCommands`.
- Сторож, `pubspec.yaml`, граф пакетов в `README.md` не меняются.
- Документы ядра до кода: `agent-core/04-execution-env.md` (§4.6.1), `07-permissions.md` (§7.6.3), `15-configuration.md`. Это задача 0.1: правка сейчас конфликтовала бы с незакоммиченным `harden-exec-cwd-tracking` в том же `07-permissions.md`.
- Независимость от `harden-exec-cwd-tracking`: по коду не зависит. ОС-слой ложится рядом с текстовой проверкой и не читает её внутренних типов. Общие точки — только метка `write to agent configuration` и `PolicyOutcome` (design.md, D4).
