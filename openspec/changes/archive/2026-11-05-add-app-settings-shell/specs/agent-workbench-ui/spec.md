## MODIFIED Requirements

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the active profile is the embedded agent, stdio or WebSocket. Whether a stdio agent process starts in the project directory SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6).

#### Scenario: Project applies to a WebSocket session
- **WHEN** CodeLab is connected via WebSocket and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected falls back to the current process directory
- **WHEN** the user creates a session and no project has been explicitly selected
- **THEN** CodeLab uses the same fallback it uses today (the CodeLab process's own current directory) as the session's `cwd`

#### Scenario: Switching connection does not clear the selected project
- **WHEN** the user reconnects or connects another profile from the Connection settings page while a project is selected
- **THEN** the selected project remains the same, and is used for the next session created after the switch

#### Scenario: stdio process runs from the project directory by default
- **WHEN** the current profile is a stdio profile with `Run in the project folder` on, and a project is selected (or none is, falling back to the current process directory)
- **THEN** CodeLab spawns the agent process with that same directory as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** the current profile is a stdio profile with `Run in the project folder` off
- **THEN** CodeLab spawns the agent process without an explicit working directory override, while the selected project's path is still sent as `cwd` in `session/new` for sessions created afterward

### Requirement: Тип подключения «Встроенный агент»
Встроенный агент SHALL быть первой строкой списка профилей страницы настроек «Connection» (spec app-settings «Список профилей на странице «Connection»»), а не типом в форме подключения (design.md change `add-app-settings-shell`, D6). У строки нет полей. Рабочая папка выбирается «Open Project», как у других профилей. Конфигурация агента берётся из `$CODELAB_HOME/config.yaml` и проектного `.codelab/config.yaml`, ключи — из хранилища секретов агента.

Подключение SHALL строить профиль `ConnectionProfile.embedded(id: 'embedded', hostProfile: 'embedded-app-desktop')`, а транспорт ему даёт `EmbeddedTransportResolver`, зарегистрированный в composition root (`apps/codelab_desktop/lib/app/`). Виджеты и Cubit-ы НЕ SHALL импортировать `package:codelab_embedded/io.dart`.

Без сохранённого выбора профиля по умолчанию профилем по умолчанию SHALL быть встроенный агент; профиль `default` из `profiles.json` app не учитывает (design.md change `add-app-settings-shell`, D5).

Требования к поведению:
- **Невалидная или отсутствующая конфигурация** встроенного агента SHALL переводить подключение в `ConnectionFailed` (design.md change `add-embedded-agent-mode`, D13, п. 2). Баннер соединения SHALL показывать текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет.
- **Нет ключа провайдера.** Подключение SHALL открываться. Первый ход с этим провайдером SHALL завершаться ошибкой провайдера с именем секрета без значения и показываться заметкой «Failed turn» (требование «Failed turn notice with Retry»), как у внешнего агента. Отдельной проверки готовности провайдера при подключении нет.
- **Одобрения, очередь промптов, список сессий, отмена хода и транскрипт** встроенного агента SHALL работать теми же компонентами, что для внешнего агента.
- **Обрыв соединения** (отказ встроенного агента, `ConnectionLost`) SHALL отображаться так же, как обрыв внешнего агента.
- **Повторный Connect во время подключения** встроенного агента SHALL прерывать прежнюю попытку без промежуточного `ConnectionFailed`: баннер соединения показывает подключение новой попытки, агент прерванной попытки освобождается резолвером (требование acp-client-kit «Явный автомат соединения»; design.md change `add-embedded-agent-mode`, D6).
- **Закрытие root scope** SHALL ждать остановки встроенного агента не дольше 10 s. По истечении приложение SHALL писать событие `embedded.close_timeout` уровня `warning` без текста ошибки и продолжать освобождение транспорта и `AcpClientApplication` (D9).

#### Scenario: Выбор встроенного агента
- **WHEN** пользователь открывает страницу настроек «Connection» и нажимает «Connect» в строке «Embedded agent» при выбранном проекте
- **THEN** CodeLab подключается к встроенному агенту без запуска дочернего процесса, а метка подключения — `Embedded agent`

#### Scenario: Встроенный агент по умолчанию
- **WHEN** CodeLab запускается впервые с пустым `CODELAB_HOME`, и пользователь нажимает «Connect» на экране подключения
- **THEN** CodeLab подключается к встроенному агенту

#### Scenario: Нет конфигурации встроенного агента
- **WHEN** `$CODELAB_HOME` не содержит `config.yaml`, и пользователь подключается к встроенному агенту
- **THEN** подключение в состоянии `ConnectionFailed`, баннер показывает проблему конфигурации и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — путь `CODELAB_HOME`

#### Scenario: Невалидный проектный конфиг встроенного агента
- **WHEN** выбранный проект содержит `.codelab/config.yaml` с `budget.max_steps: 0`, и пользователь подключается к встроенному агенту
- **THEN** подключение в состоянии `ConnectionFailed`, баннер называет файл, строку и ключ `budget.max_steps` и содержит ту же подсказку

#### Scenario: Нет ключа провайдера
- **WHEN** `config.yaml` валиден и задаёт провайдера с `api_key_secret: codelab/p`, секрет `codelab/p` не задан, и пользователь подключается к встроенному агенту и отправляет промпт
- **THEN** подключение установлено, ход завершается заметкой «Failed turn» с ошибкой провайдера, называющей `codelab/p`, без значения секрета

#### Scenario: Одобрение во встроенном режиме
- **WHEN** встроенный агент спрашивает одобрение `write` в режиме `standard`, и пользователь выбирает вариант отказа в карточке одобрения
- **THEN** файл не изменён, а строка вызова в транскрипте показывает отказ

#### Scenario: Повторный Connect во время подключения встроенного агента
- **WHEN** пользователь подключается к встроенному агенту, и, пока агент ещё открывается, снова нажимает `Connect`
- **THEN** баннер соединения не показывает `ConnectionFailed` прерванной попытки, подключение завершается исходом второй попытки, а агент первой попытки остановлен

#### Scenario: Зависшая остановка встроенного агента
- **WHEN** root scope закрывается, а остановка встроенного агента не завершается за 10 s
- **THEN** в логе приложения есть `embedded.close_timeout` уровня `warning`, а транспорт и `AcpClientApplication` освобождены

## REMOVED Requirements

### Requirement: Connection profile is edited in a modal dialog
**Reason**: Форма одного несохраняемого профиля заменена списком профилей на странице настроек «Connection» и диалогом «Add connection profile», общими с CLI (`~/.codelab/profiles.json`; `dart-agent-and-clients` §12.4.9; design.md change `add-app-settings-shell`, D6).

**Migration**: «Configure connection» на экране подключения и в баннере соединения и кнопка «Settings» в сайдбаре открывают страницу «Connection». Своего агента пользователь один раз сохраняет через «Add profile». Поле «Run agent from project directory» стало полем stdio-профиля «Run in the project folder». Данных для переноса нет: форма не сохранялась (D7).
