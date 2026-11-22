## MODIFIED Requirements

### Requirement: Изоляция process execution за platform-boundary
Реализация запуска и управления процессами SHALL находиться в infrastructure-слое приложения и SHALL NOT быть доступна напрямую из `domain`, `application` или `presentation`, и SHALL оставаться независимой от порта `UserShellLauncher` и владельца вкладок панели Terminal (`integrated-terminal`, «Терминал пользователя независим от ACP terminal/*»).

#### Scenario: Domain/application не содержат прямых вызовов dart:io Process
- **WHEN** запускается статический анализ `packages/dart/codelab_client_acp`
- **THEN** пакет не импортирует `dart:io` для управления процессами напрямую, а обращается к ним через порт/интерфейс, реализуемый в `apps/codelab_desktop`
