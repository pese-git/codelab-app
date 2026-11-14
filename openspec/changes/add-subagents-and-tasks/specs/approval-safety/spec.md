## MODIFIED Requirements

### Requirement: Редактирование секретов
CodeLab SHALL редактировать секреты в логах, диагностике, деталях инспектора и персистентном/debug-состоянии.

Числовое значение (`num`) под именем поля-счётчика токенов — `tokens`, `tokens_<…>` или `<…>_tokens` (слово `tokens` во множественном числе, разделитель `_` или `-`, регистр не важен) — секретом НЕ SHALL считаться и SHALL показываться как есть: это счётчик расхода модели (`subagent.end`, сжатие контекста), а не учётные данные (решение пользователя 2026-11-15; design.md change `add-subagents-and-tasks`, D41 п. 7). Строковое значение под тем же именем, любое значение под другими именами правила (`token`, `access_token`, `session_token`, `api_key`, `password`, `secret`, …) и пары `key=value` внутри текста SHALL по-прежнему скрываться.

#### Scenario: Отображаются переменные окружения
- **WHEN** launch environment показан в диагностике
- **THEN** значения, похожие на токены, пароли, API-ключи или приватные ключи, скрыты

#### Scenario: Открыт debug-лог
- **WHEN** пользователь открывает debug/протокольный лог
- **THEN** чувствительные prompt'ы и секреты скрыты, если явная настройка debug не разрешает их показ

#### Scenario: Счётчик токенов виден
- **WHEN** запись лога встроенного агента несёт поля `tokens: 1200`, `tokens_in: 900`, `tokens_out: 300`, `tokens_before: 4000`, `max_output_tokens: 4096`
- **THEN** журнал app и лог `codelab --verbose` показывают эти числа как есть (`secret_redaction_test.dart`)

#### Scenario: Секрет под похожим именем скрыт
- **WHEN** запись несёт поля `tokens: "abc123"`, `token: 123`, `access_token: 5`, `api_key: 42`, `session_token: "s"`, а текстовое поле — строку `tokens_in=sk-abc`
- **THEN** все пять значений скрыты как `<redacted>`, в тексте значение после `tokens_in=` скрыто (`secret_redaction_test.dart`)
