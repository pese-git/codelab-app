## MODIFIED Requirements

### Requirement: Заметка исхода хода в ленте
Лента SHALL показывать `NoticeItem` вида `turnStopped` (spec acp-client-kit «Инкрементальная проекция транскрипта») строкой заметки после вывода хода, тем же видом, что заметку `emptyTurn` (design.md change `add-provider-setup-ui`, Q33, D27). Для причины `ResponseHeldReason` (удержанный ответ, design.md change `add-final-response-guardrails`, D7) лента SHALL показывать локализованный префикс на языке интерфейса (spec app-settings «Язык интерфейса app») и строку причины агента без перевода.

#### Scenario: Молчаливый max_tokens
- **WHEN** ход встроенного агента после размышлений завершается с `stopReason: max_tokens`
- **THEN** лента показывает под размышлениями строку `The model reached its token limit, so the turn ended.`

#### Scenario: Удержанный ответ на русском
- **WHEN** язык интерфейса `ru`, ход встроенного агента завершается `end_turn` с причиной удержания `revision limit reached: [unverified_success] …`
- **THEN** под ответом агента строка заметки начинается с русского префикса из ARB-каталога `ru`, а причина `revision limit reached: [unverified_success] …` подставлена без перевода

#### Scenario: Удержанный ответ на английском
- **WHEN** язык интерфейса `en`, тот же ход
- **THEN** строка заметки — английский префикс из ARB-каталога `en` и та же причина
