## ADDED Requirements

### Requirement: Второй рубеж PERM-11 для exec на уровне ОС
Текстовая проверка PERM-11 и критических шаблонов (§7.6, §7.6.1) SHALL оставаться первым рубежом и НЕ SHALL ослабляться при активной защите ОС. Защита записи на уровне ОС — второй рубеж для процессов `exec` (design.md change `add-exec-os-write-sandbox`, D1).

**Guard сессии.** Рантайм SHALL создавать на каждую сессию `ExecWriteGuard` и передавать его политике разрешений и инструменту `exec` этой сессии. Субагент SHALL получать guard родителя.

**Защищаемые пути.** `ExecWriteGuard.protectionFor(toolCallId)` SHALL на каждый вызов строить `ExecWriteProtection` из двух источников:
- `AgentConfigPaths.paths` сессии — то же значение, что у политики сессии, включая пути `withSession`;
- `<корень сессии>/.codelab` и `<корень сессии>/.agents/skills` целиком, существуют они или нет (D2).

Инструмент `exec` SHALL передавать результат в `ExecOptions.writeProtection`.

**Режимы `permissions.exec_sandbox`** (D8):
- `off` — `protectionFor` SHALL возвращать `null`;
- `required` — если `ctx.env` не реализует `ExecSandboxShell` или его статус не `ExecSandboxActive`, политика SHALL отклонять `exec` без вопроса с причиной `OS write protection is required but unavailable: <reason>`. Проверка идёт после явных запретов и запретов хода (шаги 1–2 §7.4) и до критических шаблонов.

**Снятие одобрением.** Если человек ответил `allowOnce` на запрос одобрения `exec`, чья критическая метка содержит `write to agent configuration`, политика SHALL отметить этот `toolCallId` в guard. Следующий `protectionFor` того же `toolCallId` SHALL вернуть `null` и снять отметку. Снятие SHALL действовать на один вызов (PERM-4). Другие метки, обычное одобрение `exec`, `allowAlways`, решения режима и правил защиту НЕ SHALL снимать. В `autopilot` защита НЕ SHALL сниматься никогда.

**Сообщения модели** (D11):
- если `ExecResult.writeProtected`, код ненулевой, а вывод содержит `Operation not permitted`, инструмент SHALL добавить заметку `[Note: writes to agent configuration (.codelab, CODELAB_HOME, skill roots) are blocked by the OS sandbox. Do not retry; ask the user to make this change.]`;
- `sandboxFailed` SHALL давать ошибку инструмента `Command was not run: OS write protection could not be applied (<message>).` без отмены хода.

**Наблюдаемость** (D9, §16):
- при открытии сессии рантайм SHALL писать одно событие `exec.sandbox.status` с `session_id`, `mode`, `status` (`active`, `unavailable` или `off`) и `mechanism` или `reason`; уровень `warning` — для `unavailable` при `auto` и `required`;
- снятие SHALL логироваться `exec.sandbox.lifted` с `tool_call_id`;
- `sandboxFailed` SHALL логироваться `exec.sandbox.failed` с `tool_call_id`;
- защищаемые пути SHALL попадать в журнал только на уровне `debug`.

#### Scenario: Текстовый рубеж не меняется
- **WHEN** при активной фейковой песочнице табличные тесты `critical_patterns_test.dart` и `config_exec_whitelist_test.dart` прогоняются через политику
- **THEN** метки, вопросы и отказы совпадают с прогоном без песочницы

#### Scenario: Состав защиты на вызов
- **WHEN** сессия с корнем `/work/demo` и `AgentConfigPaths` с путями `/home/u/.codelab/config.yaml`, `/home/u/.agents/skills` и путём сессии `/work/.agents/skills` вызывает `exec`
- **THEN** `ExecOptions.writeProtection.paths` содержит эти три пути, `/work/demo/.codelab` и `/work/demo/.agents/skills` (`exec_write_guard_test.dart`)

#### Scenario: Одобрение правки конфигурации снимает защиту для одного вызова
- **WHEN** в режиме `bypass` модель вызывает `exec` с `echo x >> .codelab/config.yaml` (`call_1`) и человек отвечает `allow_once`, затем модель вызывает ту же команду (`call_2`) и человек отвечает `reject_once`
- **THEN** `call_1` запускается с `writeProtection == null` и событием `exec.sandbox.lifted`, повторный `protectionFor('call_1')` возвращает защиту, `call_2` не исполняется и отметки снятия не получает

#### Scenario: Прочие одобрения защиту не снимают
- **WHEN** человек отвечает `allow_once` на `exec` с меткой `unparsable command`, на некритический `exec` в режиме `ask` и на `exec` с меткой `recursive delete of a protected path`
- **THEN** все три вызова получают непустой `writeProtection`

#### Scenario: Autopilot
- **WHEN** в `autopilot` модель вызывает `python3 -c "open('.codelab/config.yaml','w')"`, а текстовый рубеж эту запись не распознаёт
- **THEN** политика разрешает вызов режимом, `exec` запускается с непустым `writeProtection`, а guard не содержит отметок снятия

#### Scenario: Режим required без механизма
- **WHEN** `permissions.exec_sandbox: required`, env сессии — `BoundedEnv` поверх `AcpClientExecutionEnv`, а модель вызывает `exec ls` в режиме `bypass`
- **THEN** вызов отклонён без запроса одобрения с причиной `OS write protection is required but unavailable: environment has no OS sandbox`, `ToolOutcome.rejected`, ход продолжается

#### Scenario: Режим off
- **WHEN** `permissions.exec_sandbox: off`, механизм активен, а модель вызывает `exec`
- **THEN** `writeProtection` равен `null`, текстовый рубеж работает как прежде, а `exec.sandbox.status` сообщает `off`

#### Scenario: Заметка об отказе записи
- **WHEN** фейковый env возвращает `ExecResult(exitCode: 1, output: 'sh: .codelab/x: Operation not permitted', writeProtected: true)`
- **THEN** результат инструмента содержит вывод, строку кода выхода и заметку про OS sandbox; при `writeProtected: false` заметки нет

#### Scenario: Сбой песочницы — ошибка инструмента
- **WHEN** env возвращает `Err(ExecError(sandboxFailed, message: 'sandbox-exec not found'))`
- **THEN** результат — ошибка `Command was not run: OS write protection could not be applied (sandbox-exec not found).`, событие `exec.sandbox.failed` с `tool_call_id`, ход продолжается

#### Scenario: Статус при открытии сессии
- **WHEN** сессия открывается над env без `ExecSandboxShell` при режиме `auto`
- **THEN** журнал содержит ровно одно событие `exec.sandbox.status` уровня `warning` со `status: unavailable` и `reason`, без путей конфигурации
