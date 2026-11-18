## ADDED Requirements

### Requirement: Ключи subagents в схеме и реестре настроек
Схема конфига SHALL содержать ключи базового этапа субагентов (решение пользователя 2026-11-10; design.md change `add-subagents-and-tasks`, D17, D22):

| Ключ | Тип | По умолчанию | Диапазон |
|---|---|---|---|
| `subagents.enabled` | bool | `true` | — |
| `subagents.max_depth` | int | `3` | 1–3 |
| `subagents.max_concurrent` | int | `3` | 1–8 |
| `subagents.max_per_turn` | int | `10` | 1–50 |
| `subagents.max_steps` | int | `30` | 1–500 |
| `subagents.max_tokens` | int | нет | ≥ 1 |
| `subagents.max_cost` | float | нет | > 0 |
| `subagents.max_duration` | duration | `10m` | > 0 |
| `subagents.report_max_bytes` | int | `16384` | 1024–1048576 |
| `subagents.progress_interval` | duration | `2s` | > 0 |
| `subagents.heartbeat_interval` | duration | `15s` | > 0 |
| `subagents.cancel_grace` | duration | `10s` | > 0 |

Правила:
- значение вне диапазона или неверного типа SHALL давать `ConfigIssue` с путём ключа, строкой и столбцом, а не исключение; ключ остаётся со значением по умолчанию;
- проектный слой SHALL только ужесточать: меньшие числа, `enabled: false`; смягчение SHALL отбрасываться с логом `config.project.untrusted_key` (как у `permissions`);
- ключи других этапов §17.3.10 (`background`, `follow_ups` и др.) в схему НЕ SHALL входить до своих changes (CFG-5).

`SettingsRegistry` SHALL вместо опакового дескриптора `subagents` содержать по дескриптору на каждый ключ таблицы:
- `scope: shared`, раздел `Subagents`, непустые `label` и `description`;
- `type`, `defaultValue`, `min`/`max` совпадают со схемой (требование «Реестр настроек», тест полноты: граница принимается, значение за ней отклоняется);
- `restartRequired: false`: лимиты читаются при каждом `spawn`;
- `layers` — по правилам доверия: проектный слой только ужесточает.

Так ключи доступны `config get|set`, `/settings` CLI и страницам настроек app через `ConfigWriter` без отдельного кода.

#### Scenario: Умолчания
- **WHEN** конфиг пустой
- **THEN** `CoreConfig.subagents` — `enabled: true`, `max_depth: 3`, `max_concurrent: 3`, `max_per_turn: 10`, `max_steps: 30`

#### Scenario: Диапазон глубины
- **WHEN** глобальный слой задаёт `subagents.max_depth: 4`, затем `0`, затем `3`
- **THEN** первые два значения дают `ConfigIssue` с путём `subagents.max_depth` и итоговым значением 3; третье принимается

#### Scenario: Проект не повышает глубину
- **WHEN** глобальный слой задаёт `max_depth: 2`, а проект — `max_depth: 3`
- **THEN** итоговое значение 2, лог `config.project.untrusted_key`

#### Scenario: Дескрипторы в реестре
- **WHEN** запускается `settings_registry_complete_test.dart`
- **THEN** каждый ключ `subagents.*` таблицы покрыт дескриптором `shared` с совпадающими `min`/`max`; опакового дескриптора `subagents` нет

#### Scenario: Запись через config set
- **WHEN** выполняется `codelab-agent config set subagents.max_concurrent 9`, затем `… 2`
- **THEN** первая команда отклоняется проверкой `ConfigWriter` с проблемой `subagents.max_concurrent` (CLI — код `64`, как у любого ключа с `min`/`max`), байты файла не меняются; вторая записывает значение, и после применения перезагрузки следующий `spawn` использует 2 слота без перезапуска агента

#### Scenario: Глубина 1
- **WHEN** `subagents.max_depth: 1`
- **THEN** у ребёнка нет `agent`, описание `agent` корня содержит `Subagents you start cannot start other subagents.`
