## MODIFIED Requirements

### Requirement: Тесты Flutter UI
CodeLab SHALL тестировать состояния соединения, поведение prompt composer, рендеринг потокового transcript, approvals, видимость отмены, состояния ошибок и layout workbench.

#### Scenario: Рендерится UI approval
- **WHEN** состояние approval передано в UI
- **THEN** inline approval в строке вызова виден с элементами approve/reject

#### Scenario: Рендерится следующее действие для состояния ошибки
- **WHEN** UI получает состояние disconnected или failed
- **THEN** он показывает понятную пользователю сводку и конкретное действие для восстановления

#### Scenario: Рендерится панель Protocol
- **WHEN** в буфере кадров есть запросы, уведомления и ошибка, а сборка теста задаёт политику payload `full` или `metadataOnly`
- **THEN** виджет-тест видит таблицу кадров с подписями и тоном ошибки, панель выбранного кадра с InfoBar своей политики и замаскированными значениями — без реального агента и без Flutter-плагинов
