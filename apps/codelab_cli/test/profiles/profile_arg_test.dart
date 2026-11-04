// Значение `--agent` (tasks 2.3; spec codelab-cli «Профили подключения
// CLI»; design.md change `add-codelab-cli`, D4).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/memory_profile_store.dart';

void main() {
  final store = MemoryProfileStore([
    const StdioProfile(
      id: 'default',
      label: 'Default',
      command: 'codelab-agent',
      args: ['serve', '--stdio'],
    ),
    const StdioProfile(id: 'py', label: 'Python', command: 'codelab'),
  ]);

  test('stdio: is split like a shell command', () async {
    final profile = await resolveAgentProfile(
      'stdio:python -m "codelab agent" --stdio',
      store: store,
    );

    expect(
      profile,
      isA<StdioProfile>()
          .having((p) => p.command, 'command', 'python')
          .having((p) => p.args, 'args', ['-m', 'codelab agent', '--stdio'])
          .having((p) => p.runInProjectDirectory, 'cwd', isTrue),
    );
  });

  test('stdio: without a command or with a broken quote is a usage '
      'error', () async {
    for (final value in ['stdio:', 'stdio:   ', 'stdio:run "oops']) {
      await expectLater(
        resolveAgentProfile(value, store: store),
        throwsA(isA<UsageError>()),
        reason: value,
      );
    }
  });

  test('ws:// and wss:// read the token from CODELAB_AGENT_TOKEN', () async {
    for (final value in ['ws://127.0.0.1:8765', 'wss://agent.test/acp']) {
      final profile = await resolveAgentProfile(value, store: store);

      expect(
        profile,
        isA<WebSocketProfile>()
            .having((p) => p.uri, 'uri', Uri.parse(value))
            .having((p) => p.tokenRef, 'tokenRef', 'env:CODELAB_AGENT_TOKEN'),
      );
    }
  });

  test(
    'embedded is the built-in profile for the CLI host (D13, п. 1)',
    () async {
      final profile = await resolveAgentProfile('embedded', store: store);

      expect(
        profile,
        const ConnectionProfile.embedded(
          id: 'embedded',
          label: 'Embedded agent',
          hostProfile: 'embedded-cli',
        ),
      );
    },
  );

  test('explicit embedded beats the "default" profile and never reads the '
      'store', () async {
    expect(
      await resolveAgentProfile('embedded', store: MemoryProfileStore.broken()),
      isA<EmbeddedProfile>(),
    );
  });

  test('a profile id is looked up in the store', () async {
    expect(
      await resolveAgentProfile('py', store: store),
      isA<StdioProfile>().having((p) => p.command, 'command', 'codelab'),
    );
  });

  test('an unknown profile id is a usage error', () async {
    await expectLater(
      resolveAgentProfile('nope', store: store),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('Unknown agent profile "nope"'),
        ),
      ),
    );
  });

  test(
    'without --agent the embedded agent is used and the store is '
    'never read, even with a "default" record or a broken file (D21)',
    () async {
      const embedded = ConnectionProfile.embedded(
        id: 'embedded',
        label: 'Embedded agent',
        hostProfile: 'embedded-cli',
      );

      expect(await resolveAgentProfile(null, store: store), embedded);
      expect(
        await resolveAgentProfile(null, store: MemoryProfileStore()),
        embedded,
      );
      expect(
        await resolveAgentProfile(null, store: MemoryProfileStore.broken()),
        embedded,
      );
    },
  );

  test('-a default is an alias of embedded: the stored "default" record is '
      'not used and a broken file does not matter (D21)', () async {
    expect(
      await resolveAgentProfile('default', store: store),
      embeddedCliProfile,
    );
    expect(
      await resolveAgentProfile('default', store: MemoryProfileStore.broken()),
      embeddedCliProfile,
    );
  });

  test('-a default ignores any read error of the store, not only a broken '
      'format (EACCES is a FileSystemException)', () async {
    final warnings = <String>[];

    final profile = await resolveAgentProfile(
      'default',
      store: _UnreadableStore(),
      onWarning: warnings.add,
    );

    expect(profile, embeddedCliProfile);
    expect(warnings, isEmpty);
  });

  test('-a default with profiles.json as a directory starts the embedded '
      'agent', () async {
    final tmp = Directory.systemTemp.createTempSync('codelab_default_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/profiles.json').createSync();

    expect(
      await resolveAgentProfile(
        'default',
        store: JsonFileProfileStore('${tmp.path}/profiles.json'),
        onWarning: (_) {},
      ),
      embeddedCliProfile,
    );
  });

  test(
    'an old profile with capital letters is selected by -a as before',
    () async {
      final old = MemoryProfileStore([
        ConnectionProfile.webSocket(
          id: 'Old',
          label: 'Old',
          uri: Uri.parse('wss://agent.test/acp'),
          tokenRef: 'env:CODELAB_AGENT_TOKEN',
        ),
      ]);

      expect(
        await resolveAgentProfile('Old', store: old),
        isA<WebSocketProfile>().having((p) => p.id, 'id', 'Old'),
      );
    },
  );

  test('a broken profiles file is a usage error', () async {
    await expectLater(
      resolveAgentProfile('py', store: MemoryProfileStore.broken()),
      throwsA(isA<UsageError>()),
    );
  });
}

/// Хранилище, чтение которого падает как при `EACCES`.
final class _UnreadableStore implements ProfileStore {
  @override
  Future<List<ConnectionProfile>> load() async =>
      throw const FileSystemException('Permission denied', 'profiles.json');

  @override
  Future<void> save(ConnectionProfile profile) async {}

  @override
  Future<bool> remove(String id) async => false;
}
