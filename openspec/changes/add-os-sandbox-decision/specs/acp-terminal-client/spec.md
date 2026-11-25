## ADDED Requirements

### Requirement: Окружение процесса terminal/create по allowlist
Процесс `terminal/create` SHALL NOT наследовать окружение клиента целиком (REV-29; design.md change `add-os-sandbox-decision`, D2). Окружение процесса SHALL состоять из:

1. базового набора — значений окружения хоста для имён из allowlist, если они заданы:
   - на всех платформах: `PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL` (тот же список, что у команд агента, ENV-6);
   - на Windows дополнительно: `SystemRoot`, `SystemDrive`, `windir`, `ComSpec`, `PATHEXT`, `TEMP`, `TMP`, `USERPROFILE`, `USERNAME`, `HOMEDRIVE`, `HOMEPATH`, `APPDATA`, `LOCALAPPDATA`, `ProgramData`, `ProgramFiles`, `ProgramFiles(x86)`, `CommonProgramFiles`, `CommonProgramFiles(x86)`, `ProgramW6432`, `ALLUSERSPROFILE`, `COMPUTERNAME`, `PSModulePath`, `OS`, `PROCESSOR_ARCHITECTURE`, `NUMBER_OF_PROCESSORS`; имена на Windows сравниваются без учёта регистра;
2. переменных `env` запроса поверх базового набора: значение из запроса SHALL перекрывать базовое. На Windows слияние SHALL идти без учёта регистра имён: переменная запроса заменяет базовую с тем же именем в любом регистре, и в окружении процесса остаётся одна переменная.

Клиент SHALL NOT добавлять другие переменные. Построенное окружение процесса SHALL NOT записываться в журнал и диагностику. Параметр `env` запроса `terminal/create` записывается только в составе кадра протокола по действующим правилам маскирования кадров (`SecretRedactor`), как любой другой входящий кадр.

Терминал пользователя (панель Terminal) это требование не затрагивает.

#### Scenario: Секрет клиента не виден команде
- **WHEN** в окружении клиента заданы `CODELAB_SECRET_OPENAI` и `OPENAI_API_KEY`, и агент запускает через `terminal/create` команду, печатающую окружение
- **THEN** вывод не содержит ни этих имён, ни их значений и содержит `PATH`

#### Scenario: Переменная запроса передаётся и перекрывает базовую
- **WHEN** агент отправляет `terminal/create` с `env` `[{"name":"GIT_PAGER","value":"cat"},{"name":"LANG","value":"C"}]`
- **THEN** процесс видит `GIT_PAGER=cat` и `LANG=C`, а не значение `LANG` хоста

#### Scenario: Пустой env запроса
- **WHEN** агент отправляет `terminal/create` без `env`
- **THEN** процесс получает только базовый набор allowlist

#### Scenario: Построение окружения на Windows
- **WHEN** окружение хоста содержит `Path`, `SYSTEMROOT`, `ComSpec` и `OPENAI_API_KEY`, клиент работает на Windows, и `env` запроса пуст
- **THEN** построенное окружение содержит `Path`, `SYSTEMROOT` и `ComSpec` со значениями хоста и не содержит `OPENAI_API_KEY`

#### Scenario: Path запроса перекрывает PATH хоста на Windows
- **WHEN** клиент работает на Windows, в окружении хоста есть `PATH=C:\Windows`, и агент отправляет `terminal/create` с `env` `[{"name":"Path","value":"C:\tools"}]`
- **THEN** построенное окружение содержит ровно одну переменную пути без учёта регистра, и её значение — `C:\tools`

#### Scenario: Windows без системных переменных не ломается
- **WHEN** клиент работает на Windows, и агент запускает `cmd.exe /c echo %SystemRoot%`
- **THEN** вывод содержит значение `SystemRoot` хоста
