## ADDED Requirements

### Requirement: Вызов смены режима и неизвестного вида в ленте
Строка вызова вида `switch_mode` SHALL показывать метку `Mode` и деталь из `ToolRowView` (требование «Строка инструмента без сырого JSON» acp-client-kit). Строка вызова, чей строковый `kind` CodeLab не знает, SHALL выглядеть как строка вызова вида `other`. Пока у такого вызова ждёт одобрение, строка SHALL показывать тег `Unknown risk` (требование «Тег неизвестного риска одобрения», change `add-provider-setup-ui`) и варианты агента без изменений. Строка SHALL NOT показывать wire-имя вида (`switch_mode`, исходное незнакомое значение) (design.md change `tolerate-unknown-tool-kind`, D5, D7).

#### Scenario: Выход из plan-режима ждёт одобрения
- **WHEN** агент запрашивает разрешение на вызов `switch_mode` с `title` "Ready for implementation" и вариантами «Yes, and auto-accept all actions», «Yes, and manually accept actions», «No, stay in architect mode»
- **THEN** строка вызова читается «Mode Ready for implementation», показывает тег `Unknown risk`, раскрыта с панелью решения из трёх вариантов агента и не содержит `switch_mode`

#### Scenario: Вызов незнакомого вида ждёт одобрения
- **WHEN** агент запрашивает разрешение на вызов, которого ещё нет в ходе, с `kind: "future_kind"` и `title` "Plan sync"
- **THEN** строка вызова читается «Plan sync» с тегом `Unknown risk` и не содержит `future_kind`
