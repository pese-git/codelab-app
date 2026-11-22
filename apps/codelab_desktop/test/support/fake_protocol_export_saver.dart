import 'package:codelab_desktop/core/platform/protocol_export_saver.dart';

/// Двойник порта [ProtocolExportSaver] (design.md change
/// `redesign-protocol-pane`, D10): записывает вызовы и возвращает [result].
///
/// Как использовать: `CodeLabTestBinding(protocolExportSaver: fake)`; после
/// `Export…` проверять `fake.saved`.
final class FakeProtocolExportSaver implements ProtocolExportSaver {
  FakeProtocolExportSaver({this.result = const ProtocolExportSaved()});

  ProtocolExportSaveResult result;

  final List<({String suggestedName, String text})> saved = [];

  @override
  Future<ProtocolExportSaveResult> save({
    required String suggestedName,
    required String text,
  }) async {
    saved.add((suggestedName: suggestedName, text: text));
    return result;
  }
}
