import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// Файл `usage.json` в каталоге сессии (agent-sessions «Файл usage.json и
/// порт UsageLedgerStore», сценарий «Удалённый файл восстанавливается»;
/// design.md change `add-usage-ledger`, D3, D13; `agent-core-architecture`
/// §8.9). Задача 1.5.
///
/// Всё — во временном каталоге; настоящий `~/.codelab` не читается.
void main() {
  late String root;
  late JsonlSessionStore sessions;
  late JsonlUsageLedgerStore port;

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  setUp(() async {
    root = tempRoot('usage_ledger_', addTearDown);
    sessions = storeAt(root);
    port = JsonlUsageLedgerStore(sessions);
    await sessions.create(headerOf(id));
  });

  /// Каталог сессии: путь файла журнала без `.jsonl` (§8.9).
  String sessionDir() {
    final journal = journalFile(root, id).path;
    return journal.substring(0, journal.length - '.jsonl'.length);
  }

  String ledgerPath() => '${sessionDir()}/usage.json';

  test('write: <journal without .jsonl>/usage.json, the content as is, no '
      'temporary file left', () async {
    await port.write(sid, '{"version":1}\n');

    expect(File(ledgerPath()).readAsStringSync(), '{"version":1}\n');
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
    expect(
      Directory(sessionDir()).listSync().map((e) => e.path.split('/').last),
      ['usage.json'],
    );
  });

  test('write replaces the previous content', () async {
    await port.write(sid, 'old\n');

    await port.write(sid, 'new\n');

    expect(File(ledgerPath()).readAsStringSync(), 'new\n');
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
  });

  test('read returns what was written; a missing file is null', () async {
    expect(await port.read(sid), isNull);

    await port.write(sid, '{"version":1}\n');

    expect(await port.read(sid), '{"version":1}\n');
  });

  test('read of a session the store does not know is null', () async {
    expect(
      await port.read(const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0Z')),
      isNull,
    );
  });

  test('the file path is inside the root of the sessions', () async {
    await port.write(sid, 'x\n');

    expect(ledgerPath(), startsWith('$root/'));
    expect(File(ledgerPath()).existsSync(), isTrue);
  });

  test('a SessionId with a path does not get out of the sessions root: a '
      'typed error, no file anywhere (D13)', () async {
    const evil = SessionId('../../escaped');

    await expectLater(
      port.write(evil, 'x\n'),
      throwsA(isA<UsageLedgerStoreException>()),
    );
    expect(await port.read(evil), isNull);
    final outside = Directory(root).parent
        .listSync(recursive: true, followLinks: false)
        .where(
          (e) => e.path.contains('escaped') || e.path.endsWith('usage.json'),
        )
        .where((e) => !e.path.startsWith(root));
    expect(outside, isEmpty);
  });

  test('a directory without write permission: UsageLedgerStoreException '
      'with a reason, the process lives, no temporary file', () async {
    final dir = Directory(sessionDir())..createSync(recursive: true);
    final chmod = await Process.run('chmod', ['500', dir.path]);
    expect(chmod.exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['700', dir.path]));
    // Суперпользователь пишет и в такой каталог: проверка бессмысленна.
    try {
      File('${dir.path}/probe').writeAsStringSync('x');
      File('${dir.path}/probe').deleteSync();
      markTestSkipped('the user can write to a read-only directory (root)');
      return;
    } on FileSystemException {
      // Каталог закрыт — то, что нужно.
    }

    await expectLater(
      port.write(sid, 'x\n'),
      throwsA(
        isA<UsageLedgerStoreException>().having(
          (e) => e.message,
          'message',
          isNotEmpty,
        ),
      ),
    );
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
    expect(File(ledgerPath()).existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'chmod есть только на POSIX' : false);

  test('a deleted usage.json is rebuilt byte for byte the same by the core '
      '(scenario "Удалённый файл восстанавливается")', () async {
    final logger = RecordingLogger();
    final model = ScriptedStreamFunction.fromJson({
      'steps': [
        for (var i = 0; i < 2; i++)
          {
            'reply': [
              {'text': 'answer $i'},
            ],
            'usage': {
              'input': 100 + i,
              'output': 10,
              'cost': {'input': 0.0003, 'output': 0.0001},
            },
          },
      ],
    });
    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        HostCapability.shellExec: const CapabilityOff('тест без shell'),
      }),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/work/demo'),
        logger: logger,
        clock: FakeClock(start: t0),
        ids: SequentialIdGenerator(),
        sessions: sessions,
        usageLedger: port,
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'model-1',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost:8080/v1'),
          contextWindow: 32768,
          maxOutputTokens: 4096,
        ),
      ),
      streamFunction: model.call,
    );
    addTearDown(core.runtime.dispose);
    final session = await core.runtime.createSession(
      SessionSpec(cwd: '/work/demo'),
    );
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    final first = await session.usageLedger();
    final file = File('${_sessionDirOf(root, session.id.value)}/usage.json');
    expect(first.state, UsageLedgerFileState.rebuilt);
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    file.deleteSync();

    final again = await session.usageLedger();

    expect(again.state, UsageLedgerFileState.rebuilt);
    expect(again.reason, UsageLedgerRebuildReason.missing);
    expect(file.readAsBytesSync(), bytes);
  });
}

/// Каталог сессии с идентификатором [id] под [root] (§8.9).
String _sessionDirOf(String root, String id) {
  final journal = journalFile(root, id).path;
  return journal.substring(0, journal.length - '.jsonl'.length);
}
