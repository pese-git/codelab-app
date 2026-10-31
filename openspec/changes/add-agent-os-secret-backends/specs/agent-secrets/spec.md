## ADDED Requirements

### Requirement: Бэкенды хранилища ОС
`codelab_agent_io` SHALL предоставлять бэкенды `DescribedSecretStore`:
- `keychain-macos` — утилита `/usr/bin/security`;
- `secret-service` — `secret-tool`;
- `wincred` — Windows Credential Manager через `CredWriteW`, `CredReadW`, `CredDeleteW`, `CredEnumerateW`;

Служба — `codelab`, учётная запись — имя секрета; у `wincred` цель — `codelab:<name>`, тип `CRED_TYPE_GENERIC`, значение — UTF-16LE. Значение секрета НЕ SHALL передаваться в argv дочернего процесса: только через stdin. Оболочка НЕ SHALL использоваться. Каждое обращение к хранилищу ОС SHALL ограничиваться 10 с; по истечении процесс утилиты убивается, а результат вызова `wincred` отбрасывается, итог — `SecretStoreUnavailableException` с причиной `<tool> did not answer within 10 s`. Текст исключения НЕ SHALL включать stdout и stderr утилиты и значение. Значение с `\n` или `\r` SHALL отклоняться при записи всеми бэкендами; значение длиннее 1280 UTF-16 единиц SHALL отклоняться `wincred`. 

`dart:ffi` и `package:ffi/` SHALL импортироваться в `codelab_agent_io` только из `lib/src/secrets/wincred/`; логика `wincred` SHALL работать через порт `WinCredApi`, чтобы её тесты шли на любой ОС.

`names()`:
- у `keychain-macos` и `secret-service` SHALL читать индекс `$CODELAB_HOME/secret-names.json`, где хранятся только имена: файл с правами `0600`, записанный атомарно. Индекс SHALL сверяться с хранилищем без вывода значений в лог. Битый индекс SHALL давать пустой список и предупреждение `secrets.index.unreadable {path}`, а не ошибку чтения секрета;
- у `wincred` SHALL перечислять цели `codelab:*` через `CredEnumerateW` без перевода значений в строки; индекс не используется.

#### Scenario: Значение только в stdin
- **WHEN** `write("codelab/openai", "sk-test-0123456789abcdef")` выполняется на `keychain-macos` и на `secret-service` с фейковым `SecretProcessRunner`
- **THEN** ни один элемент `arguments` ни одного вызова не содержит значения, значение есть только в `stdin`

#### Scenario: Таймаут утилиты
- **WHEN** фейковый запуск `secret-tool lookup` не завершается
- **THEN** `read` бросает `SecretStoreUnavailableException` с причиной `secret-tool did not answer within 10 s` (время фейковое), процесс помечен убитым

#### Scenario: Не найдено
- **WHEN** утилита чтения завершается кодом «не найдено» (по итогам разведки, design.md, D2), а фейковый `WinCredApi` — ошибкой `1168`
- **THEN** `read` возвращает `null`, а не исключение

#### Scenario: Список без значений
- **WHEN** записаны `codelab/a` и `codelab/b`, затем `codelab/a` удалён в обход агента
- **THEN** `names()` возвращает `[codelab/b]`, индекс обновлён, файл индекса не содержит значений

#### Scenario: wincred на фейковом API
- **WHEN** `WincredSecretStore` с фейковым `WinCredApi` записывает `codelab/openai`, читает его и перечисляет имена на macOS или Linux
- **THEN** фейк получил цель `codelab:codelab/openai` и пользователя `codelab/openai`, чтение вернуло значение, `names()` — `[codelab/openai]`; значение длиной 1281 символ отклонено без вызова API

### Requirement: Выбор хранилища ОС в auto
`secrets.backend: auto` SHALL выбирать бэкенд при первом обращении к хранилищу, а не при старте: macOS с `/usr/bin/security` → `keychain-macos`; Linux с `secret-tool` в `PATH`, заданным `DBUS_SESSION_BUS_ADDRESS` и успешной пробой за 3 с → `secret-service`; Windows с загруженной `advapi32.dll` → `wincred`; иначе → `env` с `unavailableReason` и одним предупреждением `secrets.backend.unavailable`. `auto` НЕ SHALL выбирать `file`. `secrets.backend: keychain` SHALL проверять хранилище ОС при старте хоста; недоступно — `serve` завершается кодом `1` с текстом `secrets.backend is keychain, but the OS keychain is unavailable: <reason>`.

#### Scenario: Linux без D-Bus
- **WHEN** `auto` на Linux, `secret-tool` есть в `PATH`, `DBUS_SESSION_BUS_ADDRESS` не задан
- **THEN** бэкенд — `env` с причиной `DBUS_SESSION_BUS_ADDRESS is not set`, одно предупреждение, ни одного процесса `secret-tool`

#### Scenario: Windows выбирает wincred
- **WHEN** `auto` на Windows (подменённая платформа и фабрика `WinCredApi` в тесте), библиотека загружается
- **THEN** бэкенд — `wincred`, `secrets.backend.selected {backend: wincred}`

#### Scenario: auto по-прежнему не выбирает file
- **WHEN** `auto` на macOS с доступной связкой ключей, а в `$CODELAB_HOME` лежит `secrets.yaml`
- **THEN** бэкенд — `keychain-macos`, файл не читается

#### Scenario: keychain без хранилища ОС
- **WHEN** `serve` запускается с `secrets.backend: keychain` на Linux без `secret-tool`
- **THEN** код `1` до старта транспорта, stderr содержит `the OS keychain is unavailable`
