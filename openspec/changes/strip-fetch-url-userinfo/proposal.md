## Why

Строка инструмента `fetch` показывает учётные данные из адреса. `ToolRowFormatter` (`packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart`) строит деталь `fetch` функцией `_withoutSchemeAndQuery`: она снимает схему `^scheme://` и отрезает всё от `?` или `#`. Потом `_clean` прогоняет деталь через `SecretRedactor.redactText`. Поэтому `rawInput.url` вида `https://user:pass@example.com/x?t=1` попадает в `ToolRowView.detail` как `user:pass@example.com/x`. Эту строку видят транскрипт app и CLI, копирование строки, снимки экрана и запись экрана.

Маскировка в `SecretRedactor` (`codelab_client_acp`) не помогает:

- в `develop` у `redactText` нет правила для userinfo адреса;
- правило `://…@` → `://<redacted>@` добавляет change `extend-secret-name-redaction` (D4), но он ещё не слит. Даже после слияния правило не сработает: оно ищет `://`, а схему `ToolRowFormatter` снимает раньше. Этот пробел нашёл архитектор того change и вынес в follow-up (его design.md, D6 и Q2).

Это утечка секрета в интерфейс (`AGENTS.md` §2, приоритет 1; §10: «Secrets и tokens НЕ ДОЛЖНЫ … попадать в logs»). Требование «Строка инструмента без сырого JSON» spec `acp-client-kit` и VIEW-9 (`dart-agent-and-clients` §12.1) уже запрещают query-строку в детали, потому что она может нести секрет. Userinfo несёт секрет чаще query, но правило о нём молчит.

## What Changes

- Деталь `fetch` теряет userinfo. После нормализации пробелов и управляющих символов и снятия схемы с ведущими слэшами `ToolRowFormatter` отбрасывает всё до последнего `@` в authority, то есть до первого `/`, `?` или `#` (`\` границей не считается). Адрес без схемы обрабатывается так же, authority считается от начала. `https://user:pass@example.com/x?t=1` → `example.com/x`; `https://example.com/a@b` не меняется (D1, D2).
- Требование «Строка инструмента без сырого JSON» (spec `acp-client-kit`): правило `fetch` перечисляет схему, userinfo, query-строку и фрагмент. Фрагмент код отбрасывает и сейчас, требование его просто называет. Добавлены сценарии: userinfo, пароль с `@`, `@` в пути, адрес без схемы.
- Внутренняя функция `_withoutSchemeAndQuery` переименовывается по новой ответственности. Её doc-комментарий и doc-комментарий `ToolRowFormatter` обновляются по `AGENTS.md` §15.
- Таблица §12.1.6 и инвариант VIEW-9 в `docs/architecture/proposals/dart-agent-and-clients/12-1-view-model.md` называют userinfo рядом с query-строкой (D5).

## Что НЕ входит

- Правило userinfo в `SecretRedactor.redactText` для свободного текста. Это change `extend-secret-name-redaction` (D4), здесь от него ничего не зависит (D3).
- Деталь вида `other` с ключом `url` и `title` вызова в запасном правиле детали. Userinfo там закрывает правило `extend-secret-name-redaction` после слияния, обоснование — D3, решение пользователя — не расширять (Q1).
- Адрес в других местах интерфейса: заголовок вызова в карточке одобрения и в инспекторе, текст результата инструмента. Они идут через `SecretRedactor` и правило `extend-secret-name-redaction`.
- Невалидный адрес с неэкранированным `/` в пароле (`https://u:pa/ss@h`). Граница authority по RFC 3986 проходит по `/`, и отличить такой адрес от `https://host/a@b` нельзя (D2, «Остаточные утечки»).
- ACP, протокольные модели, публичный API пакетов и форма `ToolRowView` не меняются.

## Impact

- Код: `packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart` — одна внутренняя функция и doc-комментарии.
- Тесты: `packages/dart/codelab_client_core/test/transcript/tool_row_test.dart`.
- Spec: `acp-client-kit`, требование «Строка инструмента без сырого JSON» (MODIFIED).
- Документы: `docs/architecture/proposals/dart-agent-and-clients/12-1-view-model.md` (§12.1.6, VIEW-9). `README.md` и `doc/` пакетов и `docs/user/` деталь `fetch` не описывают; правка не нужна.
- Хосты (`apps/codelab_desktop`, `apps/codelab_cli`) получают исправленную деталь из `ToolRowView` без своих правок.
