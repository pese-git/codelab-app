## ADDED Requirements

### Requirement: Признак секретов в файле конфига
`EmbeddedAgent` (основной барель `codelab_embedded`) SHALL предоставлять `bool get secretsInConfig` (решение пользователя 2026-11-04 R8-3, R8-4; design.md change `add-config-literal-secrets-and-migrate`, D8). `localEmbeddedAgentOpener` SHALL ставить `true`, если загрузка конфига дала хотя бы одно предупреждение `config.secret.in_file`; `scriptedEmbeddedAgentOpener` SHALL ставить `false`. Признак НЕ SHALL нести значения, пути ключей или тексты; предупреждения по-прежнему пишутся в логгер хоста. Старт встроенного агента такие предупреждения НЕ SHALL блокировать. Признак вычисляется при открытии и до переподключения не пересчитывается.

`package:codelab_embedded/io.dart` SHALL реэкспортировать движок переноса `SecretMigrator`, `SecretMigrationReport`, опции и пункты отчёта (`codelab_agent_io`) для composition root codelab-app. Мост уже зависит от `codelab_agent_io`, поэтому нового ребра графа и правила сторожа нет; основной барель `codelab_embedded.dart` их НЕ SHALL экспортировать (он web-безопасен).

#### Scenario: Литеральный ключ в конфиге
- **WHEN** временный `CODELAB_HOME` содержит `config.yaml` с провайдером модели по умолчанию и `api_key: sk-<30 символов>`, и вызывается `localEmbeddedAgentOpener` с профилем `embedded-cli`
- **THEN** агент открыт, `secretsInConfig == true`, логгер получил `config.secret.in_file` без значения

#### Scenario: Конфиг со ссылками
- **WHEN** провайдер задаёт `api_key_secret: codelab/p`
- **THEN** `secretsInConfig == false`

#### Scenario: Мигратор доступен через io.dart
- **WHEN** тест импортирует `package:codelab_embedded/io.dart` и вызывает `SecretMigrator` с `--dry-run` над временным `CODELAB_HOME` с литеральным `api_key`
- **THEN** отчёт содержит пункт для `providers.<id>.api_key` без значения; основной барель `SecretMigrator` не экспортирует (`melos run guard`, `web-compile` зелёные)
