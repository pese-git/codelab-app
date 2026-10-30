## ADDED Requirements

### Requirement: Поле записи command
Запись `message` с ролью `user`, полученная разворачиванием шаблона команды, SHALL нести необязательное поле записи `command` — объект `{"source": "template", "name": <string>, "args": <string>}` (§8.2.3; design.md change `add-agent-project-files`, D8). Поле НЕ SHALL входить в `Message` и в контекст модели. Запись без поля SHALL читаться как раньше. Неизвестное значение `source` SHALL сохраняться при чтении и записи без потери (совместимость вперёд), а реплей для такой записи SHALL показывать развёрнутый текст.

#### Scenario: Запись и чтение
- **WHEN** сессия разворачивает `/review lib` и журнал перечитывается `parseRecord`
- **THEN** запись сообщения содержит `command: {"source":"template","name":"review","args":"lib"}`, а `buildLlmContext` отдаёт модели только развёрнутый текст

#### Scenario: Неизвестный источник
- **WHEN** журнал содержит запись с `command.source: "plugin"`
- **THEN** запись читается без ошибки, поле сохраняется при повторной записи, реплей показывает текст сообщения
