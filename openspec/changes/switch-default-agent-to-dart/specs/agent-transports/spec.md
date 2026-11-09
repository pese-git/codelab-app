## MODIFIED Requirements

### Requirement: Референсный профиль codelab-agent
CodeLab SHALL предоставлять встроенное описание stdio-агента `codelabAgentStdioProfile` (основной барель `codelab_acp_transports`) для Dart-агента CodeLab (задача 9.3; design.md change `switch-default-agent-to-dart`, D10). Значения описания:
- имя — `codelab-agent (stdio)`;
- команда — `codelab-agent`;
- аргументы — `serve --stdio`;
- env — `CODELAB_LOG_LEVEL=DEBUG`.

Описание SHALL быть единственным источником значений по умолчанию команды и аргументов stdio-черновика профиля подключения (`ProfileDraft`, `codelab_client_core`): «Command» — `codelab-agent`, «Arguments» — `serve --stdio`.

Описание НЕ SHALL сохраняться в `profiles.json` и НЕ SHALL показываться на странице «Connection» отдельной строкой. Профиль по умолчанию в app и CLI — встроенный агент (capability `app-settings` «Список профилей на странице «Connection»», capability `codelab-cli` «Профили подключения CLI»).

Ни встроенное описание, ни значение по умолчанию какого-либо черновика профиля НЕ SHALL содержать команду `codelab` с аргументом `serve`: после переключения команда `codelab` принадлежит терминальному клиенту.

#### Scenario: Описание указывает на Dart-агента
- **WHEN** код читает `codelabAgentStdioProfile`
- **THEN** имя — `codelab-agent (stdio)`, команда — `codelab-agent`, аргументы — `['serve', '--stdio']`, env — `{'CODELAB_LOG_LEVEL': 'DEBUG'}`, `cwd` не задан

#### Scenario: Описание подключается
- **WHEN** stdio-транспорт открывается с аргументами и env `codelabAgentStdioProfile`, а команда заменена запуском бинаря `apps/codelab_agent` из исходников (тест бинаря, сценарий `--llm-script`)
- **THEN** процесс агента принимает аргументы `serve --stdio`, и `initialize` ACP получает ответ `protocolVersion: 1`

#### Scenario: Черновик «Add profile» совпадает с описанием
- **WHEN** создаётся stdio-черновик `ProfileDraft` без явных значений команды и аргументов
- **THEN** его команда и аргументы равны команде и аргументам `codelabAgentStdioProfile`

#### Scenario: Нет умолчаний Python-агента
- **WHEN** проверяются `codelabAgentStdioProfile` и значения по умолчанию `ProfileDraft`
- **THEN** ни одно из них не содержит команду `codelab` с аргументом `serve`
