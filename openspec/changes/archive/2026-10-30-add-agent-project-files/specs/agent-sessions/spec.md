## ADDED Requirements

### Requirement: Поле записи command
Запись `message` с ролью `user`, полученная разворачиванием шаблона команды, SHALL нести необязательное поле записи `command` — объект `{"source": "template", "name": <string>, "args": <string>}` (§8.2.3; design.md change `add-agent-project-files`, D8). Поле НЕ SHALL входить в `Message` и в контекст модели. Запись без поля SHALL читаться как раньше. Неизвестное значение `source` SHALL сохраняться при чтении и записи без потери (совместимость вперёд), а реплей для такой записи SHALL показывать развёрнутый текст.

#### Scenario: Запись и чтение
- **WHEN** сессия разворачивает `/review lib` и журнал перечитывается `parseRecord`
- **THEN** запись сообщения содержит `command: {"source":"template","name":"review","args":"lib"}`, а `buildLlmContext` отдаёт модели только развёрнутый текст

#### Scenario: Неизвестный источник
- **WHEN** журнал содержит запись с `command.source: "plugin"`
- **THEN** запись читается без ошибки, поле сохраняется при повторной записи, реплей показывает текст сообщения

### Requirement: Заголовок сессии из команды
Для записи `message` с полем `command` и известным `source` заголовок сессии SHALL строиться по исходному тексту `/<name>` (или `/<name> <args>` при непустом `args`), как реплей, а не по развёрнутому телу: в `summarize`, в `session/list` и в автоматическом `session_info` с `source: "auto"` (а значит и в `session_info_update`) (design.md change `add-agent-project-files`, D8). Для записи с неизвестным `source` заголовок SHALL строиться по тексту сообщения.

#### Scenario: Автозаголовок по команде
- **WHEN** первый ход сессии — `/review lib/parser`, а тело шаблона — `Review $1 carefully`, и `session_info` нет
- **THEN** `session_info` с `source: "auto"` и `summarize` дают заголовок `/review lib/parser`, а не `Review lib/parser carefully`
