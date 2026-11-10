## MODIFIED Requirements

### Requirement: Интеграционный тест палитры с командами агента
CodeLab SHALL проверять команды агента в палитре интеграционным тестом `apps/codelab_desktop/integration_test/command_palette_flow_test.dart` (строка Must R-20 матрицы паритета) на scripted-агенте в режиме `withAvailableCommands` из `codelab_acp_testing`. Режим SHALL объявлять после `session/new` команды `compact` без `input` и `plan` с `input.hint` и отвечать на промпт `/compact` отчётом о сжатии. Файл SHALL содержать два теста (design.md change `add-agent-builtin-slash-commands`, D9): тест с тегом `scripted-only` — полный сценарий на scripted-агенте (вытеснение заглушки `/plan`, команда `plan` с `input.hint`); и тест без тега, который идёт во всех режимах (`scripted`, `dart`, `embedded`) и проверяет встроенную команду агента `compact`: вытеснение заглушки клиента `/compact`, вставку в композер без `session/prompt` и отправку промпта `/compact`. Ответ агента на `/compact` в разных режимах разный (отчёт scripted-агента; `Nothing to compact.` или `Compacted: …` у Dart-агента) и SHALL браться из помощника `integration_test/support/e2e_agent.dart`. Пропуск по `!isScripted` убирается: Dart-агент объявляет `compact` (capability `agent-slash-commands`, «Встроенные команды MVP»). Тест SHALL покрывать открытие палитры по `Ctrl/Cmd+K`, вытеснение заглушки клиента, вставку команды в композер без `session/prompt`, отправку, нечёткий поиск inline-триггера `/` и выполнение команды клиента без `session/prompt`.

#### Scenario: Команда агента доходит до агента
- **WHEN** агент объявил `compact`, пользователь открывает палитру `Ctrl/Cmd+K`, выбирает `compact` и отправляет промпт из композера
- **THEN** до отправки агент не получил `session/prompt`, после отправки получил `session/prompt` с текстом `/compact`, а лента показывает реплику `/compact` и ответ агента на неё

#### Scenario: Палитра против Dart-агента
- **WHEN** тест без тега идёт в режиме `CODELAB_E2E_AGENT=dart` или `embedded`
- **THEN** тест не пропускается: палитра показывает `/compact` агента вместо заглушки клиента, отправка даёт в ленте реплику `/compact` и ответ Dart-агента из помощника `e2e_agent.dart`

#### Scenario: Команда клиента выполняется в app
- **WHEN** пользователь выбирает в палитре `/new`
- **THEN** создаётся новая сессия, а агент не получает `session/prompt`
