Пары «тест → реализация»: сначала красный тест. Коммит красного теста — только по просьбе пользователя (`CLAUDE.md`). Сценарии — требование «Строка инструмента без сырого JSON» spec `acp-client-kit` (далее «Строка»). Все пути кода — в `packages/dart/codelab_client_core`.

## 1. Красные тесты

- [x] 1.1 `[client]` В `test/transcript/tool_row_test.dart`, рядом с тестом `example.com/docs`, добавить тесты `fetch`:
  - `https://user:pass@example.com/x?t=1` → `ToolRowView(label: 'Fetch', detail: 'example.com/x')`; деталь не содержит `user` и `pass` («Строка»: «Адрес fetch теряет userinfo»; D1, D2);
  - `https://user:p@ss@example.com/x` → деталь `example.com/x`; нет `user`, `p@ss`, `ss@` («Строка»: «Пароль адреса fetch с символом @»; D2, последний `@`);
  - `https://example.com/a@b` → деталь `example.com/a@b` («Строка»: «Символ @ в пути адреса fetch»; D2);
  - `user:pass@example.com/x` → деталь `example.com/x`; нет `user` и `pass` («Строка»: «Адрес fetch без схемы с userinfo»; D2).

  Красные: первый, второй и четвёртый (деталь сейчас `user:pass@example.com/x`). Третий зелёный и остаётся регрессионным. Существующий тест `example.com/docs` не меняется («Строка»: «URL без query-строки»).
- [x] 1.2 `[client]` Там же — табличный тест строк D2, которых нет в сценариях: `https://ghp_token@github.com/org/repo` → `github.com/org/repo`, `https://example.com?u=a@b` → `example.com`, `ssh://git@host/repo` → `host/repo`, `https://example.com#a@b` → `example.com`. Красные — те, где `@` стоит в authority.

- [x] 1.3 `[client]` По ревью: тест обходов D2 — `//user:pass@host/x`, ` https://…`, `\nhttps://…`, `ht\ttps://…`, `https:///…`, `https:/…`, `https:/\…`, `https:\\…`, `https:user:pass@host/x`, `https://h\user:pass@host/x`, NBSP/BOM/U+3000 в начале, `https:// /user:pass@host/x`, ` / /user:pass@host/x` → `host/x` без `pass`; в таблицу — `localhost:8080/x` без изменений, `https://h\a@b/x` → `b/x`, ведущие слэши у `/docs/a@b` и `https:///x` снимаются; в тест пароля с `@` — проверка `p@ss`.

## 2. Реализация

- [x] 2.1 `[client]` `lib/src/transcript/tool_row.dart`: переименовать `_withoutSchemeAndQuery` в `_hostAndPath` и реализовать порядок D2. Сначала отрезать всё от `?`/`#`, затем снять схему, затем в участке до первого `/` отбросить всё по последний `@` включительно. Только `String` и `RegExp`, без `Uri` (D1, альтернативы) и без новых импортов. Doc-комментарий функции на русском — почему, для чего, как, по `AGENTS.md` §15 и D1, с примерами `https://user:pass@example.com/x?t=1` → `example.com/x` и `https://example.com/a@b` без изменений. В doc-комментарии `ToolRowFormatter` заменить «query-строка адреса отбрасывается» на «у адреса `fetch` отбрасываются схема, userinfo, query и фрагмент». 1.1 и 1.2 зелёные. По ревью (1.3): нормализация краёв и `\t\n\r`, схема только перед `/` или `\`, снятие ведущих `/` и `\`, граница authority только по `/`, выражения — `static final`.
- [x] 2.2 `[client]` Проверить, что ветки `ToolKind.other` и запасная деталь из `title` не изменились (D3). Существующие тесты `tool_row_test.dart` зелёные без правки ожиданий.
- [x] 2.3 `[client]` Проверки затронутого (§21):
  - `fvm dart format --set-exit-if-changed lib/src/transcript/tool_row.dart test/transcript/tool_row_test.dart`;
  - `fvm dart analyze` в `packages/dart/codelab_client_core`;
  - `fvm dart test` в `packages/dart/codelab_client_core`.

  `web-compile` не нужен: импорты пакета не меняются. Публичный API не меняется, поэтому анализ и тесты зависимых пакетов не обязательны (design, «Влияние на архитектуру»). Полный `melos run check` — только по просьбе пользователя.

## 3. Документы

- [x] 3.1 `[client]` (правит `codelab-architect`) `docs/architecture/proposals/dart-agent-and-clients/12-1-view-model.md`. Строка `fetch` таблицы §12.1.6: «`rawInput.url` без схемы, userinfo, query-строки и фрагмента (userinfo и query могут содержать секрет)». VIEW-9: «Деталь строки инструмента проходит `SecretRedactor` и не содержит userinfo и query-строки URL» (D5). `README.md` пакета, `doc/` приложений и `docs/user/` деталь `fetch` не описывают; если при сверке diff это окажется не так — передать документ `docs-writer`.
- [x] 3.2 `[client]` `openspec validate strip-fetch-url-userinfo --strict` зелёный.
