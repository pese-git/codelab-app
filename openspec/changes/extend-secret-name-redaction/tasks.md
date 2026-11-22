Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; `packages/dart/codelab_client_acp/AGENTS.md` §4). Красные тесты — отдельный коммит до кода; коммит — только по просьбе пользователя. В скобках — сценарий spec `approval-safety` «Редактирование секретов» или решение design.md.

Метки исполнителей:
- `[client]` — `packages/dart/codelab_client_acp` (код и тесты), проверки зависимых `codelab_client_core`, `apps/codelab_cli`, `apps/codelab_desktop`;
- `[protocol]`, `[agent]`, `[desktop]` — задач нет: правка кода `apps/codelab_desktop` не нужна, там только прогон существующих тестов (итерация 3).

Документы: `docs/architecture/**` и `openspec/**` — `codelab-architect` (без метки). README и `doc/` пакетов не меняются (design.md, D7).

Порядок с `redesign-protocol-pane`: если тот change влит в `develop` раньше, перед итерацией 1 обновить ветку от `develop` и разрешить конфликт по design.md, D3. Итерация 4 выполняется только после его слияния.

## 1. Красные тесты (итерация 1)

Файл — `packages/dart/codelab_client_acp/test/secret_redaction_test.dart`, стиль — как у существующих групп (таблица `имя → значение`, тест на каждую запись).

- [x] 1.1 `[client]` Группа «a key-like name is redacted» (сценарии «Имя ключа с последним сегментом key скрыто», «Ключ доступа AWS скрыт», «Заголовки ключей API скрыты»; D1): `OPENAI_KEY`, `STRIPE_KEY`, `ENCRYPTION_KEY`, `SIGNING_KEY`, `openai-key`, `openaiKey`, `signingKey`, `subscriptionKey`, `AWS_ACCESS_KEY_ID`, `aws_access_key`, `accessKeyId`, `Ocp-Apim-Subscription-Key`, `X-Functions-Key` со строковыми значениями → `redactedSecret`; то же через `redactMap` вложенного map. Сейчас красные все: прежнее правило их не видит.
- [x] 1.2 `[client]` Группа «a key-like name that is not a secret stays visible» (сценарий «Похожие на ключ имена видны»; D1): `key`, `keyboard`, `monkey`, `turnkey`, `hotkey`, `keys`, `key_count`, `keyId`, `KEY_ID`, `signing_key_id` — значение как есть, включая строку `key: "providers.openai.api_key"`; текст `keyboard=us`, `key_count=3`, `hotkey=ctrl+k` не меняется. Это страж: зелёный уже сейчас и должен остаться зелёным после 2.1.
- [x] 1.3 `[client]` Группа «an identifier under a key name is redacted by design» (сценарий «Идентификатор под именем key скрыт осознанно»; D1): `cache_key`, `primary_key`, `idempotency_key`, `public_key`, `hotKey` → `redactedSecret`. Комментарий теста — ссылка на D1 (цена правила, а не дефект). Сейчас красный.
- [x] 1.4 `[client]` Счётчики токенов (сценарии «Счётчик токенов виден», «Счётчик с секретным словом скрыт»; D2): в существующие таблицы добавить `monkey_tokens: 5` (видим, страж) и `tokens_key: 1`, `key_tokens: 1` (скрыты, красные). Прежние записи таблиц не меняются.
- [x] 1.5 `[client]` Группа «a key assignment in text is redacted» (сценарий «Присваивание ключа в тексте скрыто»; D3): `OPENAI_KEY=sk-1`, `X-Functions-Key: abc`, `export AWS_ACCESS_KEY_ID=AKIA1`, `openaiKey: sk-2` — значение скрыто, имя видно; `url=https://h/x?access_token=abc` → `url=https://h/x?access_token=<redacted>` (страж прежнего поведения, зелёный уже сейчас); `token=foo=abc` → `token=<redacted>`; `my_api_key=x` → `my_api_key=<redacted>`.
- [x] 1.6 `[client]` Группа «URL userinfo is redacted» (сценарии «Учётные данные адреса скрыты», «Адрес без учётных данных не меняется»; D4): `redact('postgres://user:pass@db.local:5432/app', key: 'DATABASE_URL')`; тексты `REDIS_DSN=redis://:pw@cache:6379/0`, `clone https://ghp_abc@github.com/org/repo.git`, `mysql://u:p@ss@h/db`, `ssh://git@host/repo` → `ssh://<redacted>@host/repo`; JSON-строка `{"url":"https://h","mail":"a@b.c"}` не меняется (граница на `"`); неизменные `https://example.com/a?u=a@b`, `https://example.com/@user`, `git@github.com:org/repo.git`, `mailto:a@b.c`, `https://example.com`; идемпотентность — `redactText(redactText(x)) == redactText(x)` для адреса с userinfo.
- [x] 1.7 `[client]` Группа «masking is linear in input length» (сценарий «Маскирование длинного текста за линейное время»; D5): `Stopwatch` и бюджет 2 с на строку (или бюджет файла, если тесты `redesign-protocol-pane` уже в `develop`) для `'a' * 262144`, `'_key' * 65536`, `'access_key' * 26214`, `'token' * 52428`, `'://' * 87381`, `'a://' + 'b' * 262140`, `'x=' * 131072`, `'OPENAI_KEY=' + 'v' * 262133`; для последней проверить и результат (`OPENAI_KEY=<redacted>`). Сейчас ожидаемо красные (квадратичный ведущий префикс и хвост прежнего шаблона): `'a' * …`, `'_key' * …`, `'access_key' * …`, `'token' * …`; остальные — стражи. Отметить в комментарии, какие строки красные до 2.2.

## 2. Реализация (итерация 2)

Файл — `packages/dart/codelab_client_acp/lib/src/domain/secret_redaction.dart`. Doc-комментарии на русском по §15 корневого `AGENTS.md` (почему, для чего, как) со ссылками на D1–D5 этого change и на требование spec; английские комментарии изменяемых сущностей переводятся.

- [x] 2.1 `[client]` Правило имён (1.1–1.4; D1, D2): регистронезависимый шаблон признаков `access[_-]?key` и `[_-]key$` и регистрозависимый `[a-z0-9]Key$` в приватной функции `_isKeyLikeName`; `_isSensitiveKey` — прежний шаблон `||` `_isKeyLikeName`; `key` в `_credentialStopWords` (doc-комментарий стоп-слов дополнить `key` и примером `key_tokens`). Публичный API без изменений.
- [x] 2.2 `[client]` Присваивания в тексте (1.5, 1.7; D3): шаблон `(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]+)\s*[:=]\s*`, проверка имени `_isSecretAssignmentName` (прежние слова текста или `_isKeyLikeName`), один проход с пропуском совпадений внутри скрытого значения `[^\s,;]+`, для несекретного имени — продолжение сразу после разделителя. Прежний `_assignmentSecretPattern` удаляется. Комментарий объясняет линейность и почему не шаблон со словами и хвостом (D3).
- [x] 2.3 `[client]` Userinfo адреса (1.6, 1.7; D4): шаблон `://[^/?#\s"<>\\`]*@` → `://<redacted>@` в `redactText` после `_authorizationPattern` и до присваиваний.
- [x] 2.4 `[client]` Прогнать весь `secret_redaction_test.dart`, `structured_logging_test.dart`, `codelab_client_acp_test.dart` — прежние ожидания не меняются. Если тест пакета ожидает видимым значение под новым секретным именем, это сигнал к сверке с D1, а не к правке теста молча: сообщить архитектору.

## 3. Документация и проверки (итерация 3)

- [x] 3.1 `docs/architecture/observability.md` §14 «Structured redaction»: вместо списка `authorization`, `token`, `api_key`, `password`, `secret` — правила редактора: слова; признаки `key` (последний сегмент, `access_key`, camelCase); имя `key` целиком не секрет; исключение счётчиков токенов; присваивания в тексте; userinfo адреса; линейное время. Ссылка на spec `approval-safety` «Редактирование секретов» и design.md этого change (D7).
- [x] 3.2 `[client]` Проверки затронутого (`AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_client_acp`;
  - зависимые пакеты, где используется `SecretRedactor` (`grep -rl SecretRedactor packages apps`): `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_client_core` и `apps/codelab_cli` (в том числе `test/e2e/headless_print_basic_test.dart`); `fvm flutter analyze` и `fvm flutter test test/features/workbench/application/connection_cubit_test.dart test/features/settings/application/mcp_settings_cubit_test.dart` в `apps/codelab_desktop`;
  - `fvm dart run melos run web-compile`: пакет web-безопасный, lookbehind (D3, D7);
  - `openspec validate extend-secret-name-redaction --strict`.

  `guard` не нужен: импорты и `pubspec.yaml` не меняются. `conformance:*` и `test:e2e:cli:*` не нужны: ACP-модели, транспорты и проводной формат не меняются, маскируется только представление. Полный `melos run check` — только по просьбе пользователя.

## 4. Пары `{name, value}` после слияния `redesign-protocol-pane` (итерация 4)

Условие: change `redesign-protocol-pane` влит в `develop`, и в `SecretRedactor` есть правило пары. Порядок слияния решён: этот change вливается первым (design.md, Q3).

- [ ] 4.1 `[client]` Тест пар в `secret_redaction_test.dart` (требование «Редактирование секретов», «везде, где редактор сверяет имя»; D6): `{"name": "OPENAI_KEY", "value": "sk-1"}`, `{"name": "Ocp-Apim-Subscription-Key", "value": "abc"}`, `{"name": "AWS_ACCESS_KEY_ID", "value": "AKIA1"}`, `{"name": "openaiKey", "value": "sk-2"}` → `value` скрыт, `name` виден; `{"name": "DATABASE_URL", "value": "postgres://u:p@h/db"}` → `value` = `postgres://<redacted>@h/db`; `{"name": "key", "value": "x"}` и `{"name": "keyboard", "value": "us"}` → `value` виден. Ожидается зелёный сразу: правило пары вызывает расширенный `_isSensitiveKey`. Если красный — правило пары завело свой список имён, что противоречит требованию; сообщить архитектору.
- [ ] 4.2 `[client]` Проверки 3.2 для `codelab_client_acp` повторно, после слияния.

## 5. Приватный ключ без строки `END` (итерация 5, D8)

- [x] 5.1 `[client]` Красный тест в `secret_redaction_test.dart` (сценарий «Приватный ключ без строки END скрыт»): `BEGIN` без `END` → всё от `BEGIN` скрыто; закрытый блок и текст после `END` — как прежде; линейное время на `'-----BEGIN RSA PRIVATE KEY-----' * N`.
- [ ] 5.2 `[client]` Реализация в `redactText`: поиск `BEGIN`/`END` в коде вместо одного шаблона (D8).
- [ ] 5.3 `[client]` Проверки `codelab_client_acp` и `openspec validate --strict`; `observability.md` §14 дополнить незакрытым блоком.
