## Why

Строка вызова инструмента в app и CLI показывает секреты из текста агента. Два пути обходят маскировку `SecretRedactor`. Оба описаны в design.md change `strip-fetch-url-userinfo`, раздел «Остаточные утечки».

1. **Вторая строка `ToolRowView.secondary`** (`packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart`). `ToolRowFormatter` берёт её функцией `_firstLine(view.textOutput)` в `format` и в `_agentRow`. Строка не проходит ни очистку управляющих символов и ESC-последовательностей (`_clean`), ни `SecretRedactor.redactText`. Упавший `fetch` с выводом `Error: request to https://user:pass@host/x failed` отдаёт пароль в `secondary`. Десктоп переносит это поле в строку ленты (`apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`, `_toolCallRowOf`).
2. **Построчный вывод CLI** (`apps/codelab_cli/lib/src/render/tool_row.dart`, `toolRow`). Строка собирается из `item.title` и `item.details?.command`, и оба проходят только `sanitizeTerminalText`, без маскировки. Строку печатают REPL и TUI: для вызовов, кроме `agent`, и для потомков `transcript_lines.dart` вызывает тот же `toolRow`. Команда `curl https://user:pass@host/x?token=…` печатается в терминал как есть.

При разборе нашёлся третий путь того же рода в том же файле. **Метка вызова вида `other`** — это `title.trim()` без `_clean`. Заголовок MCP-инструмента или неизвестного вида с адресом или токеном попадает в метку как есть, вместе с управляющими символами. Он входит в этот change (design D2).

Это утечка секрета в интерфейс: снимок экрана, запись экрана, копирование строки, вывод терминала в журнал CI (`AGENTS.md` §2, приоритет 1; §10). Требование «Строка инструмента без сырого JSON» spec `acp-client-kit` и VIEW-9 уже требуют маскировать деталь строки. Метку и вторую строку правило не называет, и код их пропускает.

## What Changes

- **`ToolRowFormatter` (`codelab_client_core`):**
  - вторая строка упавшего вызова — первая строка первого текстового элемента, которая непуста после очистки. Очистка та же, что у детали: ESC-последовательности и управляющие символы заменяются пробелом, пробелы схлопываются, затем маскирование секретов и усечение до 160 символов с `…`. Так же для вызова `agent` (D1, D3);
  - метка вида `other` (и неизвестного вида, который проецируется в `other`) проходит ту же очистку (D2).
- **Хвост вывода раскрытой строки десктопа** (решение пользователя, D7):
  - новая функция kit `ToolRowFormatter.outputTail(item, maxLines:)` берёт последние `maxLines` строк вывода, обходя их с конца, и маскирует их;
  - функция возвращает `null`, если вывод — та же одна строка, что вторая строка, без усечения. Так однострочная ошибка не показывается дважды, а строка вывода, которой нет во второй строке, не пропадает;
  - маппер десктопа передаёт в `CodeLabToolCallRow.output` этот хвост вместо сырого `textOutput`; `codelab_ui` не меняется.
- **`toolRow` (`apps/codelab_cli`):** название и команда проходят `SecretRedactor.redactText` после `sanitizeTerminalText` и до выбора первой строки. Вид строки `<значок> <название> <команда?> <время?>` не меняется: строки без секретов печатаются байт в байт как раньше (D4).
- **Spec `acp-client-kit`**, требование «Строка инструмента без сырого JSON» (MODIFIED целиком, поверх дельты `strip-fetch-url-userinfo`): очистка метки `other` и второй строки, порядок «маскирование до усечения», новые сценарии. Все сценарии дельты `strip-fetch-url-userinfo` сохранены дословно (D5).
- **Spec `acp-client-kit`**, новое требование «Хвост вывода строки инструмента» (ADDED). **Spec `agent-workbench-ui`**, новое требование «Вывод раскрытой строки инструмента без секретов» (ADDED).
- **Spec `codelab-cli`**, требование «Рендер хода в REPL» (MODIFIED): название и команда строки инструмента маскируются. TUI получает правило через своё требование «Кадр TUI»: строки инструментов строятся «тем же правилом, что в REPL».
- **Документы:** `docs/architecture/proposals/dart-agent-and-clients/12-1-view-model.md` (§12.1.6, шаги 2, 3, 5; VIEW-9) и `12-2-cli-display-and-input.md` (§12.2.4, правило маскировки) (D6).

## Что НЕ входит

- **Блок одобрения.** `title` и `command` в REPL и TUI (`approval_prompt.dart`) и `command` в карточке одобрения десктопа. Это семантика решения пользователя: что именно он разрешает. Отдельное решение по `approval-safety` (design, «Вне scope»).
- **Строка stderr headless о решении** (`describeApproval(call?.title …)`): рекомендован отдельный небольшой follow-up вместе с блоком одобрения (design, «Вне scope», Q2).
- **Ответ агента и мысли** не маскируются. Вывод инструмента маскируется только в хвосте раскрытой строки десктопа (D7).
- **Правила `SecretRedactor`.** Новых шаблонов нет. Userinfo в свободном тексте маскирует правило change `extend-secret-name-redaction` (D4 того change).
- ACP, протокольные модели, форма `ToolRowView`, сигнатуры `ToolRowFormatter.format` и `toolRow` не меняются. Публичный API `codelab_client_core` пополняется функцией `ToolRowFormatter.outputTail`.

## Зависимости и порядок слияния

Change собирается поверх двух неслитых changes и сливается **после обоих** (D5):

1. `extend-secret-name-redaction`. Его правило userinfo (`://…@` → `://<redacted>@`) в `redactText` нужно сценариям этого change: без него `https://user:pass@host` в свободном тексте не маскируется, и тесты второй строки и CLI остаются красными.
2. `strip-fetch-url-userinfo`. Тот же файл `tool_row.dart` и то же требование spec. Дельта этого change содержит текст требования из той дельты как основу.

Архивация: `strip-fetch-url-userinfo` архивируется раньше этого change. В обратном порядке архивация `strip-fetch-url-userinfo` заменит требование своей версией и сотрёт правила второй строки и метки. `extend-secret-name-redaction` меняет другую capability (`approval-safety`) и архивируется в любом порядке.

## Impact

- Код:
  - `packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart` — приватные `_firstLine` и `_clean`, выражения метки и второй строки, новая `ToolRowFormatter.outputTail`, doc-комментарии;
  - `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart` — `_toolCallRowOf`: `output` из `outputTail`;
  - `apps/codelab_cli/lib/src/render/tool_row.dart` — `toolRow` и его doc-комментарий, новый импорт `package:codelab_client_acp/codelab_client_acp.dart` (`show SecretRedactor`). Импорт разрешён: правило сторожа `apps/codelab_cli` запрещает только `flutter`, `fluent_ui`, `codelab_ui` и `codelab_agent_`, а зависимость уже есть в `pubspec.yaml` и используется в `approval_prompt.dart` и `cli_logger.dart`.
- Тесты:
  - `packages/dart/codelab_client_core/test/transcript/tool_row_test.dart`;
  - `apps/codelab_cli/test/render/tool_row_test.dart`;
  - тесты десктопа: маппер — `apps/codelab_desktop/test/features/workbench/application/tool_call_row_secrets_test.dart` (новый), лента — `apps/codelab_desktop/test/features/workbench/presentation/tool_call_output_secrets_test.dart` (новый).
- Specs: `acp-client-kit` («Строка инструмента без сырого JSON» MODIFIED, «Хвост вывода строки инструмента» ADDED), `agent-workbench-ui` (ADDED), `codelab-cli` («Рендер хода в REPL» MODIFIED).
- Документы: §12.1.6 и VIEW-9, §12.2.4. `README.md` и `doc/` пакетов и приложений и `docs/user/` строку инструмента на этом уровне не описывают. Это сверяется на шаге документации (tasks 4.3).
- `codelab_ui` не меняется.
