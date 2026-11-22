## Why

`SecretRedactor` (`packages/dart/codelab_client_acp/lib/src/domain/secret_redaction.dart`) — единственный редактор секретов клиента. Через него проходят журнал app и `codelab --verbose`, диагностика, инспектор и строки инструментов транскрипта. Правило секретных имён (`_sensitiveKeyPattern`) ловит `api_key`, `token`, `secret`, `password` и подобные слова, но не видит частые имена ключей без этих слов. Ревью безопасности нашло, что открытыми остаются:

- имена, у которых последний сегмент — `key`, но нет `api`: `OPENAI_KEY`, `STRIPE_KEY`, `ENCRYPTION_KEY`, `SIGNING_KEY`, и их camelCase-формы (`openaiKey`, `signingKey`);
- `AWS_ACCESS_KEY_ID` и `accessKeyId`: сегмент `key` здесь не последний;
- HTTP-заголовки `Ocp-Apim-Subscription-Key` (Azure API Management) и `X-Functions-Key` (Azure Functions);
- адреса с учётными данными в значении: `DATABASE_URL`, `*_DSN` = `postgres://user:pass@host/db`. Имя переменной не секретное, а пароль лежит в userinfo адреса.

Утечка секрета в журнал или диагностику нарушает приоритет 1 (`AGENTS.md` §2) и правила §10 и §16: секреты не попадают в журналы и маскируются до логгера.

## What Changes

- **Правило секретных имён** (ключ map и любое другое место, где редактор сверяет имя с этим правилом) получает три новых признака:
  - последний сегмент имени — `key`, отделённый `_` или `-`, регистр не важен: `OPENAI_KEY`, `X-Functions-Key`;
  - в имени есть `access_key`, `access-key` или `accesskey`, регистр не важен: `AWS_ACCESS_KEY_ID`, `accessKeyId`;
  - имя оканчивается на `Key` после строчной буквы или цифры (camelCase, регистр важен): `openaiKey`, `subscriptionKey`.

  Имя `key` целиком секретом не считается (D1). Не скрываются `keyboard`, `monkey`, `hotkey`, `keys`, `key_count`. Скрываются как осознанная цена `cache_key`, `primary_key`, `sort_key`, `idempotency_key`, `public_key` и подобные (D1).
- **Исключение счётчиков токенов** (D41 п. 7 change `add-subagents-and-tasks`): `key` становится стоп-словом. `tokens_key: 1` и `key_tokens: 1` скрываются, `tokens_in: 900` и остальные счётчики видны, как прежде (D2).
- **Присваивания в тексте** (`имя=значение`, `имя: значение`) — те же три признака `key` вдобавок к прежним словам. `OPENAI_KEY=sk-…` в выводе терминала и `X-Functions-Key: …` в тексте ошибки маскируются. Шаблон переписан так, что время работы линейно, включая длинные строки без разделителей и повторы секретного слова (D3).
- **Учётные данные в адресе**: в тексте `<схема>://<userinfo>@` userinfo целиком заменяется на `<redacted>`: `postgres://<redacted>@host/db`. Правило действует для любого строкового значения, в том числе под несекретным ключом (`DATABASE_URL`) (D4).
- **Линейное время** — требование ко всем шаблонам текста, с регрессионными тестами на строках 256 KiB (D5).
- **Документация:** `docs/architecture/observability.md` §14 «Structured redaction» — вместо примера из пяти имён описание правил (D7).

## Не входит

- **Агентская сторона.** У неё свои правила: `isSecretLikeName` и `isSecretScalarName` (`codelab_agent_core/lib/src/config/secret_name_rule.dart`), `maskUrl`, маскирование настроек и MCP в `codelab_setup`, будущий редактор ядра (задача 8.11, `RedactSettings`). Клиентские пакеты не зависят от `codelab_agent_*` (ADR-0002), общего кода нет (D6).
- **`ToolRow._withoutSchemeAndQuery`** (`codelab_client_core`). Он снимает схему адреса `fetch` до маскирования, поэтому `https://user:pass@host` в строке инструмента остаётся `user:pass@host/…`, и правило D4 это место не закрывает. Это отдельная правка `codelab_client_core`: follow-up, открытый вопрос Q2 в design.md.
- **Пара `{name, value}`** (`HttpHeader`, `EnvVariable` ACP). Правило пары вводит change `redesign-protocol-pane` (D4 того change, ещё не в `develop`). Оно вызывает то же правило имён и получит новые имена без отдельной правки. Здесь пары не вводятся, а тесты пары с новыми именами добавляются после слияния того change (tasks.md, итерация 4).
- Секреты в JSON внутри строки (`"api_key":"…"` в тексте: между именем и `:` стоит кавычка), секреты без имени (голый `sk-…`), секреты в query адреса без секретного имени параметра. Поведение для них не меняется.
- Невалидные адреса с неэкранированным `/` в пароле (`://u:pa/ss@h`): граница userinfo по RFC 3986 — первый `/`, такой адрес не маскируется (design.md, Risks).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `approval-safety` — требование «Редактирование секретов»: новые секретные имена с `key`, признак `access_key`, camelCase `…Key`, стоп-слово `key` в исключении счётчиков, текстовые присваивания с новыми именами, userinfo адреса, линейное время.

## Impact

- **Пакеты:** код — только `packages/dart/codelab_client_acp` (`lib/src/domain/secret_redaction.dart`, `test/secret_redaction_test.dart`). Публичный API не меняется: `SecretRedactor`, `redactedSecret` и сигнатуры прежние. Новых зависимостей нет. Правила сторожа и граф пакетов в `README.md` не меняются. Пакет остаётся web-безопасным (`RegExp`, без новых импортов).
- **Наблюдаемое поведение:** в журнале app, `codelab --verbose`, диагностике, инспекторе и строках инструментов (`codelab_client_core`, `apps/codelab_desktop`, `apps/codelab_cli`) больше значений показывается как `<redacted>`. В том числе ложные срабатывания: `cache_key`, `primary_key`, `public_key`, `hotKey` и userinfo в `ssh://git@host` (D1, D4).
- **Параллельный change `redesign-protocol-pane`** (ветка `feature/redesign-protocol-pane`) правит ту же строку `_assignmentSecretPattern`. При слиянии будет конфликт; как его разрешить, описано в design.md (D3).
