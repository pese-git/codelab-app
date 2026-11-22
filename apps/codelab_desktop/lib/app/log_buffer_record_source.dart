import 'dart:async';

import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../features/protocol/application/log_record_source.dart';

/// Адаптер порта [LogRecordSource] над `LogBuffer` встроенного журнала.
///
/// Почему в `lib/app/`: `LogBuffer` — тип `structured_log_flutter`, а
/// application панели Protocol его не импортирует (правило сторожа, design.md
/// change `redesign-protocol-pane`, D7, D15); сборка адаптера — дело
/// composition root.
///
/// Для чего: вид Log и полноэкранный просмотр читают один буфер, поэтому
/// `Clear` вида Log очищает оба (spec agent-workbench-ui «Pause, Clear и
/// Export…»). Как использовать: `LogBufferRecordSource(scope.resolve<LogBuffer>())`;
/// каждая подписка на [changes] — отдельный слушатель буфера, который
/// снимается вместе с подпиской.
final class LogBufferRecordSource implements LogRecordSource {
  LogBufferRecordSource(this._buffer);

  final LogBuffer _buffer;

  /// Неизменяемый снимок буфера, те же объекты записей, без копий: выбор
  /// записи в панели сравнивается по ссылке и должен переживать новые записи
  /// журнала (ревью change `redesign-protocol-pane`, major 1). Список
  /// неизменяем (`LogBuffer` отдаёт `List.unmodifiable`), а записи после
  /// захвата не меняются.
  @override
  List<Map<String, Object?>> get records => _buffer.entries.value;

  @override
  Stream<void> get changes {
    late StreamController<void> controller;
    void notify() => controller.add(null);
    controller = StreamController<void>.broadcast(
      onListen: () => _buffer.entries.addListener(notify),
      onCancel: () => _buffer.entries.removeListener(notify),
    );
    return controller.stream;
  }

  @override
  void clear() => _buffer.clear();
}
