## ADDED Requirements

### Requirement: Домашний каталог CLI CODELAB_HOME
Домашний каталог CLI (`profiles.json`, `cli_history`) — `CODELAB_HOME`, по умолчанию `$HOME/.codelab` (`%USERPROFILE%\.codelab` на Windows); его SHALL вычислять `CodelabHome.resolve` (design.md change `add-agent-project-files`, D17; решение пользователя 2026-10-30). Значение `CODELAB_HOME`, равное `~` или начинающееся с `~/`, SHALL раскрываться так же, как у агента (agent-configuration «Корень состояния CODELAB_HOME»): `~` заменяется `HOME`, а если он не задан или пуст, `USERPROFILE`. Так `codelab` и `codelab-agent` с одним окружением видят один каталог. Любое другое значение, начинающееся с `~` (`~user/…`, `~\…`), SHALL быть ошибкой использования (`UsageError`, код `64`) с текстом `CODELAB_HOME: ~user is not supported, use an absolute path`. Значение `~` или `~/…` при неизвестном домашнем каталоге (`HOME` и `USERPROFILE` не заданы или пусты) SHALL быть ошибкой использования с кодом `64` и текстом `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`. Тексты совпадают с агентом. Пустой `CODELAB_HOME` SHALL считаться незаданным. `codelab config check` передаёт окружение процесса загрузчику агента без изменений, поэтому его корень состояния определяет agent-configuration.

#### Scenario: Тильда раскрывается в HOME
- **WHEN** `codelab profiles add default stdio:agent` запускается с `CODELAB_HOME='~/cl'` (буквально) и `HOME=<tmp>`
- **THEN** профиль записан в `<tmp>/cl/profiles.json`; каталога `./~` нет

#### Scenario: Тильда без домашнего каталога
- **WHEN** `codelab -p hi` запускается с `CODELAB_HOME='~/cl'` без `HOME` и `USERPROFILE`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`, агент не запускается

#### Scenario: ~user — ошибка использования
- **WHEN** `codelab -p hi` или `codelab config check` запускается с `CODELAB_HOME='~bob/cl'` и `HOME=<tmp>`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: ~user is not supported, use an absolute path`, агент не запускается, каталог `./~bob` не создаётся
