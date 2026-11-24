# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет `codelab_setup` или подключает его к клиенту. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты ошибок и имена событий взяты из кода; рядом указан файл, где они появляются, а там, где текст получен запуском, это сказано.

Случаи по теме:

- снимок и запись: [`StateError` при чтении расширений](#stateerror-the-config-snapshot-has-no-loaded-configuration), [слой не прочитан](#слой-конфига-не-прочитан), [`ConfigConflict` повторяется](#configconflict-повторяется), [`ConfigInlineSecret`](#configinlinesecret-при-записи-mcp), [источник ключа пропал](#источник-ключа-пропал-или-назван-неверно), [ошибка `CODELAB_HOME`](#ошибка-codelab_home);
- мастер провайдера: [мастер не реагирует на событие](#мастер-не-реагирует-на-событие), [проверка называет TLS недоступностью](#проверка-называет-ошибку-tls-недоступностью), [проверка не поддерживается](#проверка-models-не-поддерживается), [мастер вернулся на шаг ключа](#мастер-вернулся-на-шаг-ключа-после-save), [ключ найден в хранилище, а статус «missing»](#статус-ключа-missing-хотя-секрет-записан);
- удаление и очистка секретов: [секрет остался после удаления](#секрет-остался-после-удаления);
- MCP: [форма отклоняет переименование](#форма-отклоняет-переименование);
- настройки: [строка настроек не правится](#строка-настроек-не-правится), [переключатель навыка неактивен](#переключатель-навыка-неактивен);
- сборка: [сторож или `web-compile` упал](#сторож-или-web-compile-упал), [путь «Open» неверный на Windows](#путь-open-неверный-на-windows);
- тесты: [готовность всегда «не нужна» в тесте](#готовность-в-тесте-не-срабатывает);
- [события журнала](#события-журнала).

## `StateError: The config snapshot has no loaded configuration`

**Симптом.** `readAgentExtensions` или `agentExtensionsOf` бросают `Bad state: The config snapshot has no loaded configuration`.

**Причина.** У снимка нет `loaded.config`: загрузчик не смог собрать конфиг. Это значит проблемы вида `syntax`, `type` или `profile`. Получено запуском на конфиге `providers: [` (битый YAML): `layers=[project, projectLocal]`, `issues=[syntax]`, `config=null`.

**Что сделать.** Не вызывайте функции расширений при `snapshot.loaded.config == null`. Показывайте `snapshot.issues`, как делает страница. Функции бросают `StateError`, потому что вызов без читаемого конфига — ошибка программиста (`lib/src/extensions/agent_extensions_of.dart`, `lib/src/io/agent_extensions_reader.dart`).

## Слой конфига не прочитан

**Симптом.** В журнале `config.snapshot.layer_unreadable` с полем `layer`; страница не пишет файл; в `snapshot.layers` нет слоя; `snapshot.isReadable(layer)` ложно.

**Причина.** `ConfigWriter.read` бросил `ConfigException` для этого слоя (битый YAML, неверный тип в карте) — `lib/src/io/file_agent_config_store.dart`. Слой остаётся вне карты намеренно: писать в нечитаемый файл небезопасно. Причину называет загрузчик в `snapshot.issues`.

**Что сделать.** Исправьте файл (путь — в `ConfigSourceView.label` других ключей или в сообщении проблемы). Правки через мост, которые зависят от слоя, вернут отказ: `layerUnreadable` у `ProviderRemover`, `McpServerRefusal.layerUnreadable`, `SkillsListLayerUnreadable`, `PlanRefusal.layerUnreadable` у мастера.

## `ConfigConflict` повторяется

**Симптом.** Сколько ни нажимай «Save», запись возвращает `ConfigConflict(<путь>)`.

**Причина.** Клиент пишет по устаревшему слою: `base` взят из снимка до чужой правки, отпечаток не совпадает. Автоповтора нет намеренно (SETUP-6). Мастер перечитывает снимок сам (`ProviderSetupCommitter.reload`), поэтому у него повтор проходит; коммитеры MCP и свой код клиента должны делать то же.

**Что сделать.** После `ConfigConflict` вызовите `AgentConfigStore.snapshot` и берите `base` из **нового** `snapshot.layers[слой]`. Прогон на временном конфиге: запись по старому слою после дописывания в файл — `ConfigConflict`, по свежему — `ConfigSaved`. Черновик пользователя не теряйте.

## `ConfigInlineSecret` при записи MCP

**Симптом.** `apply` возвращает `ConfigInlineSecret(mcp.servers[docs].headers.Authorization)` с `suggestedSecretName` `codelab/mcp/docs/authorization`.

**Причина.** В элементе секрет написан значением (`Authorization: Bearer sk-live-…`), и писатель конфига отклонил такую запись (CFG-2). Получено запуском на временном `CODELAB_HOME`.

**Что сделать.** Не пишите секрет в конфиг. Используйте значение `McpValueDraft.secret(SecretValue(...))`: форма сама положит секрет в хранилище и запишет `${secret:codelab/mcp/docs/authorization}`. Вид `McpTextValue` предназначен для ссылок `${VAR}` и `${secret:…}` и нейтральных значений.

## Источник ключа пропал или назван неверно

**Симптом.** `snapshot.originOf('ключ')` вернул `null`, или источником назван не тот файл, или у строки таблицы источник `default`, хотя ключ в файле есть.

**Причина (по частоте).**

1. Ключ лежит в слое **недоверенного проекта**. Загрузчик его не применил (предупреждение `config.project.untrusted_key`), и мост не приписывает такому слою источник (`isIgnoredByTrust`). Это правильное поведение.
2. Ключ пришёл из `--config` или окружения, а файл `--config` не назван в `ConfigPaths.extraConfig` или в `CODELAB_CONFIG`: тогда источник — `environment`.
3. Значения в слоях и итоге не совпали: источник определяется по равенству значений (`sameConfigValue`), поэтому перекрытое значение источником не становится.
4. Снимок построен вручную (`snapshotOf`) без итога загрузки: источники считаются только по слоям.

**Что сделать.** Проверьте доверие (`projectTrustedIn(snapshot.loaded.config)`), проверьте `snapshot.loaded.warnings` на `config.project.untrusted_key`, сравните значения слоёв. Для ключа, который недоверенный проект объединяет с нижними слоями (`skills.disabled`), источник ищется без проектных слоёв ([глава 02](02-config-store.md#откуда-берётся-источник-ключа)).

## Ошибка `CODELAB_HOME`

**Симптом.** Страница показывает проблему с пустым ключом: `CODELAB_HOME: ~user is not supported, use an absolute path`.

**Причина.** `ConfigUsageException` (`~user` в `CODELAB_HOME`, `.toml` в `--config`) `FileAgentConfigStore.snapshot` превращает в проблему загрузки `ConfigIssue(kind: value, key: '')`, а не бросает исключение. Текст получен запуском с `codelabHome: '~nobody/x'`.

**Что сделать.** Исправьте значение `CODELAB_HOME` или аргумент `--config`. Страница в таком состоянии показывает `issues` и не пишет.

## Мастер не реагирует на событие

**Симптом.** Событие отправлено, а состояние не изменилось. В журнале `provider_wizard.event_ignored` (`debug`) с полями `state` и `event`.

**Причина.** Событие не подходит к текущему состоянию. Автомат не бросает исключение, а игнорирует событие. Частые случаи:

| Событие | Почему игнорируется |
|---|---|
| `KeySubmitted` | состояние `ChoosingKey` ещё с `ready: false`: порт `ProviderKeys.stored` не ответил |
| `ConfirmSave` | состояние не `Reviewing` |
| `SkipCheck(confirmed: true)` | проверка не упала с `unreachable` или `timeout` (`canSkip` ложно) |
| `UseV1Address` | `canUseV1` ложно: не `notFound`, не `openai-compatible` или путь уже кончается на `/v1` |
| `Back` | `ChoosingPreset`, `EnteringBaseUrl` при правке провайдера, `Saving`, `Done`, `Cancelled` — шага назад нет |
| `Cancel` | `Saving`, `Done`, `Cancelled` |
| `InsecureAddressConfirmed` | нет `insecureHost` в `EnteringBaseUrl` |
| `ModelChosen` | id модели нет в списке `ChoosingModel.models` |

**Что сделать.** Смотрите `flow.current` перед отправкой события; в клиенте отправляйте только те события, которые разрешает текущее состояние. Диспетчер — `ProviderSetupFlow.dispatch` (`provider_setup_flow.dart`).

## Проверка называет ошибку TLS недоступностью

**Симптом.** При неверном сертификате мастер показывает `unreachable`, а не `tlsError`.

**Причина.** `HttpProviderCheck` создан напрямую без классификатора. В основном бареле нельзя назвать `TlsException` (тип `dart:io`), поэтому без классификатора любая сетевая ошибка — `unreachable`.

**Что сделать.** В composition root используйте `ioProviderCheck()` из `lib/io.dart`: он передаёт `classifyProviderCheckError` (`TlsException` → `tlsError`, `SocketException` → `unreachable`). Текст исключения не разбирается.

## Проверка `/models` не поддерживается

**Симптом.** `CheckFailure(badResponse)` с текстом `the model list check is not supported for this provider kind`.

**Причина.** Вид провайдера не `openai-compatible` и не `anthropic`, например `gemini`. Получено запуском. Это не отказ провайдера: запрос не отправлялся.

**Что сделать.** Перед вызовом проверьте `supportsProviderCheck(kind)`; страница делает «Check» неактивным. Добавить вид — [рецепт 6](08-extending.md#6-новый-вид-провайдера-в-проверке-models).

## Мастер вернулся на шаг ключа после Save

**Симптом.** После `ConfirmSave` состояние снова `ChoosingKey` с ошибкой.

**Причина.** Два исхода коммитера возвращают на шаг ключа и ничего не записывают в конфиг:

- `keyAlreadyStored` — `A stored key <имя> already exists in <бэкенд>.`: секрет с этим именем появился после шага ключа (`ProviderKeyAppeared`), журнал — `provider_wizard.save_failed` с `outcome: secret_appeared`. Предложите «Use the stored key» или «Replace it».
- `keyNotStored` — хранилище отказало (`ProviderKeyNotStored`); `error` — причина хранилища как есть, `outcome: secret_failed`.

**Что сделать.** Покажите `error` и дайте выбрать другой источник ключа. Если `rollback` в `save_failed` равен `failed`, созданный секрет остался в хранилище: сообщите об этом пользователю.

## Статус ключа missing, хотя секрет записан

**Симптом.** `ProviderEntryView.key` — `KeySecretMissing`, подпись `Key: missing in <бэкенд>`.

**Причина.** `providerEntriesOf` проверяет **имя** через `isSecretSet`. Секрета с именем из `api_key_secret` нет в бэкенде, который выбран сейчас (`secrets.backend`), либо секрет записан в другой бэкенд, либо клиент передал не тот `isSecretSet`. Переменная `CODELAB_SECRET_<имя>` в окружении агента даёт `KeyInSecretStore(backendId: 'env')`.

**Что сделать.** Проверьте бэкенд (`snapshot.secrets.id`), имя в `api_key_secret` и окружение, которое вы передали в `environment`. Значение секрета мост не читает.

## Секрет остался после удаления

**Симптом.** Провайдер или MCP-сервер удалён, а секрет в хранилище остался. Итог — `ProviderRemoved.secret` или `McpServerRemoved.secrets[<имя>]`.

**Причина — по значению `SecretCleanup`:**

| Значение | Почему секрет остался |
|---|---|
| `notRequested` | `deleteStoredKey` не включён или секрет «чужой» (не `codelab/<id>`, на него ссылаются другие) |
| `stillReferenced` | по свежему снимку на секрет есть ссылка (другой слой, другой провайдер, `${secret:<имя>}` в заголовках MCP) |
| `kept` | секрет вне пространства страницы (`${secret:shared}` у MCP): принадлежит пользователю |
| `failed` | хранилище отказало, либо свежий снимок получить не удалось, либо любой слой не прочитан, либо в конфиге проблемы `syntax` или `profile`: безопасность удаления не доказана (SETUP-24) |

**Что сделать.** Это защита, а не сбой. Если секрет действительно не нужен, удалите его подкомандой `codelab secret delete` после устранения причины. Автоматически удалять «на всякий случай» нельзя.

## Форма отклоняет переименование

**Симптом.** `McpServerDraft.validate()` вернул проблему `renameNotAllowed`: `Remove the server and add it again to rename it.`

**Причина.** Переименование при правке не записывается: `UpsertMcpServer` заменил бы элемент по новому имени, а старый остался бы, и секреты `codelab/mcp/<имя>/` потеряли бы владельца.

**Что сделать.** Удалите сервер и добавьте заново под новым именем. В форме поле имени правки доступно только для чтения.

## Строка настроек не правится

**Симптом.** Страница не открывает поле правки; `settingEditRefusalOf(row)` вернул отказ.

**Причина.** Один из пяти отказов `SettingEditRefusal` ([глава 06](06-views.md#можно-ли-править-строку-settingeditrefusal)): неизвестный ключ, `trusted_projects`, секрет, `--config` или окружение, замаскированное значение. Порядок проверки: ключ, источник, маска. Строки с `masked: true` править по значению нельзя: сырое значение берётся из `snapshot.leaves`.

**Что сделать.** Покажите причину пользователю и подскажите путь: для секрета — `codelab secret set <name>`, для `--config` и окружения — править источник.

## Переключатель навыка неактивен

**Симптом.** `SkillEntryView.toggle.isAvailable` ложно.

**Причина.** `skillsListEdit` вернул отказ ([глава 05](05-agent-extensions.md#правило-записи-списков-навыков-skillslistedit)): список действует из слоя `project`, `--config` или окружения (`SkillsListNotEditable`); имя выключено недоверенным проектом (`SkillsListDisabledByProject`); согласие на относительный каталог в недоверенном проекте (`SkillsListUntrustedProject`); нечитаемый слой (`SkillsListLayerUnreadable`).

**Что сделать.** Для каждой причины клиент показывает подсказку. Источник и слой — в данных отказа.

## Сторож или `web-compile` упал

**Симптом.** `melos run guard` падает на импорте, либо `web-compile` не собирает `test/web_smoke/main.dart`.

**Причина.** В основной барель или `lib/src/` вне `lib/src/io/` попал запрещённый импорт: `dart:io`, `package:codelab_agent_io/`, `package:http/io_client.dart`, `package:flutter/` или ссылка на `lib/io.dart`. Либо в `pubspec.yaml` появилась зависимость вне allowlist (`codelab_agent_core`, `codelab_agent_io`, `http`, `meta`).

**Что сделать.** Перенесите код, которому нужен `dart:io`, в `lib/src/io/` и откройте его из `lib/io.dart`; в основном бареле зависьте от порта. Лишнюю зависимость уберите или оформите OpenSpec change с правкой allowlist ([рецепт 9](08-extending.md#9-новый-реэкспорт)). Правила — раздел «Границы» [`AGENTS.md`](../AGENTS.md) и `rules.dart` сторожа.

## Путь Open неверный на Windows

**Симптом.** Кнопка «Open» у навыка или файла получает путь вида `/c/…`.

**Причина.** Новое поле вида с путём не переведено в форму хоста: ядро хранит `C:\p` как `/c/p`, а `extensionsInHostForm` переводит только известные ему поля (`lib/src/io/extensions_host_paths.dart`).

**Что сделать.** Добавьте перевод поля и проверку в `test/io/extensions_host_paths_test.dart` ([рецепт 8](08-extending.md#8-новое-поле-с-путём-в-виде-расширений)).

## Готовность в тесте не срабатывает

**Симптом.** `providerSetupNeeded(snapshot)` в тесте всегда ложно; `checkProviderReadiness` возвращает `NoProviderConfigured` или `ConfigBroken` неожиданно.

**Причина.** `snapshotOf` строит снимок с пустым `ConfigLoadResult`: проблем загрузчика в нём нет, `loaded.config` — `null`. Для готовности нужен настоящий итог загрузки.

**Что сделать.** Используйте `RealHome` (`test/support/real_home.dart`): он создаёт временный `CODELAB_HOME` и строит снимок настоящим `FileAgentConfigStore`.

## События журнала

Мост пишет события в `Logger` ядра. Значений секретов и адресов с путём они не содержат. В тесте их читает `RecordingLogger.records`; формат журнала агента и маскирование описаны в [главе ядра об наблюдаемости](../../codelab_agent_core/doc/10-observability-and-errors.md).

| Событие | Уровень | Поля | Где пишется |
|---|---|---|---|
| `provider_wizard.started` | info | `mode` (`add`, `edit`), `entry` (`app`, `banner`, `cli`, `first_run`, `flags`, `onboarding`) | конструктор мастера |
| `provider_wizard.address_rejected` | info | `reason` (`invalid`, `userinfo`) | шаг адреса |
| `provider_wizard.insecure_address` | info | `origin` | `http://` на нелокальный хост |
| `provider_wizard.keys_unavailable` | warning | `error_type` | порт ключей бросил при `stored` или `read` |
| `provider_wizard.check_finished` | info | `operation_id`, `preset`, `endpoint`, `outcome`, `status` | проверка закончилась |
| `provider_wizard.check_discarded` | debug | те же, `outcome: discarded` | попытка устарела |
| `provider_wizard.reload_failed` | warning | `error_type` | не удалось перечитать снимок после конфликта |
| `provider_wizard.saved` | info | `provider_id`, `key` (`secret`, `env`, `none`), `target` (`user`, `local`), `make_default`, `skipped_check` | запись удалась |
| `provider_wizard.save_failed` | warning | `provider_id`, `outcome` (`secret_appeared`, `secret_failed`, `conflict`, `rejected`, `inline_secret`, `error`), `rollback`, `error_type` | запись не удалась |
| `provider_wizard.cancelled` | debug | `state` | `Cancel` |
| `provider_wizard.event_ignored` | debug | `state`, `event` | событие не к месту |
| `provider_check.result` | info | `origin`, `kind`, `outcome`, `status`, `models` | `HttpProviderCheck` |
| `config.snapshot.layer_unreadable` | warning | `layer` | `FileAgentConfigStore.snapshot` |

Источник событий мастера — `lib/src/provider/provider_setup_flow.dart`, проверки — `http_provider_check.dart`, снимка — `lib/src/io/file_agent_config_store.dart`. `FileAgentConfigStore` без `logger` молчит, поэтому событие снимка в клиентах видно только если composition root передал логгер.
