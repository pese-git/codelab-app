## Context

Задача 8.11 плана (`09-13-stage-8-mcp-config.md`, п. 11) объединяла две вещи:
- редакцию секретов (цель P-10, `agent-core-architecture` §12.4–§12.4.3);
- распознавание литеральных секретов в конфиге (пункты 2–3 CFG-9, `agent-parity-goals.md`, P-12).

Первая версия change покрывала обе. Двойное ревью change и итерации 0 нашло в части P-10 существенные пробелы (раздел «Перенесено после 1.0»). Пользователь 2026-11-04 принял решения:
- **R8-1.** До 1.0 агент работает «как Claude Code»: модель, журнал, запрос к провайдеру и кадры ACP видят всё как есть, P-10 переносится после 1.0.
- **R8-4.** Заменяет OQ2 и R8-2. Литеральный секрет в **файле** конфига — не ошибка загрузки ни в каком слое, а предупреждение с подсказкой `secret migrate`. Запись литерала через CLI по-прежнему отклоняется.
- **R8-3.** Кнопка переноса в codelab-app.

В 8.11 остаются:
- распознавание литералов в конфиге (предупреждение при загрузке, отказ записи, маскирование `args`);
- перенос `secret migrate`;
- кнопка в app.

Что уже есть в коде (на `develop`):
- **Ключи `redact.*`.** `config/redact_settings.dart`, узел `redact` в `config/schema.dart`, проверки `config/resolve.dart` и `config/trust.dart`. В реестре `redact` — `fileOnly` без потребителя: явно заданный ключ даёт `config.key.not_applied`.
- **Вычистка текстов ошибок провайдера.** `llm/providers/http_support.dart`: `redactSecrets(text, ProviderConfig.secrets)` (D7 change `add-agent-core-llm-contract`).
- **Правило литералов писателя и маскирования.** `config/secret_name_rule.dart` (`isSecretLikeName`, `hasSecretReference`), `codelab_agent_io/lib/src/config/literal_secret_rule.dart` (D5 change `add-config-writer-and-reload`), `cli/config_output.dart` (R0-2, R4-5).
- **CFG-9, п. 1 в валидаторе.** Проблема `inlineSecret`, `ConfigInlineSecretException` с `suggestedSecretName`, `inlineSecretKeys` в `config/config_issue.dart`. Провайдер с литеральным `api_key` сейчас не стартует (`core/config-rejects-inline-api-key`).
- **Ключ провайдера.** `ProviderConfig.apiKey` (готовое значение) и ссылки `ProviderKeyRef` (`EnvKeyRef`, `SecretKeyRef`, `llm/model_catalog.dart`). `api_key_env` и `api_key_secret` вместе — проблема.
- **Подкоманды `secret set|delete|list`.** `SecretCommands` и `SecretAdmin` (`codelab_agent_io`), мост `codelab_setup/io.dart`, разбор argv — `apps/codelab_agent/lib/src/cli/secret_cli.dart` и `apps/codelab_cli`.
- **Предупреждения конфига встроенного агента в app.** `localEmbeddedAgentOpener` пишет их через `logConfigWarnings(logger, loaded)` в логгер приложения (`CodeLabEmbeddedLogger` → структурный журнал и окно лога). В интерфейсе рабочего места их нет. Ошибка старта — `EmbeddedAgentConfigException` → `ClientWorkspaceException(message)` → баннер `ConnectionFailed` (`lib/app/embedded_transport_resolver.dart`, `CodeLabConnectionBanner`).

Ограничения:
- PKG-1, PKG-2, PKG-4 (`codelab_agent_core/AGENTS.md`);
- CFG-5;
- `AGENTS.md` §3.4 (ACP не меняется), §5 (сторонний код), §6 (нет IO в виджетах), §9 и §12 (поздние результаты), §10 (доверие).

## Goals / Non-Goals

**Goals:**
- литеральные секреты в файлах конфига (CFG-9, пп. 1–3, R1-1, DSN по L5) видны: предупреждение при загрузке и в `config check` с подсказкой `secret migrate`;
- запись литерала через CLI и app по-прежнему отклоняется (D5 change `add-config-writer-and-reload`, OQ3);
- `config get` маскирует `args` (R4-6);
- литеральный `providers.<id>.api_key` работает как ключ провайдера;
- `secret migrate` у обоих бинарей и кнопка в codelab-app с безопасным порядком записей;
- ни одного нового поля ACP, ни одной новой зависимости ядра.

**Non-Goals** (после 1.0, R8-1):
- редакция вывода инструментов, промпта, payload, журнала и кадров ACP (P-10);
- `Redactor`, `RedactingLogger`;
- `AgentTool.redactResult` и `readPathOf`;
- прогресс `exec` по строкам;
- применение `redact.*`;
- `/redact`, P-14, P-18, P-19.

## Decisions

### D1. До 1.0 модель и журнал видят всё как есть (R8-1)

Вывод инструментов, промпт пользователя, payload провайдера, журнал сессии и кадры ACP в 1.0 **не редактируются**. P-10 в `agent-parity-goals.md` получает этап «после 1.0» со ссылкой на R8-1 и находки ревью. §12.4–§12.4.3 документа ядра целиком помечаются «после 1.0»: разделы не переписываются (архитектурная находка №5).

Почему (решение пользователя 2026-11-04):
- в P-10 ревью нашло пробелы H1–H3, M1, M3–M9, а закрывать их до 1.0 ради цели уровня *Should* — большой объём;
- модель всё равно читает файлы рабочей папки, а редакция вывода — эвристика, не граница безопасности: короткий, нестандартный или разрезанный потоком секрет проходит;
- журнал лежит в `$CODELAB_HOME` с правами пользователя рядом с исходными файлами.

*Альтернативы:*
- (а) **P-10 целиком в 8.11** (первая версия change). Отклонено R8-1; сохранено как вход будущего change.
- (б) **Как Claude Code** — вывод модели не редактируется, транскрипт хранится как есть, `.mcp.json` допускает литералы. Принято для 1.0.
- (в) **Как Codex** — вывод модели не редактируется, но окружение подпроцессов фильтруется по именам с `KEY`, `SECRET`, `TOKEN`. Отклонено для 8.11: это меняет поведение `exec` — сборки и тесты читают `NPM_TOKEN` и подобные. Путь размечен как фильтр `exec.env`/`exec.secrets` (§17.12.6, после MVP) и рассматривается вместе с P-14.

### D2. Защита лога и текстов ошибок в 1.0; ключи `redact.*`

Нового `Redactor` и `RedactingLogger` нет. Лог ядра на `info` и выше не содержит текстов сообщений и аргументов (§12.3), значения секретов не пишутся ни в одно событие (CFG-10), `mcp.server.stderr` — только `trace`. Тексты ошибок провайдера проходят `redactSecrets(ProviderConfig.secrets)`. С D4 туда входит и литеральный `api_key` от 8 символов. Не-HTTP исключения транспорта (`FormatException` и подобные, текст которых может процитировать заголовок) в текст ошибки хода попадают только через `redactSecrets` или одним именем типа, без сырого `toString()`.

Логгер только с точными значениями закрыл бы `debug`/`trace`. Но рядом остаётся сырой журнал (D1), так что защита одного лога асимметрична и малоценна. Логгер придёт с P-10.

Ключи `redact.*` остаются `not_applied`: у них нет потребителя. Решение пользователя OQ1 («все `redact.*` — только после перезапуска») сохранено для будущего change.

*Альтернатива:* `RedactingLogger` с точными значениями. Отклонено по доводу выше; записано во входы будущего change.

### D3. Распознавание: `literalSecretTag`, `findInlineSecrets`

Функции живут в ядре: `codelab_agent_core/lib/src/config/inline_secrets.dart`, публичный барель (находка №8). Ими пользуются валидатор, писатель и маскирование в `codelab_agent_io` и `secret migrate`. Копии нет — довод D5 change `add-config-writer-and-reload`.

```dart
/// Тег первого совпадения шаблона §12.4 (formats, pem, connection_strings, key_values)
/// в литеральных частях value; null — литерала нет. Значение и его части не возвращаются.
/// asName: значение — имя (п. 3: api_key_env, api_key_secret, имя в ${…}); шаблон sk- — только
/// в начале значения.
String? literalSecretTag(String value, {bool asName = false});

/// Узкий предикат «в строке есть литеральный секрет» для маскера config get и плана
/// перезагрузки (R0-4, D12): без пути ключа и без вида находки.
bool hasInlineSecret(String value);

enum InlineSecretKind { inlineKey, literalPart, nameLiteral, referenceName }

final class InlineSecretFinding {
  final String keyPath;              // providers.lm.api_key, mcp.servers[gh].headers.Authorization
  final InlineSecretKind kind;
  final String tag;                  // inline-key, sk, github, connection-string, …
  final String suggestedSecretName;  // SecretNames.suggestFor / SecretNames.forMcp
  final List<(int, int)> spans;      // участки секрета в значении (literalPart, referenceName)
}

/// Находки одного слоя: CFG-9 пп. 1–3 (виды — D7).
List<InlineSecretFinding> findInlineSecrets(ConfigTree layer);
```

Публичный барель экспортирует через `show` ровно пять символов: `InlineSecretFinding`, `InlineSecretKind`, `findInlineSecrets`, `literalSecretTag`, `hasInlineSecret`. Функция `valueFindings` (находки одного значения) — внутренняя.

- **Шаблоны** — таблица §12.4: `sk-…`, GitHub, AWS, Google, Slack, JWT, Bearer, PEM, присваивание секрета, URL с паролем. Хранятся в `config/inline_secrets.dart`, будущий редактор P-10 возьмёт их отсюда.
  - В Dart нет встроенного `(?i)` — используется `caseSensitive: false`.
  - **Отступления от таблицы §12.4** (линейность и ложные срабатывания; ревью итерации 1):
    - в «присваивании секрета» части имени ограничены 64 символами;
    - JWT: заголовок не длиннее 256 символов, а поиск идёт без `RegExp` — сканированием по `eyJ` и точкам (повторы `eyJ` давали квадратичный перебор);
    - «URL с паролем»: схема не длиннее 31 символа;
    - пробелы между частями шаблонов — `\s{0,16}` вместо `\s*`;
    - PEM: метка между `BEGIN`/`END` — `{0,32}` символов, а участок секрета заканчивается на строке `END` (а не жадным `[\s\S]*` до последнего `END`).

    Записываются в §12.4 как отступления реализации; будущий редактор P-10 берёт шаблоны вместе с ними.
  - Встроенный белый список `git_sha`, `uuid` учитывается.
  - Шаблоны пишутся для CodeLab; правила gitleaks, detect-secrets, trufflehog не копируются (`AGENTS.md` §5; пункт ревью каждой итерации).
- **Литеральные части.** Значение режется по `${…}`: `Bearer ${secret:x}` проходит, `Bearer ghp_… ${X}` — нет (R1-1).
- **Имена в п. 3** (`api_key_env`, `api_key_secret`, имя в `${secret:…}` и `${VAR}`). Шаблон `sk-…` для имени применяется только **в начале** значения: имя `codelab/sk-test-…`, предложенное подсказкой, иначе ложно считалось бы ключом. Токен вместо имени переменной в `${ghp_…}` — находка `referenceName` (п. 3 расширен на `${VAR}`): в шаблоне — маркер `UnusableSecretReference`, окружение не читается, **проблемы загрузки нет — только предупреждение** (R8-4). MCP-сервер с таким заголовком — `failed`, провайдер — ошибка `auth` хода; тексты имени не содержат. Подсказки имён `SecretNames` (`suggestFor`, `forMcp`) не меняются: правка их сборки в итерации 1 откатывается.
- **DSN, разрезанный подстановкой** (L5). Пароль userinfo URL (`user:password@`), который не состоит целиком из одной `${…}`, — находка `connection-string`: `postgres://u:lit${X}@h/db` — находка, `postgres://u:${PW}@h/db` — нет.
- **`url`/`base_url`** в `config get` после `maskUrl` (R4-5) дополнительно проверяются шаблонами: токен в пути или под несекретным именем query-параметра даёт `<redacted>` всего значения (ревью итерации 1, D5).
- **`url`/`base_url` с userinfo** при загрузке не распознаются (L5). `${secret:…}` там запрещён, перенос невозможен, а `config get` уже печатает URL без userinfo (R4-5). Граница — в Risks.

### D4. Литерал в файле конфига — предупреждение (R8-4)

Решение пользователя 2026-11-04 заменяет OQ2 (ошибка загрузки) и R8-2 (исключение для недоверенного проекта). Находки `findInlineSecrets` в **файловых** слоях (`user`, `project`, `projectLocal`, `CODELAB_CONFIG`/`--config`) дают **предупреждение** `config.secret.in_file {key, source}` — по одному на находку. Находки считаются по слою, независимо от `enabled` элемента: предупреждения выключенных серверов не откатываются вместе с их проблемами (`resolve.dart`, откат предупреждений выключенных серверов). Шаблон текста один и тот же везде — D4, требования `agent-configuration`, сценарии, §15.4, §17.5.4 (английский, без значения):

```text
<key>: a secret is stored in the config file; move it to the secret store: <command>
```

`<command>`:
- `codelab secret migrate` — у слоя `user`;
- `codelab secret migrate --project` и `codelab secret migrate --local` — у проектных слоёв;
- `codelab secret set <suggestedSecretName>` — у `CODELAB_CONFIG`/`--config`: `migrate` этот файл не пишет (D7), и совет переноса там был бы тупиком. `ConfigIssue` предупреждения несёт файл, строку и столбец. `config check` печатает его строкой `warning:`, код выхода не меняется. Проблемы `inlineSecret` для файловых слоёв больше нет; `ConfigInlineSecretException` остаётся у писателя и предконфигурации.

**Что значит каждая находка при загрузке:**

| Находка | Поведение |
|---|---|
| `providers.<id>.api_key: ${VAR}` или `${secret:x}` (R8-8, решение пользователя 2026-11-04) | **ссылка, не литерал**: раскрывается как в заголовках (`${VAR}` при загрузке, `${secret:x}` — резолвером при запросе), предупреждения нет, `migrate` не трогает. Вместе с `api_key_env`/`api_key_secret` — R8-6; в R0-4 — как подстановка (D12) |
| `providers.<id>.api_key` (литерал) | **используется как ключ провайдера**: `ProviderConfig.apiKey`, без резолвера. Литерал длиной от 8 символов попадает в `ProviderConfig.secrets` и вычищается из текстов ошибок (D2). Порог действует **только для литерального `api_key` из файла**: ключи из хранилища и окружения вычищаются без порога, как раньше. Более короткие литералы (`x`, `ollama`) не вычищаются, иначе текст ошибки превратился бы в маркеры (Risks). Литерал с управляющими или не-ASCII символами — проблема загрузки `value` без значения (`api_key must be printable ASCII`): такой ключ не уйдёт в заголовок HTTP, а исключение транспорта могло бы его процитировать. Та же проверка для литерала секретно названного заголовка провайдера — `<Header> must be printable ASCII`. В MCP-заголовках проверки нет: транспорт MCP отдаёт только тип ошибки. Смесь литерала и ссылки в `api_key` (`sk-… ${secret:x}`) — проблема `api_key may use ${secret:…} only as the whole value`. **Механизм порога:** флаг `ProviderConfig.literalApiKey` ставит только загрузка конфига (хосты его не выставляют); при нём `redactSecrets` пропускает ключ короче 8 символов. **R8-6:** `api_key` вместе с `api_key_env` или `api_key_secret` у одного провайдера **после слияния слоёв** — проблема загрузки `value` с ключом `providers.<id>.api_key` и текстом `api_key, api_key_env and api_key_secret are mutually exclusive`. Это конфликт источников, а не «секрет в файле»: то же правило, что для пары `api_key_env` + `api_key_secret` |
| прочие `inlineSecretKeys` (`apiKey`, `token`, `secret`, `password` у провайдера; любые у элемента `mcp.servers`) | предупреждение; ключ **не применяется**: у этих полей нет смысла в схеме (раньше они давали проблему и тоже не применялись). Предупреждение подсказывает `secret migrate`, который сохраняет значение и показывает, куда сослаться (D7) |
| литеральная часть `headers.*`/`env.*` провайдеров и MCP-серверов (п. 2, R1-1, DSN) | предупреждение; значение **применяется как есть** (как в `.mcp.json` Claude Code) |
| `api_key_env`/`api_key_secret`/имя в `${secret:…}`, похожие на ключ (п. 3) | предупреждение; **проблемы формата имени нет**: при `literalSecretTag(value) != null` проверка формата не выполняется. В `CoreConfig` такое значение попадает **не как ссылка**, а как маркер: `UnusableKeyRef(keyPath)` у ключа провайдера (ветка `ProviderKeyRef`) и `UnusableSecretReference` в шаблоне заголовка или `env` (провайдера и MCP-сервера). Ход с заголовком провайдера `${secret:<токен>}` получает ошибку `API key reference providers.<id>.headers.<H> looks like a secret value, not a name; run: codelab secret migrate`. Маркер исключён из поиска в хранилище в `config check` (строки `secret <имя> is not set`), из `config.provider.key_missing`, `providerProblems` и `secrets.lookup`/`--debug-secrets`. Ход с этим провайдером получает ошибку `auth` без HTTP-запроса и без значения: `API key reference providers.<id>.<key> looks like a secret value, not a name; run: codelab secret migrate`; MCP-сервер — `failed` с тем же текстом для своего ключа (требование `agent-secrets` «Секреты MCP-серверов конфигурации»). Почему так: иначе токен ушёл бы как *имя* в тексты ошибок и события, то есть именно туда, где имена печатаются |

**Недоверенный проектный слой.** Правило доверия §15.3 и так отбрасывает его `providers.*` и `mcp.servers` с предупреждением `config.project.untrusted_key`. Предупреждения `config.secret.in_file` для таких ключей **нет** — принято самостоятельно:
- секрет в чужом репозитории — не секрет пользователя, а `secret migrate` его не переносит (H4, D7); подсказка «перенесите в своё хранилище» вела бы в тупик;
- достаточно одного предупреждения `untrusted_key` (без значения).

Отдельное правило R8-2 не нужно.

**Реестр и запись ключа.** Дескриптор `providers.*.api_key` в `SettingsRegistry` — `fileOnly`, `secret: true` (тест полноты CFG-19): ключ читается из файла, а клиенты его не пишут. `provider add` включает `api_key` в `_keySourceFields` (`provider_commands.dart`, R4-4): `--api-key-stdin|--api-key-secret|--api-key-env` удаляют литеральный `api_key` той же правкой, и пары источников не остаётся (R8-6).

**`provider list`** показывает источник ключа: `key: literal in config file` — без значения; для `api_key: ${VAR}` — `env <VAR>: set|not set`; для `api_key: ${secret:x}` — `secret x: found|not set|unavailable`. `config get` маскирует литеральный `api_key` и ссылку п. 3 (D5).

**Предконфигурация из окружения** (`env:CODELAB_PROVIDER_CONFIG`, `…_BASE64`, `--provider-config`) не меняется. `--provider-config @путь` читает файл, но это **не слой конфига** — значение флага: перенос невозможен, а `api_key` там остаётся проблемой `inlineSecret`. `api_key` там — проблема `inlineSecret` (L-25, D3 change `add-config-writer-and-reload`). Принято самостоятельно:
- R8-4 говорит о **файле** конфига;
- у предконфигурации есть `api_key_env`, а окружение — источник ключа;
- `secret migrate` её не переносит.

*Альтернативы* (решение пользователя 2026-11-04 — оставить R8-4):
- (А) **Ошибка загрузки** (прежний OQ2). Отклонено:
  - это BREAKING для конфигов, правленных руками;
  - ложные срабатывания шаблонов отказывали бы в старте;
  - понадобилось бы исключение для недоверенного проекта (R8-2).
- (Б) **Только хранилище, без ссылок на окружение** (`api_key_env`, `${VAR}`). Отклонено: ломает `OPENAI_API_KEY`-сценарии, предконфигурацию L-25 и CI.
- Путь Claude Code до 1.0: `.mcp.json` допускает литералы, а предупреждение с готовой командой переноса лучше отказа старта.

### D5. Запись и R4-6

- **Писатель** (`literal_secret_rule.dart`, CLI `config set`, `mcp add`, `provider add` и будущие страницы настроек) применяет `literalSecretTag` к изменённым значениям `headers`, `env` и к элементам `mcp.servers[*].args` и отклоняет запись `ConfigInlineSecretException` (OQ3). У элемента `args` подсказка — `--env <NAME>='${secret:<name>}'`. Литерал, уже лежащий в файле, переходит в предупреждения записи, как и раньше. Правило имён D5 change `add-config-writer-and-reload` и CFG-9 п. 1 на записи не меняются. CLI и app не пишут секрет значением никогда.
- **Загрузка `args` не проверяет** (OQ3): CFG-9 их не покрывает, а некоторые серверы принимают токен только аргументом.
- **`config get`** маскирует элементы `args`:
  - элемент с `literalSecretTag != null` → `<redacted>`;
  - элемент после флага с секретным именем по `isSecretLikeName` (`--token X`) → `<redacted>`;
  - `--api-key=X` → `--api-key=<redacted>`;
  - ссылки `${…}` — как есть.

  `mcp list` элементы `args` не печатает.
- **`url`/`base_url` в `config get`:** после `maskUrl` (без userinfo, секретные query — R4-5) значение проверяется `hasInlineSecret`; находка (токен в пути, под несекретным именем query) → `<redacted>`.
- **Маскер `config get` и `provider list`** (`config_output.dart`) прогоняет через `findInlineSecrets` и `literalSecretTag` **все** листья, включая листья реестра и значения с `${…}`. Ранний выход «лист реестра печатается как есть» больше не пропускает литеральный `api_key` и ссылку п. 3: такие листья печатаются как `<redacted>`.

### D6. Имя секрета, похожее на значение

`secret set|delete <name>` с `literalSecretTag(name) != null` — ошибка использования `64`: `the secret name looks like a secret value; pass the value on stdin`. Имя не печатается, хранилище не вызывается. `SecretNames.problem` не меняется.

### D7. Подкоманда `secret migrate` (решение 2026-11-03; удобство после R8-4)

```text
secret migrate [--project | --local | --all] [--cwd <dir>] [--dry-run] [--force]
```

**Код.** Движок `SecretMigrator` (`codelab_agent_io/lib/src/secrets/secret_migrator.dart`) возвращает типизированный `SecretMigrationReport` — пункты без значений и итог. `SecretCommands.migrate` печатает его строками. App вызывает тот же движок через `codelab_embedded/io.dart` (D8); CLI — через `codelab_setup/io.dart`. У пункта есть `describe()` — тот же английский текст, что строка CLI.

**Чтение конфига.** С R8-4 литералы загрузку не блокируют, поэтому мягкий режим загрузчика (находка L9) **не нужен**: команда загружает конфиг обычным `ConfigLoader` со всеми проверками — containment ссылок 8.5, доверием, синтаксисом. Любая проблема загрузки — код `1` с проблемой, как у `config check`. Бэкенд — из `secrets.backend`.

**Находки и правки** — находки `findInlineSecrets` в применяемых слоях (D4):

| Вид | Где | Правка файла |
|---|---|---|
| `inlineKey` | `providers.<id>.api_key` / `apiKey` | ключ удаляется, ставится `api_key_secret: <name>` |
| `inlineKey` | прочие `inlineSecretKeys` у провайдера или элемента `mcp.servers` (`mcp.servers[gh].token`) | значение **сначала** сохраняется в хранилище, затем ключ удаляется (архитектурная находка №3); строка `action required: reference ${secret:<name>} in <место>` |
| `literalPart` | `headers`/`env` | участок → `${secret:<name>}`, остальное и подстановки сохраняются; следующие участки одного значения — `<name>-2`, `<name>-3` (не пул `<name>_2` §17.10.4) |
| `nameLiteral` | `api_key_env` / `api_key_secret` | `api_key_secret: <name>` (`api_key_env` удаляется той же правкой) |
| `referenceName` | `${secret:<литерал>}` | литерал — значение секрета, ссылка → `${secret:<name>}` |

`<name>` — `suggestedSecretName` находки, то есть то же имя, что в подсказке предупреждения.

**Не переносятся:**
- `mcp.servers[*].args` → строка `not migrated: mcp.servers[<n>].args[<i>] looks like a secret (<tag>); pass it to the server via --env <NAME>='${secret:codelab/mcp/<n>/<name>}'`;
- литералы, которых не распознаёт `findInlineSecrets`;
- **недоверенные проектные слои** (H4): значение такого слоя **никогда** не попадает в хранилище; при `--project`/`--local`/`--all` в недоверенном проекте — строка `not migrated: <path> is an untrusted project config`;
- `CODELAB_CONFIG` → `not migrated: <source> is not a writable layer`;
- значение, которое хранилище не примет (`secretValueProblem`, `secret_value_checks.dart`: перевод строки — например PEM; больше 64 КиБ; непарный суррогат), → `not migrated: <key> cannot be stored (<причина>)`. Причина — текст `secretValueProblem` (`secret value must be a single line`, `… longer than 64 KiB`, `… not valid Unicode (unpaired surrogate)`), без значения.

Строки `not migrated` код выхода не меняют. Литерал там не блокирует загрузку (R8-4), а значит, и не является сбоем.

**Слои:**
- по умолчанию — `user`, как у `config set`;
- `--project`, `--local` — слои проекта `--cwd` (иначе каталога процесса);
- `--all` — `user`, `project`, `local`;
- `--all` вместе с `--project`/`--local` — `64`;
- `-C`/`--cwd` верхнего уровня у `codelab secret` запрещён, `--cwd` — флаг подкоманды.

**Порядок и атомарность** (H4, №3, L7):
1. **Проверка без записи:**
   - загрузка и находки;
   - **проверка доверия писателя** для каждой правки проектного слоя (H4) — правка, которую писатель отклонил бы, превращает находку в `not migrated`, и значение не читается для хранилища;
   - `SecretAdmin.checkStore`;
   - `secretValueProblem` каждого значения;
   - конфликты имён;
   - кандидат каждого файла через `ConfigLoader.validateCandidate`, без новых проблем.

   Любой отказ — без единой записи.
2. **Конфликт имени:**
   - внутри запуска то же значение — один секрет; **другое значение — следующее свободное имя `<name>-2`, `<name>-3`** в порядке слоёв (`user`, `project`, `local`), затем порядка файла. Ссылка в файле получает это имя, план показывает его. Пример — шлюз с `api_key` и `headers.X-Gateway-Key` с разными значениями или одноимённые ключи пользовательского и проектного слоя. Отказ всего запуска из-за двух законных находок был бы хуже различимого суффикса. Имена `forMcp` разных серверов, которые совпали после нормализации (`GH`/`gh`, `my server`/`my-server`, обрезка до 50 символов), разводятся так же;
   - с хранилищем то же значение — `Reused secret <name>` без записи, другое — код `1` до записи (`secret <name> already exists with a different value; rerun with --force to replace it`);
   - `--force` перезаписывает **безвозвратно** (L7): `warning: replaced the existing secret <name>; the previous value cannot be restored; also referenced by: <ключи>`. В конце перечислены ключи всех слоёв загруженного конфига, которые ссылаются на это имя (например, пользовательский ключ при `--project --force`). Если таких нет, хвоста нет.
3. По файлу: сначала секреты файла (`SecretAdmin.store`), затем **одна** атомарная `ConfigWriter.apply` (lock, отпечаток, tmp и `rename`; комментарии сохраняет `yaml_edit`). `ConfigConflictException` — одно перечитывание и повтор шага 1 для файла.
4. **Сбой записи конфига после секретов** — код `1`, stderr называет сохранённые имена, файл не изменён. Это безопасно: значения уже были открытым текстом в конфиге, повтор их переиспользует. Сбой хранилища посреди файла — код `1`, конфиг файла не пишется. Перенесённые раньше файлы остаются перенесёнными; общей транзакции нет (§13).

**`--dry-run`** — шаги 1–2 полностью, включая конфликты, суффиксы и `cannot be stored`. План `<path>: <ключ> -> <ссылка> (new|reuse|replace)` и строки `action required`/`not migrated`, без записи; код — как у настоящего запуска.

**Вывод и коды:**
- строки `Moved <ключ> in <path> to secret <name>`; без находок — `Nothing to migrate`;
- значения, длины, префиксы, хеши не печатаются; stdin не читается;
- коды: `0` — успех; `1` — хранилище только для чтения или недоступно, конфликт, отказ писателя, новая проблема кандидата, проблема загрузки; `64` — использование;
- бэкенд только для чтения (`env`, в том числе при `auto`) — код `1` с подсказкой: `secrets.backend: file` или переменные `CODELAB_SECRET_<…>` (имена, не значения).

**После переноса** работающий агент подхватывает изменение перезагрузкой конфига, но смена источника ключа провайдера с ключом и HTTP-серверов с подстановками требует перезапуска (R0-4, D8 change `add-config-writer-and-reload`). `secret migrate` печатает последней строкой `restart the agent to use the moved secrets`, если что-то перенесено.

*Альтернативы:*
- (а) ручной `secret set` по каждому ключу — много шагов и ручная правка YAML;
- (б) `config migrate-secrets` — операция прежде всего пишет в хранилище, а проверки бэкенда и имён уже у `secret`.

### D8. Кнопка «Перенести секреты» в codelab-app (R8-3, после R8-4)

С R8-4 агент со секретами в файле **стартует**. Предупреждения конфига сейчас видны только в окне лога (Context). Минимальный путь показать их в UI:

1. **`codelab_embedded`** (основной барель, web-безопасный): у `EmbeddedAgent` есть `bool get secretsInConfig`. Его вычисляет открыватель (`localEmbeddedAgentOpener`): `true`, если среди предупреждений загрузки есть `config.secret.in_file`. App не может назвать тип ядра (PKG-4), поэтому признак вычисляет мост. `scriptedEmbeddedAgentOpener` отдаёт `false`. Признак вычисляется **при открытии**: после переноса предупреждение держится до переподключения. Это граница: перезагрузка конфига признак не пересчитывает.
2. **Резолвер** (`lib/app/embedded_transport_resolver.dart`) после успешного открытия передаёт признак в `SecretMigrationOffer` — источник состояния уровня app, созданный composition root. При закрытии агента признак сбрасывается. `codelab_client_core` и ACP не меняются: признак касается только встроенного агента app.
3. **Порт** `SecretMigrationRunner` (`features/workbench/application/`): `plan(cwd)` и `apply(cwd)` → пункты `describe()`, признаки «можно применить» и «бэкенд только для чтения». Реализация — в `lib/app/` через `SecretMigrator`, который отдаёт **`package:codelab_embedded/io.dart`**: мост уже зависит от `codelab_agent_io`, а app уже импортирует `codelab_embedded/io.dart` из `lib/app/` (`localEmbeddedAgentOpener`). Нового ребра графа, правки allowlist и правила сторожа нет. App не зависит от `codelab_setup`, а `codelab_setup` остаётся мостом CLI. Параметры движка: `--all` для папки проекта, без `--force`; **тот же** `CODELAB_HOME`, `CODELAB_CONFIG` и окружение, что у открывателя встроенного агента (`app_scope.dart`, где создаётся `localEmbeddedAgentOpener`). Тексты `planFailed`/`applyFailed` и лог app строятся только из типизированного отчёта или имени типа исключения, никогда из `error.toString()`: исключение разбора YAML может нести фрагмент строки с литералом. Подсказка для бэкенда `env` на Windows — та же ветка, что у `secret set` (только переменные). Порт оправдан (§13): изолирует файловый IO и хранилище, Cubit тестируется на фейке. Виджеты IO не делают (`AGENTS.md` §6).
4. **`SecretMigrationCubit`** — явный автомат:

   ```text
   hidden → offered → planning → planReady(items, canApply) | planFailed(message)
          → applying → applied | applyFailed(message)
   ```

   Поздний результат после `close` или новой попытки отбрасывается по номеру попытки (`AGENTS.md` §9, §12). `applied` → кнопка `Restart agent`.
5. **Presentation workbench.** При `offered` над транскриптом — Fluent `InfoBar` уровня `warning`, рядом с баннером соединения и тем же способом (`CodeLabConnectionBanner` тоже построен на `InfoBar`). Текст `Secrets are stored in the agent config file.`, кнопка `Migrate secrets`. Закрытие крестиком скрывает `InfoBar` до следующего подключения. Диалог:
   - план (строки `describe()`);
   - бэкенд `env` — `Secrets cannot be stored: the env backend is read-only. Add secrets.backend: file to <home>/config.yaml, or set CODELAB_SECRET_* variables.` и только `Close`;
   - конфликт имени с хранилищем — текст конфликта и `Close` (`--force` в app нет: перезапись безвозвратна, L7);
   - все находки только в `CODELAB_CONFIG` (`not migrated`) — строки плана и только `Close`;
   - иначе — `Migrate` и `Cancel`.

   После `applied`: `Secrets moved. Restart the embedded agent to use them.` и кнопка `Restart agent` — повторное подключение тем же профилем, оно закрывает прежнего агента (D6 change `add-embedded-agent-mode`). Во время идущего хода `Restart agent` недоступна, а подсказка говорит дождаться конца хода. Тексты английские, как остальной UI app.

Старт **не блокируется**. `ConnectionFailed` из-за конфига (другие проблемы) показывается по-прежнему.

*Альтернативы:*
- (а) Показывать все предупреждения конфига в UI. Отклонено как шире задачи: отдельная страница диагностики — change `add-provider-setup-ui`.
- (б) Разбирать события лога. Отклонено: лог не контракт.
- (в) Вызывать процесс `codelab secret migrate`. Отклонено: зависимость от установленного бинаря и разбор текста.

### D9. Пакеты, зависимости, сторож

| Пакет | Что меняется | Метка |
|---|---|---|
| `codelab_agent_core` | `config/inline_secrets.dart` (публичный барель, D3); `config/resolve.dart` — предупреждения, литеральный `api_key`, правило трёх источников, неразрешаемые ссылки п. 3 (D4); `llm/` — `ProviderConfig.apiKey` из литерала, ошибка ссылки п. 3 | `[agent]` |
| `codelab_agent_io` | `config/literal_secret_rule.dart` и `cli/config_output.dart` (D5); `secrets/secret_migrator.dart` и `cli/secret_commands.dart` (D6, D7); `cli/mcp_server_commands.dart` — `--header-stdin`, `--env-stdin`, `--header-scheme` (D11); `config_warnings.dart` — текст `config check` | `[agent]` |
| `codelab_setup` | `io.dart` реэкспортирует для CLI `SecretMigrator`, `SecretMigrationReport`, опции, пункты и опции `mcp add` (находка №7 — отдельная задача) | `[agent]` |
| `codelab_embedded` | `EmbeddedAgent.secretsInConfig`; `io.dart` реэкспортирует для app `SecretMigrator`, `SecretMigrationReport`, опции и пункты (D8) | `[agent]` |
| `apps/codelab_agent` | `cli/secret_cli.dart` — `migrate`; argv `mcp add` — флаги stdin (D11) | `[agent]` |
| `apps/codelab_cli` | argv `secret migrate` и флагов stdin `mcp add`, e2e (D7, D11) | `[client]` |
| `apps/codelab_desktop` | `lib/app/` — резолвер, `SecretMigrationOffer`, реализация порта через `codelab_embedded/io.dart`; `features/workbench/` — порт, Cubit, `InfoBar` и диалог (D8) | `[desktop]` |
| `docs/architecture/**`, вложенные `AGENTS.md` | итерация 0, сверка | `[docs]` |

Новых пакетов и зависимостей нет, PKG-2 не меняется. Направление зависимостей и рёбра графа прежние: app берёт мигратор из `codelab_embedded/io.dart`, на который уже опирается, а `codelab_embedded` уже зависит от `codelab_agent_io`. Правило сторожа и allowlist не меняются; граф в `README.md` — тоже. `inline_secrets.dart` использует только `RegExp` и `Uri` (web-безопасно); `codelab_embedded/io.dart` — не основной барель, его `dart:io` допустим.

### D10. Итерации

Каждая — отдельный PR в `develop`:
0. документы;
1. распознавание и предупреждения загрузки: `findInlineSecrets` до правки валидатора (находка №10), литеральный `api_key`, правило источников (R8-6), ссылки п. 3 (маркер), реестр, литералы в перезагрузке (D12);
2. писатель и R4-6;
3. `secret set|delete` с именем-значением, `secret migrate` (движок, мост, оба бинаря), `mcp add --header-stdin|--env-stdin` (D11), строки справки R8-7 (D13);
4. app (`codelab_embedded` и `[desktop]`);
5. матрица и DoD.

Зависимости: 2 ← 1; 3 ← 1, 2; 4 ← 3; 5 ← все.

### D11. `mcp add --header-stdin` и `--env-stdin` (R8-5, решение пользователя 2026-11-04)

Запись литерала через argv CLI по-прежнему отклоняется (D5). Чтобы добавить сервер с токеном одной командой, у `mcp add` обоих бинарей (общая реализация `McpServerCommands`, `codelab` — через `codelab_setup/io.dart`) появляются флаги по схеме `provider add --api-key-stdin`:

```text
mcp add <name> … [--header-stdin <Name> [--header-scheme <Scheme>] | --env-stdin <NAME>] [--project|--local]
```

- **Значение** читается из stdin через `SecretInput`, как у `secret set` и `--api-key-stdin`: с TTY — скрытый ввод с подсказкой в stderr, без TTY — поток без одного завершающего перевода строки. Пустое значение, перевод строки внутри или не UTF-8 — ошибка значения `64` (тексты `SecretInput`: `empty secret value` и т. д.); значение не печатается никогда.
- **Имя секрета** — `SecretNames.forMcp(server, key)`, то есть `codelab/mcp/<server>/<key>` в нижнем регистре. Это то же имя, что называют подсказки ошибок и предупреждений сейчас (agent-secrets «Имена секретов»). Отдельного сегмента `env/` нет: правило имён общее для заголовков и `env`, и подсказки уже его печатают. Совпадение заголовка `Authorization` и переменной `AUTHORIZATION` одного сервера даёт одно имя — граница записана в Risks.
- **В файл** пишется `headers.<Name>: "${secret:<имя>}"` или `env.<NAME>: "${secret:<имя>}"`. С `--header-scheme Bearer` пишется `"Bearer ${secret:<имя>}"`, а в хранилище лежит только токен. Почему отдельный флаг, а не «весь заголовок из stdin»:
  - в хранилище остаётся сам секрет, и его можно переиспользовать в `env` другого сервера;
  - префикс схемы — не секрет и виден в конфиге;
  - пользователю не нужно помнить пробел после `Bearer`.

  Без `--header-scheme` значение stdin — весь заголовок (для `X-Api-Key` и подобных). `--header-scheme` без `--header-stdin` — `64`.
- **Ровно один флаг `-stdin` на вызов**, иначе `64` (`only one of --header-stdin, --env-stdin can be used per call`). stdin один: два значения потребовали бы протокола разделителей, неоднозначного при скрытом вводе с TTY. Второй секрет того же сервера добавляется повторным `mcp add` с тем же набором флагов, где первый задан ссылкой `--header Name='${secret:codelab/mcp/<server>/<key>}'` (`UpsertMcpServer` заменяет элемент по ключам), либо заранее через `secret set`.
- **Хранилище:** бэкенд только для чтения (`env`, `auto`) — код `1`, stdin не читается, подсказка та же, что у `--api-key-stdin` (`secrets.backend: file` или переменная `CODELAB_SECRET_<…>` с именем переменной).
- **Конфликт** с существующим секретом — как у `provider add`: замена и строка `warning: replaced the existing secret <имя>`. Это не `secret migrate`: здесь человек сам вводит новое значение для этого сервера, а в `migrate` значение берётся из файла и может принадлежать другому месту.
- **Порядок** — как у `--api-key-stdin` и D7:
  1. кандидат конфига без записи (`validateCandidate`, доверие, реестр);
  2. `SecretAdmin.checkStore`;
  3. чтение stdin;
  4. `SecretAdmin.store`;
  5. одна атомарная `ConfigWriter.apply`.

  Сбой записи конфига после сохранения — код `1`, stderr называет сохранённое имя.
- **Совместимость.** `--header Name='${secret:…}'`, `--header Name='${VAR}'` и `--env K='${…}'` работают как раньше. Флаг `-stdin` с тем же именем заголовка (без учёта регистра) или переменной, что и в `--header`/`--env`, — `64`.
- **Имя, похожее на токен.** `--header-stdin <Name>` или `--env-stdin <NAME>` с `literalSecretTag(Name) != null` — `64`, имя не печатается (как D6).
- **Коллизия имён.** `forMcp` нормализует имя: `GH` и `gh`, `my server` и `my-server`, обрезка до 50 символов. Поэтому до чтения stdin, кодом `1`, команда отказывает в двух случаях:
  - целевое имя секрета упоминается в загруженном конфиге (`${secret:<имя>}` или `api_key_secret`) другим сервером или провайдером;
  - `forMcp` другого сервера конфига даёт то же имя.

  Текст: `secret <имя> is already used by <ключ>; store the value with codelab secret set <другое имя> and reference it with --header/--env`. Замена без вопроса допустима только для собственного имени этого же сервера (повторный `mcp add`).

### D12. Литералы и живая перезагрузка (R0-4)

Литерал может увести секрет на новый адрес так же, как подстановка: смена `url` HTTP-сервера с литеральным `Authorization` или `base_url` провайдера с литеральным `api_key`. Поэтому правило R0-4 (D8 change `add-config-writer-and-reload`) расширяется — `config_reload_plan.dart`:
- **`api_key` входит в атомарную группу провайдера** (`_providerGroup`): его правка откладывается вместе с `base_url`, `headers` и остальными полями группы.
- **Провайдер «с ключом»** (`_providerWithKey`) — также при литеральном `api_key` или при любой находке `findInlineSecrets` в элементе провайдера.
- **MCP-сервер «с подстановкой»** (`_serverHasSubstitution`) — также при любой находке `findInlineSecrets` в `url`, `headers`, `env` или в ключах `inlineSecretKeys` элемента, **и** при литерале в заголовке с секретным именем (`isSecretLikeName`), как у провайдера. Ссылка `api_key: ${…}` (R8-8) — подстановка. Тогда HTTP-сервер с литеральным `Authorization` при смене `url` ждёт перезапуска.
- **Новый провайдер или сервер с литералом** — только после перезапуска, как с подстановкой.

Требование `agent-runtime` «Живая перезагрузка конфигурации» меняется MODIFIED-дельтой (шаг 4), таблица §17.5.6 — в итерации 0. Тест — в итерации 1.

### D13. Предупреждение пользователю о 1.0 (R8-7, решение пользователя 2026-11-04)

Пользователь должен знать, что до 1.0 провайдер, журнал и ACP получают секреты как есть (D1). Строка добавляется в справку `codelab-agent serve`, `codelab-agent secret`, `codelab secret` и в общую справку `codelab --help`. У `codelab` нет `serve`: агентом он пользуется через встроенный режим, и общая справка — его аналог. Текст:

```text
Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.
```

Раздел «Известные ограничения» в `CHANGELOG.md` или release notes: файла пока нет, поэтому это задача релизного чек-листа — создать раздел в ветке `release/*` (задача 5.5). Сам файл этот change не создаёт.


*Альтернатива:* разрешить литерал в argv (`claude mcp add --header "Authorization: Bearer …"` в Claude Code). Отклонено решением R8-5: значение argv оседает в истории shell, видно в `ps` другим пользователям машины и попадает в логи CI. Сторонние отчёты об утечках через этот путь в Claude Code (issues, не проверено нами): [anthropics/claude-code#18692](https://github.com/anthropics/claude-code/issues/18692) — `claude mcp add` записывал раскрытые значения в `.mcp.json`; [claudeissues.com #62705](https://claudeissues.com/issue/62705-claude-mcp-list-prints-expanded-env-values-in-plain-text-leaking-secrets-to-term) — `claude mcp list` печатал раскрытые `${ENV}` в терминал. Флаг `-stdin` даёт ту же одну команду без этих каналов утечки.

## Перенесено после 1.0: вход будущего change редакции (P-10)

Сохраняется как вход будущего change; в 8.11 не реализуется.

**Решения первой версии этого change** (их полный текст — в истории git этого change до решения R8-1):
- `final class Redactor` (`redact`, `redactJson`, `addExactSecret`, `addEnvironment`, `isExemptTool`, `generation`); точка `error`; `findSecrets` и `stats` — со своими потребителями.
- Послойный алгоритм §12.4.1:
  - совпадения по исходному тексту, перекрытия — по приоритету слоя;
  - идемпотентность через пропуск участка внутри маркера;
  - переводы строк сохраняются;
  - `entropy` выключен.
- Точные секреты только растут. Источники: резолвер, окружение по `isSecretSourceName` (без значений-путей), литералы конфига до замены снимка, MCP-серверы `session/new`/`session/load`. С R8-4 к ним добавляются литералы файлов конфига (D4).
- Точки:
  - `userInput`, `toolResult` (до усечения, повторно после `afterToolCall`);
  - прогресс `exec` по строкам (PEM держится до `END`, буфер 64 КиБ);
  - `journal` при записи и открытии без перезаписи файла;
  - `providerRequest` с кэшем по сообщению и поколению;
  - `log` через `RedactingLogger` хоста;
  - `error`.
- `AgentTool.redactResult` (`false` у `write`/`edit`) и `readPathOf`.
- Кадры ACP: `tool_call`/`request_permission` в эфире не редактируются; `tool_call_update` редактируется; реплей — из редактированного журнала.
- Один экземпляр редактора на процесс у резолвера, логгера и `AgentCoreServices`.

**Решения пользователя для будущего change:**
- OQ1 — все `redact.*` только после перезапуска;
- OQ4 — `agent_message_chunk` в эфире не редактируется;
- OQ5 — старые журналы редактируются при открытии.

**Альтернатива Codex** — фильтр окружения подпроцессов по `KEY|SECRET|TOKEN` (D1, в), вместе с P-14 и `exec.env`.

**Находки ревью безопасности итерации 0 (2026-11-04) по редакции** — будущий change закрывает каждую явным решением:
- **H1. Пути отмены и исключений обходят точку `toolResult`.** До шага редакции возвращаются:
  - `ToolCancelled` отменённого `exec` с хвостом вывода (`_tail(error.outputTail)`);
  - исключения инструментов и MCP (`errorText`);
  - исключение `afterToolCall`;
  - `block.reason` из `beforeToolCall`.

  Места: `executor.dart:331-342`, `exec.dart:133-137`. Исправление — идемпотентный проход в `_finish` (`executor.dart:376`); тест «отмена `exec env` посреди вывода».
- **H2. Освобождение `write`/`edit` выпускает содержимое файла пользователя.** Результат `edit` содержит 3 строки контекста исходного файла (`unified_diff.dart`), а `FileDiff.oldText`/`newText` — файл целиком в журнале без редакции. Исправление — редактировать `diff` журнала (или не хранить `oldText`) и строки контекста (` `) в результате `edit`.
- **H3. Цикл «маркер → запись в файл» портит данные.** Модель берёт `oldText` или содержимое из прочитанного с маркером, и `write`/`edit` записывает `[REDACTED]` вместо ключа. Исправление — `preflight` `write`/`edit` отклоняет новый маркер, которого нет в текущем файле; остаток через `exec` — в Risks и P-14.
- **M1. Сжатие идёт мимо `providerRequest`.** `summarizer.dart:106-117` вызывает `stream` напрямую. Исправление — точка как декоратор `StreamFunction` в `buildAgentCore` и требование редактированного `writer.snapshot`.
- **M3. Ложные точные секреты из окружения.** `GIT_AUTHOR_NAME`/`EMAIL` (`AUTH` в `AUTHOR`), `*_KEYMAP`, `AUTH_URL`; слой `exact` не снимается. Исправление — сопоставление по `_`-сегментам, исключения `AUTHOR` и `*_PATH|_FILE|_DIR|_SOCK`, URL без userinfo или ключ `redact.exempt_env`.
- **M4. Выбор без пересечений оставляет остаток большего секрета** (точный секрет внутри участка нижнего слоя). Исправление — заменять объединение участков.
- **M5. ReDoS.** Белый список применяется к участку неограниченной длины. Шаблоны квадратичны на враждебном входе: PEM `[\s\S]*?` при многих `BEGIN`, `a://b:` без `@`, повторы `eyJ`. Исправление — враждебный корпус на каждый шаблон, предел длины участка для белого списка, окно PEM.
- **M6. Редакция в UI isolate.** Встроенный агент desktop работает не в отдельном isolate (`app_scope.dart:172`), а синхронная редакция в UI isolate нарушает `AGENTS.md` §12. Нужны бюджеты под UI или агент в отдельном isolate (отдельный change).
- **M7. Порядок при `session/load`.** Секреты MCP из `session/load` регистрируются уже после редакции снимка. Исправление — хранить `generation` со снимком и редактировать заново при расхождении.
- **M8. Неполные формы точных значений.** Регистрировать значение после схемы (`Bearer`, `token`; для `Basic` — декодированный `user:pass`), percent- и base64-формы; `Basic` — в `formats`.
- **M9. Неразрешённые значения хранилища невидимы слою `exact`** (`exec cat $CODELAB_HOME/secrets.yaml`). Хост с бэкендом `file` регистрирует все значения при старте и изменении; `exec.env` и `auth_header` добавляются в источники.
- **L1–L8:**
  - L1 — усечение до редакции (`_tail`, `read`, stderr MCP ≤ 4 КиБ) режет секрет;
  - L2 — скользящий хвост буфера прогресса;
  - L3 — `readPathOf` по сырому аргументу (`foo -> .env`, `./x/../.env`): сопоставлять разрешённый путь;
  - L4 — утверждение «модель видит только редактированный контекст» неверно;
  - L6 — `redactJson` по записям `custom` портит служебные данные;
  - L8 — прямой stderr хоста идёт мимо логгера.
- **NIT.** У точки `error` два входа (`_onEvent`, `_sessionEvent`); проверять и верхний `error.message`.
- **Архитектурные:**
  - №1 — аргументы истории после открытия журнала уходят модели редактированными: принять в решениях о `journal`/`toolResult` или хранить как есть;
  - №11 — окно между итерациями, когда `redact.*` применяются только к логу;
  - №13 — альтернатива: переиспользовать клиентский `SecretRedactor` (`codelab_client_acp/lib/src/domain/secret_redaction.dart`) или общий нейтральный модуль.

**Находки, решённые здесь:**
- M2 → снята R8-4 (D4);
- H4, №3, L7 → D7;
- L9 → не нужна после R8-4 (D7, «Чтение конфига»);
- L5 → D3 и Risks;
- №5 → D1;
- №7, №8 → D9, D3;
- №10 → D10;
- №12 → дельта `agent-secrets`.

## Risks / Trade-offs

- **[Секреты видны модели и лежат в журнале]** (D1) Вывод `exec env`, `read .env`, промпт с ключом и литералы конфига уходят провайдеру и в журнал как есть — сознательно, как у Claude Code. P-10 — после 1.0.
- **[Секрет в проектном конфиге уйдёт в git]** (R8-4) Предупреждение `config.secret.in_file` показывает проблему, но не предотвращает коммит. `config check` и кнопка app подсказывают перенос, CLI и app литерал не пишут.
- **[Литеральный `api_key` в файле — рабочий ключ]** Ослабление CFG-2 и P-12. Компенсации: предупреждение, перенос одной командой, запрет записи CLI/app, вычистка значения из текстов ошибок провайдера (D2).
- **[Ссылка п. 3 не разрешается]** Провайдер с `api_key_env: ghp_…` перестаёт работать. Так значение не уходит как имя в тексты ошибок и `secrets.lookup`, а ошибка хода говорит, что делать.
- **[Ложные срабатывания шаблонов]** Несекретное значение `env`, похожее на присваивание или JWT, даёт лишнее предупреждение (не отказ). Обход — `${VAR}`.
- **[`--force` безвозвратен]** (L7) Сказано в выводе, в app не предлагается.
- **[Частичный перенос, значения в хранилище после сбоя конфига]** Каждый файл атомарен; повтор переиспользует значения; stderr называет сохранённые имена.
- **[`url`/`base_url` с паролем]** (L5) Не распознаются; `config get` печатает без userinfo (R4-5); перенос в заголовок — вручную.
- **[Конфликт источников ключа]** (R8-6) Литеральный `api_key` в одном слое и `api_key_secret`/`api_key_env` в другом после слияния дают проблему загрузки: агент не стартует, пока источник не один. Текст называет ключ, значения не содержит; `provider add --api-key-*` и `secret migrate` убирают литерал.
- **[Короткие литеральные ключи]** Литеральный `api_key` из файла короче 8 символов не вычищается из текстов ошибок провайдера (D4): иначе слова вроде `ollama` превращались бы в маркеры. Такие «ключи» локальных серверов — не секреты. Ключи из хранилища и окружения вычищаются без порога.
- **[Ключ с управляющими символами]** Литерал `api_key` с управляющими или не-ASCII символами — проблема загрузки без значения (D4). Не-HTTP исключения транспорта в текст ошибки хода попадают через `redactSecrets` или именем типа (D2).
- **[`api_key` и явный заголовок авторизации]** (NIT2 ревью) R8-6 не ловит пару `api_key` и явный `headers.<auth_header>` с `${secret:x}`: побеждает заголовок, а ключ молча не используется. Это известная неоднозначность.
- **[Межсерверная коллизия имён]** (D7, D11) `forMcp` нормализует имена серверов (`GH`/`gh`). `mcp add --*-stdin` отказывает при занятом имени. `secret migrate` разводит имена суффиксом `-2`, а `--force` называет ключи, которые ссылаются на заменяемое имя.
- **[Признак app вычисляется при открытии]** (D8) После переноса предупреждение держится до переподключения.
- **[Одно имя для заголовка и переменной]** (D11) `--header-stdin Authorization` и `--env-stdin AUTHORIZATION` одного сервера дают имя `codelab/mcp/<server>/authorization`; второй вызов заменит секрет с предупреждением. Это редкость; обход — `secret set` под своим именем и ссылка `${secret:…}`.
- **[`args` MCP]** Загрузкой не распознаются (OQ3). Запись отклоняется, `config get` маскирует, `migrate` подсказывает `--env`.
- **[Гонки в app]** Номер попытки отбрасывает поздний `plan`/`apply`. Перезапуск агента недоступен во время хода. IO — в фоне через порт (`AGENTS.md` §12).
- **[Права]** Политика разрешений не меняется. Доверие проектных слоёв проверяется до записи в хранилище (H4); недоверенные значения в хранилище не попадают.

## Migration Plan

- BREAKING нет: литералы в файлах загружаются с предупреждением (R8-4). Конфиги, которые раньше не стартовали из-за литерального `api_key` (CFG-9, п. 1, с 8.9), теперь стартуют. Исключение — `api_key` вместе с `api_key_env`/`api_key_secret`: это проблема «три источника ключа».
- Перенос по желанию: `codelab secret migrate --all --dry-run`, затем `--all`, или кнопка в app; затем перезапуск агента.
- Журналы и формат хранилища не меняются. Откат — revert PR итерации.

## Open Questions

Открытых вопросов нет. Решения пользователя:

| # | Решение | Где отражено |
|---|---|---|
| R8-1 (2026-11-04) | до 1.0 «как Claude Code»: вывод инструментов, промпт, payload, журнал, ACP не редактируются; P-10 — после 1.0 | D1, D2; «Перенесено после 1.0»; задачи 0.x, 5.1 |
| R8-4 (2026-11-04) | литерал в файле конфига — предупреждение с подсказкой `secret migrate` в любом слое, не ошибка; запись CLI литерал отклоняет; заменяет OQ2 и R8-2 | D4, D5; agent-configuration; задачи 1.x |
| R8-3 (2026-11-04) | кнопка «Перенести секреты» в codelab-app; после R8-4 — предупреждение работающего агента, не блокировка | D8; embedded-agent, agent-workbench-ui; задачи 4.x |
| R8-5 (2026-11-04) | запись литерала через argv CLI отклоняется; взамен `mcp add --header-stdin`/`--env-stdin` (один флаг на вызов, значение — в хранилище, в файл — ссылка) | D5, D11; agent-configuration, codelab-cli, agent-binary; задачи 3.x |
| R8-6 (2026-11-04) | литеральный `api_key` + `api_key_secret`/`api_key_env` у одного провайдера после слияния слоёв — проблема загрузки (конфликт источников) | D4; Risks; agent-configuration; задача 1.2 |
| R8-8 (2026-11-04) | `api_key: ${VAR}` / `${secret:x}` — ссылка (как в заголовках), не литерал: без предупреждения, R8-6 и R0-4 — как для подстановки, `migrate` не трогает | D4, D12; agent-configuration, agent-secrets |
| R8-7 (2026-11-04) | предупредить пользователя: строка в справке `secret` и `serve` обоих бинарей; раздел «Известные ограничения» в CHANGELOG/release notes — в `release/*` | D13; agent-binary, codelab-cli; задачи 3.6, 3.7, 5.5 |
| R8-4, повтор (2026-11-04) | после повторного ревью оставлено: литерал — предупреждение; альтернативы А (ошибка загрузки) и Б (без ссылок на окружение) отклонены | D4 |
| OQ2 (2026-11-03) | ошибка загрузки — **заменено R8-4** | — |
| R8-2 (2026-11-04) | исключение для недоверенного проекта — **снято R8-4**; для недоверенных ключей предупреждения `in_file` нет (D4) | D4 |
| OQ2+ (2026-11-03) | перенос одной командой `secret migrate` у обоих бинарей | D7 |
| OQ3 (2026-11-03) | `args` — маскирование вывода и отказ записи; загрузка не проверяет | D5 |
| OQ1, OQ4, OQ5 (2026-11-03) | `redact.*` только после перезапуска; эфир `agent_message_chunk` не редактируется; старые журналы — при открытии | сохранены для будущего change P-10 |
