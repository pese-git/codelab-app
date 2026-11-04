// Аргументы stdio-профиля со словами с пробелом (tasks 2.2 change
// `add-codelab-cli`; spec acp-client-kit «Профили и резолверы транспорта»;
// design.md, D14; задача 2.4 change `add-app-settings-shell`).
//
// Разбор строки аргументов с кавычками теперь делает `ProfileDraft` диалога
// «Add connection profile» (задача 3.1: «незакрытая кавычка»): профиль уже
// хранит список слов. Здесь остаётся исход «слово с пробелом доходит до
// процесса одним аргументом».

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_cubit_characterization/harness.dart';

void main() {
  setUp(setUpCharacterization);

  test(
    'a stdio argument with a space reaches the transport as one word',
    () async {
      final configs = <StdioAcpTransportConfig>[];
      final h = ShellHarness(
        stdioTransportFactory: (config) {
          configs.add(config);
          return FakeAcpTransport();
        },
      );

      await h.cubit.connect(
        const ConnectionProfile.stdio(
          id: 'quoted',
          label: 'Quoted',
          command: 'codelab',
          args: ['serve', '--name', 'codelab agent'],
        ),
      );
      await h.settle();

      expect(h.cubit.state.connectionStatus, CodeLabConnectionStatus.connected);
      expect(configs.single.args, ['serve', '--name', 'codelab agent']);
    },
  );
}
