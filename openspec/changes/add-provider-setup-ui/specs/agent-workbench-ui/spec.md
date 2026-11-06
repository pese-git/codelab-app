## ADDED Requirements

### Requirement: Отказ подключения из-за токена в workbench
Если WebSocket-агент отклоняет рукопожатие со статусом 401 или 403 (`tokenRejectionStatus` kit, spec acp-client-kit «Отказ рукопожатия из-за токена»), баннер сбоя подключения в main pane и диагностика `ConnectionCubit` SHALL показывать причину `The agent rejected the token (HTTP <код>).`, если токен был отправлен, и `The agent requires a token (HTTP <код>).`, если нет (`describeConnectFailureByToken` kit отдаёт строчный текст без точки, app делает первую букву заглавной и ставит точку, как в D3; design.md change `add-provider-setup-ui`, D25), вместо общего `Failed to connect ACP transport.`. Остальные ошибки подключения SHALL показываться как раньше. Значение токена, его ссылка и имя переменной НЕ SHALL попадать в баннер, диагностику и журнал.

#### Scenario: Отправленный токен отклонён
- **WHEN** окно подключается к WebSocket-профилю с `tokenRef: env:DEVBOX_TOKEN` (переменная задана значением `sk-test-leak-0123456789`), а сервер отвечает на рукопожатие `401`
- **THEN** баннер и диагностика содержат `The agent rejected the token (HTTP 401).` и не содержат маркера

#### Scenario: Токена нет
- **WHEN** окно подключается к WebSocket-профилю без токена (или с `secret:`, у которого нет значения), а сервер отвечает `403`
- **THEN** баннер и диагностика содержат `The agent requires a token (HTTP 403).`

#### Scenario: Прочие ошибки без изменений
- **WHEN** сервер отвечает на рукопожатие `500` или порт закрыт
- **THEN** баннер показывает прежний текст сбоя подключения, без слов о токене

### Requirement: Встроенный агент без провайдера
Если встроенный агент не открылся только потому, что нет ни одного провайдера с моделью (`providerSetupNeeded` моста `codelab_setup` истинно для снимка конфига, с которым он открывался: нет файла, нет провайдеров или у них нет моделей; spec client-agent-setup «Готовность провайдера»; без `agent.default_model` при провайдере с моделью агент открывается на первой модели, design.md change `optional-default-model`, D3), баннер соединения SHALL показывать `No model provider is configured for the embedded agent.` и действие «Add provider» (ключ `connection-banner-add-provider`) вместо сырого текста проблем (решение пользователя 2026-11-06; design.md change `add-provider-setup-ui`, D26). Признак SHALL определяться по типизированным проблемам загрузчика и составу слоёв конфига, а не по тексту. Прочие ошибки конфига встроенного агента SHALL показываться как раньше.

«Add provider» SHALL открывать мастер провайдера (spec app-settings «Мастер провайдера в app») с целью `user` по умолчанию и неснимаемым «Make default». После `ConfigSaved` app SHALL переподключать встроенного агента, если с момента сбоя не начиналась новая попытка подключения окна; если началась (к любому профилю), переподключения НЕ SHALL быть. Отмена мастера SHALL оставлять баннер.

#### Scenario: Новая установка
- **WHEN** app с пустым `CODELAB_HOME` подключается к встроенному агенту
- **THEN** баннер показывает `No model provider is configured for the embedded agent.` и «Add provider», текста `agent.default_model: required` и `codelab config check` в нём нет

#### Scenario: Провайдер добавлен из баннера
- **WHEN** пользователь нажимает «Add provider» в баннере, проходит мастер и сохраняет провайдера
- **THEN** `config.yaml` содержит провайдера и `agent.default_model` (мастер с неснимаемым «Make default» пишет ключ, D7; для старта агента ключ не обязателен), app переподключает встроенного агента, баннер исчезает, а модель видна в селекторе композера

#### Scenario: Другой профиль за время мастера
- **WHEN** мастер открыт из баннера, и пока он открыт, окно начинает подключение к stdio-профилю (диалог модальный, поэтому тест начинает попытку через `ConnectionCommands.connect`), затем пользователь сохраняет провайдера
- **THEN** конфиг записан, переподключения к встроенному агенту нет, окно остаётся подключённым к stdio-профилю, журнал содержит `provider_wizard.reconnect_skipped`

#### Scenario: Прочая ошибка конфига
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, но содержит `budget.max_steps: 0`; либо задаёт провайдера `gw` и `agent.default_model: gw/typo`, которой нет в каталоге
- **THEN** баннер показывает прежний текст проблемы с подсказкой `codelab config check`, действия «Add provider» нет

