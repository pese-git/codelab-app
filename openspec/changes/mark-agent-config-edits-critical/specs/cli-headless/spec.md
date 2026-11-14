## ADDED Requirements

### Requirement: allow-all не одобряет правку конфигурации Dart-агента
С Dart-агентом — встроенным (`codelab_embedded`) и `codelab-agent serve` — политика `--approve allow-all` SHALL отклонять вопрос о правке конфигурации агента (PERM-11, `agent-core/07-permissions.md` §7.6.1) через `write` и `edit` так же, как через `exec`: агент помечает такой вопрос `_meta.codelab.critical: true` (capability `agent-acp-server`, «Запросы агента к клиенту»), и он получает `reject_once` с причиной `critical` по requirement «Политика одобрений headless» (design.md change `mark-agent-config-edits-critical`, D6). Защищаемый файл SHALL оставаться нетронутым; ход SHALL продолжаться, модель получает отказ (PERM-7). Политики `reject` и `read-only` такой вопрос отклоняют и без пометки.

Подсказку, как разрешить такую правку, headless НЕ SHALL печатать: правку конфигурации агента делает человек (PERM-11).

#### Scenario: Правка проектного конфига в allow-all
- **WHEN** `codelab -p … --approve allow-all` идёт со встроенным агентом или с `codelab-agent` в режиме `bypass`, и модель вызывает `write .codelab/config.yaml`
- **THEN** агент получает `reject_once`, stderr содержит строку `permission "<title>": reject_once (critical)`, файл `.codelab/config.yaml` в рабочей папке не создан, код выхода `0` при непустом ответе модели после отказа

#### Scenario: Обычная запись в allow-all не меняется
- **WHEN** `--approve allow-all`, режим `standard`, и модель вызывает `write NOTES.md`
- **THEN** агент получает `allow_once`, строка stderr называет причину `policy`
