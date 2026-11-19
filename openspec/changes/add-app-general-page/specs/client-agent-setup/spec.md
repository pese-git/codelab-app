## ADDED Requirements

### Requirement: Правила правки строк настроек агента
Основной барель `codelab_setup` SHALL давать правило «можно ли править строку настроек агента» одной функцией для всех клиентов (SETUP-8; design.md change `add-app-general-page`, D6):
- `settingKeyEditRefusalOf(String key)` → `SettingEditRefusal?` — отказ по самому ключу до чтения слоёв;
- `settingEditRefusalOf(SettingFieldView row)` → `SettingEditRefusal?` — отказ по ключу, источнику и маске строки; `null` — строку можно менять.

`SettingEditRefusal` SHALL быть закрытой иерархией с ветками:
- `UnknownSetting` — ключа нет в реестре или он не `scope: shared`;
- `TrustBoundarySetting` — `trusted_projects`;
- `SecretSetting` — дескриптор `secret: true` или тип `secretName`;
- `ExternalSourceSetting(source)` — источник `config` (`CODELAB_CONFIG`/`--config`) или `env`;
- `MaskedSetting` — `SettingFieldView.masked`.

Ветки SHALL проверяться в этом порядке. Отказ НЕ SHALL содержать значение ключа, а `toString()` отказа — значение строки.

Клиенты SHALL строить свои тексты по ветке отказа и НЕ SHALL повторять правило. `/settings` CLI SHALL сохранить прежние тексты отказов: `Unknown setting <key>. Run /settings to list them.`, `trusted_projects is a trust boundary; it cannot be changed here.`, `Use codelab secret set <name>`, `<key> is set by <source>; it cannot be changed here.`.

#### Scenario: Порядок веток
- **WHEN** строка `providers.gw.api_key_secret` задана переменной окружения
- **THEN** `settingEditRefusalOf` возвращает `SecretSetting`, а не `ExternalSourceSetting`

#### Scenario: Источник config
- **WHEN** `budget.max_steps` задан файлом `--config`
- **THEN** `settingEditRefusalOf` возвращает `ExternalSourceSetting` с источником `config`

#### Scenario: Замаскированное значение
- **WHEN** `providers.gw.base_url` содержит в query литеральный токен, и строка помечена `masked`
- **THEN** `settingEditRefusalOf` возвращает `MaskedSetting`, а `toString()` отказа и строки не содержат токена

#### Scenario: Тексты CLI не меняются
- **WHEN** пользователь CLI вводит `/settings trusted_projects []`
- **THEN** REPL печатает `trusted_projects is a trust boundary; it cannot be changed here.`, как до этого change

#### Scenario: Обычный ключ можно править
- **WHEN** `compaction.enabled` задан в слое `user`
- **THEN** `settingEditRefusalOf` возвращает `null`
