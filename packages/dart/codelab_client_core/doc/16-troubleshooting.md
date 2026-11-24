# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет клиентский слой или встраивает его в хост. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты ошибок, диагностики и имена событий взяты из кода пакета; рядом указан файл или тест. Случаи, помеченные «проверено запуском», воспроизведены в прогоне 2026-11-25.

Случаи по теме:

- сборка и тесты: [нет `*.freezed.dart`](#нет-freezeddart-при-сборке-и-тестах), [тесты печатают JSON](#тесты-печатают-json-в-stdout), [тест зависает на ожидании запроса](#тест-зависает-на-ожидании-запроса), [сторож упал на списке зависимостей](#сторож-melos-run-guard-упал-на-списке-зависимостей);
- подключение: [`connect` завершился, а `Connected` нет](#connect-завершился-а-connected-нет), [«No transport resolver supports profile»](#no-transport-resolver-supports-profile), [`ConnectionLost` и что дальше](#connectionlost-и-что-дальше), [WebSocket: «agent requires a token»](#websocket-the-agent-requires-a-token);
- сессии: [сессия `detached`](#сессия-detached), [список сессий пуст](#список-сессий-пуст), [сессия `notLoaded` не открывается после перезапуска](#сессия-notloaded-не-открывается-после-перезапуска), [`restoreProject()` вернул `null`](#restoreproject-вернул-null);
- промпты и одобрения: [промпт не уходит](#промпт-не-уходит), [`send` из обработчика ломает публикацию](#send-из-обработчика-ломает-публикацию), [промпт ушёл раньше очереди](#промпт-ушёл-раньше-очереди), [ответ на одобрение завершился ошибкой](#ответ-на-одобрение-завершился-ошибкой);
- расход и кадры: [usage `unknown`](#usage-unknown-или-не-обновляется), [кадры без payload](#кадры-без-payload), [диагностика не доходит до журнала](#диагностика-не-доходит-до-журнала);
- профили: [профиль не сохранился](#профиль-не-сохранился-или-остался-секрет).

## Нет `*.freezed.dart` при сборке и тестах

**Симптом.** `dart analyze` или `dart test` падает на модели слоя. Проверено запуском на `queue/prompt_queue.dart` без сгенерированного файла:

```text
error - prompt_queue.dart:5:6 - Target of URI doesn't exist: 'package:codelab_client_core/src/queue/prompt_queue.freezed.dart'. … - uri_does_not_exist
error - prompt_queue.dart:13:34 - Classes can only mix in mixins and classes. - mixin_of_non_class
error - prompt_queue.dart:15:7 - The name '_QueuedPrompt' isn't a type and can't be used in a redirected constructor. … - redirect_to_non_class
```

**Причина.** Модели слоя — `freezed`, а `*.freezed.dart` в git не хранятся (`.gitignore`). В чистом worktree или после правки модели файла нет.

**Что сделать.** Выполнить генерацию из [главы 0](00-getting-started.md#подготовка-репозитория) (`build_runner build --delete-conflicting-outputs`). CI создаёт файлы шагом `Generate code`.

## Тесты печатают JSON в stdout

**Симптом.** Вывод `fvm dart test` забит записями с полями `logger`, `category`, `component`, `event`.

**Причина.** Ядро клиента и `ClientWorkspace` без параметра `logger` (он создаёт `StructuredLogLogger('codelab_client_core')`) пишут журнал в stdout; `KitAgent` логгер не подменяет. Это не ошибка.

**Что сделать.** Запускать узкие тесты с `--reporter expanded` или фильтровать вывод; чтобы читать записи слоя, передать `ClientWorkspace(logger: RecordingLogger())` (как `UsageAgent`).

## Тест зависает на ожидании запроса

**Симптом.** Тест висит на `agent.next(метод)` или падает через 3 секунды: `TestFailure: No <метод> request #N was sent.` (`GatedWorkspace.nextRequest`).

**Причина.** Запрос не отправлен, либо подписка на `FakeAcpTransport.sent` оформлена после действия. `sent` — broadcast-поток: событие, пришедшее до подписки, потеряно.

**Что сделать.** Сначала `final request = agent.next(метод)`, потом действие, потом `await request`. Если слой ждёт ответа на `initialize`, проверьте, что `FakeAcpTransport.autoRespondToInitialize` не выключен ([глава 14](14-testing.md)).

## Сторож `melos run guard` упал на списке зависимостей

**Симптом.** `fvm dart test packages/dart/codelab_architecture_tests` падает: `not in allowlist: <пакет>` или запрещённый импорт.

**Причина.** В `pubspec.yaml` слоя появилась зависимость вне `kitAllowlist` либо в `lib/**` импортирован `dart:io`, Flutter, `package:intl` или `package:codelab_acp_transports/io.dart` (`test/support/rules.dart`, `test/pubspec_allowlist_test.dart`).

**Что сделать.** Убрать импорт или зависимость. Нужен доступ к файлам, процессам или платформе — объявить порт в слое, а реализацию положить в `codelab_client_io` или composition root. Расширение списка зависимостей — только через OpenSpec change.

## `connect` завершился, а `Connected` нет

**Симптом.** `await workspace.connect(…)` вернулся без ошибки, но `workspace.current.connection` — `Connecting`, `Reconnecting` или не тот профиль.

**Причина.** Попытка вытеснена: повторный `connect`, `reconnect` или `ensureAgent` начался, пока `open` ещё шёл. Вытесненная попытка завершается без ошибки и без изменения состояния ([глава 3](03-connection.md)).

**Что сделать.** Читать итог из `workspace.state` и `current`, а не из `Future`. Проверить, не вызывает ли хост `connect` из нескольких мест; для параллельных триггеров использовать `ensureAgent` (single-flight).

## «No transport resolver supports profile»

**Симптом.** `ConnectionFailed(startFailed)` с сообщением `No transport resolver supports profile "<label>".` и исключение `UnsupportedConnectionProfileException` (проверено запуском).

**Причина.** В `ClientWorkspace(resolvers: …)` нет резолвера, у которого `supports(profile)` истинен. Для `EmbeddedProfile` `ConfigTransportResolver` не годится по определению: нужен резолвер встроенного агента из composition root. Для stdio или WebSocket не передана фабрика (`stdio:` или `webSocket:`).

**Что сделать.** Зарегистрировать резолвер. Порядок списка важен: берётся первый подходящий. [Рецепт](15-extending.md#рецепт-свой-резолвер-транспорта).

## `ConnectionLost` и что дальше

**Симптом.** Хост показывает баннер «соединение потеряно», сессия не отвечает.

**Причина.** Транспорт установленного соединения оборвался сам (процесс агента завершился, сокет закрылся). Слой публикует `ConnectionLost` и диагностику `Connection to ACP agent lost: <причина>`; идущий ход завершается ошибкой, ожидающие одобрения снимаются.

**Что сделать.** Дать пользователю Reconnect (`workspace.reconnect()`): после успеха сессии загружаются заново или становятся `detached`. Автоповтора у слоя нет. Прогон сценария — в [главе 3](03-connection.md).

## WebSocket: «the agent requires a token»

**Симптом.** Подключение к WebSocket-агенту падает с отказом рукопожатия, `describeConnectFailureByToken` дал `the agent requires a token (HTTP 401)`.

**Причина.** Токен не ушёл серверу: переменная `env:<NAME>` не задана или пуста, секрет `secret:<имя>` отсутствует, либо ссылка неподдерживаемая (`UnsupportedTokenRef`: голое имя, `secret:` с недопустимым именем, искажённый `env:`) — тогда подключение идёт без токена. Если токен ушёл, текст — `the agent rejected the token (HTTP 401)`: сервер его не принял.

**Что сделать.** Проверить ссылку (`ProfileTokenRef.parse`), переменную окружения процесса клиента или секрет в хранилище. Перед подключением хост может записать `secretMissingWarning(profileId)` для `secret:` без значения. [Глава 12](12-profiles-and-secrets.md).

## Сессия `detached`

**Симптом.** Статус `detached`, в ленте заметка `The agent cannot restore sessions after reconnecting.` или `Session <id> could not be restored after reconnecting.`; `send` возвращает `PromptFailed` с `Session <id> is detached from the agent.` (проверено запуском).

**Причина.** После `connect` или `reconnect` новое соединение сессию не знает: агент не объявил `loadSession` либо `session/load` не удался. Слой не подменяет сессию новой — потерялся бы контекст.

**Что сделать.** Для агента с `loadSession` — вызвать `workspace.loadSession(id, cwd: …)` по фокусу на сессии: при успехе связь возвращается, заметка снимается, очередь сливается. Иначе открыть новую сессию. Очередь `detached`-сессии сохраняется. [Глава 4](04-sessions.md).

## Список сессий пуст

**Симптом.** `WorkspaceState.sessions` не содержит сессий агента, `hasMoreSessions` ложно.

**Причина.** Агент не объявил `sessionCapabilities.list`, либо нет `projectDirectory` (агент поднят `ensureAgent` без выбранного проекта: ACP без `cwd` вернул бы сессии всех папок). Первый `session/list` уходит после `connect` и `reconnect` и при `selectProject` на подключённом агенте.

**Что сделать.** Проверить возможности агента и вызвать `selectProject(path)`. Сбой запроса — диагностика `Failed to list ACP sessions: …`, соединение остаётся. [Глава 4](04-sessions.md).

## Сессия `notLoaded` не открывается после перезапуска

**Симптом.** После перезапуска хоста сессия из снимка осталась строкой `notLoaded`, хотя была активной.

**Причина.** `cwd` активной сессии снимка не равен проекту снимка (точное равенство строк): такую сессию слой не загружает и не активирует, чтобы не отдать агенту лишнюю папку (D10 change `require-project-folder`). Либо снимок прочитан после первого подключения.

**Что сделать.** Открыть сессию явным выбором хоста: `loadSession(id, cwd: …)`. [Глава 5](05-restore.md).

## `restoreProject()` вернул `null`

**Симптом.** Снимок был, а проект не вернулся.

**Причина.** Вариантов четыре: не передан `snapshots:`; хост уже вызвал `startWithoutRestore()` (второй метод после первого — пустая операция); снимок битый или другой версии — диагностика `Workspace snapshot is invalid; starting fresh.`, и снимок удалён; чтение завершилось ошибкой (`Failed to read workspace snapshot: …`). В CLI восстановления нет вовсе: он `snapshots:` не передаёт.

**Что сделать.** Читать диагностику `source: restore`. Хост вызывает ровно один из двух методов. [Глава 5](05-restore.md).

## Промпт не уходит

**Симптом.** `send` вернул `PromptQueued`, а `session/prompt` не уходит.

**Причина.** Очередь сливается, только когда сессия свободна (не `running` и не `cancelling`), связь `attached` и соединение `Connected`. Отказывает любое из трёх условий: ход идёт, сессия `detached` или переподключается, соединение потеряно.

**Что сделать.** Смотреть `SessionView.status` и `ConnectionView`. После `reconnect` очередь сливается, когда сессия загружена в новом соединении. Для `detached` вернуть связь `loadSession`. [Глава 6](06-prompt-and-queue.md).

## `send` из обработчика ломает публикацию

**Симптом.** Промпты, отправленные из обработчика `SessionHandle.view`, завершаются `PromptFailed Bad state: Cannot fire new event. Controller is already firing an event`, а очередь пустеет (проверено запуском).

**Причина.** Потоки слоя синхронные; обработчик выполняется внутри `add` потока, и `send` в нём меняет сессию, то есть публикует в тот же поток вложенно.

**Что сделать.** Не вызывать методы слоя, меняющие состояние, из обработчиков `state`, `view` и `promptOutcomes` напрямую: вынести вызов в микрозадачу (`scheduleMicrotask`) или в обработчик действия пользователя. [Глава 6](06-prompt-and-queue.md).

## Промпт ушёл раньше очереди

**Симптом.** Порядок `session/prompt`: `first`, `third`, затем `second`, хотя `second` стоял в очереди раньше (проверено запуском).

**Причина.** Между концом хода и сливом очереди сессия на одну ревизию `idle` при непустой очереди. `send` в этом окне видит свободную сессию и отправляет промпт сразу.

**Что сделать.** Не отправлять новый промпт, пока `SessionView.queue` не пуста; ставить его в конец очереди. Это известное ограничение слоя, а не поведение, закреплённое спецификацией. [Глава 6](06-prompt-and-queue.md).

## Ответ на одобрение завершился ошибкой

**Симптом.** `SessionHandle.respond` бросает `StateTransitionException: permission request is not pending`, ответ агенту не ушёл.

**Причина.** Одобрение уже не ожидает: решено, снято при замене транспорта (`reconnect`, `connect`) или потере соединения, либо принадлежит другой сессии. Решение для одного вызова не переносится на другой.

**Что сделать.** Показывать только то, что есть в `SessionView.pendingApprovals`; после смены соединения список обновляется сам. Запрос нового соединения с тем же JSON-RPC `id` — новый запрос. [Глава 8](08-approvals.md).

## Usage `unknown` или не обновляется

**Симптом.** `SessionView.usage.support` — `unknown` или `awaiting`, числа не растут.

**Причина.** `unknown`: агент не объявил `usage` и снимков не было — например, сторонний агент. `awaiting`: объявил, но снимок ещё не пришёл (агент CodeLab присылает первый снимок только после первого хода). Числа стоят на месте — снимки с `seq` не больше последнего (`usage.stale` в журнале kit), например при перезапуске агента без смены поколения. Журнал не запрашивается сам: `usageLedger` — `idle` до `refreshUsageLedger`.

**Что сделать.** Подключить `Logger` к `ClientWorkspace` и читать `usage.*`. Помнить: расход сбрасывается при смене соединения и при `session/load`. [Глава 10](10-usage.md).

## Кадры без payload

**Симптом.** `ProtocolFrameLog.frames` содержит кадры с `payload == null`, `payloadOmitted == policy`.

**Причина.** Базовая политика `ProtocolPayloadPolicy.metadataOnly` (по умолчанию). Режим Trace включается явно и действует только на новые кадры.

**Что сделать.** `workspace.protocolFrames.setTrace(true)` при `traceAvailable`; в CLI — запуск с `--verbose` (политика `full`). Если `traceAvailable == false`, базовая политика уже `full`, и Trace не нужен. [Глава 11](11-inspector-diagnostics-frames.md).

## Диагностика не доходит до журнала

**Симптом.** События слоя (`Failed to send prompt: …`) нигде не видны.

**Причина.** `ClientWorkspace.diagnostics` — поток событий, а не журнал. Слой сам ничего не пишет; хост обязан подписаться.

**Что сделать.** Подписаться на `workspace.diagnostics` и писать `source` и `message` в журнал хоста. [Глава 11](11-inspector-diagnostics-frames.md).

## Профиль не сохранился или остался секрет

**Симптом.** `ProfileCommitter.save` вернул `ProfileSaveFailed`, а в хранилище секретов остался токен.

**Причина.** Порядок записи — «секрет, затем профиль»; если профиль записать не удалось, созданный секрет откатывается. Откат тоже может не удаться (`orphanedSecret` заполнено), например при бэкенде «только чтение». Если `reason` — `secretReadOnly`, секрет не записан вовсе, а `storeReason` несёт причину хранилища.

**Что сделать.** Показать пользователю `orphanedSecret` и подсказку удалить его (`codelab secret delete <имя>`); хост пишет в журнал `errorType`, а не текст ошибки. Запись `default` в `profiles.json` хранилище не прячет: слой даёт `usableStoredProfiles`, а игнорирует её потребитель (CLI, страница «Connection»). [Глава 12](12-profiles-and-secrets.md).
