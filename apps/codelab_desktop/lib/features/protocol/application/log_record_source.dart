/// Порт источника записей встроенного журнала для панели Protocol.
///
/// Почему порт: записи хранит `LogBuffer` пакета `structured_log_flutter`, а
/// application панели Protocol не импортирует ни Flutter, ни пакеты
/// отображения журнала (правило сторожа, design.md change
/// `redesign-protocol-pane`, D7, D15). Реализация над `LogBuffer` —
/// `LogBufferRecordSource` в `lib/app/` (composition root).
///
/// Для чего: `ProtocolPaneCubit` читает записи, подписывается на изменения и
/// очищает буфер действием `Clear` вида Log; буфер тот же, что у полноэкранного
/// просмотра журнала.
///
/// Как использовать: [records] — снимок записей по порядку записи (старые
/// первыми); [changes] — сигнал «буфер изменился», подписка принадлежит
/// вызывающему и отменяется им; [clear] очищает общий буфер.
abstract interface class LogRecordSource {
  List<Map<String, Object?>> get records;

  Stream<void> get changes;

  void clear();
}
