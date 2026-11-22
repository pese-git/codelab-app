// Вид Log над настоящим `LogBufferRecordSource` и `LogBuffer` (ревью change
// `redesign-protocol-pane`, major 1): выбор записи должен переживать новые
// записи журнала. Адаптер раньше копировал записи, а Cubit сравнивал выбор
// по `identical`, поэтому выбор терялся при каждой записи.

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/app/log_buffer_record_source.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_cubit.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/fake_protocol_export_saver.dart';
import '../../../support/fake_protocol_workspace.dart';
import '../../../support/recording_logger.dart';

void main() {
  late LogBuffer buffer;
  late FakeProtocolWorkspace workspace;
  late ProtocolPaneCubit cubit;

  void capture(String event) =>
      buffer.capture({'event': event, 'level': 'info'}, LogLevel.info);

  /// `LogBuffer` уведомляет подписчиков микрозадачей, `Cubit` — таймером.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> bootstrap(WidgetTester tester) async {
    buffer = LogBuffer();
    workspace = FakeProtocolWorkspace();
    cubit = ProtocolPaneCubit(
      workspace: workspace,
      logRecords: LogBufferRecordSource(buffer),
      exportSaver: FakeProtocolExportSaver(),
      basePolicy: ProtocolPayloadPolicy.metadataOnly,
      logger: RecordingLogger(),
    );
    cubit.selectView(ProtocolView.log);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(cubit.close);
    await tester.runAsync(workspace.dispose);
  }

  testWidgets('записи адаптера — те же объекты, что в буфере', (tester) async {
    await bootstrap(tester);
    capture('a');

    final source = LogBufferRecordSource(buffer);

    expect(identical(source.records.first, buffer.entries.value.first), isTrue);
    await close(tester);
  });

  testWidgets('выбранная запись остаётся выбранной после новой записи '
      'журнала', (tester) async {
    await bootstrap(tester);
    capture('first');
    capture('second');
    final sub = cubit.stream.listen((_) {});
    await settle(tester);
    cubit.selectRecord(cubit.state.visibleRecords.first);

    capture('third');
    await settle(tester);

    final selected = cubit.state.selectedRecord;
    expect(cubit.state.visibleRecords, hasLength(3));
    expect(selected, isNotNull);
    expect(identical(selected, cubit.state.visibleRecords.first), isTrue);
    await tester.runAsync(sub.cancel);
    await close(tester);
  });

  testWidgets('Alt+↓ после новой записи выбирает следующую, а не первую', (
    tester,
  ) async {
    await bootstrap(tester);
    capture('first');
    capture('second');
    await settle(tester);
    cubit.selectRecord(cubit.state.visibleRecords.first);
    capture('third');
    await settle(tester);

    cubit.selectNext();

    expect(cubit.state.selectedRecord!['event'], 'second');
    await close(tester);
  });
}
