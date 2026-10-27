## Purpose

Планка тестирования и качества workspace, которой CodeLab придерживается сам: Melos-скрипты, по которым проверяется каждое изменение, и многоуровневое тестовое покрытие (протокол, core state, stdio-интеграция, Flutter UI), на котором держится Definition of Done для задач реализации.
## Requirements
### Requirement: Проверки workspace
CodeLab SHALL предоставлять Melos-скрипты для format, analyze, test, protocol conformance, сторожа архитектуры (`guard`), компиляции ядра агента для web (`web-compile`) и полной проверки. Конфигурация Melos SHALL храниться в одном месте — секции `melos:` корневого `pubspec.yaml`. Полная проверка `check` SHALL включать `check-format`, `analyze`, `guard`, `test`, `protocol-conformance` и `web-compile`.

#### Scenario: Запускается полная проверка
- **WHEN** в развёрнутом workspace выполняется `fvm dart run melos run check`
- **THEN** форматирование, анализ, сторож, тесты, protocol conformance и web-компиляция ядра проходят либо сообщают конкретные, действенные ошибки

#### Scenario: Протокол изменился
- **WHEN** меняются модели, кодеки или потоки протокола ACP
- **THEN** запускается `fvm dart run melos run protocol-conformance`

#### Scenario: Один источник конфигурации Melos
- **WHEN** выполняется `fvm dart run melos list` или любой скрипт из прежнего `melos.yaml`
- **THEN** команда работает, а файла `melos.yaml` в корне нет

#### Scenario: Сборка бинаря агента
- **WHEN** выполняется `fvm dart run melos run build:agent`
- **THEN** появляется исполняемый файл `build/bin/codelab-agent`, который отвечает на `initialize` по stdio; скрипт не входит в `check` (design.md change `add-codelab-agent-binary`, D9)

### Requirement: Модульные тесты протокола
CodeLab SHALL тестировать encode/decode протокола, обработку неизвестных полей, валидацию невалидных сообщений и отображение протокольных ошибок.

#### Scenario: Декодируются неизвестные поля
- **WHEN** валидное сообщение ACP включает `_meta` или совместимые с будущим поля
- **THEN** round-trip encode/decode сохраняет поддерживаемые данные расширения

#### Scenario: Декодируется невалидное сообщение
- **WHEN** получены невалидные данные ACP
- **THEN** тесты подтверждают типизированную протокольную ошибку вместо падения приложения

### Requirement: Тесты core state
CodeLab SHALL тестировать переходы состояния сессии, обработку дублирующихся событий потока, политику approval и пути отмены.

#### Scenario: Получено дублирующееся событие потока
- **WHEN** fake transport эмитирует одно и то же обновление-снимок (не чанк содержимого) дважды
- **THEN** видимое состояние содержит одну логическую запись сообщения/tool/approval

#### Scenario: Снимок возвращается к прежнему значению
- **WHEN** fake transport эмитирует `plan` A, `plan` B и снова `plan` A в одном ходе
- **THEN** тесты подтверждают, что текущий план равен A

#### Scenario: Получены одинаковые чанки содержимого
- **WHEN** fake transport эмитирует один и тот же `agent_message_chunk` дважды
- **THEN** тесты подтверждают, что в ходе две дельты и склеенный текст полный

#### Scenario: Отмена происходит при ожидающих approval
- **WHEN** отмена происходит при наличии ожидающих запросов разрешения
- **THEN** тесты подтверждают, что каждый запрос получает outcome cancelled

### Requirement: Интеграционные тесты stdio
CodeLab SHALL тестировать stdio-интеграцию с `codelab-agent` либо совместимым тестовым двойником, использующим ту же семантику запуска/профиля. E2E-тесты `apps/codelab_desktop/integration_test/` SHALL параметризоваться агентом через `--dart-define=CODELAB_E2E_AGENT=scripted|dart` (по умолчанию `scripted`) и помощник `integration_test/support/e2e_agent.dart`; в режиме `dart` агент — бинарь `CODELAB_E2E_AGENT_BIN` со сценарием `integration_test/llm_scripts/<режим>.json`. Тесты поведения именно scripted-агента SHALL иметь тег `scripted-only` и исключаться в режиме `dart`. Код `apps/codelab_desktop/lib` для этого НЕ SHALL меняться. Прогон на устройстве или симуляторе (`melos run test:e2e:app:dart-agent`) SHALL выполняться только в ветке `release/<version>`; в feature-ветке тесты SHALL проходить статический анализ.

#### Scenario: Референсный агент инициализируется
- **WHEN** тест stdio-интеграции запускает настроенную команду
- **THEN** CodeLab завершает `initialize` ACP

#### Scenario: Prompt turn стримит
- **WHEN** интеграционный тест отправляет `session/prompt`
- **THEN** CodeLab получает потоковые `session/update` и финальный ответ на prompt

#### Scenario: Тест в режиме Dart-агента
- **WHEN** `permission_flow_test.dart` запускается с `CODELAB_E2E_AGENT=dart`
- **THEN** карточка одобрения показывает команду `echo hello` из аргументов вызова `exec` — она же заголовок вызова

#### Scenario: Тест только для scripted-агента
- **WHEN** e2e-прогон идёт с `--exclude-tags scripted-only`
- **THEN** тест `agent dying mid-turn` не запускается

### Requirement: Тесты Flutter UI
CodeLab SHALL тестировать состояния соединения, поведение prompt composer, рендеринг потокового transcript, approvals, видимость отмены, состояния ошибок и layout workbench.

#### Scenario: Рендерится UI approval
- **WHEN** состояние approval передано в UI
- **THEN** inline approval и детали инспектора видны с элементами approve/reject

#### Scenario: Рендерится следующее действие для состояния ошибки
- **WHEN** UI получает состояние disconnected или failed
- **THEN** он показывает понятную пользователю сводку и конкретное действие для восстановления

### Requirement: Соблюдение Definition of Done
CodeLab SHALL рассматривать тесты, архитектурные границы, политику безопасности и требования UI/UX как критерии приёмки для задач реализации.

#### Scenario: Задача реализации завершена
- **WHEN** задача помечена выполненной
- **THEN** релевантные тесты проходят, и задача удовлетворяет Definition of Done из спеки

### Requirement: Непрерывная интеграция
CodeLab SHALL запускать CI (`.github/workflows/ci.yml`) на каждый pull request и на push в `master` и `develop`. Обязательные джобы `format`, `analyze`, `test`, `conformance`, `guard` и `web-compile` SHALL запускать соответствующие Melos-скрипты на FVM-закреплённом SDK. Ночной запуск по расписанию SHALL прогонять те же джобы. Интеграционные тесты в CI SHALL выполняться только на Dart VM (`ubuntu-latest`); Flutter-тесты приложения на macOS (`test:e2e:app:*`) в CI НЕ SHALL запускаться — это локальные приёмочные ворота этапа. Шаблон pull request SHALL содержать чек-лист: OpenSpec change, тесты, сторонний код.

#### Scenario: Pull request с нарушением
- **WHEN** открыт pull request, в котором нарушен формат, анализ, тест, сторож или web-компиляция
- **THEN** соответствующий джоб CI красный

#### Scenario: Интеграционные тесты на Dart VM
- **WHEN** CI запускается на pull request, push или по расписанию
- **THEN** интеграционные тесты чистых Dart-пакетов (реальные процессы и сокеты `codelab_acp_transports`) выполняются в джобе `test` на `ubuntu-latest`, а джобов на macOS в workflow нет

#### Scenario: Шаблон pull request
- **WHEN** автор открывает pull request на GitHub
- **THEN** описание заполнено чек-листом из `.github/pull_request_template.md` с пунктами об OpenSpec change, тестах и стороннем коде

### Requirement: Клиентская conformance-проверка на корпусе фикстур
CodeLab SHALL проигрывать каждую golden-фикстуру с ролью `client` против `AcpClientApplication` тестом `packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart`. Melos-скрипт `conformance:client` SHALL запускать эту проверку и SHALL входить в полную проверку `check` и в джоб CI `conformance`.

#### Scenario: Корпус этапа 0 проходит
- **WHEN** выполняется `fvm dart run melos run conformance:client`
- **THEN** все 12 фикстур этапа 0 с ролью `client` проходят

#### Scenario: Полная проверка включает клиентский прогон
- **WHEN** выполняется `fvm dart run melos run check` или джоб CI `conformance`
- **THEN** запускается и `protocol-conformance`, и `conformance:client`

### Requirement: Характеризационные тесты фасада приложения
Перенос логики клиента из `CodeLabShellCubit` в `codelab_client_core` SHALL быть защищён характеризационными тестами публичной поверхности Cubit в `apps/codelab_desktop/test/features/workbench/application/shell_cubit_characterization/`: подключение, сессии, промпты и очередь, отмена, опции конфигурации, одобрения, переподключение. Тесты SHALL создавать Cubit через граф cherrypick app (`CodeLabTestBinding`) с `FakeAcpTransport`, проверять только публичные методы и поля `CodeLabShellState` и конечные состояния, а не число промежуточных `emit`. Тесты SHALL быть зелёными до первого переноса и после каждой итерации change без изменения их текста; тексты 8 интеграционных тестов `apps/codelab_desktop/integration_test/` на время переноса НЕ SHALL меняться.

#### Scenario: Тесты пишутся до переноса
- **WHEN** открывается первый PR change `extract-acp-client-kit`
- **THEN** он содержит только характеризационные тесты, код `apps/codelab_desktop/lib` не изменён, и тесты зелёные

#### Scenario: Перенос не меняет тесты
- **WHEN** итерация переносит часть логики Cubit в kit
- **THEN** характеризационные тесты и `test/widget_test.dart` зелёные без правок, а `fvm dart analyze` собирает интеграционные тесты

### Requirement: Интеграционный тест Reconnect посреди хода
CodeLab SHALL проверять Reconnect посреди хода интеграционным тестом в `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart` в режиме `CODELAB_E2E_AGENT=dart`. Тест SHALL сам запускать `codelab-agent serve --ws` со сценарием `--llm-script` долгого хода и `--sessions-dir` во временной папке и подключать app по WebSocket. Процесс агента переживает Reconnect, поэтому тест проверяет отмену хода самим агентом. В режиме `scripted` тест SHALL пропускаться.

#### Scenario: Reconnect посреди хода по WebSocket
- **WHEN** app отправляет промпт, сценарий агента отвечает с задержкой, а тест вызывает `Reconnect` до ответа
- **THEN** после переподключения активна та же сессия, лента показывает реплику и «Completed with stopReason cancelled.», `isPromptSubmitting` и `canCancel` — `false`, а следующий промпт получает ответ агента

### Requirement: Интеграционный тест списка и загрузки сессий
CodeLab SHALL проверять список и загрузку сессий интеграционным тестом `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart` в обоих режимах e2e-агента. В режиме `scripted` агент — режим `withSessionList` из `codelab_acp_testing`, агент со списком и загрузкой сессий, которые переживают перезапуск его процесса. В режиме `dart` агент — бинарь `codelab-agent` со сценарием `--llm-script` и `--sessions-dir` во временной папке теста: без журнала на диске агент не объявляет `loadSession` (change `add-llm-script-session-store`). Тест SHALL покрывать сайдбар со списком сессий проекта, загрузку выбранной сессии, загрузку открытой сессии после `Reconnect` и перезапуск app с теми же `SharedPreferences`. Перед каждым e2e-тестом снимок рабочего пространства в `SharedPreferences` SHALL удаляться, чтобы восстановление одного теста не влияло на другой.

#### Scenario: Перезапуск app восстанавливает активную сессию
- **WHEN** тест создаёт две сессии, отправляет промпт в одну, закрывает корневой scope app и создаёт его заново с теми же значениями `SharedPreferences`, затем подключается
- **THEN** сайдбар показывает обе сессии, активная сессия загружена через `session/load`, и её транскрипт совпадает с транскриптом до перезапуска

#### Scenario: Снимок не переходит между тестами
- **WHEN** e2e-тест начинается после теста, который сохранил снимок рабочего пространства
- **THEN** подключение в новом тесте не запускает восстановление сессий прошлого теста

