// Composition root панели Protocol (задача 5.1 change
// `redesign-protocol-pane`; design.md D3, D7, D15; spec agent-workbench-ui
// «Режим Trace панели Protocol»; observability.md §27, §48).
//
// Красный до задачи 5.2: у `createCodeLabRootScope` и `CodeLabTestBinding`
// нет шва `debugBuild:` и `protocolExportSaver:`, в root scope нет
// `ProtocolPaneCubit`, `ProtocolExportSaver` и `LogRecordSource`, а файла
// `lib/app/log_buffer_record_source.dart` нет.
//
// Ожидаемый API:
//
// * `debugBuild: bool?` — шов режима сборки (по умолчанию `kDebugMode`);
//   тест не подменяет `kDebugMode`, а передаёт значение через шов (D3);
// * `protocolExportSaver: ProtocolExportSaver?` — шов порта сохранения;
// * `LogBufferRecordSource(LogBuffer)` в `lib/app/` — адаптер порта
//   `LogRecordSource` над `LogBuffer` (D7);
// * `ProtocolPaneCubit` и `ProtocolExportSaver` — в root scope; закрытие —
//   в `CodeLabRootLifecycle`.

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show AcpClientApplication;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/log_buffer_record_source.dart';
import 'package:codelab_desktop/core/platform/protocol_export_saver.dart';
import 'package:codelab_desktop/features/protocol/application/log_record_source.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_pane_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/fake_protocol_export_saver.dart';
import '../support/test_app_scope.dart';

void main() {
  group('политика payload в composition root (D3)', () {
    test('debug-сборка: ядро создано с full, Trace не нужен', () {
      final binding = CodeLabTestBinding(debugBuild: true);
      addTearDown(binding.scope.dispose);

      final application = binding.scope.resolve<AcpClientApplication>();

      expect(application.traceAvailable, isFalse);
      expect(
        binding.scope.resolve<ProtocolPaneCubit>().state.traceAvailable,
        isFalse,
      );
    });

    test('release-сборка: ядро создано с metadataOnly, Trace доступен', () {
      final binding = CodeLabTestBinding(debugBuild: false);
      addTearDown(binding.scope.dispose);

      final application = binding.scope.resolve<AcpClientApplication>();

      expect(application.traceAvailable, isTrue);
      expect(
        binding.scope.resolve<ProtocolPaneCubit>().state.traceAvailable,
        isTrue,
      );
    });
  });

  group('root scope', () {
    test('порт экспорта подменяется швом и один на scope', () {
      final saver = FakeProtocolExportSaver();
      final binding = CodeLabTestBinding(protocolExportSaver: saver);
      addTearDown(binding.scope.dispose);

      expect(binding.scope.resolve<ProtocolExportSaver>(), same(saver));
    });

    test('без шва порт — настоящий адаптер file_selector', () {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);

      expect(
        binding.scope.resolve<ProtocolExportSaver>(),
        isA<FileSelectorProtocolExportSaver>(),
      );
    });

    test('Cubit один на root scope (singleton)', () {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);

      expect(
        binding.scope.resolve<ProtocolPaneCubit>(),
        same(binding.scope.resolve<ProtocolPaneCubit>()),
      );
    });

    test('LogRecordSource читает тот же LogBuffer, что и полноэкранный '
        'просмотр', () {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);
      final buffer = binding.scope.resolve<LogBuffer>();
      final source = binding.scope.resolve<LogRecordSource>();

      buffer.capture({
        'event': 'protocol_probe',
        'level': 'info',
      }, LogLevel.info);

      expect(source, isA<LogBufferRecordSource>());
      expect(source.records.map((r) => r['event']), contains('protocol_probe'));
    });

    test('закрытие CodeLabRootLifecycle закрывает Cubit панели', () async {
      final binding = CodeLabTestBinding();
      final cubit = binding.scope.resolve<ProtocolPaneCubit>();

      await binding.scope.resolve<CodeLabRootLifecycle>().dispose();

      expect(cubit.isClosed, isTrue);
    });
  });

  group('LogBufferRecordSource (D7)', () {
    late LogBuffer buffer;
    late LogBufferRecordSource source;

    setUp(() {
      buffer = LogBuffer(capacity: 3);
      source = LogBufferRecordSource(buffer);
    });

    void capture(String event) =>
        buffer.capture({'event': event, 'level': 'info'}, LogLevel.info);

    test('records — записи буфера по порядку записи', () {
      capture('a');
      capture('b');

      expect(source.records.map((r) => r['event']), ['a', 'b']);
    });

    test('ёмкость буфера соблюдается: старые вытесняются', () {
      for (final e in ['a', 'b', 'c', 'd']) {
        capture(e);
      }

      expect(source.records.map((r) => r['event']), ['b', 'c', 'd']);
    });

    test('changes сообщает об изменении буфера', () async {
      var notifications = 0;
      final sub = source.changes.listen((_) => notifications++);
      addTearDown(sub.cancel);

      capture('a');
      await Future<void>.delayed(Duration.zero);

      expect(notifications, greaterThan(0));
    });

    test('clear очищает буфер: полноэкранный просмотр тоже пуст', () async {
      capture('a');
      capture('b');
      var notifications = 0;
      final sub = source.changes.listen((_) => notifications++);
      addTearDown(sub.cancel);

      source.clear();
      await Future<void>.delayed(Duration.zero);

      expect(buffer.entries.value, isEmpty);
      expect(source.records, isEmpty);
      expect(notifications, greaterThan(0));
    });

    test('после отмены подписки слушателей буфера не остаётся', () async {
      final sub = source.changes.listen((_) {});
      await sub.cancel();

      // Запись после отмены не должна падать и не доставляется.
      expect(() => capture('late'), returnsNormally);
    });
  });
}
