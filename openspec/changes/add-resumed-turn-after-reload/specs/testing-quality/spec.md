## ADDED Requirements

### Requirement: Интеграционный тест хода, пережившего переподключение
CodeLab SHALL проверять ход, переживший `Reconnect`, интеграционным тестом в `apps/codelab_desktop/integration_test/session_list_load_flow_test.dart` в режиме `CODELAB_E2E_AGENT=dart`. Тест SHALL сам запускать `codelab-agent serve --ws` со сценарием `--llm-script` долгого хода и `--sessions-dir` во временной папке и подключать app по WebSocket. В режиме `scripted` тест SHALL пропускаться: у scripted-агента нет `detachGrace`.

#### Scenario: Reconnect посреди хода по WebSocket
- **WHEN** app отправляет промпт, сценарий агента отвечает с задержкой, а тест вызывает `Reconnect` до ответа
- **THEN** после переподключения активна та же сессия, лента показывает реплику и ответ агента, а `isPromptSubmitting` и `canCancel` возвращаются в `false`
