// Аргументы stdio-профиля с кавычками (tasks 2.2 change `add-codelab-cli`;
// spec acp-client-kit «Профили и резолверы транспорта»; design.md, D14).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_cubit_characterization/harness.dart';

void main() {
  setUp(setUpCharacterization);

  test('an unterminated quote in the stdio arguments fails the connection '
      'with a reason and opens no transport', () async {
    final h = ShellHarness();

    h.cubit.updateStdioArgs('serve "--stdio');
    await h.cubit.connect();

    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
    expect(h.stdioStarts, 0);
    expect(
      h.logEvents,
      contains(
        'Stdio arguments are invalid before connecting: '
        'Unterminated double quote.',
      ),
    );
  });

  test('quoted stdio arguments connect', () async {
    final h = ShellHarness();

    h.cubit.updateStdioArgs('serve --name "codelab agent"');
    await h.connect();
    await h.settle();

    expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
    expect(h.stdioStarts, 1);
  });
}
