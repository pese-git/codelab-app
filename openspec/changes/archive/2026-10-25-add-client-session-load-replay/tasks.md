## 1. Реплей session/load в клиенте

- [x] 1.1 Красные тесты: реплей до ответа виден в сессии после `loadSession`; подряд идущие чанки пользователя — одна реплика; буфер отбрасывается при ошибке; `current_mode_update`/`session_info_update` без хода; `replayHistory`
- [x] 1.2 Буфер реплея в `AcpClientApplication.loadSession` и `_handleSessionUpdate`
- [x] 1.3 `SessionStateMachine.replayHistory` и сессионные обновления режима и заголовка
- [x] 1.4 `fvm dart run melos run check`

## 2. Клиентское покрытие FIX-2 (после слияния итерации 4 этапа 4)

- [x] 2.1 Действие `session/load` в клиентском драйвере фикстур (`_User.act`); роль `client` и проверки состояния у `acp/session-load-replay`, `acp/session-load-interrupted-turn`, `acp/config-effort-option` (id запросов — через `$capture`, образцы `modes` и опции `mode` — полные, чтобы клиент мог их разобрать)
- [x] 2.2 Убрать покрытые элементы из `pendingCoverage` (`session/load`, `user_message_chunk`, `current_mode_update`, `config_option_update`); `session/list` и `session/set_mode` остаются — клиент их не вызывает
- [x] 2.3 `fvm dart run melos run check`, включая `conformance:client` и `conformance:agent`
