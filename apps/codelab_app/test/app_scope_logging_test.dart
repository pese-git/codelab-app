import 'dart:io';

import 'package:codelab_app/app/app_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';

void main() {
  tearDown(StructlogConfiguration.reset);

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
