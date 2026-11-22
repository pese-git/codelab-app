## ADDED Requirements

### Requirement: Места вызова с номером строки
`ToolCallView` SHALL нести `locations` — места вызова (`path` и необязательный `line` из ACP `ToolCallLocation`) в порядке прихода; поле `paths` SHALL сохраняться без изменений. Обновление вызова с новыми `locations` SHALL заменять места, как это делает доменная модель. Инкрементальная проекция SHALL совпадать с проекцией с нуля (требование «Инкрементальная проекция транскрипта»). Диапазон строк kit НЕ SHALL выводить: ACP его не определяет (design.md change `add-file-preview-and-tree`, D8).

#### Scenario: Место со строкой
- **WHEN** агент присылает `tool_call` с `locations: [{"path": "/w/lib/a.dart", "line": 42}]`
- **THEN** `ToolCallView.locations` содержит одно место с путём `/w/lib/a.dart` и строкой 42, а `paths` — `["/w/lib/a.dart"]`

#### Scenario: Место без строки
- **WHEN** агент присылает место без `line`
- **THEN** у места в `ToolCallView.locations` строка не задана
