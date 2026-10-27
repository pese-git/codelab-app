## MODIFIED Requirements

### Requirement: Workbench честно отражает спонтанную потерю соединения
CodeLab SHALL отражать спонтанную (не инициированную явным `connect()`/`reconnect()`) потерю ACP-соединения как отдельное состояние `lost` в UI, отличное от неудачной попытки подключения `failed`, и SHALL очищать состояние активного запроса, которое больше не может считаться достоверным, вместо того чтобы бесконечно показывать `Connected` и зависший `running` turn.

#### Scenario: Агент падает во время активной сессии
- **WHEN** активное соединение (`connectionStatus == connected`) спонтанно теряется — например, дочерний процесс агента завершается неожиданно
- **THEN** CodeLab переводит `connectionStatus` в `lost`, очищает `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval` и `isRespondingToConfigOption`, и записывает диагностику с причиной

#### Scenario: Explicit connect/reconnect failure не задваивается
- **WHEN** пользователь явно вызывает `Connect`/`Reconnect`, и попытка завершается неудачей
- **THEN** CodeLab переводит `connectionStatus` в `failed` и показывает ровно одну diagnostic-запись об этой неудаче — реакция на спонтанную потерю соединения не создаёт вторую, дублирующую запись для того же события

#### Scenario: История сессии не теряется при потере соединения
- **WHEN** происходит спонтанная потеря соединения
- **THEN** CodeLab сохраняет видимыми `transcriptEntries` уже случившейся сессии — они не считаются недостоверными, в отличие от состояния активного запроса

## ADDED Requirements

### Requirement: Connection banner above a non-empty transcript
When the transcript of the active session is not empty and the connection is `lost`, `failed` or `reconnecting`, the workbench SHALL show a banner above the transcript that states the connection status and its reason. The banner SHALL offer Reconnect and Connection settings while the connection is `lost` or `failed`, and SHALL show progress without a Reconnect action while it is `reconnecting`. The banner SHALL NOT be dismissible and SHALL disappear when the connection becomes `connected`. When the transcript is empty, the workbench SHALL keep showing the connection screen instead of the banner.

#### Scenario: The agent process exits during a session
- **WHEN** the active session's transcript has entries and the agent process exits unexpectedly
- **THEN** a "Connection to the agent lost" banner with the reason, a Reconnect action and a Connection settings action appears above the transcript, and the transcript entries stay visible

#### Scenario: Reconnect from the banner
- **WHEN** the user selects Reconnect in the banner and the reconnect succeeds
- **THEN** the banner shows "Reconnecting…" without the Reconnect action while reconnecting, and disappears once the connection is `connected`

#### Scenario: Reconnect from the banner fails
- **WHEN** the user selects Reconnect in the banner and the attempt fails
- **THEN** the banner shows "Could not connect to the agent" with the failure reason and offers Reconnect again

#### Scenario: Empty transcript keeps the connection screen
- **WHEN** the connection is lost while the active session's transcript is empty
- **THEN** the workbench shows the connection screen with Reconnect and no banner

### Requirement: Failed turn notice with Retry
A failed prompt turn SHALL be shown in the transcript as a notice whose title describes the failure class and whose body is the agent's message, with the raw error text available only in collapsed details. The title SHALL follow the agent's `errorClass`:

| `errorClass` | Title |
|---|---|
| `auth` | The agent could not sign in to the model provider |
| `network`, `timeout`, `server` | The model provider is unavailable |
| `rateLimited` | The model provider's rate limit was reached |
| `overflow` | The conversation is too long for the model |
| a turn interrupted by a lost connection | The connection to the agent was lost |
| any other or no class | The agent could not complete the turn |

The notice of the session's last turn SHALL offer a Retry action exactly when the session can retry it (`SessionView.canRetry`, requirement "Повтор сорвавшегося хода" of `acp-client-kit`) and the connection is `connected`. Selecting Retry SHALL send the same prompt as a new turn.

#### Scenario: Provider authentication failure
- **WHEN** the agent answers the prompt as in fixture `acp/prompt-failed-provider-auth`
- **THEN** the transcript shows "The agent could not sign in to the model provider" with the body "401 Unauthorized from openai: check api_key_env", no Retry action, and the raw error text only inside collapsed details

#### Scenario: Retry after a provider outage
- **WHEN** the last turn failed with `errorClass: "server"` and `retryable: true`, and the user selects Retry
- **THEN** the same prompt is sent as a new turn, and the failed turn with its notice stays in the transcript above it

#### Scenario: Turn interrupted by a lost connection
- **WHEN** the agent process exits while a turn is running
- **THEN** the turn's notice reads "The connection to the agent was lost" without a Retry action, and the connection banner offers Reconnect

#### Scenario: Error from a third-party agent
- **WHEN** an agent without the CodeLab extension answers the prompt with a JSON-RPC error without `data`
- **THEN** the notice reads "The agent could not complete the turn" with the JSON-RPC error message as its body, and offers Retry
