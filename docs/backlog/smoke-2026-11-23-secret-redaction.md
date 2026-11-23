# Backlog: находки смоук-прогона маскировки секретов 2026-11-23

Смоук-прогон change `extend-secret-name-redaction` на ветке `feature/extend-secret-name-redaction` @ `e9f80ff0`, PR [#450](https://github.com/pese-git/codelab-app/pull/450). Ветка уже содержит merge `develop` с change `redesign-protocol-pane`. Модель — `qwen/qwen3.5-9b` в LM Studio (`openai-compatible`). `CODELAB_HOME` изолирован во временном каталоге, ключ провайдера фиктивный.

Автоматически прогнаны:
- `test:e2e:cli:embedded`: 99 тестов прошли, 2 пропущены;
- `test:e2e:cli:dart-agent`: 91 прошёл, 10 пропущены;
- `conformance:embedded`: 50 прошли, 0 упали, 35 пропущены — фикстуры транспорта, которые проигрываются только против бинаря агента.

Вручную, CLI (бинарь `codelab` из ветки):
- **Учётные данные в адресе агента.** `-a 'ws://alice:<пароль>@127.0.0.1:9/acp' -p hi`, с `-v` и без. В ошибке подключения адрес показан как `ws://127.0.0.1:9`, пароль не попал ни в stdout, ни в stderr.
- **Секреты в выводе команды.** Встроенный агент с `--approve allow-all -v` выполнил `printf` со строками `OPENAI_KEY=…`, `X-Functions-Key: …`, `DATABASE_URL=postgres://bob:<пароль>@…`. Ход завершился с кодом `0`. Записи журнала `-v` секретов не содержат. Сама команда видна в двух строках stderr — SMK-47 и SMK-48.

Вручную, desktop (отладочная сборка macOS из ветки, встроенный агент):
- агент прочитал `env.txt` со строками `OPENAI_KEY=…`, `X-Functions-Key: …`, `AWS_ACCESS_KEY_ID=…`, `DATABASE_URL=postgres://bob:<пароль>@db/app` и PEM-блоком `-----BEGIN RSA PRIVATE KEY-----` без строки `END`;
- кадр `session/update · tool_call_update` в панели «Protocol» показан и скопирован кнопкой «Copy» замаскированным: `OPENAI_KEY=<redacted>`, `X-Functions-Key: <redacted>`, `AWS_ACCESS_KEY_ID=<redacted>`, `DATABASE_URL=postgres://<redacted>@db/app`; PEM-блок скрыт до конца текста. Имена переменных, хост и путь адреса видны.

Сценарии change прошли по дельте spec `approval-safety` «Редактирование секретов». Регрессий от change нет. Утечки SMK-47 и SMK-48 существовали и до него: эти строки не проходят через `SecretRedactor`.

Не проверялись: release-сборка с переключателем «Trace», экспорт кадров, раскрытая строка инструмента в ленте desktop.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-47 | P1 | bug | cli, client | Строка инструмента в REPL, TUI и headless печатает команду с секретами без маскировки | да, `redact-tool-row-text` (не влит) | — |
| SMK-48 | P1 | bug | cli | Строка решения headless `codelab: permission "<title>"` печатает команду с секретами без маскировки | да | — |
| SMK-49 | P3 | ux | agent | Подсказка `secrets.backend.selected` в журнале выводится как `secrets.backend: <redacted>` | нет | — |

## Карточки

### SMK-47. Строка инструмента печатает команду с секретами (P1)

**Где:** `apps/codelab_cli/lib/src/render/tool_row.dart`, функция `toolRow`. Название и команда проходят только `sanitizeTerminalText`, без `SecretRedactor`.

**Шаги:** `codelab -v --approve allow-all -p 'Use your shell tool to run exactly this command: printf "OPENAI_KEY=sk-…\nDATABASE_URL=postgres://bob:<пароль>@db/app\n" …'`.

**Факт:** в stderr строка `✓ printf "OPENAI_KEY=sk-…\n…postgres://bob:<пароль>@db/app\n"`: название и команда целиком, без маскировки.

**Почему важно:** вывод терминала попадает в журналы CI, на снимки экрана и в отчёты (`AGENTS.md` §2, приоритет 1).

**Что сделать:** закрывает change `redact-tool-row-text`, D4: название и команда проходят `SecretRedactor.redactText`. Change готов в ветке `feature/redact-tool-row-text` и сливается после `extend-secret-name-redaction` и `strip-fetch-url-userinfo`. После слияния повторить шаги.

### SMK-48. Строка решения headless печатает команду с секретами (P1)

**Где:** `apps/codelab_cli/lib/src/headless/approval_policy.dart` — строка `codelab: permission "$title": <outcome> (policy)`, которую собирает `describeApproval`.

**Шаги:** те же, что в SMK-47.

**Факт:** в stderr `codelab: permission "printf "OPENAI_KEY=sk-…\n…postgres://bob:<пароль>@db/app\n"": allow_once (policy)`.

**Почему важно:** headless-режим запускают в скриптах и CI, его stderr сохраняется в журналах.

**Что сделать:** change `redact-tool-row-text` этой строки не касается: она вынесена из его scope (proposal, «Что НЕ входит»; design, Q2) вместе с блоком одобрения REPL, TUI и desktop, потому что это семантика решения пользователя — что именно он разрешает. Нужен отдельный change по `approval-safety`. Как минимум для строки stderr headless (решение уже принято политикой, пользователь его не видит) — маскирование `redactText`.

### SMK-49. Ложное срабатывание в подсказке хранилища секретов (P3)

**Где:** запись журнала агента `secrets.backend.selected`, поле `reason`. Её маскирует `SecretRedactor` клиента в журнале `codelab -v` (`apps/codelab_cli/lib/src/embedded_logger.dart`).

**Факт:** `reason=OS keychain backends are not available in this version; set secrets.backend: <redacted> or CODELAB_SECRET_* variables`. Подсказка теряет значение, которое советует задать: имя `secrets.backend` содержит слово `secret`, поэтому присваивание в тексте маскируется. Прежний шаблон присваиваний вёл себя так же, это не регрессия change.

**Почему важно:** пользователь не видит, какое значение задать.

**Что сделать:** переписать текст подсказки агента без формы `имя: значение` — например, `set secrets.backend to env`. Правила маскировки не трогать: ложное срабатывание здесь безопаснее, чем исключение для имён с `secret`.
