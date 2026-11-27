## ADDED Requirements

### Requirement: Ключ permissions.exec_sandbox
Схема конфигурации SHALL содержать ключ `permissions.exec_sandbox` со значениями `auto`, `required` и `off`; по умолчанию — `auto` (design.md change `add-exec-os-write-sandbox`, D8).

Значения:
- `auto` — защита записи `exec` на уровне ОС, если механизм есть;
- `required` — без механизма `exec` отклоняется политикой;
- `off` — защиты ОС нет, действует только текстовая проверка.

Неизвестное значение SHALL быть проблемой ключа с подсказкой допустимых значений.

Правила ключа:
- Проектный слой SHALL только ужесточать значение в порядке `off < auto < required`. Ослабление SHALL отбрасываться с предупреждением `config.project.untrusted_key`, как у `permissions.mode`.
- Ключ SHALL требовать перезапуска (`restartRequired: true`, как все `permissions.*`) и НЕ SHALL применяться живой перезагрузкой.
- `SettingsRegistry` SHALL содержать дескриптор `enum` со `scope: fileOnly` и причиной `exec sandbox is configured in the config file`.

#### Scenario: Проект только ужесточает
- **WHEN** глобальный слой задаёт `permissions.exec_sandbox: auto`, а проект — `off`; во втором варианте проект задаёт `required`
- **THEN** в первом варианте итог `auto` и предупреждение `config.project.untrusted_key` для `permissions.exec_sandbox`, во втором — `required` без предупреждения

#### Scenario: Неизвестное значение
- **WHEN** `config.yaml` задаёт `permissions.exec_sandbox: strict`
- **THEN** загрузка даёт проблему `permissions.exec_sandbox` с перечнем `auto, required, off`

#### Scenario: Перезагрузка не меняет режим
- **WHEN** во время работы агента глобальный `permissions.exec_sandbox` меняется с `required` на `off`, а наблюдатель перезагружает конфиг
- **THEN** режим открытых и новых сессий до перезапуска остаётся `required`

### Requirement: config check показывает защиту exec на уровне ОС
`config check` (обе подкоманды, одна реализация `ConfigCommands`) SHALL печатать строку состояния защиты `exec` на уровне ОС:
- `Exec sandbox: active (<mechanism>)`, если механизм обнаружен и режим не `off`;
- `Exec sandbox: unavailable (<reason>)`, если механизма нет;
- `Exec sandbox: off`, если режим `off`.

Строка SHALL стоять перед строкой `Default model:`, а без неё — перед последней строкой. При невалидном конфиге строка SHALL печататься с режимом по умолчанию. Если режим `required`, а механизма нет, SHALL печататься предупреждение `warning: permissions.exec_sandbox: required, but no OS sandbox is available: exec will be denied`. Код выхода от состояния защиты НЕ SHALL зависеть.

#### Scenario: Механизм есть
- **WHEN** на macOS с работающим `sandbox-exec` и валидным конфигом без ключа запускается `config check`
- **THEN** stdout содержит `Exec sandbox: active (sandbox-exec)` перед `Default model:`, код `0`

#### Scenario: Required без механизма
- **WHEN** обнаружение механизма подменено так, что механизма нет, а `config.yaml` задаёт `permissions.exec_sandbox: required`
- **THEN** stdout содержит `Exec sandbox: unavailable (<reason>)` и строку `warning: permissions.exec_sandbox: required, but no OS sandbox is available: exec will be denied`, последняя строка `Config: valid`, код `0`
