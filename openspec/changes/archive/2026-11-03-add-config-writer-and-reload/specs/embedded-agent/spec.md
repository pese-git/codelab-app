## ADDED Requirements

### Requirement: Перезагрузка конфига встроенного агента
`localEmbeddedAgentOpener` SHALL после успешной загрузки конфигурации передавать ядру `FileConfigSource` папки проекта и `modelsFor` над той же публичной функцией модели ядра и каталогом, что при открытии (design.md change `add-config-writer-and-reload`, D13). Источник получает окружение из параметра `environment` открывателя и `config.watch`/`config.poll_interval` из загруженного конфига. Начальные `streamFunction` и `services.models` SHALL браться из одного вызова `modelsFor`. Открыватель SHALL передавать `AgentCoreServices.agentConfigPaths` из той же функции `agentConfigPathsFor`, что строит список наблюдаемых файлов (PERM-11; design.md change `add-config-writer-and-reload`, D8). `scriptedEmbeddedAgentOpener` источник НЕ SHALL передавать.

`EmbeddedAgent.dispose()` SHALL закрывать источник отдельным шагом после освобождения runtime, в своём `try`. Сбой этого шага пишется `embedded.agent.dispose_failed {step: "config_source", error_class}`. После `dispose()` наблюдателей, таймеров опроса и сигналов источника НЕ SHALL оставаться. Если открытие сорвалось после создания источника, источник SHALL закрываться до проброса ошибки.

Невалидный конфиг при перезагрузке НЕ SHALL закрывать соединение и НЕ SHALL менять состояние клиента: агент продолжает работать на прежнем снимке (CFG-15).

#### Scenario: Правка из другого процесса
- **WHEN** встроенный агент открыт для папки проекта, и `codelab config set` в другом процессе добавляет модель в `$CODELAB_HOME/config.yaml`
- **THEN** клиентская сессия встроенного агента получает `config_option_update` с новой моделью без переподключения (`embedded_config_reload_test.dart`)

#### Scenario: dispose закрывает наблюдатель
- **WHEN** встроенный агент закрывается `dispose()`
- **THEN** источник закрыт, после этого правка файла не вызывает загрузок и событий, тест не находит активных таймеров `FakeClock` источника

#### Scenario: Новый ключ провайдера
- **WHEN** при `secrets.backend: file` страница настроек или `codelab secret set` заменяет значение `codelab/p` в `secrets.yaml`
- **THEN** следующий ход встроенного агента несёт новое значение ключа без перезапуска приложения
