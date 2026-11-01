> **Черновик, после 1.0.** Решения перенесены из change `add-agent-secret-store` при сужении задачи 8.9 (решение пользователя 2026-10-31): в 1.0 агент хранит секреты в переменных `CODELAB_SECRET_*` и в файле `secrets.yaml`, а хранилища ОС подключаются этим change позже. Реализация начинается только после архивации `add-agent-secret-store`; до неё порт `SecretStore`, `SecretResolver`, `openSecretStore`, `SecretAdmin`, подкоманды `secret` и тексты D-решений 8.9 считаются данностью. Перед стартом решения перепроверяются (версии утилит, `package:ffi`, условие D16 change 8.9 о готовой библиотеке).

## Context

После 8.9 (`add-agent-secret-store`) есть:
- порт ядра `SecretStore`/`DescribedSecretStore`, `SecretResolver` (кэш → `CODELAB_SECRET_*` → хранилище), ленивое разрешение ссылок;
- бэкенды `env` (только чтение) и `file` (`$CODELAB_HOME/secrets.yaml`, `0600`), `auto` = `env` на всех ОС, `keychain` — проблема конфига «not supported yet»;
- `SecretProcessRunner` (порт запуска процесса; в 8.9 нужен для `chmod` файла `file`), `openSecretStore`, `openHostSecrets`, `SecretAdmin`, `SecretCommands`.

Этот change добавляет три бэкенда ОС за тем же портом: вызывающие (резолвер, подкоманды, `config check`, встроенные профили) не меняются.

**Сверка с итогом 8.9 (2026-11-01, итерация 5 change `add-agent-secret-store`).** Код 8.9, на который опирается черновик:
- `codelab_agent_io/lib/src/secrets/secret_process_runner.dart`: `SecretProcessRunner.run(executable, arguments, {String? stdin, Duration? timeout})`, `SecretProcessResult` — только `exitCode` и `timedOut`; `IoSecretProcessRunner` запускает процесс без оболочки и **без окружения родителя** (`includeParentEnvironment: false`), stdout и stderr вычитывает и отбрасывает. Расширение порта — D2 ниже;
- `secretsBackendProblem(choice, platform)` (`secrets_backend_problem.dart`) — одна проверка `secrets.backend` у `ConfigLoader`, `openSecretStore` и `FileSecretStore`; сейчас `keychain` даёт `keychain is not supported yet (supported: auto, env, file)`. Этот change снимает проблему для `keychain` в этой функции, а не в каждом вызывающем (D5);
- `openSecretStore({choice, environment, home, logger, runner, platform, selectionReason})` — синхронная фабрика: выбирает бэкенд и сразу пишет `secrets.backend.selected {backend, path, reason}`; причина `auto` — `OS keychain backends are not available in this version; …` (на Windows без `secrets.backend: file`). Ленивый выбор D5 должен уложиться в эту сигнатуру или явно её изменить (OQ3);
- `openHostSecrets({codelabHome, environment, backend, debug, logger, platform, runner, selectionReason})` — синхронная, вызывается внутри isolate ядра; `AgentHost` под `--llm-script` передаёт `backend: 'env'` и `selectionReason: 'forced by --llm-script'` — сценарий не должен запускать пробы хранилищ ОС и после этого change;
- `AgentHost.build` превращает `SecretStoreUnavailableException` из `openHostSecrets` в ошибку использования (код `64`, `secrets.backend: <reason>`); D5 ниже называет для недоступного `keychain` код `1` — расхождение решается при старте (OQ4);
- `FileSecretStore` пишет через приватный `$CODELAB_HOME/.secrets-tmp` (`0700`), проверяет владельца `$CODELAB_HOME` no-op `chmod`, держит одну очередь записей на нормализованный путь и удаляет брошенные tmp старше 10 минут; индекс имён D3 пишется тем же механизмом, а не своим tmp рядом с файлом;
- `SecretAdmin` (`store`/`delete`/`list`/`checkStore`, результаты `SecretStored` … `SecretReadOnly {backend, variable, fileBackendOffered}`) и `SecretCommands` не меняются: при бэкенде ОС ветка `SecretReadOnly` просто не возникает; меняются только тексты причины `auto` в `openSecretStore` и подсказки, которые на неё ссылаются (`config check`, `secret set` при `env`);
- общие пределы значения — `secretValueProblem` (`secret_value_checks.dart`: одна строка, 64 КиБ UTF-8, без непарных суррогатов); бэкенды ОС применяют её до своих пределов (`wincred` — 1280 UTF-16 единиц);
- поле `path` события `secrets.backend.selected` по §12.3 — путь `secrets.yaml` или `null`; путь утилиты (`secret-tool`) пишется в него только с правкой §12.3.

## Goals / Non-Goals

**Goals:** P-12 целиком — ключи в хранилище ОС на macOS, Linux и Windows; `auto` выбирает хранилище ОС; значение никогда не в argv.

**Non-Goals:** смена порта ядра; шифрованный файл; мобильные и web-хранилища (D16 change 8.9).

## Decisions

### D1. `ffi` в allowlist `codelab_agent_io` и правило сторожа

**Allowlist `codelab_agent_io` меняется: добавляется `ffi`** (решение пользователя 2026-10-31 по OQ1 change `add-agent-secret-store`; перенесено сюда при сужении 8.9).
- **Почему.** Бэкенд `wincred` вызывает `CredWriteW`/`CredReadW`/`CredDeleteW`/`CredEnumerateW` из `advapi32.dll` через `dart:ffi`. Голому `dart:ffi` не хватает аллокатора нативной памяти (`calloc`, `free`) и перевода строк в UTF-16 (`toNativeUtf16`). Своя аллокация через `HeapAlloc` из `kernel32` — лишний нативный код с теми же рисками, а `package:ffi` — маленький пакет команды Dart (`tools.dart.dev`, BSD-3-Clause, все нативные платформы). Он уже в `pubspec.lock` транзитивно через `dart_tui`, поэтому в workspace не появляется новая технология (`AGENTS.md` §4).
- **`package:win32` не берётся.** Нужны четыре функции и две структуры (`CREDENTIALW`, `FILETIME`). Свои привязки на несколько десятков строк меньше и проще проверить, чем большой пакет с генерированными привязками всего Win32 (§13).
- **Где.** `dart:ffi` и `package:ffi/` импортируются только из `codelab_agent_io/lib/src/secrets/wincred/`. Это новое правило сторожа в `rules.dart`: `PackageRule('packages/dart/codelab_agent_io/lib/src', forbidden: ['dart:ffi', 'package:ffi/'], exclude: ['secrets/wincred/'], sealExclude: false)`. Остальной пакет не получает FFI случайно, а `WincredSecretStore` работает через порт `WinCredApi`, поэтому тестируется без Windows (D4).
- **Проверка.** `pubspec_allowlist_test.dart`: `ioAllowlist` получает `ffi`, плюс тест «IO-пакет агента может зависеть от ffi, ядро — нет» (`coreAllowlist` не меняется). `import_guard_test.dart` получает случай нового правила. Красные тесты сторожа идут первыми (задачи 2.1–2.2).
- **Документы.** Allowlist §1.2 (`agent-core/01-layers-and-packages.md`), `codelab_agent_io/AGENTS.md` §2 и `technology-stack.md` (запись о `ffi` как прямой зависимости `codelab_agent_io`) — задача 0.2.


### D2. Бэкенды на утилитах ОС (`keychain-macos`, `secret-service`)

```dart
/// codelab_agent_io/lib/src/secrets/secret_process_runner.dart — порт есть с 8.9 (D5 change 8.9);
/// этот change добавляет два необязательных элемента, не меняя вызывающих 8.9.
abstract interface class SecretProcessRunner {
  /// stdin пишется целиком и закрывается; по истечении timeout процесс убивается.
  /// environment — явный список переменных для дочернего процесса (новое); окружение
  /// родителя целиком по-прежнему не передаётся.
  Future<SecretProcessResult> run(String executable, List<String> arguments,
      {String? stdin, Duration? timeout, Map<String, String>? environment});
}
/// stdout — новое необязательное поле: нужно чтению секрета; stderr по-прежнему
/// вычитывается и отбрасывается.
final class SecretProcessResult { final int exitCode; final bool timedOut; final String? stdout; }
```

Порт узкий и свой, а не общий `ExecutionEnv.exec`:
- `exec` работает в границе `BoundedEnv`, с allowlist окружения и выводом для модели;
- утилитам секретов нужен stdin и несколько переменных хоста (`DBUS_SESSION_BUS_ADDRESS`, по итогам разведки 0.1 — возможно `XDG_RUNTIME_DIR`): они передаются явным списком через `environment`, а не окружением родителя целиком — в нём `CODELAB_SECRET_*` и ключи провайдеров (D5 change 8.9);
- их stdout нельзя ни логировать, ни буферизовать в общем выводе.

Реализация — `IoSecretProcessRunner` (`Process.start`, `runInShell: false`, `includeParentEnvironment: false`). Тестовая — фейк `test/support/fake_secret_process_runner.dart`, записывающий `executable`, `arguments` и `stdin`. Бэкенды ОС передают `timeout` всегда (10 с).

| Бэкенд | Запись | Чтение | Удаление | Ошибки |
|---|---|---|---|---|
| `keychain-macos` | `/usr/bin/security -i`, в stdin — строка `add-generic-password -U -s codelab -a <name> -w "<value>"\n` (экранирование — по итогу разведки 0.1) | `/usr/bin/security find-generic-password -s codelab -a <name> -w` → stdout без завершающего `\n` | `/usr/bin/security delete-generic-password -s codelab -a <name>` | код «не найдено» (по разведке; ожидается `44`) → `null` / «не было»; иной код → `SecretStoreUnavailableException(reason: "security exited with code <n>")` |
| `secret-service` | `secret-tool store --label "CodeLab: <name>" service codelab account <name>`, значение — stdin без `\n` | `secret-tool lookup service codelab account <name>` → stdout | `secret-tool clear service codelab account <name>` | пустой stdout и код по разведке → `null`; иначе — исключение с кодом |
| `wincred` | `CredWriteW` через `WinCredApi` (D4) | `CredReadW` | `CredDeleteW` | D4 |
| `file` | `$CODELAB_HOME/secrets.yaml`, атомарно, `0600` (D14 change 8.9) | тот же файл; права шире `0600` → отказ | ключ удаляется из файла | D14 change 8.9 (без изменений) |
| `env` | `SecretStoreUnavailableException("env backend is read-only")` | `CODELAB_SECRET_<…>` | то же исключение, что у записи | — |

Правила для всех бэкендов (у `wincred` и `file` процессов нет — к ним относятся пункты про значение, таймаут и перевод строки):
- **Значение никогда не в argv** — ни у утилиты, ни у оболочки (оболочка не используется). Тест проверяет каждую запись фейка: значение не входит ни в один элемент `arguments`.
- **Абсолютный путь** `/usr/bin/security` на macOS: подмена через `PATH` исключена. `secret-tool` ищется в `PATH` один раз при выборе бэкенда (D5); найденный абсолютный путь пишется в `secrets.backend.selected`.
- **stderr утилиты не попадает ни в текст ошибки, ни в лог**, только код выхода: в некоторых режимах утилита может повторить ввод. Порт 8.9 stderr вычитывает и отбрасывает, и этот change это сохраняет (прежний вариант «stderr в лог под `--debug-secrets`, усечённый до 200 символов» снят при сверке с 8.9: он требовал бы протаскивать stderr через порт и вычищать из него значение). Причина — фиксированный текст и код.
- **stdout чтения** возвращается вызывающему и больше нигде не хранится и не логируется.
- **Таймаут 10 с** на вызов. По истечении процесс убивается, результат — `SecretStoreUnavailableException(reason: "<tool> did not answer within 10 s")`. Почему 10 с: первое обращение к Secret Service может поднимать демон связки ключей, а ход не должен висеть дольше таймаута соединения провайдера.
- **Перевод строки в значении** (`\n`, `\r`) отклоняется при записи, у всех бэкендов: `security -i` читает по строкам, `secret-tool` хранил бы перевод буквально, а одинаковое правило у всех бэкендов не даёт секрету «не переехать» между ними. Ключи API однострочны.

**Разведка 0.1** (исключение (д), не дольше одного дня) уточняет на macOS и Linux:
- экранирование `"` и `\` в `security -i`; если оно ненадёжно — такие значения отклоняются при записи с понятной ошибкой;
- что `security -i` без TTY не повторяет команду в stdout или stderr;
- коды «не найдено» у `find-`/`delete-generic-password` и `secret-tool lookup`/`clear`;
- команду пробы Secret Service, которая не печатает значений.

Итоги вписываются в этот D2 и в §17.5.4 до тестов итерации 1.


### D3. Список имён у бэкендов ОС

| Бэкенд | Источник `names()` |
|---|---|
| `keychain-macos`, `secret-service` | индекс `$CODELAB_HOME/secret-names.json` (ниже) |
| `wincred` | `CredEnumerateW(L"codelab:*", 0)`: из каждой записи берётся только `TargetName` без префикса `codelab:`; `CredentialBlob` в строку Dart не переводится, массив освобождается `CredFree` (D4). Индекс не нужен: перечисление — штатный API без вывода значений наружу |
| `file` | ключи файла `secrets.yaml` (D14 change 8.9) |
| `env` | имена переменных `CODELAB_SECRET_*` (необратимы, поэтому `list` показывает их строкой `Environment overrides`) |

**Индекс macOS и Linux.** `names()` у `keychain-macos` и `secret-service` читает индекс `$CODELAB_HOME/secret-names.json`: `{"version": 1, "names": [...]}`, только имена. Запись — атомарно, права `0600`, тем же механизмом, что у `FileSecretStore` 8.9 (приватный `.secrets-tmp`, проверка владельца `$CODELAB_HOME`, очередь записей на путь); механизм выносится в общую функцию, а не копируется. `write` добавляет имя, `delete` убирает. `names()` сверяет индекс с хранилищем проверкой существования и отбрасывает исчезнувшие имена: пользователь мог удалить запись в «Связке ключей».
- **Проверка существования.** macOS — `security find-generic-password -s codelab -a <name>` без `-w`: значение не выводится. Linux — `lookup`: значение читается в память процесса и сразу отбрасывается.

**Отступление от §17.5.4 для Linux.** Документ предлагал `secret-tool search --all service codelab`, но эта команда печатает значения (`secret = …`) всех найденных записей. Индекс одинаков на обеих платформах, и значения при `list` не читаются массово. Поправка документа — задача 0.1.

Индекс — не источник истины для чтения: `read` идёт прямо в хранилище. Потерянный или битый индекс даёт пустой `list` и предупреждение `secrets.index.unreadable {path}`, но не ломает разрешение секретов.


### D4. Бэкенд `wincred` (решение пользователя 2026-10-31, OQ1 change `add-agent-secret-store`)

```dart
/// codelab_agent_io/lib/src/secrets/wincred_secret_store.dart — без dart:ffi
abstract interface class WinCredApi {
  String? read(String target);                 // null — ERROR_NOT_FOUND (1168)
  void write(String target, String userName, String value);
  bool delete(String target);                  // false — записи не было
  List<String> enumerate(String filter);       // только TargetName
}
final class WinCredException implements Exception { final String function; final int error; }
final class WincredSecretStore implements DescribedSecretStore {
  WincredSecretStore({required WinCredApi Function() api, String service = 'codelab'});
}
/// codelab_agent_io/lib/src/secrets/wincred/ffi_win_cred_api.dart — единственное место с dart:ffi и package:ffi
final class FfiWinCredApi implements WinCredApi { … }
```

- **Привязки.** `DynamicLibrary.open('advapi32.dll')`, `lookupFunction` для `CredWriteW`, `CredReadW`, `CredDeleteW`, `CredEnumerateW`, `CredFree` с `isLeaf: true`, чтобы `GetLastError` (`kernel32`) читался сразу после вызова. Своя `Struct` `CREDENTIALW` (`Flags`, `Type`, `TargetName`, `Comment`, `LastWritten: FILETIME`, `CredentialBlobSize`, `CredentialBlob`, `Persist`, `AttributeCount`, `Attributes`, `TargetAlias`, `UserName`). `package:win32` не используется (D1).
- **Запись.** Цель `<service>:<name>` (`codelab:codelab/openai`), `Type = CRED_TYPE_GENERIC`, `Persist = CRED_PERSIST_LOCAL_MACHINE` (§17.5.4), `UserName` — имя секрета. Значение — UTF-16LE без завершающего нуля, как у записей, которые создаёт «Диспетчер учётных данных». Предел `CRED_MAX_CREDENTIAL_BLOB_SIZE` (2560 байт) → значение длиннее 1280 UTF-16 единиц отклоняется: `secret value is too long for Windows Credential Manager (max 1280 characters)`. Буфер значения выделяется `calloc`, после вызова заполняется нулями и освобождается.
- **Чтение и перечисление.** `CredReadW` → значение из `CredentialBlob`, затем `CredFree`. `ERROR_NOT_FOUND` → `null`. `CredEnumerateW(L"<service>:*", 0)` → только `TargetName` без префикса; `CredentialBlob` перечисленных записей в строки Dart не переводится; `ERROR_NOT_FOUND` → пустой список. Индекс имён не нужен (D3).
- **Ошибки.** Иной код → `WinCredException`, бэкенд переводит её в `SecretStoreUnavailableException(reason: "<function> failed with error <n>")` без значения.
- **Таймаут.** Вызовы FFI синхронны и блокировали бы изолят хоста. `WincredSecretStore` выполняет каждый вызов в `Isolate.run` (порт создаётся фабрикой `api` внутри изолята: `DynamicLibrary` не пересылается) с пределом 10 с, как у утилит (D2). Прервать нативный вызов нельзя: по таймауту результат отбрасывается, изолят доживает до возврата из `advapi32`.
- **Выбор.** `auto` и `keychain` на Windows выбирают `wincred`, если `advapi32.dll` загрузилась и функции найдены (D5). На macOS и Linux `FfiWinCredApi` не создаётся.
- **Тестируемость.** Вся логика бэкенда — над портом `WinCredApi`, поэтому тесты идут на любой ОС (D6). Нативный путь проверяет только ручной тест `os-keychain` на Windows (пока не выполняется, D6).

Альтернативы:
- (а) `cmdkey`/PowerShell процессом. Отклонена: `cmdkey` не читает пароль обратно, а `/pass:<value>` кладёт значение в argv.
- (б) `package:win32`. Отклонена: большой пакет ради четырёх функций (D1).


### D5. `auto` и `keychain` с хранилищем ОС

Меняется только `openSecretStore` (change 8.9, D7):
- `auto` выбирает лениво, при первом обращении (как это совместить с синхронными `openSecretStore`/`openHostSecrets` и геттером `backend` — OQ3): macOS с `/usr/bin/security` → `keychain-macos`; Linux с `secret-tool` в `PATH`, `DBUS_SESSION_BUS_ADDRESS` и успешной пробой за 3 с → `secret-service`; Windows с загруженной `advapi32.dll` → `wincred`; иначе `env` с причиной и одним `secrets.backend.unavailable`.
- `auto` по-прежнему **никогда не выбирает `file`** (OQ2 change 8.9).
- `keychain` перестаёт быть проблемой «not supported yet» — правка одной `secretsBackendProblem` (8.9): проба при старте хоста, недоступно → `serve` код `1` с текстом `secrets.backend is keychain, but the OS keychain is unavailable: <reason>` (в 8.9 `AgentHost` переводит отказ `openHostSecrets` в код `64` — OQ4).
- `--llm-script` по-прежнему выбирает `env` без проб (`selectionReason: forced by --llm-script`, D11 change 8.9).
- Пользователь, который в 1.0 выбрал `file`, переносит секреты сам: `codelab secret set` при `auto` и удаление файла. Автоматического переноса нет: открытый файл не должен «тихо» переезжать (решение — при старте change, OQ2 ниже).

### D6. Тесты

- Бэкенды ОС — на фейковом `SecretProcessRunner` (`secret_store_backends_test.dart`: значение только в stdin, коды «не найдено», таймаут, перевод строки) и фейковом `WinCredApi` (`wincred_secret_store_test.dart`, `win_cred_bindings_test.dart`) — на любой ОС, в `melos run test`.
- Настоящие хранилища — `os_keychain_test.dart` с тегом `os-keychain`, объявленным в `packages/dart/codelab_agent_io/dart_test.yaml` со `skip`; служба `codelab-test-<pid>`, временный `CODELAB_HOME`, удаление в `tearDown`. Ручной запуск `fvm dart test -t os-keychain --run-skipped` на macOS и Linux; CI его не запускает.
- Windows: ручной прогон пока не выполняется — `wincred` проверен только на фейке (OQ6 change 8.9, 2026-10-31): известный пробел, не блокирует выпуск; вернуться, когда появится машина или CI с Windows.

### D7. Desktop: App Sandbox и `wincred` из isolate ядра

**macOS App Sandbox.** Сейчас у `apps/codelab_desktop` `com.apple.security.app-sandbox = false` (`macos/Runner/DebugProfile.entitlements`, `Release.entitlements`), поэтому запуск `/usr/bin/security` работает так же, как из CLI. Если sandbox будет включён (например, для Mac App Store), дочерний процесс унаследует sandbox и потеряет доступ к записям службы `codelab`, созданным CLI. Тогда бэкенд `keychain-macos` для desktop нужно пересмотреть отдельным change: Keychain Services через `dart:ffi` (`Security.framework`) или плагин с общей группой доступа (`keychain-access-groups`), с теми же службой и учётными записями. Условие пересмотра — правка entitlements; оно записывается в §17.5.4.

**`wincred` из isolate ядра.** `Isolate.run` можно вызывать из любого isolate, в том числе из isolate ядра, а `DynamicLibrary.open('advapi32.dll')` выполняется внутри короткого isolate (D4). Credential Manager привязан к сеансу пользователя процесса, а не к потоку, поэтому вызов из рабочего isolate видит те же записи. Ручная проверка на Windows отложена (OQ6, известный пробел); когда появится Windows, проверить тестом `os-keychain`: запуск из основного isolate и из `Isolate.spawn`-изолята, который сам вызывает `Isolate.run`.


## Risks / Trade-offs

- **[Значение в argv]** → только stdin; тесты на фейке проверяют каждый вызов.
- **[`security -i` и экранирование]** → разведка 0.1 до кода; запасной путь — отказ записи значений с `"` и `\`.
- **[Зависание связки ключей]** → предел 10 с на вызов; ненайденное не кэшируется, поэтому при недоступном Secret Service ход может ждать до 10 с; предупреждение один раз на причину.
- **[Окно связки ключей macOS]** → записи, созданные не через `/usr/bin/security`, могут вызвать окно доступа.
- **[Нативный код `wincred`]** → смещения `CREDENTIALW` проверяются тестом на любой ОС, `CredFree` и обнуление буфера — в `finally`; нативный путь на Windows не проверяется до появления машины или CI (OQ6).
- **[Зависший вызов `advapi32`]** → таймаут отбрасывает результат, изолят живёт до возврата (D4).
- **[Sandbox macOS]** → пересмотр `keychain-macos` при включении App Sandbox (D7).
- **[Allowlist]** → `ioAllowlist` получает `ffi`; FFI ограничен каталогом `secrets/wincred/` (D1).

## Migration Plan

1. Итерация 0 — разведка утилит, документы (`01-layers-and-packages.md` §1.2, `technology-stack.md`, `codelab_agent_io/AGENTS.md`).
2. Итерация 1 — `keychain-macos`, `secret-service`, индекс, ручной `os-keychain` на macOS и Linux.
3. Итерация 2 — сторож (`ffi`), `wincred`.
4. Итерация 3 — `auto`/`keychain` в `openSecretStore`, документы, матрица P-12 «выполнено».

Откат: возвращает `auto` к `env`; записи в хранилищах ОС и индекс остаются, их удаляет `codelab secret delete` или менеджер паролей.

## Open Questions

Решения, принятые в change 8.9 и перенесённые сюда (2026-10-31): OQ1 — `wincred` за портом `WinCredApi` со своими привязками `advapi32` и `ffi` в `ioAllowlist`; OQ6 — ручной прогон на Windows не обязателен, пробел известен.

Открыты (решаются при старте change):
- **OQ1. Перенос секретов из `secrets.yaml` в хранилище ОС.** (а) Рекомендуется: без автоматики, подсказка в `config check` при `secrets.backend: file` и доступном хранилище ОС. (б) Команда `codelab secret migrate`.
- **OQ2. Перепроверка условия D16 change 8.9** — если к старту появилась зрелая библиотека без Flutter от подтверждённого издателя, бэкенды берутся из неё.
- **OQ3. Ленивый выбор и синхронная фабрика.** `openSecretStore` и `openHostSecrets` 8.9 синхронны, `DescribedSecretStore.backend` — синхронный геттер, а его id нужен строке `Backend:` в `secret list`, `note: secrets backend` в `config check` и `SecretMissing.backend`. Варианты: (а) обёртка-хранилище, которая пробует при первом `read`/`write`/`names`, а до пробы отдаёт `backend.id` `auto`; (б) асинхронная фабрика (`Future<DescribedSecretStore>`) с пробой при старте — меняет сигнатуры 8.9 и вызов внутри isolate ядра. Решается при старте; критерий — не ломать вызывающих 8.9 без нужды.
- **OQ4. Код выхода при недоступном `keychain`.** D5 называет `1`, а `AgentHost` 8.9 отдаёт отказ `openHostSecrets` как ошибку использования `64`. Либо `keychain` без хранилища — проблема конфигурации (`64`, как в 8.9), либо отдельная ветка с кодом `1`; спецификация agent-secrets меняется вместе с решением.
