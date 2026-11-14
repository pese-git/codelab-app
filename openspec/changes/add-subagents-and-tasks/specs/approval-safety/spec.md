## MODIFIED Requirements

### Requirement: Редактирование секретов
CodeLab SHALL редактировать секреты в логах, диагностике, деталях инспектора и персистентном/debug-состоянии.

Числовое значение (`num`) под именем поля-счётчика токенов секретом НЕ SHALL считаться и SHALL показываться как есть: это счётчик расхода модели (`subagent.end`, сжатие контекста), а не учётные данные (решение пользователя 2026-11-15; design.md change `add-subagents-and-tasks`, D41 п. 7). Имя — счётчик токенов, если одновременно:
- имя имеет вид `tokens`, `tokens_<…>` или `<…>_tokens` (слово `tokens` во множественном числе, разделитель `_` или `-`, регистр не важен);
- остаток имени после вырезания части `tokens` (первое вхождение `(^|[_-])tokens([_-]|$)`) НЕ совпадает с правилом секретных имён (`secret`, `password`, `api_key`, `auth`, `token`, `cookie`, `credential`, …);
- остаток имени, разбитый на сегменты по разделителям `_` и `-` (любое их число подряд, регистр не важен), НЕ содержит отдельным сегментом ни одного стоп-слова учётных данных: `access`, `refresh`, `id`, `csrf`, `otp`, `pin`, `session`.

Так `tokens`, `tokens_in`, `tokens_out`, `input_tokens`, `max_output_tokens`, `tokens_before`, `Tokens-In` с числом видны, а `secret_tokens`, `tokens_api_key`, `auth_tokens`, `password_tokens` (правило секретных имён) и `access_tokens`, `refresh_tokens`, `id_tokens`, `csrf_tokens`, `otp_tokens`, `pin_tokens`, `session_tokens`, `tokens_session`, `session__tokens` (стоп-слова) скрываются при любом значении. Стоп-слово сравнивается с целым сегментом, а не с подстрокой: `input` и `output` не содержат сегмента `pin` или `id`. Строковое значение под именем-счётчиком, любое значение под другими именами правила (`token`, `access_token`, `session_token`, `api_key`, `password`, `secret`, …) и пары `key=value` внутри текста SHALL по-прежнему скрываться.

#### Scenario: Отображаются переменные окружения
- **WHEN** launch environment показан в диагностике
- **THEN** значения, похожие на токены, пароли, API-ключи или приватные ключи, скрыты

#### Scenario: Открыт debug-лог
- **WHEN** пользователь открывает debug/протокольный лог
- **THEN** чувствительные prompt'ы и секреты скрыты, если явная настройка debug не разрешает их показ

#### Scenario: Счётчик токенов виден
- **WHEN** запись лога встроенного агента несёт поля `tokens: 1200`, `tokens_in: 900`, `tokens_out: 300`, `input_tokens: 800`, `tokens_before: 4000`, `max_output_tokens: 4096`, `Tokens-In: 7`
- **THEN** журнал app и лог `codelab --verbose` показывают эти числа как есть (`secret_redaction_test.dart`)

#### Scenario: Секрет под похожим именем скрыт
- **WHEN** запись несёт поля `tokens: "abc123"`, `token: 123`, `access_token: 5`, `api_key: 42`, `session_token: "s"`, а текстовое поле — строку `tokens_in=sk-abc`
- **THEN** все пять значений скрыты как `<redacted>`, в тексте значение после `tokens_in=` скрыто (`secret_redaction_test.dart`)

#### Scenario: Счётчик с секретным словом скрыт
- **WHEN** запись несёт числовые поля `secret_tokens: 1`, `tokens_api_key: 1`, `auth_tokens: 1`, `password_tokens: 1` (правило секретных имён) и `access_tokens: 1`, `refresh_tokens: 1`, `id_tokens: 1`, `csrf_tokens: 1`, `otp_tokens: 1`, `pin_tokens: 1`, `session_tokens: 1`, `tokens_session: 1`, `session__tokens: 1`, `Access-Tokens: 1` (стоп-слова)
- **THEN** все значения скрыты как `<redacted>`, хотя они числа (`secret_redaction_test.dart`)
