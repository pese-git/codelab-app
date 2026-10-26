## 1. Тесты

- [x] 1.1 Widget-тест `CodeLabTranscriptPanel`: лента у низа, дописаны записи выше высоты видимой части — последняя запись onstage
- [x] 1.2 Widget-тест: пользователь прокрутил вверх, дописаны записи — позиция не изменилась
- [x] 1.3 Widget-тест: пользователь вернулся к низу — следование возобновилось
- [x] 1.4 Существующие тесты автопрокрутки к approval проходят без изменений

## 2. Реализация

- [x] 2.1 `_CodeLabTranscriptPanelState.didUpdateWidget`: решение о следовании по метрикам до раскладки (D1, D4), приоритет approval (D3)
- [x] 2.2 Флаг `_isFollowingTail`, сброс по `UserScrollNotification`, догон низа в `_followMovedBottom` (D2)

## 3. Проверка

- [x] 3.1 e2e `fs_flow_test`, `terminal_flow_test`, `prompt_queue_flow_test` против Dart-агента (`CODELAB_E2E_AGENT=dart`) и scripted-агента
- [x] 3.2 `fvm dart run melos run check`
