## ADDED Requirements

### Requirement: Тип подключения «Встроенный агент»
Диалог подключения CodeLab SHALL предлагать третий тип подключения `Embedded agent` рядом с `stdio` и `WebSocket` (design.md change `add-embedded-agent-mode`, D9). У типа нет полей. Рабочая папка выбирается «Open Project», как у других типов. Конфигурация агента берётся из `$CODELAB_HOME/config.yaml` и проектного `.codelab/config.yaml`, ключи — из хранилища секретов агента. Подключение SHALL строить профиль `ConnectionProfile.embedded(hostProfile: 'embedded-app-desktop')`, а транспорт ему даёт `EmbeddedTransportResolver`, зарегистрированный в composition root (`apps/codelab_desktop/lib/app/`). Виджеты и Cubit-ы НЕ SHALL импортировать `package:codelab_embedded/io.dart`. Тип подключения по умолчанию в форме остаётся `stdio`.

Требования к поведению:
- **Невалидная или отсутствующая конфигурация** встроенного агента SHALL переводить подключение в `ConnectionFailed` (design.md change `add-embedded-agent-mode`, D13, п. 2). Баннер соединения SHALL показывать текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет.
- **Нет ключа провайдера**: подключение SHALL открываться. Первый ход с этим провайдером SHALL завершаться ошибкой провайдера с именем секрета без значения и показываться заметкой «Failed turn» (требование «Failed turn notice with Retry»), как у внешнего агента. Отдельной проверки готовности провайдера при подключении нет.
- **Одобрения, очередь промптов, список сессий, отмена хода и транскрипт** встроенного агента SHALL работать теми же компонентами, что для внешнего агента.
- **Обрыв соединения** (отказ встроенного агента, `ConnectionLost`) SHALL отображаться так же, как обрыв внешнего агента.

#### Scenario: Выбор встроенного агента
- **WHEN** пользователь открывает диалог подключения, выбирает `Embedded agent` и нажимает `Connect` при выбранном проекте
- **THEN** CodeLab подключается к встроенному агенту без запуска дочернего процесса, а метка подключения — `Embedded agent`

#### Scenario: Нет конфигурации встроенного агента
- **WHEN** `$CODELAB_HOME` не содержит `config.yaml`, и пользователь подключается типом `Embedded agent`
- **THEN** подключение в состоянии `ConnectionFailed`, баннер показывает проблему конфигурации и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — путь `CODELAB_HOME`

#### Scenario: Невалидный проектный конфиг встроенного агента
- **WHEN** выбранный проект содержит `.codelab/config.yaml` с `budget.max_steps: 0`, и пользователь подключается типом `Embedded agent`
- **THEN** подключение в состоянии `ConnectionFailed`, баннер называет файл, строку и ключ `budget.max_steps` и содержит ту же подсказку

#### Scenario: Нет ключа провайдера
- **WHEN** `config.yaml` валиден и задаёт провайдера с `api_key_secret: codelab/p`, секрет `codelab/p` не задан, и пользователь подключается типом `Embedded agent` и отправляет промпт
- **THEN** подключение установлено, ход завершается заметкой «Failed turn» с ошибкой провайдера, называющей `codelab/p`, без значения секрета

#### Scenario: Одобрение во встроенном режиме
- **WHEN** встроенный агент спрашивает одобрение `write` в режиме `standard`, и пользователь выбирает вариант отказа в карточке одобрения
- **THEN** файл не изменён, а строка вызова в транскрипте показывает отказ
