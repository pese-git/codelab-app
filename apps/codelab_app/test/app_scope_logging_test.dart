import 'dart:io';

import 'package:cherrypick/cherrypick.dart';
import 'package:codelab_app/app/app_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import 'support/test_app_scope.dart';

void main() {
  tearDown(StructlogConfiguration.reset);

  test(
    'LogBuffer resolves from the root scope and captures application-level '
    'events (replace-debug-log-panel-with-fluent/design.md, Decision 3)',
    () async {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);

      final buffer = binding.scope.resolve<LogBuffer>();
      expect(buffer.entries.value, isEmpty);

      binding.transport.emitDiagnostic(
        message: 'stderr line',
        source: 'stderr',
      );

      expect(buffer.entries.value, isNotEmpty);
      expect(
        buffer.entries.value.every((e) => e['category'] == 'application'),
        isTrue,
      );
    },
  );

  test('CodeLabLoggingLifecycle.dispose() awaits pending writes on both sinks '
      '(design.md Decision 8 — graceful shutdown)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'codelab-logging-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final applicationOutput = AsyncFileOutput(
      '${tempDir.path}/application.log',
    );
    final protocolTraceOutput = AsyncRotatingFileOutput(
      '${tempDir.path}/protocol.log',
    );
    final lifecycle = CodeLabLoggingLifecycle(
      applicationOutput: applicationOutput,
      protocolTraceOutput: protocolTraceOutput,
    );

    applicationOutput({'event': 'queued'}, LogLevel.info);
    protocolTraceOutput({'event': 'queued'}, LogLevel.trace);

    await lifecycle.dispose();

    expect(File('${tempDir.path}/application.log').existsSync(), isTrue);
    expect(File('${tempDir.path}/protocol.log').existsSync(), isTrue);
  });

  test('CodeLabLoggingLifecycle.dispose() works when the application sink is '
      'console-only (debug build, no AsyncFileOutput)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'codelab-logging-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final protocolTraceOutput = AsyncRotatingFileOutput(
      '${tempDir.path}/protocol.log',
    );
    final lifecycle = CodeLabLoggingLifecycle(
      applicationOutput: null,
      protocolTraceOutput: protocolTraceOutput,
    );

    await expectLater(lifecycle.dispose(), completes);
  });
}
