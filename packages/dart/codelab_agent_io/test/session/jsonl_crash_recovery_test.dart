import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// Задача 6.2: журнал на диске после сбоя загружается через
/// `AgentRuntime.loadSession`, и ход продолжается (SES-5;
/// `core/session-crash-mid-turn-loads`).
void main() {
  late String root;
  late String cwd;

  setUp(() {
    root = tempRoot('jsonl_crash_', addTearDown);
    cwd = tempRoot('jsonl_crash_cwd_', addTearDown);
  });

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  test('a journal cut mid-line loads and the turn continues', () async {
    final store = storeAt(root);
    await store.create(headerOf(id, cwd: cwd));
    await store.append(sid, userRecord('aaaaaaaa', null, 'start the task'));
    await store.close(sid);
    journalFile(root, id).writeAsStringSync(
      '{"type":"message","id":"bbbbbbbb","parentId":"aaaa',
      mode: FileMode.append,
    );

    final run = await _continueTurn(root, cwd, sid);

    expect(run.result.reason, TurnEndReason.completed);
    expect(run.opened.repair.quarantinedLines, 1);
    expect(run.userTexts, ['start the task', 'go on']);
    _expectReadable(journalFile(root, id));
  });

  test('core/session-crash-mid-turn-loads: SIGKILL mid-write', () async {
    final child = await Process.start(_dartExecutable(), [
      'test/session/crash_child.dart',
      root,
      id,
      cwd,
    ], workingDirectory: _ioPackageDir());
    // Под `flutter test` дочерний VM сначала печатает адрес VM service.
    await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line == 'ready')
        .timeout(const Duration(seconds: 60));
    child.kill(ProcessSignal.sigkill);
    expect(await child.exitCode, isNot(0));

    final file = journalFile(root, id);
    final run = await _continueTurn(root, cwd, sid);

    expect(run.opened.records.map((r) => r.id), ['k3f9a1c2', 'p7d2e8b4']);
    expect(run.opened.repair.isClean, isFalse);
    expect(run.opened.repair.quarantinedLines, 1);
    final quarantined =
        jsonDecode(File('${file.path}.corrupt').readAsLinesSync().single)
            as Map<String, Object?>;
    expect(quarantined['reason'], 'truncated');
    expect(run.result.reason, TurnEndReason.completed);
    expect(run.userTexts, ['start the task', 'go on']);
    _expectReadable(file);
  });
}

/// Итог продолжения: снимок открытия, результат хода и тексты user-
/// сообщений в запросе к модели.
typedef _Run = ({
  SessionSnapshot opened,
  TurnResult result,
  List<String> userTexts,
});

/// Загружает сессию [sid] из журналов [root] через `buildAgentCore` с
/// включённым `sessionPersistence` и выполняет один ход.
Future<_Run> _continueTurn(String root, String cwd, SessionId sid) async {
  final store = _OpenSpy(storeAt(root));
  final model = ScriptedStreamFunction.fromJson({
    'steps': [
      {
        'reply': [
          {'text': 'Continuing.'},
        ],
      },
    ],
  });
  final core = buildAgentCore(
    profile: HostProfile.of('embedded-cli'),
    services: AgentCoreServices(
      baseEnv: LocalExecutionEnv(cwd: cwd),
      gate: const _DenyGate(),
      logger: RecordingLogger(),
      clock: FakeClock(start: t0),
      ids: SequentialIdGenerator(),
      sessions: store,
    ),
    config: CoreConfig(defaultModel: _model),
    streamFunction: model.call,
  );
  final session = await core.runtime.loadSession(sid, const SessionHostPorts());
  final result = await session.prompt(const [TextContent('go on')]);
  await core.runtime.dispose();
  model.verify();
  return (
    opened: store.opened!,
    result: result,
    userTexts: [
      for (final m in model.requests.single.messages.whereType<UserMessage>())
        for (final b in m.content.whereType<TextContent>()) b.text,
    ],
  );
}

/// Каждая строка журнала разбирается: дописанное после ремонта не склеилось
/// с оборванной строкой.
void _expectReadable(File file) {
  for (final line in file.readAsLinesSync()) {
    expect(() => jsonDecode(line), returnsNormally, reason: line);
  }
}

/// Исполняемый `dart`: под `flutter test` (`melos run check`)
/// `Platform.resolvedExecutable` — это `flutter_tester`, который не
/// запускает скрипты, поэтому SDK ищется через `FLUTTER_ROOT`, как в
/// `acp_transports_test.dart`.
String _dartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/$name');
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  final current = File(Platform.resolvedExecutable);
  return current.uri.pathSegments.last == name ? current.path : name;
}

String _ioPackageDir() {
  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    for (final candidate in [
      dir.path,
      '${dir.path}/packages/dart/codelab_agent_io',
    ]) {
      final pubspec = File('$candidate/pubspec.yaml');
      if (pubspec.existsSync() &&
          pubspec.readAsStringSync().contains('name: codelab_agent_io')) {
        return candidate;
      }
    }
    if (dir.parent.path == dir.path) {
      throw StateError('codelab_agent_io is not above ${Directory.current}');
    }
  }
}

final _model = ModelRef(
  provider: 'test',
  id: 'model-1',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

/// Хранилище, запоминающее снимок первого [open] — по нему тест видит
/// `RepairReport`, который сессия не публикует.
final class _OpenSpy implements SessionStore {
  _OpenSpy(this._inner);

  final SessionStore _inner;
  SessionSnapshot? opened;

  @override
  Future<SessionSnapshot> open(SessionId id) async =>
      opened ??= await _inner.open(id);

  @override
  Future<void> create(SessionHeader header) => _inner.create(header);

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) => _inner.append(id, record, durable: durable);

  @override
  Future<void> flush(SessionId id) => _inner.flush(id);

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      _inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => _inner.close(id);
}

/// В ходе этих тестов инструменты не вызываются.
final class _DenyGate implements PermissionGate {
  const _DenyGate();

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async => PermissionDecision.rejectOnce;
}
