// Политика payload кадров в composition root CLI (задача 2.3 `[client]`
// change `redesign-protocol-pane`; design.md, D3; spec structured-logging
// «Protocol tracing выключен по умолчанию в release»).
//
// Красный тест: файл не компилируется, пока задача 1.4 не добавит
// `AcpClientApplication.protocolFrames` и `ProtocolPayloadPolicy`, а 2.2 —
// `ClientWorkspace.protocolFrames` (`traceAvailable`). Политику задаёт хост:
// без `--verbose` — `metadataOnly`, с ним — `full` (задача 2.4). Тест
// проверяет наблюдаемое: что несут кадры, пришедшие при подключении к
// встроенному агенту, и доступен ли Trace в буфере kit.

import 'dart:async';
import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_cli/src/composition_root.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

const _script = {
  'model': {
    'provider': 'scripted',
    'modelId': 'scripted-1',
    'contextWindow': 32768,
  },
  'steps': <Object?>[],
};

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('codelab_policy_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(CliRuntime, List<ProtocolFrame>)> connected({
    required bool verbose,
  }) async {
    final runtime = buildCliRuntime(
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      stderr: StringBuffer(),
      verbose: verbose,
      embeddedOpener: scriptedEmbeddedAgentOpener(
        llm: _script,
        codelabHome: '${tmp.path}/home',
        logger: const CliEmbeddedLogger.silent(),
      ),
    );
    final frames = <ProtocolFrame>[];
    final sub = runtime.application.protocolFrames.listen(frames.add);
    addTearDown(() async {
      await sub.cancel();
      await runtime.dispose();
    });
    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );
    await pumpEventQueue();
    return (runtime, frames);
  }

  test('без --verbose ядро создано с metadataOnly: кадры без payload, '
      'Trace в буфере доступен', () async {
    final (runtime, frames) = await connected(verbose: false);

    expect(frames, isNotEmpty);
    final initialize = frames.firstWhere(
      (f) =>
          f.direction == ProtocolFrameDirection.outbound &&
          f.method == 'initialize',
    );
    expect(initialize.payload, isNull);
    expect(initialize.payloadOmitted, ProtocolPayloadOmitted.policy);
    expect(frames.where((f) => f.payload != null), isEmpty);
    expect(runtime.workspace.protocolFrames.traceAvailable, isTrue);
  });

  test('с --verbose ядро создано с full: кадры несут payload, '
      'Trace недоступен', () async {
    final (runtime, frames) = await connected(verbose: true);

    final initialize = frames.firstWhere(
      (f) =>
          f.direction == ProtocolFrameDirection.outbound &&
          f.method == 'initialize',
    );
    expect(initialize.payload, isA<Map<dynamic, dynamic>>());
    expect(initialize.payloadOmitted, isNull);
    expect(runtime.workspace.protocolFrames.traceAvailable, isFalse);
  });
}
