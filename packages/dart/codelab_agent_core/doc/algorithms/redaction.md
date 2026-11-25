# Алгоритм маскирования секретов на стороне агента

Секрет в конфиге, в тексте ошибки провайдера или в записи лога может уехать туда, где его увидят посторонние: в вывод `config get`, в строку списка настроек, в журнал CI, в скриншот. Механизм маскирования закрывает эти пути. Он сквозной: агент и клиенты делают его части по-разному, и вместе они дают полную картину.

Этот документ описывает сторону агента: что `codelab_agent_core` и мосты над ним скрывают, чем и в каком порядке. Сторона клиента — редактор `SecretRedactor`, политика полезной нагрузки кадров, точки применения в CLI и app — описана в [`codelab_client_acp/doc/redaction.md`](../../../codelab_client_acp/doc/redaction.md) и здесь не повторяется. Документ читается подряд, без переходов по ссылкам; справочные главы перечислены в конце.

Важное ограничение: **у агента нет универсального редактора**. Он не просматривает текст промптов, вывод инструментов и записи лога. Агент решает три узкие задачи: распознаёт литеральные секреты в конфиге и не печатает их; не выводит ключи в текстах ошибок провайдера; не кладёт значения секретов в записи лога по дисциплине вызывающего кода. Всё остальное маскирует клиент. Ключи `redact.*` читаются, но не применяются (раздел «Настраиваемые параметры»).

Пути даны от `packages/dart/`: `core` — `codelab_agent_core/lib/src/`, `io` — `codelab_agent_io/lib/src/`, `setup` — `codelab_setup/lib/src/`.

## Что защищается и от чего

**Что защищается.** Значения секретов: ключи API провайдеров, токены в заголовках провайдеров и MCP-серверов, переменные `env` серверов, пароли в адресах (`user:pass@host`), токены в query-параметрах, приватные ключи PEM.

**От кого.** От случайного показа, а не от злоумышленника с доступом к файлам. Угрозы:

| Куда секрет мог бы утечь | Как | Что закрывает на стороне агента |
|---|---|---|
| вывод `config get`, `provider list` | человек правил `config.yaml` руками и записал токен значением | `maskConfigValue` в `io/cli/config_output.dart` поверх `displaySafeConfigValue` ядра |
| строки страницы настроек и списка MCP-серверов в клиентах | то же | `displaySafeConfigValue`, `maskMcpArgs`, `hidesConfigLiteral` через `setup/mcp/mcp_masking.dart`; `displayBaseUrl` |
| текст ошибки хода и событие `ErrorEvent` | провайдер вернул в теле `401` ключ из запроса | `redactSecrets` в `core/llm/providers/http_support.dart`; `_safeErrorText` в `core/llm/stream_state.dart` |
| запись лога агента | вызывающий код положил значение в поле | правило логгера: значения секретов в поля не пишутся (`core/util/logger.dart`); маскирования нет |
| файл конфига | токен лежит значением, а не ссылкой | предупреждение `config.secret.in_file` и `codelab secret migrate` (`core/config/inline_secrets.dart`) |
| журнал кадров, UI ленты, диагностика, строка инструмента | вывод инструмента или текст модели несут секрет | на стороне агента не закрыто; маскирует клиент, но не везде: известные пробелы (`toolRow` в CLI, команда в блоке одобрения, `secondary` и `summary` строки инструмента, деталь `fetch`) — в разделе «Пределы» ([`redaction.md` клиента](../../../codelab_client_acp/doc/redaction.md)) |
| промпт модели | файл проекта или вывод инструмента с секретом попал в контекст | не закрыто: модель получает текст как есть |

Основание — [`approval-safety`](../../../../../openspec/specs/approval-safety/spec.md) «Редактирование секретов» (общая норма для CodeLab), [`agent-secrets`](../../../../../openspec/specs/agent-secrets/spec.md) (тексты ошибок, сценарии «Сырое значение в теле ошибки» и «Литеральный ключ в файле»), [`agent-configuration`](../../../../../openspec/specs/agent-configuration/spec.md) («Подкоманды записи и чтения конфига», «Маскирование args MCP-серверов в выводе», «Литеральные секреты в файле конфига», «Ключи редакции секретов») и [`docs/architecture/observability.md`](../../../../../docs/architecture/observability.md).

## Вход и выход

**Вход.**

- Имя ключа, заголовка, переменной или флага — для правила секретных имён.
- Строковое значение конфига — для распознавания литерального секрета.
- Адрес `base_url` или `url`.
- Путь ключа в форме `KeyPath` (`providers.p.api_key`, `mcp.servers[gh].env.TOKEN`) и значение листа — для маскирования вывода.
- Список аргументов MCP-сервера `args`.
- Тело HTTP-ответа провайдера и список известных значений секретов `ProviderConfig.secrets`.

**Выход.**

- Строка или дерево значений, пригодное для печати: секрет заменён на `<redacted>` (`redactedMask`), непрозрачное поддерево — на `<opaque: edit the file>` (`opaqueMask`), значение слоя окружения или флагов — на `<from env:NAME>` или `<from flags>`.
- Метка формата секрета (`sk`, `github`, `bearer`…) без значения — для предупреждений.
- Текст ошибки провайдера, где известные значения заменены на `[REDACTED]`.

**Побочных эффектов нет.** Ни одна функция не пишет файлы и не пишет в лог. Метки и находки не содержат ни значения, ни его части (CFG-2): их безопасно печатать.

## Общая схема

На схеме стрелки показывают путь данных, ромбы — места, где секрет скрывается или остаётся.

```mermaid
flowchart TD
  file["config.yaml: токен значением, правка руками"] --> load["загрузка: findInlineSecrets"]
  load -->|"предупреждение config.secret.in_file, без значения"| warn["config check, лог"]
  file --> get["config get, provider list"]
  get --> mco["maskConfigValue: io/cli/config_output.dart"]
  mco --> dsc["displaySafeConfigValue и maskUrl: core/config/mask_url.dart"]
  dsc --> tty["вывод в терминал: токены скрыты"]
  file --> setup["codelab_setup: списки настроек и MCP"]
  setup --> dsc
  prov["ответ провайдера: HTTP 401 с телом"] --> hdr["describeHttpError, redactSecrets"]
  hdr --> err["ErrorEvent и текст ошибки хода: ключ скрыт"]
  tool["вывод инструмента, текст модели"] --> upd["session/update, лог агента"]
  upd -->|"агент не маскирует"| cli["клиент: SecretRedactor"]
  cli --> ui["журнал, лента, панель Protocol"]
  lg["поля записи лога"] -->|"только дисциплина кода"| host["HostLogger: stderr, файл"]
```

Левая часть схемы (конфиг и ошибки провайдера) — то, что агент делает сам. Правая (вывод инструментов, лог) — граница: агент пишет как есть, а скрывает клиент.

## Псевдокод

Запись Dart-подобная. Комментарий `// файл: символ` указывает место в коде. Порядок шагов совпадает с кодом; пропущены защитные проверки и вспомогательные функции, которые не меняют результат. Каждый блок нумеруется заново: блоки А–Ж вызывают друг друга по цепочке, как показано в комментариях.

### А. Правило секретных имён

```text
isSecretLikeName(name) -> bool                 // core/config/secret_name_rule.dart: isSecretLikeName
  1. normalized = name в нижнем регистре, без '-' и '_'
  2. return normalized содержит любой из корней:
        token, secret, password, apikey, auth, cookie, key, privatetoken

isSecretScalarName(name) -> bool               // core/config/secret_name_rule.dart: isSecretScalarName
  1. words = name, разрезанное по '-', '_', пробелу и границе camelCase, в нижнем регистре
  2. если words пусто: return false
  3. normalized = name в нижнем регистре, без '-' и '_'
  4. return words.last ∈ {token, key, apikey, auth, cookie, secret, password,
                          privatetoken, accesstoken}
         или normalized ∈ тех же слов
         или normalized ∈ {keys, tokens, secrets, passwords}

hasSecretReference(value) -> bool              // core/config/secret_name_rule.dart: hasSecretReference
  1. return value содержит `${…}` (регулярное выражение \$\{[^}]+\})
```

### Б. Распознавание литерального секрета: `literalSecretTag`, `hasInlineSecret`

```text
literalSecretTag(value, asName=false) -> String?  // core/config/inline_secrets.dart: literalSecretTag
  1. matches = _scan(value, firstOnly: true, asName)
  2. return matches.пусто ? null : метка первого совпадения

hasInlineSecret(value) -> bool                    // core/config/inline_secrets.dart: hasInlineSecret
  1. return valueFindings(value).isNotEmpty

_scan(value, firstOnly, asName)                   // core/config/inline_secrets.dart: _scan
  1. если value пусто: return без совпадений
  2. parts = литеральные куски value между подстановками `${…}`
        // `Bearer ${secret:x}` даёт часть `Bearer `: шаблоны порознь её не принимают
  3. для pattern в таблице §12.4 по приоритету:
        sk, github, aws, google, slack, jwt, bearer, private-key, assignment
       для part в parts:
         для (от, до) в участках секрета pattern внутри part:
           3.1 если участок целиком совпал с белым списком (git_sha, uuid): continue
           3.2 если asName и pattern == sk и участок не в начале значения: continue
                // `codelab/sk-anthropic-production-key` — имя секрета, а не ключ (L3)
           3.3 если участок пересекается с уже выбранным: continue
           3.4 если выбрано 64 участка: return (выбранные, truncated: true)
           3.5 выбрать участок; если firstOnly: return
  4. для URL с паролем `схема://пользователь:пароль@` по всему value (не по parts):
        // пароль, разрезанный подстановкой (`u:lit${X}@h`), виден только здесь
       4.1 chunks = литеральные куски пароля без подстановок
       4.2 если chunks пусто (пароль из одних подстановок): continue
       4.3 для каждого куска: те же проверки 3.3–3.5, метка connection-string
  5. return выбранные участки

valueFindings(path, value)                        // core/config/inline_secrets.dart: valueFindings
  1. scan = _scan(value)
  2. если есть совпадения: находка literalPart; метка — у первого шаблона по приоритету
  3. для каждой `${secret:<имя>}` и `${<ИМЯ>}` в value:
       если literalSecretTag(<имя>, asName: true) != null:
         // токен вписан вместо имени: `${ghp_…}`
         добавить участок в находку referenceName
  4. return находки
```

### В. Адрес: `maskUrl`

```text
maskUrl(raw) -> String                            // core/config/mask_url.dart: maskUrl
  1. заменить каждую `${…}` на токен refxNx (запомнить в refs)
        // иначе `Uri` не разберёт `https://${U}:${P}@h/${PATH}`
  2. uri = Uri.tryParse(результат шага 1)
     если uri == null: return '<redacted>'                      // fail closed
  3. если у uri нет авторитета и в строке есть '@': return '<redacted>'
        // `user:pass@host` разобран как схема `user`, userinfo остался бы в пути
  4. changed = userinfo не пуст
  5. для каждой пары имя=значение в query, в fragment и в matrix-параметрах пути (`;имя=значение`):
       если значение не пусто и isSecretLikeName(имя без процентного кодирования)
          и значение не состоит из токенов refxNx:
         значение := '<redacted>'; changed = true
  6. если не changed: return raw                                // байт в байт
  7. собрать authority из хоста и порта, без userinfo
     если в authority остался '@': return '<redacted>'
  8. собрать схему + authority + путь + ?query + #fragment
  9. вернуть refxNx обратно в `${…}` и return
```

### Г. Лист конфига: `displaySafeConfigValue`

```text
displaySafeConfigValue(path, value) -> Object?    // core/config/mask_url.dart: displaySafeConfigValue
  1. если value == null: return null
  2. name = последний сегмент path, не являющийся элементом списка
  3. isUrl = name ∈ {base_url, url}
  4. если value — строка и не isUrl:
       isName = name ∈ {api_key_env, api_key_secret}
       hidden = isName ? literalSecretTag(value, asName: true) != null
                       : hasInlineSecret(value)
       если hidden: return '<redacted>'
  5. shown = isUrl ? maskUrl(value) : value
  6. если isUrl и _urlCarriesSecret(shown): return '<redacted>'
        // путь, fragment или значение query после раскодирования содержат токен по шаблону;
        // уже скрытые участки `<redacted>` не считаются
  7. d = SettingsRegistry.lookup(path)
     если d есть и тип не map и не mapList:
       если name ∈ inlineSecretKeys и value — непустая строка
          и (нет ссылки `${…}` или literalSecretTag(value) != null):
         return '<redacted>'                                    // providers.*.api_key — литерал файла
       return shown
  8. secretName = name ∈ inlineSecretKeys
                  или (value — строка ? isSecretLikeName(name) : isSecretScalarName(name))
  9. если secretName и value не пусто и не (строка со ссылкой `${…}`): return '<redacted>'
 10. return shown

inlineSecretKeys = {api_key, apiKey, token, secret, password}   // core/config/config_issue.dart
```

### Д. Аргументы MCP: `maskMcpArgs`

```text
maskMcpArgs(args) -> List                         // core/config/mask_url.dart: maskMcpArgs
  afterSecretFlag = false
  для item в args:
    1. wasSecretFlag = afterSecretFlag; afterSecretFlag = false
    2. если item — карта или список: добавить '<opaque: edit the file>'; continue
    3. если item не строка: добавить wasSecretFlag ? '<redacted>' : item; continue
    4. если literalSecretTag(item) != null: добавить '<redacted>'; continue
    5. если wasSecretFlag и item не начинается с '--':
         добавить hidesConfigLiteral(item) ? '<redacted>' : item; continue
            // `hidesConfigLiteral`: после удаления `${…}` что-то осталось
    6. если item не начинается с '-': добавить item; continue
    7. flagName = item до '=' без ведущих '-'
       secretFlag = isSecretLikeName(flagName)
       если '=' нет:  afterSecretFlag = secretFlag; добавить item
       иначе если secretFlag и hidesConfigLiteral(значение): добавить 'флаг=<redacted>'
       иначе: добавить item
```

### Е. Вывод `config get`: `maskConfigValue`

```text
maskConfigValue(value, key, layer) -> Object?     // io/cli/config_output.dart: maskConfigValue
  1. segments = splitKeyPath(key); name = последний сегмент, не являющийся элементом
  2. canonical = путь, собранный из сегментов
        // `mcp."servers"[gh]."args"` приводится к `mcp.servers[gh].args`: иначе обход маски
  3. если canonical — путь глубже элемента args (`…args[0][0]`): return '<opaque: edit the file>'
  4. если canonical — элемент args (`…args[1]`):
       return _Masker.maskArgsElement(...)    // маска зависит от соседей, поэтому берётся из родительского списка
  5. return _Masker.mask(value, canonical, name)

_Masker.mask(node, path, name)                    // io/cli/config_output.dart: _Masker.mask
  1. если _isOpaque(path): return '<opaque: edit the file>'
        // узел реестра: файловый map с причиной «not supported in this version»
  2. карта: если _unknownContainer(path): return '<opaque…>'; иначе mask каждого значения
  3. список: если _unknownContainer(path): return '<opaque…>'
       если path — args сервера: return _maskArgs(список)       // maskMcpArgs
       иначе mask каждого элемента с путём вида `…[имя]` или `…[индекс]`
  4. лист: _leaf(node, path)

_Masker._leaf(value, path)                        // io/cli/config_output.dart: _Masker._leaf
  1. если value == null: return null
  2. если слой — окружение или флаги: return '<from env:NAME>' / '<from env>' / '<from flags>'
        // переменная могла прийти из секретного хранилища оркестратора
  3. return displaySafeConfigValue(path, value)           // блок Г

_unknownContainer(path)                           // io/cli/config_output.dart: _Masker._unknownContainer
  1. если у path есть дескриптор в реестре: return false
  2. если path — префикс ключа реестра (`mcp.servers[gh]` для `mcp.servers[*].env`): return false
  3. иначе return true            // схемы листьев нет, секрет мог лежать под безобидным именем
```

### Ж. Ошибка провайдера: `describeHttpError`

```text
describeHttpError(provider, status, body, secrets) -> String   // core/llm/providers/http_support.dart: describeHttpError
  1. info = разбор тела; message = (info.message ?? body).trim()
  2. если message пусто: message = 'HTTP <status>'
  3. если длина message > 2000: message = первые 2000 символов + '…'
  4. если message содержит 'prompt_cache_key': дописать подсказку про providers.<имя>.prompt_cache_key
  5. return redactSecrets('<provider> <status>: <message>', secrets)

redactSecrets(text, secrets)                      // core/llm/providers/http_support.dart: redactSecrets
  1. для secret в secrets: если не пусто — заменить все вхождения на '[REDACTED]'

ProviderConfig.secrets                            // core/llm/provider_config.dart: ProviderConfig.secrets
  1. apiKey, если он не пуст и (ключ не литерал из файла или длина >= 8)
  2. значения всех заголовков провайдера (непустые)
  3. extraSecrets: исходные значения секретов шаблонов `${secret:…}` и `${VAR}`

_safeErrorText(error, errorClass, secrets)        // core/llm/stream_state.dart: _safeErrorText
  1. ProviderHttpException: return как есть          // уже прошла describeHttpError
  2. сетевой сбой: return 'connection failed: <тип>'
  3. FormatException про заголовок: return 'invalid request header: <тип>'
        // текст исключения цитирует значение заголовка, то есть ключ
  4. иначе: заменить `http(s)://…` на '<url>', затем redactSecrets(текст, secrets)
```

### З. Правило логгера

```text
Logger.log(level, event, fields, error)           // core/util/logger.dart: Logger
  1. вызывающий код кладёт в fields имена, источники и пути ключей, не значения
  2. вызывающий код не кладёт текст исключения внешней библиотеки в fields: пишет runtimeType
     // но параметр `error:` ядро часто получает сырым объектом (см. ниже)
  3. тексты сообщений и аргументы инструментов — не выше debug
  4. хост (HostLogger) пишет поля как есть: ни редактора, ни проверки нет
     // apps/codelab_agent/lib/src/log/host_logger.dart: error?.toString() и stack?.toString() в LogRecord
```

## Пошаговое пояснение

### Два правила имён, а не одно

`isSecretLikeName` смотрит на подстроку после нормализации: `X-Api-Key`, `x_api_key` и `ApiKey` дают одно и то же. Подстрока `key` или `token` внутри имени срабатывает и на счётчиках (`max_tokens`), и на безобидных именах (`X-Keyboard-Layout`, `monkey`). Для заголовков, переменных и флагов это сознательно: отказ дешевле записанного токена, а ложное срабатывание обходится ссылкой `${VAR}` (D5 change `add-config-writer-and-reload`, [`openspec/changes/archive/2026-11-03-add-config-writer-and-reload/design.md`](../../../../../openspec/changes/archive/2026-11-03-add-config-writer-and-reload/design.md)).

Для скалярных листьев схемы такое правило слишком грубо: `max_output_tokens` — число, которое нужно видеть. Поэтому `isSecretScalarName` смотрит только на последнее слово имени и на имя целиком: `max_tokens`, `X-Max-Tokens`, `tokens_in` — не секреты, а `tokens`, `keys`, `access_token`, `private_token` — секреты. Правило общее для писателя конфига и вывода (R0-2): запись и показ не расходятся в том, что считать секретным числом.

Клиентский `SecretRedactor` устроен иначе: счётчики токенов он различает по остатку имени и стоп-словам (`access_tokens` скрыт, `tokens_in` виден), а `sessionId` — корреляционный идентификатор, не секрет. Две реализации существуют потому, что у них разные входы: у агента — имена из схемы конфига, у клиента — произвольные поля записей и кадров. Правило клиента — в [`redaction.md` клиента](../../../codelab_client_acp/doc/redaction.md) и в [`approval-safety`](../../../../../openspec/specs/approval-safety/spec.md) «Редактирование секретов» (решения — [`openspec/changes/extend-secret-name-redaction/design.md`](../../../../../openspec/changes/extend-secret-name-redaction/design.md), D1–D2).

### `hasSecretReference` и литерал рядом со ссылкой

Проверка «значение — не литерал» сводится к `isSecretLikeName(name) && !hasSecretReference(value)`. Ссылка `${…}` в значении делает его «не литералом». У правила известная граница (D5, R1-1): `Bearer sk-… ${X}` содержит ссылку и поэтому проходит эту проверку. Закрывает её не имя, а второй рубеж: `hasInlineSecret` режет значение по подстановкам и ищет шаблон в литеральных частях, поэтому `config get` такое значение всё равно скроет, а загрузка предупредит `config.secret.in_file` — но только если литерал совпал с шаблоном известного формата. Литерал без признаков рядом со ссылкой (`mypassword123 ${X}`, `Basic dXNlcjpwYXNzd29yZA== ${X}`) выводится как есть (см. «Граничные случаи»).

### Шаблоны форматов, порядок и белый список

Таблица шаблонов (`sk`, `github`, `aws`, `google`, `slack`, `jwt`, `bearer`, `private-key`, `assignment`) идёт в порядке приоритета, поэтому у `Bearer ghp_…` метка `github`, а не `bearer`: участок `bearer` пересекается с уже выбранным и отбрасывается (шаг 3.3). Шаблоны написаны по публичным описаниям форматов; чужие правила не копировались.

Белый список `git_sha`, `uuid` (шаг 3.1) снимает ложное срабатывание на `API_KEY=<40 hex>`: участок, который целиком совпал с записью, секретом не считается. Белый список берётся только целиком: `API_KEY=<40 hex>abc` секрет.

JWT и PEM ищутся не регулярными выражениями, а однопроходными поисками по якорю (`.eyJ`, `-----BEGIN … PRIVATE KEY-----`). Враждебное значение вида `eyJ-eyJ-…` на регулярном выражении с перебором от каждой позиции давало бы квадратичное время (измерено: 1 МиБ — минуты). Ограничения `{0,64}`, `{8,256}` и предел 64 участка (шаг 3.4) — по той же причине.

PEM без строки `END` покрывает остаток значения: участок должен накрыть тело ключа, иначе `secret migrate` оставил бы его в файле.

### `asName`: имя секрета не секрет

Ссылка `${secret:codelab/sk-anthropic-production-key}` называет секрет. Если считать `sk-` внутри слова ключом, ссылка не разрешалась бы (L3). Поэтому для имён (`api_key_env`, `api_key_secret`, содержимое ссылок) `sk-` засчитывается только в начале значения (шаг 3.2). Обратная сторона: токен, вписанный вместо имени (`${ghp_…}`), находится — это находка `referenceName`, и такая ссылка не разрешается (`secretReferencesIn` его в список имён не включает).

### Адрес: разбор `Uri`, а не регулярное выражение

Шаблон «до первого `@`» не справляется с паролем, где есть `@`, `%40` или `/`: часть секрета осталась бы в выводе. Поэтому адрес разбирается `Uri`, а всё, что разобрать нельзя, скрывается целиком (шаги 2, 3, 7): адрес дороже показа. Ссылки `${…}` заменяются токенами `refxNx` только на время разбора (шаг 1): ссылка не значение и в выводе остаётся, а адрес `https://${U}:${P}@h` разбирается корректно.

Токен под несекретным именем параметра (`?x=sk-…`) или в пути (`/v1/sk-…`) имя не выдаёт. Его ловит `_urlCarriesSecret` (шаг 6): путь, fragment и значения query после раскодирования проходят `hasInlineSecret`. Участки, уже заменённые `<redacted>`, из проверки исключаются, иначе `token=<redacted>` совпало бы с шаблоном «присваивание секрета».

`displayBaseUrl` в `setup/config/display_base_url.dart` — отдельное, более жёсткое правило для экрана провайдера: оставляет только схему, хост, порт и путь, без query и fragment (`https://host:8443/v1`). Строки `/settings` используют `maskUrl`.

### Лист конфига: порядок проверок

Порядок шагов блока Г существенен. Сначала по шаблону проверяется любое строковое значение, кроме адресов (шаг 4): литерал скрывается независимо от имени и реестра. Затем адреса (5–6). Потом листья реестра (7): `api_key_secret`, `api_key_env`, `auth_header` хранят имена и счётчики и печатаются как есть, исключение — `api_key`, чьё значение — сам ключ. И наконец имена без схемы, то есть значения `headers` и `env` (8–9): здесь решает правило имён, а ссылка `${…}` делает значение видимым.

Две тонкости: пустое значение под секретным именем не маскируется (скрывать нечего), а `api_key` со ссылкой, но с литералом внутри (`Bearer sk-… ${X}`), скрывается уже на шаге 4: `hasInlineSecret` режет значение по подстановкам.

### Аргументы MCP

Значение секретного флага стоит в соседнем элементе (`--api-key abc`), поэтому `maskMcpArgs` помнит предыдущий элемент (`afterSecretFlag`). Одиночный дефис (`-s3cr3t`) не считается флагом известной формы: он значение. Список и карта внутри `args` — невалидный конфиг ручной правки — скрываются целиком (шаг 2). Путь на один элемент (`args[1]`) маскируется через родительский список, а без слоя, родителя или индекса — fail closed: строка скрывается, не-строка (кроме `null`) тоже.

### Значения слоёв «окружение» и «флаги»

Вместо значения печатается `<from env:NAME>` или `<from flags>` (шаг 2 `_leaf`): переменная окружения могла прийти из секретного хранилища оркестратора. Печатается только источник.

### Ошибка провайдера: известные значения, не угаданные

`redactSecrets` не ищет секрет по форме: он заменяет значения, о которых агент знает (ключ, заголовки, исходные значения шаблонов). Поэтому «сырое значение в теле ошибки» без `Bearer ` из спецификации `agent-secrets` закрыто, если значение пришло из хранилища, а ключ, который агенту не известен, не закрыт (пятая строка таблицы «Ошибка провайдера» в разделе примеров).

Литеральный ключ короче 8 символов (`ollama`, `x`) не вычищается: это заглушка локального сервера, и замена превратила бы любое такое слово в тексте ошибки в `[REDACTED]` (`ProviderConfig.minScrubbedKeyLength`, D4 change `add-config-literal-secrets-and-migrate`).

### Лог: правило, а не код

Логгер ядра — порт: ядро пишет только в него, а хост решает, куда идут записи. Маскирования в порте нет. Комментарий у `LogRecord` («после редакции, когда она появится») описывает будущее; сейчас `HostLogger` из `apps/codelab_agent` пишет поля как есть. Защита — дисциплина вызывающего кода (блок З): в записи `secrets.lookup` — имя секрета, назначение и источник, не значение; вместо текста исключения в полях — `runtimeType`. Исключение из правила — параметр `error:`: `HostLogger` пишет `error?.toString()` и стек как есть, а ядро в нескольких местах передаёт туда сырой объект ошибки (список — в разделе «Граничные случаи»). Встроенный агент защищён клиентом: адаптеры логов CLI и app прогоняют записи через `SecretRedactor`. Журнал отдельного процесса `codelab-agent` такой защиты не имеет, поэтому его нельзя публиковать без просмотра ([глава 10](../10-observability-and-errors.md#маскирование)).

## Карта точек применения

| Где | Что скрывается | Чем | Файл |
|---|---|---|---|
| вывод `config get`, `provider list` | листья, адреса, `args`, значения слоёв env и флагов, непрозрачные поддеревья | `maskConfigValue` | `io/cli/config_output.dart` |
| лист конфига в любом выводе | литерал по шаблону, секретное имя без ссылки, секретный адрес | `displaySafeConfigValue` | `core/config/mask_url.dart` |
| адрес `base_url`, `url` | userinfo, секретные query, fragment, matrix | `maskUrl` | `core/config/mask_url.dart` |
| `args` MCP-сервера | значение после секретного флага, `--флаг=значение`, токены | `maskMcpArgs`, `hidesConfigLiteral` | `core/config/mask_url.dart` |
| страница настроек (`setting_field_view`) | значения настроек | `displaySafeConfigValue` | `setup/views/setting_field_view.dart` |
| список и форма MCP-сервера | `command`, `url`, `env`, `headers`, `args` | `mcpDisplayValue`, `mcpDisplayHeader`, `mcpDisplayArgs` | `setup/mcp/mcp_masking.dart` |
| адрес на экране провайдера и в мастере | всё, кроме схемы, хоста, порта и пути | `displayBaseUrl` | `setup/config/display_base_url.dart` |
| загрузка конфига | находка литерала: путь ключа и метка, значение не пишется | `findInlineSecrets` → `config.secret.in_file` | `core/config/inline_secrets.dart`, `core/config/resolve.dart` |
| ссылки `${secret:…}` | разбор имён, `$${secret:x}` — литерал, `${ghp_…}` — не ссылка | `secretReferencesIn`, `soleSecretReference` | `core/config/secret_references.dart` |
| запись и перезагрузка конфига | отказ принять литерал в секретном заголовке | `isSecretLikeName`, `hasSecretReference` | `io/config/literal_secret_rule.dart`, `core/config/config_reload_plan.dart` |
| текст ошибки провайдера | ключ, значения заголовков, значения шаблонов | `describeHttpError`, `redactSecrets`, `streamErrorText` | `core/llm/providers/http_support.dart` |
| текст исключения хода | URL, ключ, текст заголовка | `_safeErrorText` | `core/llm/stream_state.dart` |
| запись лога агента | не маскируется; значения не пишутся по правилу | дисциплина кода | `core/util/logger.dart`, `apps/codelab_agent/lib/src/log/` |
| вывод инструментов, `session/update`, промпт | не маскируется | на клиенте; у клиента есть известные пробелы: `toolRow` в CLI, команда в блоке одобрения, строки `secondary` и `summary` инструмента, деталь `fetch` (раздел «Пределы» клиентского документа) | [`redaction.md` клиента](../../../codelab_client_acp/doc/redaction.md) |

## Разобранные примеры

Источник: временные скрипты, которые вызывали публичные функции `codelab_agent_core` и `maskConfigValue` (`codelab_agent_io`) через `fvm dart run`. Скрипты удалены. Секреты фиктивные.

### Правило имён

| Вызов | Результат | Почему |
|---|---|---|
| `isSecretLikeName('Authorization')`, `'X-Api-Key'`, `'GITHUB_TOKEN'`, `'Cookie'` | `true` | корни `auth`, `key`, `token`, `cookie` |
| `isSecretLikeName('X-Team')` | `false` | корней нет |
| `isSecretLikeName('X-Keyboard-Layout')` | `true` | подстрока `key`: ложное срабатывание |
| `isSecretLikeName('max_tokens')` | `true` | подстрока `token`: для скаляров правило другое |
| `isSecretScalarName('max_tokens')`, `'X-Max-Tokens'`, `'tokens_in'`, `'input_tokens'` | `false` | последнее слово — не секретное |
| `isSecretScalarName('tokens')`, `'keys'`, `'access_token'`, `'private_token'`, `'apiKey'`, `'password'` | `true` | имя или последнее слово в списке |
| `isSecretScalarName('session_id')` | `false` | `id` — не секретное слово |

### Литералы и метки

| Значение | `literalSecretTag` | Почему |
|---|---|---|
| `sk-test-abcdefghijklmnopqrstuvwx` | `sk` | `sk-` и 20+ символов |
| `sk-short` | `null` | короче 20 символов после префикса |
| `ghp_abcdefghijklmnopqrstuvwxyz0123456789` | `github` | `ghp_` и 36 символов |
| `Bearer abcdefghijklmnopqrst` | `bearer` | 12+ символов токена |
| `Bearer ghp_abcdefghijklmnopqrstuvwxyz0123456789` | `github` | приоритет таблицы выше, участок `bearer` отброшен |
| `-----BEGIN RSA PRIVATE KEY-----\nMIIabc` (без `END`) | `private-key` | участок до конца значения |
| `API_KEY=abcdefgh12345678` | `assignment` | имя с `KEY`, значение 8+ символов |
| `API_KEY=` и 40 hex-символов | `null` | белый список `git_sha` |
| `TOKEN=short` | `null` | значение короче 8 символов |
| `password: "hunter22hunter"` | `assignment` | значение в кавычках |
| `postgres://bob:pw123@db/app` | `connection-string` | пароль в userinfo |
| `postgres://bob@db/app` | `null` | пароля нет |
| `https://u:lit${X}@h/` | `connection-string` | литеральная часть пароля `lit` |
| `Bearer ${secret:x}` | `null` | в литеральной части нет секрета |
| `eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijk` | `jwt` | три сегмента |
| `my password is hunter22hunter` | `null` | предел: нет `:` или `=` рядом с именем |

### Адреса: `maskUrl`

| Вход | Выход |
|---|---|
| `https://gw.test:8443/v1/models?api-version=2024-02-01` | без изменений |
| `https://u:p@gw.test/v1` | `https://gw.test/v1` |
| `https://u:p%40ss/x@gw.test/v1` | `<redacted>` (после удаления userinfo остался `@`) |
| `user:pass@gw.test` | `<redacted>` (`@` без авторитета) |
| `https://gw.test/v1?api_key=sk-test-abc&x=1` | `https://gw.test/v1?api_key=<redacted>&x=1` |
| `https://gw.test/v1#token=abc` | `https://gw.test/v1#token=<redacted>` |
| `https://gw.test/v1;key=abc/x` | `https://gw.test/v1;key=<redacted>/x` |
| `https://${U}:${P}@gw.test/v1` | `https://gw.test/v1` |
| `https://[::1` | `<redacted>` (адрес не разбирается) |
| `https://gw.test/v1?x=1&refx0x=2` | без изменений: литерал, похожий на токен, остаётся |

### Листья: `displaySafeConfigValue`

| Путь = значение | Результат |
|---|---|
| `providers.p.base_url` = `https://gw.test/v1?token=abc` | `https://gw.test/v1?token=<redacted>` |
| `providers.p.base_url` = `https://gw.test/v1/sk-test-abcdefghijklmnopqrstuvwx` | `<redacted>` (токен в пути) |
| `providers.p.api_key` = `sk-test-…` | `<redacted>` |
| `providers.p.api_key` = `${secret:codelab/p}` | как есть |
| `providers.p.api_key_secret` = `codelab/sk-anthropic-production-key` | как есть: имя, `sk-` не в начале |
| `providers.p.api_key_secret` = `sk-test-…` | `<redacted>`: в поле имени лежит ключ |
| `providers.p.api_key_env` = `OPENAI_API_KEY` | как есть |
| `providers.p.headers.Authorization` = `Bearer sk-test-…` | `<redacted>` |
| `providers.p.headers.Authorization` = `Bearer ${secret:codelab/p}` | как есть |
| `providers.p.headers.X-Team` = `blue` | как есть |
| `providers.p.headers.X-Team` = `sk-test-…` | `<redacted>`: имя безобидно, значение — по шаблону |
| `providers.p.max_output_tokens` = `4096` | `4096` |
| `mcp.servers[gh].env.GITHUB_TOKEN` = `abc123` | `<redacted>` |
| `mcp.servers[gh].env.GITHUB_TOKEN` = `${secret:codelab/gh}` | как есть |
| `mcp.servers[gh].env.TOKENS` = `5` | `<redacted>`: множественное число |
| `mcp.servers[gh].env.MAX_TOKENS` = `5` (число YAML) | `5` |
| `mcp.servers[gh].env.MAX_TOKENS` = `"5"` (строка) | `<redacted>`: для строки действует `isSecretLikeName`, подстрока `token` |
| `mcp.servers[gh].env.LAYOUT` = `API_KEY=` и 40 hex | как есть: белый список `git_sha` |
| `mcp.servers[gh].env.NOTE` = `API_KEY=abcdefgh12345678` | `<redacted>` |

### Аргументы MCP: `maskMcpArgs`

Вход: `-y`, `server`, `--api-key`, `abc123`, `--token=abc123`, `--port`, `8080`, `--token=${secret:x}`, `-s3cr3t`, `ghp_abcdefghijklmnopqrstuvwxyz0123456789`, список `['a']`, `--password`, `${secret:p}`.

Выход: `-y`, `server`, `--api-key`, `<redacted>`, `--token=<redacted>`, `--port`, `8080`, `--token=${secret:x}`, `-s3cr3t`, `<redacted>`, `<opaque: edit the file>`, `--password`, `${secret:p}`.

`-s3cr3t` остался: одиночный дефис — не секретный флаг (флаг `s3cr3t` не содержит корней) и не литерал по шаблону. Это предел правила, не ошибка прогона (см. «Граничные случаи»).

### Вывод `config get`: `maskConfigValue`

| Ключ = значение, слой | Результат |
|---|---|
| `providers.p.api_key` = `sk-test-…`, слой файла | `<redacted>` |
| `providers.p.api_key` = `sk-test-…`, слой env | `<from env>` |
| `providers.p.api_key` = `sk-test-…`, слой flags | `<from flags>` |
| `providers.p.base_url` = `https://u:p@gw.test/v1?api_key=abc` | `https://gw.test/v1?api_key=<redacted>` |
| `providers.p.headers` = `{Authorization: Bearer sk-test-…, X-Team: blue, X-Note: sk-test-…}` | `{Authorization: <redacted>, X-Team: blue, X-Note: <redacted>}` |
| `providers.p.auth` = `{k: v}` | `<opaque: edit the file>` |
| `mcp.servers` = `[{name: gh, args: [-y, srv, --token, abc123], env: {GITHUB_TOKEN: abc123, LAYOUT: us}}]` | `args: [-y, srv, --token, <redacted>]`, `env: {GITHUB_TOKEN: <redacted>, LAYOUT: us}` |
| `mcp."servers"[gh].env.GITHUB_TOKEN` = `abc123` | `<redacted>`: ключ приведён к каноническому виду |
| `mcp.servers[gh].args[3]` = `x`, без слоя | `<redacted>`: нет родителя, fail closed |
| `redact.enabled` = `false`, `agent.model` = `gpt-test` | как есть |

### Ошибка провайдера

| Тело ответа, `secrets` | Текст ошибки |
|---|---|
| `{"error":{"message":"bad key sk-test-…"}}`, `[sk-test-…]` | `gw 401: bad key [REDACTED]` |
| `raw tok-test-raw-value only`, `[tok-test-raw-value]` | `gw 401: raw [REDACTED] only` |
| `ollama model not found`, `[]` | `gw 401: ollama model not found` |
| пустое тело, `[x]` | `gw 401: HTTP 401` |
| `bad key sk-test-…`, `[]` (ключ агенту не известен) | `gw 401: bad key sk-test-…` — **не скрыт** |
| 1990 символов `x`, пробел и `sk-test-abcdefghijklmnopqrstuvwx`, `[sk-test-…]` | текст оканчивается на `sk-test-a…`: **префикс ключа остался** |

Последняя строка показывает дефект порядка шагов: усечение (шаг 3 блока Ж) стоит раньше вычистки (шаг 5), и ключ, попавший на границу 2000 символов, режется на префикс, который уже не совпадает со значением. Документ описывает код как есть; предел учтён в разделе «Граничные случаи».

## Граничные случаи и пределы

| Ситуация | Что делает механизм | Где |
|---|---|---|
| секрет в произвольном тексте без признаков (`my password is hunter22hunter`) | не ловит: нужны формат токена или пара `имя=значение` | `_patterns` |
| литерал короче порога (`sk-short`, `TOKEN=short`) | не ловит | `_patterns` |
| `X-Keyboard-Layout`, `monkey`, `max_tokens` как имя заголовка или переменной | считает секретным; обход — ссылка `${VAR}` | `isSecretLikeName` |
| `$${secret:x}` | `hasSecretReference` считает ссылкой (экранирование `$$` не учитывает); `secretReferencesIn` — не ссылкой | `secret_name_rule.dart`, `secret_references.dart` |
| `mypassword123 ${X}`, `Basic dXNlcjpwYXNzd29yZA== ${X}` в `headers.Authorization` | **не скрыто**: литерал не совпал с шаблоном известного формата, а ссылка `${X}` делает значение «не литералом»; `config get` печатает как есть (подтверждено тестом) | `displaySafeConfigValue` шаг 9 |
| `Bearer sk-… ${X}` | проходит проверку «есть ссылка», но `hasInlineSecret` находит литерал: вывод скрыт, загрузка предупредит | `valueFindings` |
| `-s3cr3t` после секретного флага | маскируется как значение; сам `-s3cr3t` в позиции флага без значения остаётся | `maskMcpArgs` |
| значение под секретным флагом короче известных шаблонов (`--token abc123`) | скрыто: правило имён, а не шаблон | `maskMcpArgs` |
| ключ провайдера короче 8 символов | не вычищается из текста ошибки | `ProviderConfig.secrets` |
| ключ не из конфига агента | не вычищается из текста ошибки: агент знает только свои значения | `redactSecrets` |
| ключ на границе 2000 символов тела ошибки | усечение до вычистки оставляет префикс: **дефект кода** | `describeHttpError` |
| неразбираемый адрес | `<redacted>` целиком | `maskUrl` |
| ссылка `${secret:…}` в `args` и `url` MCP-сервера | ошибка конфигурации: их видно в списке процессов и логах; пароль в userinfo `url` `secret migrate` не переносит (L5) | `findInlineSecrets` |
| вложенный список или карта в `args` | `<opaque: edit the file>` | `maskMcpArgs` |
| поддерево реестра без схемы листьев, ключи после MVP | `<opaque: edit the file>` | `_Masker` |
| слой окружения или флагов | `<from …>` вместо значения | `_Masker._leaf` |
| запись лога агента с секретом в поле | не маскируется; защита — на ревью | `Logger`, `HostLogger` |
| `error:` записи лога: сырой объект ошибки, `HostLogger` пишет `toString()` и стек | текст исключения попадает в лог целиком, в том числе из внешней библиотеки. Места: `tool.present.error` и `tool.validate.error` (`core/tools/executor.dart`, debug), `mcp.server.failed` (warning, `core/runtime/agent_runtime.dart`), записи `core/subagents/subagent_manager.dart` (три места) и `core/tools/tasks/task_list.dart` | `Logger.log`, `HostLogger` |
| текст промпта и вывод инструментов в журнале сессии | не маскируется; ключ в разговоре остаётся в файле сессии | [`docs/user/configuration.md`](../../../../../docs/user/configuration.md#что-попадает-в-логи-и-журналы) |
| уровень лога `trace`: stderr MCP-серверов | попадает в лог без редактирования | там же |
| значение секрета из хранилища в stdout инструмента | агент не знает, где оно появится; клиент маскирует по шаблону | клиентская сторона |

## Настраиваемые параметры

Ключи раздела `redact` читаются и проверяются, но не применяются: потребителя (универсального редактора) в коде нет. Явно заданный ключ даёт предупреждение `config.key.not_applied` (`core/config/resolve.dart: _notApplied`; схема `core/config/schema.dart`, узлы `_boolU`, `_strListU` с `applied: false`). Ключ `redact` в реестре настроек — только файл (`fileOnly`, причина «security boundary: weakening redaction is a deliberate file edit»).

| Ключ | Умолчание | Проверка при загрузке | Применяется |
|---|---|---|---|
| `redact.enabled` | `true` | булево | нет |
| `redact.layers` | `exact`, `credential_files`, `formats`, `pem`, `connection_strings`, `key_values` | имена из `exact`, `credential_files`, `formats`, `pem`, `connection_strings`, `key_values`, `entropy`; иначе проблема с индексом | нет |
| `redact.allowlist.builtin` | `git_sha`, `uuid` | только эти два значения | нет |
| `redact.allowlist.patterns` | `[]` | регулярное выражение должно компилироваться, иначе проблема с путём `redact.allowlist.patterns[<i>]` | нет |
| `redact.exempt_tools` | `[]` | список строк | нет |
| `redact.block`, `redact.command_rewrite` | — | непрозрачные, без проверки | нет |

Проверенные значения попадают в `CoreConfig.redact` (`RedactSettings`). Правила доверия действуют уже сейчас (`core/config/trust.dart: _restrictRedact`): недоверенный проект может только включить редакцию, добавить слои и убрать записи белого списка; `enabled: false` и новые шаблоны отбрасываются с предупреждением `config.project.untrusted_key`.

Параметры самих функций жёстко заданы в коде:

| Параметр | Значение | Где |
|---|---|---|
| Наименьшая длина литерального ключа, который вычищается из текста ошибки | 8 | `ProviderConfig.minScrubbedKeyLength` |
| Длина тела ошибки до усечения | 2000 символов | `maxErrorBodyLength` |
| Предел участков в одном значении | 64 | `_maxSpans` |
| Метка секрета | `<redacted>` | `redactedMask` |
| Метка непрозрачного поддерева | `<opaque: edit the file>` | `opaqueMask` |
| Метка в тексте ошибки | `[REDACTED]` | `redactSecrets` |

## Как расширить

**Добавить секретное имя.** Корень имени заголовка, переменной или флага — в `_secretNameParts` (`core/config/secret_name_rule.dart`). Слово для скалярных листьев — в `_scalarSecretWords` или `_pluralSecretNames`. Имя листа, значение которого — сам ключ (как `api_key`), — в `inlineSecretKeys` (`core/config/config_issue.dart`; регистр важен). Эти правила общие для писателя конфига, вывода и перезагрузки: правка меняет все три. Тесты: `codelab_agent_core/test/config/mask_url_test.dart` (правило имён и `displaySafeConfigValue`), `inline_secrets_test.dart`, `config_inline_secret_test.dart`, `config_secret_in_file_test.dart`; `codelab_agent_io/test/cli/config_get_masking_test.dart`, `config_output_test.dart`; `codelab_setup/test/views/mcp_server_entry_view_test.dart`.

**Добавить формат токена.** Строка в `_patterns` (`core/config/inline_secrets.dart`) на месте нужного приоритета; если шаблон нельзя написать без квадратичного перебора, — `_Pattern.custom` с однопроходным поиском. Источник формата — публичное описание, не чужие правила (`AGENTS.md` §5). Тест на линейное время обязателен. Тесты: `inline_secrets_test.dart`.

**Добавить точку применения на стороне агента.** Вывод значения конфига — только через `displaySafeConfigValue` или `maskConfigValue`: не писать вторую копию правила. Новый текст ошибки провайдера — через `describeHttpError` или `redactSecrets` с `config.secrets`. Новая запись лога — по правилу блока З: имена и источники вместо значений. Универсальный редактор потребует отдельного change (`redact.*` уже в схеме).

**Включить ключ `redact.*`.** Перевести узлы схемы в `applied: true`, добавить потребителя и убрать ожидание предупреждения `config.key.not_applied` в `config_redact_test.dart` и `config_not_applied_test.dart`.

Изменение правил маскирования — изменение наблюдаемого поведения безопасности: оно начинается с OpenSpec change (`AGENTS.md` §17), и затрагивает спецификации `agent-configuration` и `agent-secrets`.

## Справочные главы

- [Глава 07. Разрешения](../07-permissions.md) — режимы и политика; механизм маскирования не заменяет их.
- [Глава 09. Конфигурация, промпты, команды](../09-config-prompts-commands.md#путь-от-источников-до-coreconfig) — слои, доверие, секреты в конфиге.
- [Глава 10. Наблюдаемость и ошибки](../10-observability-and-errors.md#маскирование) — порт `Logger`, `HostLogger`, путь ошибки модели.
- Клиентская сторона: [`codelab_client_acp/doc/redaction.md`](../../../codelab_client_acp/doc/redaction.md).
- Соседние алгоритмы: [MCP](mcp.md) (секреты серверов), [вызов инструмента](tool-call.md).
- Нормы: [`agent-secrets`](../../../../../openspec/specs/agent-secrets/spec.md), [`agent-configuration`](../../../../../openspec/specs/agent-configuration/spec.md), [`approval-safety`](../../../../../openspec/specs/approval-safety/spec.md), [`structured-logging`](../../../../../openspec/specs/structured-logging/spec.md) (журнал клиентов).
- Архитектура: [`docs/architecture/observability.md`](../../../../../docs/architecture/observability.md).
