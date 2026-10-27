## ADDED Requirements

### Requirement: Интеграционный тест Reconnect посреди хода
CodeLab SHALL проверять Reconnect посреди хода интеграционным тестом в `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart` в режиме `CODELAB_E2E_AGENT=dart`. Тест SHALL сам запускать `codelab-agent serve --ws` со сценарием `--llm-script` долгого хода и `--sessions-dir` во временной папке и подключать app по WebSocket. Процесс агента переживает Reconnect, поэтому тест проверяет отмену хода самим агентом. В режиме `scripted` тест SHALL пропускаться.

#### Scenario: Reconnect посреди хода по WebSocket
- **WHEN** app отправляет промпт, сценарий агента отвечает с задержкой, а тест вызывает `Reconnect` до ответа
- **THEN** после переподключения активна та же сессия, лента показывает реплику и «Completed with stopReason cancelled.», `isPromptSubmitting` и `canCancel` — `false`, а следующий промпт получает ответ агента
