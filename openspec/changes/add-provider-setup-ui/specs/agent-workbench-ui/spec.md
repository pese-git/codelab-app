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
