## MODIFIED Requirements

### Requirement: Редактирование секретов
CodeLab SHALL редактировать секреты в логах, диагностике, деталях инспектора и персистентном/debug-состоянии.

Правило секретных имён SHALL быть одним: оно действует везде, где редактор сверяет имя с правилом секретных имён (ключ map и любое другое место, где редактор проверяет имя), отдельного списка имён для других мест SHALL NOT быть. Имя секретное, если выполняется хотя бы одно (design.md change `extend-secret-name-redaction`, D1):
- имя содержит, без учёта регистра, одно из слов `api_key`, `auth`, `authorization`, `bearer`, `cookie`, `credential`, `jwt`, `pass`, `password`, `private_key`, `secret`, `session_token`, `session_cookie`, `session_secret`, `session_key`, `token`; в составных словах вместо `_` допустимы `-` и пустая строка (`api-key`, `apiKey`);
- имя содержит, без учёта регистра, `access_key`, `access-key` или `accesskey` (`AWS_ACCESS_KEY_ID`, `accessKeyId`);
- последний сегмент имени — `key`, отделённый `_` или `-`, без учёта регистра (`OPENAI_KEY`, `STRIPE_KEY`, `ENCRYPTION_KEY`, `SIGNING_KEY`, `Ocp-Apim-Subscription-Key`, `X-Functions-Key`);
- имя оканчивается на `Key` с заглавной `K` сразу после строчной латинской буквы или цифры (camelCase, с учётом регистра: `openaiKey`, `signingKey`, `subscriptionKey`).

Имя `key` целиком SHALL NOT считаться секретным: в структурных событиях это путь ключа настроек. Имена `keyboard`, `monkey`, `turnkey`, `hotkey`, `keys`, `key_count`, `keyId`, `KEY_ID`, `signing_key_id` SHALL NOT считаться секретными. Имена-идентификаторы с последним сегментом `key` или camelCase-окончанием `Key` (`cache_key`, `primary_key`, `sort_key`, `partition_key`, `foreign_key`, `idempotency_key`, `public_key`, `prompt_cache_key`, `hot_key`, `hotKey`, `primaryKey`, `cacheKey`) SHALL считаться секретными: это осознанная цена правила, а не дефект (D1).

Числовое значение (`num`) под именем поля-счётчика токенов секретом НЕ SHALL считаться и SHALL показываться как есть: это счётчик расхода модели (`subagent.end`, сжатие контекста), а не учётные данные (решение пользователя 2026-11-15; design.md change `add-subagents-and-tasks`, D41 п. 7). Имя — счётчик токенов, если одновременно:
- имя имеет вид `tokens`, `tokens_<…>` или `<…>_tokens` (слово `tokens` во множественном числе, разделитель `_` или `-`, регистр не важен);
- остаток имени после вырезания части `tokens` (первое вхождение `(^|[_-])tokens([_-]|$)`) НЕ совпадает с правилом секретных имён (`secret`, `password`, `api_key`, `auth`, `token`, `cookie`, `credential`, последний сегмент `key`, …);
- остаток имени, разбитый на сегменты по разделителям `_` и `-` (любое их число подряд, регистр не важен), НЕ содержит отдельным сегментом ни одного стоп-слова учётных данных: `access`, `refresh`, `id`, `csrf`, `otp`, `pin`, `session`, `key` (design.md change `extend-secret-name-redaction`, D2).

Так `tokens`, `tokens_in`, `tokens_out`, `input_tokens`, `max_output_tokens`, `tokens_before`, `Tokens-In` с числом видны, а `secret_tokens`, `tokens_api_key`, `auth_tokens`, `password_tokens`, `tokens_key` (правило секретных имён) и `access_tokens`, `refresh_tokens`, `id_tokens`, `csrf_tokens`, `otp_tokens`, `pin_tokens`, `session_tokens`, `tokens_session`, `session__tokens`, `key_tokens` (стоп-слова) скрываются при любом значении. Стоп-слово сравнивается с целым сегментом, а не с подстрокой: `input` и `output` не содержат сегмента `pin` или `id`, `monkey` — сегмента `key`. Строковое значение под именем-счётчиком, любое значение под другими именами правила (`token`, `access_token`, `session_token`, `api_key`, `password`, `secret`, …) и пары `key=value` внутри текста SHALL по-прежнему скрываться.

В тексте присваивание `имя=значение` или `имя: значение` (имя — непрерывная последовательность символов `A–Z`, `a–z`, `0–9`, `_`, `.`, `-`; вокруг `=` или `:` допустимы пробельные символы; значение — до пробельного символа, `,` или `;`) SHALL скрывать значение, если имя содержит одно из слов `api_key`, `cookie`, `credential`, `jwt`, `pass`, `password`, `private_key`, `secret`, `session_token`, `session_cookie`, `session_secret`, `session_key`, `token` или подпадает под признаки `access_key`, последнего сегмента `key` или camelCase-окончания `Key` правила секретных имён. Имя при этом SHALL оставаться видимым. Присваивание внутри значения несекретного имени SHALL проверяться так же: `url=https://h/x?access_token=abc` скрывает `abc` (D3).

В тексте учётные данные адреса SHALL скрываться: в фрагменте `<схема>://<userinfo>@` userinfo целиком — всё от `://` до последнего `@` перед первым `/`, `?`, `#`, пробельным символом, `"`, `<`, `>`, `\` или `` ` `` — SHALL заменяться на `<redacted>`. Правило SHALL действовать для строкового значения под любым ключом, в том числе несекретным (`DATABASE_URL`, `REDIS_DSN`). Фрагменты без `://` (`git@github.com:org/repo.git`, `mailto:a@b.c`) и `@` после `/`, `?` или `#` SHALL оставаться как есть. Userinfo без секрета (`ssh://git@host`) скрывается тоже: это осознанная цена (D4).

Каждое правило маскирования текста SHALL работать за время, линейное по длине входа, в том числе на строках без разделителей и на повторах секретного слова (D5).

#### Scenario: Отображаются переменные окружения
- **WHEN** launch environment показан в диагностике
- **THEN** значения, похожие на токены, пароли, API-ключи или приватные ключи, скрыты

#### Scenario: Открыт debug-лог
- **WHEN** пользователь открывает debug/протокольный лог
- **THEN** чувствительные prompt'ы и секреты скрыты, если явная настройка debug не разрешает их показ

#### Scenario: Счётчик токенов виден
- **WHEN** запись лога встроенного агента несёт поля `tokens: 1200`, `tokens_in: 900`, `tokens_out: 300`, `input_tokens: 800`, `tokens_before: 4000`, `max_output_tokens: 4096`, `Tokens-In: 7`, `monkey_tokens: 5`
- **THEN** журнал app и лог `codelab --verbose` показывают эти числа как есть (`secret_redaction_test.dart`)

#### Scenario: Секрет под похожим именем скрыт
- **WHEN** запись несёт поля `tokens: "abc123"`, `token: 123`, `access_token: 5`, `api_key: 42`, `session_token: "s"`, а текстовое поле — строку `tokens_in=sk-abc`
- **THEN** все пять значений скрыты как `<redacted>`, в тексте значение после `tokens_in=` скрыто (`secret_redaction_test.dart`)

#### Scenario: Счётчик с секретным словом скрыт
- **WHEN** запись несёт числовые поля `secret_tokens: 1`, `tokens_api_key: 1`, `auth_tokens: 1`, `password_tokens: 1`, `tokens_key: 1` (правило секретных имён) и `access_tokens: 1`, `refresh_tokens: 1`, `id_tokens: 1`, `csrf_tokens: 1`, `otp_tokens: 1`, `pin_tokens: 1`, `session_tokens: 1`, `tokens_session: 1`, `session__tokens: 1`, `Access-Tokens: 1`, `key_tokens: 1` (стоп-слова)
- **THEN** все значения скрыты как `<redacted>`, хотя они числа (`secret_redaction_test.dart`)

#### Scenario: Имя ключа с последним сегментом key скрыто
- **WHEN** запись несёт поля `OPENAI_KEY: "sk-1"`, `STRIPE_KEY: "sk_live_1"`, `ENCRYPTION_KEY: "k"`, `SIGNING_KEY: "k"`, `openai-key: "sk-2"`, `openaiKey: "sk-3"`, `signingKey: "k"`, `subscriptionKey: "k"`
- **THEN** все значения скрыты как `<redacted>` (`secret_redaction_test.dart`)

#### Scenario: Ключ доступа AWS скрыт
- **WHEN** запись несёт поля `AWS_ACCESS_KEY_ID: "AKIA1"`, `aws_access_key: "AKIA2"`, `accessKeyId: "AKIA3"`
- **THEN** все значения скрыты как `<redacted>`

#### Scenario: Заголовки ключей API скрыты
- **WHEN** запись несёт поля `Ocp-Apim-Subscription-Key: "abc"` и `X-Functions-Key: "def"`
- **THEN** оба значения скрыты как `<redacted>`

#### Scenario: Присваивание ключа в тексте скрыто
- **WHEN** маскируется текст `OPENAI_KEY=sk-1`, `X-Functions-Key: abc`, `export AWS_ACCESS_KEY_ID=AKIA1`, `openaiKey: sk-2`, `url=https://h/x?access_token=abc`
- **THEN** результат — `OPENAI_KEY=<redacted>`, `X-Functions-Key: <redacted>`, `export AWS_ACCESS_KEY_ID=<redacted>`, `openaiKey: <redacted>`, `url=https://h/x?access_token=<redacted>`

#### Scenario: Учётные данные адреса скрыты
- **WHEN** запись несёт поле `DATABASE_URL: "postgres://user:pass@db.local:5432/app"`, а текст — `REDIS_DSN=redis://:pw@cache:6379/0`, `clone https://ghp_abc@github.com/org/repo.git` и `mysql://u:p@ss@h/db`
- **THEN** значение поля — `postgres://<redacted>@db.local:5432/app`, в тексте — `REDIS_DSN=redis://<redacted>@cache:6379/0`, `clone https://<redacted>@github.com/org/repo.git` и `mysql://<redacted>@h/db`

#### Scenario: Адрес без учётных данных не меняется
- **WHEN** маскируется текст `https://example.com/a?u=a@b`, `https://example.com/@user`, `git@github.com:org/repo.git`, `mailto:a@b.c`, `https://example.com`
- **THEN** текст не меняется

#### Scenario: Похожие на ключ имена видны
- **WHEN** запись несёт поля `key: "providers.openai.api_key"`, `keyboard: "us"`, `monkey: "m"`, `hotkey: "ctrl+k"`, `keys: 3`, `key_count: 3`, `keyId: "k1"`, `KEY_ID: "k2"`, `signing_key_id: "k3"`, а текст — `keyboard=us`, `key_count=3`, `hotkey=ctrl+k`
- **THEN** все значения и текст показаны как есть

#### Scenario: Идентификатор под именем key скрыт осознанно
- **WHEN** запись несёт поля `cache_key: "c1"`, `primary_key: "id"`, `idempotency_key: "i1"`, `public_key: "ssh-ed25519 AAAA"`, `hotKey: "k"`
- **THEN** все значения скрыты как `<redacted>`: правило имён не отличает идентификатор от секрета (D1)

#### Scenario: Маскирование длинного текста за линейное время
- **WHEN** маскируются строки длиной около 256 KiB: без разделителей, из повторов `_key`, `access_key` или `token` без `=`, из повторов `://` без `@`, цепочка `x=x=…` и присваивание `OPENAI_KEY=` с длинным значением
- **THEN** каждая строка маскируется за время в пределах бюджета теста, а результат на коротких строках с секретами прежний (`secret_redaction_test.dart`)
