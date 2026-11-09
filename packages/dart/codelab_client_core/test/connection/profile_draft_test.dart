// Черновик профиля подключения (task 3.1 change `add-app-settings-shell`;
// spec acp-client-kit «Черновик профиля подключения»; SETUP-19, SETUP-21,
// SETUP-22; design.md, D11).

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

ProfileDraft _stdio({
  String id = 'dev',
  String label = 'Dev',
  String command = 'codelab-agent',
  String args = 'serve --stdio',
  String env = '',
}) => ProfileDraft(
  kind: ProfileKind.stdio,
  id: id,
  label: label,
  command: command,
  args: args,
  env: env,
);

ProfileDraft _ws({
  String id = 'devbox',
  String label = 'Devbox',
  String url = 'wss://devbox:7420',
  ProfileTokenChoice token = const NoToken(),
}) => ProfileDraft(
  kind: ProfileKind.webSocket,
  id: id,
  label: label,
  url: url,
  token: token,
);

Set<ProfileDraftIssueCode> _codes(List<ProfileDraftIssue> issues) => {
  for (final issue in issues) issue.code,
};

void main() {
  group('suggestProfileId', () {
    test('lowercases, replaces foreign characters and trims dashes', () {
      expect(suggestProfileId('My  Dev-Box!'), 'my-dev-box');
      expect(suggestProfileId('  --Agent_1.x--  '), 'agent-1-x');
      expect(suggestProfileId('!!!'), '');
    });

    test('a name "Default" yields a reserved id', () {
      final draft = _stdio(label: 'Default', id: suggestProfileId('Default'));

      expect(
        _codes(draft.validate(const [])),
        contains(ProfileDraftIssueCode.idReserved),
      );
    });
  });

  group('id', () {
    test('empty, reserved, taken (case-insensitive) and invalid ids', () {
      const existing = ['dev'];
      expect(_codes(_stdio(id: '').validate(existing)), {
        ProfileDraftIssueCode.idEmpty,
      });
      expect(_codes(_stdio(id: 'embedded').validate(existing)), {
        ProfileDraftIssueCode.idReserved,
      });
      expect(_codes(_stdio(id: 'default').validate(existing)), {
        ProfileDraftIssueCode.idReserved,
      });
      expect(_codes(_stdio(id: 'Dev').validate(existing)), {
        ProfileDraftIssueCode.idTaken,
      });
      expect(_codes(_stdio(id: 'a:b').validate(existing)), {
        ProfileDraftIssueCode.idInvalid,
      });
      expect(_stdio(id: 'ok-1').validate(existing), isEmpty);
    });

    test('an empty label is reported', () {
      expect(_codes(_stdio(label: '  ').validate(const [])), {
        ProfileDraftIssueCode.labelEmpty,
      });
    });
  });

  // Task 1.16 change `switch-default-agent-to-dart`; spec acp-client-kit
  // «Черновик «Add profile» совпадает с описанием», «Нет умолчаний
  // Python-агента»; design.md, D10: один источник умолчаний.
  group('stdio defaults come from codelabAgentStdioProfile (D10)', () {
    test('command and args of the default stdio draft equal the built-in '
        'description', () {
      const draft = ProfileDraft(kind: ProfileKind.stdio);

      expect(draft.command, codelabAgentStdioProfile.command);
      expect(draft.args, codelabAgentStdioProfile.args.join(' '));
      expect(parseShellWords(draft.args), codelabAgentStdioProfile.args);
    });

    test(
      'no Python agent defaults: the draft never offers `codelab serve`',
      () {
        const draft = ProfileDraft(kind: ProfileKind.stdio);

        expect(draft.command, 'codelab-agent');
        expect(draft.args, 'serve --stdio');
      },
    );
  });

  group('stdio', () {
    test(
      'defaults point at codelab-agent serve --stdio, project folder on',
      () {
        const draft = ProfileDraft(kind: ProfileKind.stdio);

        expect(draft.command, 'codelab-agent');
        expect(draft.args, 'serve --stdio');
        expect(draft.runInProjectDirectory, isTrue);
      },
    );

    test('quoted arguments are split, an unterminated quote is a problem', () {
      final ok = _stdio(args: '-m "codelab agent" --x');
      final profile = (ok.toProfile(const []) as DraftAccepted).profile;
      expect((profile as StdioProfile).args, ['-m', 'codelab agent', '--x']);

      final bad = _stdio(args: '-m "codelab');
      expect(_codes(bad.validate(const [])), {
        ProfileDraftIssueCode.argsInvalid,
      });
      expect(bad.toProfile(const []), isA<DraftRejected>());
    });

    test('an empty command is a problem', () {
      expect(_codes(_stdio(command: ' ').validate(const [])), {
        ProfileDraftIssueCode.commandEmpty,
      });
    });

    test('a secret-like env key is rejected without leaking the value', () {
      final draft = _stdio(env: 'GITHUB_TOKEN=ghp_x\nLOG_LEVEL=debug');

      final issues = draft.validate(const []);
      expect(issues, hasLength(1));
      expect(issues.single.code, ProfileDraftIssueCode.envSecretLike);
      expect(issues.single.message, contains('GITHUB_TOKEN'));
      expect(issues.single.message, isNot(contains('ghp_x')));
      final result = draft.toProfile(const []);
      expect(result, isA<DraftRejected>());
    });

    test(
      'secret-like keys: KEY, TOKEN, SECRET, *_KEY, *_SECRET, lowercase',
      () {
        for (final key in ['KEY', 'token', 'Secret', 'API_KEY', 'x_secret']) {
          expect(_codes(_stdio(env: '$key=v').validate(const [])), {
            ProfileDraftIssueCode.envSecretLike,
          }, reason: key);
        }
        expect(
          _stdio(env: 'KEYBOARD=us\nTOKENS=1').validate(const []),
          isEmpty,
        );
      },
    );

    test('a valid draft becomes a StdioProfile', () {
      final result = _stdio(env: 'LOG_LEVEL=debug').toProfile(const []);

      expect(
        (result as DraftAccepted).profile,
        const StdioProfile(
          id: 'dev',
          label: 'Dev',
          command: 'codelab-agent',
          args: ['serve', '--stdio'],
          env: {'LOG_LEVEL': 'debug'},
          runInProjectDirectory: true,
        ),
      );
    });
  });

  group('WebSocket', () {
    test('url needs ws/wss scheme and a host', () {
      for (final url in ['', 'http://x', 'ws://', 'devbox:7420', 'wss:///p']) {
        expect(_codes(_ws(url: url).validate(const [])), {
          ProfileDraftIssueCode.urlInvalid,
        }, reason: url);
      }
    });

    test('plaintext ws:// warns only for non-local hosts', () {
      bool warns(String url) => _ws(url: url)
          .validate(const [])
          .any((i) => i.code == ProfileDraftIssueCode.plaintextToRemote);

      expect(warns('ws://localhost:8765'), isFalse);
      expect(warns('ws://127.0.0.5:8765'), isFalse);
      expect(warns('ws://[::1]:8765'), isFalse);
      expect(warns('ws://10.0.0.5:8765'), isTrue);
      expect(warns('wss://devbox:7420'), isFalse);
    });

    test('a URL with userinfo is rejected without echoing the secret', () {
      const marker = 'sk-test-leak-0123456789';
      final draft = _ws(url: 'wss://user:$marker@devbox:7420');

      final issues = draft.validate(const []);
      final issue = issues.singleWhere(
        (i) => i.code == ProfileDraftIssueCode.urlUserInfo,
      );

      expect(issue.field, ProfileDraftField.url);
      expect(issue.isWarning, isFalse);
      expect(
        issue.message,
        'Remove the user name and password from the URL; '
        'use the Token setting instead.',
      );
      expect(issue.message, isNot(contains(marker)));
      expect(issue.toString(), isNot(contains(marker)));
      final result = draft.toProfile(const []);
      expect(result, isA<DraftRejected>());
      expect(result.toString(), isNot(contains(marker)));
    });

    test('plaintext warning does not block toProfile', () {
      final result = _ws(url: 'ws://10.0.0.5:8765').toProfile(const []);

      expect(result, isA<DraftAccepted>());
      expect(
        (result as DraftAccepted).warnings.single.code,
        ProfileDraftIssueCode.plaintextToRemote,
      );
      expect(result.warnings.single.isWarning, isTrue);
    });

    test('EnvToken writes env:<NAME>, a bad name is a problem', () {
      final ok = _ws(token: const EnvToken('DEVBOX_TOKEN')).toProfile(const []);
      expect(
        (ok as DraftAccepted).profile,
        WebSocketProfile(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420'),
          tokenRef: 'env:DEVBOX_TOKEN',
        ),
      );

      final bad = _ws(token: const EnvToken('1BAD'));
      expect(_codes(bad.validate(const [])), {
        ProfileDraftIssueCode.tokenEnvNameInvalid,
      });
      expect(bad.toProfile(const []), isA<DraftRejected>());
    });

    test('NoToken gives no tokenRef, KeepTokenRef keeps the reference', () {
      final none = (_ws().toProfile(const []) as DraftAccepted).profile;
      expect((none as WebSocketProfile).tokenRef, isNull);

      final kept = _ws(
        token: const KeepTokenRef('codelab/profiles/x/token'),
      ).toProfile(const []);
      expect(
        ((kept as DraftAccepted).profile as WebSocketProfile).tokenRef,
        'codelab/profiles/x/token',
      );
    });

    test('KeepTokenRef toString does not print the reference', () {
      expect(
        const KeepTokenRef('sk-test-leak-0123456789').toString(),
        isNot(contains('sk-test-leak')),
      );
    });
  });

  group('toProfile enforces the rules itself', () {
    test('a reserved id never becomes a profile', () {
      expect(_stdio(id: 'default').toProfile(const []), isA<DraftRejected>());
      expect(_stdio(id: 'embedded').toProfile(const []), isA<DraftRejected>());
    });
  });

  group('profileKindsFor', () {
    test('without a stdio factory only WebSocket is offered', () {
      final kinds = profileKindsFor([
        ConfigTransportResolver(webSocket: (config) => FakeAcpTransport()),
      ]);

      expect(kinds, [ProfileKind.webSocket]);
    });

    test('both factories offer both kinds; no resolvers offer none', () {
      final both = profileKindsFor([
        ConfigTransportResolver(
          stdio: (config) => FakeAcpTransport(),
          webSocket: (config) => FakeAcpTransport(),
        ),
      ]);

      expect(both, [ProfileKind.stdio, ProfileKind.webSocket]);
      expect(profileKindsFor(const []), isEmpty);
    });
  });
}
