## ADDED Requirements

### Requirement: Интеграционный тест палитры с командами агента
CodeLab SHALL проверять команды агента в палитре интеграционным тестом `apps/codelab_desktop/integration_test/command_palette_flow_test.dart` (строка Must R-20 матрицы паритета) на scripted-агенте в режиме `withAvailableCommands` из `codelab_acp_testing`. Режим SHALL объявлять после `session/new` команды `compact` без `input` и `plan` с `input.hint` и отвечать на промпт `/compact` отчётом о сжатии. В режиме `CODELAB_E2E_AGENT=dart` тест SHALL пропускаться (`skip`, а не тег `scripted-only`: тег исключил бы единственный тест файла), пока бинарь `codelab-agent` объявляет пустой `availableCommands`. Тест SHALL покрывать открытие палитры по `Ctrl/Cmd+K`, вытеснение заглушки клиента, вставку команды в композер без `session/prompt`, отправку, нечёткий поиск inline-триггера `/` и выполнение команды клиента без `session/prompt`.

#### Scenario: Команда агента доходит до агента
- **WHEN** агент объявил `compact`, пользователь открывает палитру `Ctrl/Cmd+K`, выбирает `compact` и отправляет промпт из композера
- **THEN** до отправки агент не получил `session/prompt`, после отправки получил `session/prompt` с текстом `/compact`, а лента показывает реплику `/compact` и ответ агента об успешном сжатии

#### Scenario: Команда клиента выполняется в app
- **WHEN** пользователь выбирает в палитре `/new`
- **THEN** создаётся новая сессия, а агент не получает `session/prompt`
