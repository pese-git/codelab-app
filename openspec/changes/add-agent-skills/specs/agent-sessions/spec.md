## MODIFIED Requirements

### Requirement: Поле записи command
Запись `message` с ролью `user`, полученная разворачиванием шаблона команды или команды навыка, SHALL нести необязательное поле записи `command` — объект `{"source": <"template" | "skill">, "name": <string>, "args": <string>}` (§8.2.3; design.md change `add-agent-project-files`, D8; design.md change `add-agent-skills`, D8). У навыка `name` — имя навыка без префикса `skill:`; реплей и заголовок для него — `/skill:<name>` или `/skill:<name> <args>` при непустом `args`. Поле НЕ SHALL входить в `Message` и в контекст модели. Запись без поля SHALL читаться как раньше. Неизвестное значение `source` SHALL сохраняться при чтении и записи без потери (совместимость вперёд), а реплей для такой записи SHALL показывать развёрнутый текст.

#### Scenario: Запись и чтение
- **WHEN** сессия разворачивает `/review lib` и журнал перечитывается `parseRecord`
- **THEN** запись сообщения содержит `command: {"source":"template","name":"review","args":"lib"}`, а `buildLlmContext` отдаёт модели только развёрнутый текст

#### Scenario: Неизвестный источник
- **WHEN** журнал содержит запись с `command.source: "plugin"`
- **THEN** запись читается без ошибки, поле сохраняется при повторной записи, реплей показывает текст сообщения

#### Scenario: Команда навыка в журнале
- **WHEN** сессия разворачивает `/skill:release-notes v1.2 v1.3` и загружается в новом соединении
- **THEN** запись сообщения содержит `command: {"source":"skill","name":"release-notes","args":"v1.2 v1.3"}`, реплей содержит `user_message_chunk` с текстом `/skill:release-notes v1.2 v1.3`, а не обёртку навыка
