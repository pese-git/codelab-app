## ADDED Requirements

### Requirement: Недавние проекты CLI
Интерактивные режимы `codelab` — построчный REPL и `--ui tui` — SHALL записывать папку сессии в общий список недавних проектов `$CODELAB_HOME/recent_projects.json` через `JsonFileRecentProjectsStore` (acp-client-kit «Хранилище недавних проектов в CODELAB_HOME»). Запись SHALL выполняться один раз за запуск, в том числе с `--resume` и `--continue`: после мастера первого запуска и успешного подключения к агенту (`ClientWorkspace.connect` завершился без ошибки), до открытия или загрузки сессии. Если мастер завершил процесс или старт агента не удался (ошибка конфигурации встроенного агента, сбой запуска или подключения), записи нет. С `--resume` и `--continue` папка записывается и тогда, когда сессия не найдена или не загрузилась. Папка — проверенная папка сессии: `-C`/`--cwd` или текущая, абсолютный нормализованный путь (design.md change `share-recent-projects-store`, D6).

Headless (`-p`, `-f`, промпт из stdin без TTY), `test-scenario`, `config`, `provider`, `mcp`, `secret`, `profiles`, алиас `serve`, `--version` и `--help` НЕ SHALL создавать или менять `recent_projects.json`. Сбой записи (нечитаемый файл, ошибка ФС) НЕ SHALL менять поведение и код выхода. С `--verbose` SHALL печататься одна строка в stderr: `codelab: cannot record a recent project: <тип ошибки>`, без текста ошибки. Без `--verbose` вывода нет. Нечитаемый файл НЕ SHALL перезаписываться. Список CLI не показывает.

#### Scenario: REPL записывает папку
- **WHEN** `codelab -C <tmp>/proj` запускается на терминале с `CODELAB_HOME=<home>` и выходит по `/exit`
- **THEN** `<home>/recent_projects.json` содержит `<tmp>/proj` первой записью

#### Scenario: Полноэкранный режим записывает папку
- **WHEN** `codelab --ui tui` запускается на терминале в папке `<tmp>/proj` с `CODELAB_HOME=<home>` и завершается
- **THEN** `<home>/recent_projects.json` содержит `<tmp>/proj`

#### Scenario: Продолжение сессии записывает папку
- **WHEN** `codelab --continue -C <tmp>/proj` запускается на терминале с `CODELAB_HOME=<home>` и выходит по `/exit`
- **THEN** `<home>/recent_projects.json` содержит `<tmp>/proj` первой записью

#### Scenario: Неудачный старт не записывает папку
- **WHEN** `codelab -C <tmp>/proj` запускается на терминале с `CODELAB_HOME=<home>`, где нет `recent_projects.json`, и старт агента не удаётся: у встроенного агента не настроена модель (`EmbeddedAgentConfigException`) или профиль `stdio:` указывает несуществующую команду
- **THEN** процесс завершается с ненулевым кодом (`64` для ошибки конфигурации, `1` для сбоя запуска агента), а файла `<home>/recent_projects.json` нет

#### Scenario: Headless не трогает список
- **WHEN** `codelab -p hi -C <tmp>/proj` выполняется с `CODELAB_HOME=<home>`, где `recent_projects.json` отсутствует
- **THEN** код выхода не зависит от списка, а файла `<home>/recent_projects.json` нет

#### Scenario: Подкоманды не трогают список
- **WHEN** `codelab config check`, `codelab test-scenario` и `codelab profiles list` выполняются с `CODELAB_HOME=<home>`, где лежит `recent_projects.json`
- **THEN** байты `<home>/recent_projects.json` не изменились

#### Scenario: Нечитаемый файл не мешает REPL
- **WHEN** `<home>/recent_projects.json` содержит `{not json`, и `codelab --verbose` запускается на терминале с `CODELAB_HOME=<home>`
- **THEN** REPL работает как обычно, в stderr одна строка `codelab: cannot record a recent project: FormatException`, код выхода прежний, байты файла не изменились
