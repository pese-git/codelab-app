## ADDED Requirements

### Requirement: Ошибка запуска агента в test-scenario без аргументов
Если агент фикстуры не запускается, строка `FAIL` драйвера (`the agent did not run the fixture: <причина>`) SHALL называть причину без аргументов команды агента: для `ProcessException` — только текст ОС (`ProcessException.message`), для остальных ошибок — прежний `describeFailure` (design.md change `redact-cli-stdio-profile-args`, D9). Значения аргументов stdio-профиля, в том числе подставленный путь `{fixture}`, НЕ SHALL попадать в stdout и stderr драйвера; код выхода `1` не меняется.

#### Scenario: Несуществующая команда агента
- **WHEN** запускается `codelab test-scenario <каталог фикстур> --agent 'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789 {fixture}'`
- **THEN** строки фикстур — `FAIL` с причиной `the agent did not run the fixture: …`, код выхода `1`; ни stdout, ни stderr не содержат `sk-test-leak-0123456789`, `--api-key` и `Command:`
