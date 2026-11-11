// `sessionFolderIsLocal` (задача 2.8 change `add-file-preview-and-tree`; spec
// workspace-file-browser «Панель Files в доке инструментов» — «Нет панели для
// WebSocket-агента»; design.md D7, D9): один предикат «папка сессии на этой
// машине», которым пользуются Files и (позже) терминал.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/session_folder_is_local.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the embedded agent works in a local folder', () {
    const profile = ConnectionProfile.embedded(
      id: 'embedded',
      label: 'Embedded agent',
      hostProfile: 'embedded-app-desktop',
    );

    expect(sessionFolderIsLocal(profile), isTrue);
  });

  test('a stdio agent sees the folder of this machine', () {
    const profile = ConnectionProfile.stdio(
      id: 'dev',
      label: 'Dev',
      command: 'codelab-agent',
      args: ['serve', '--stdio'],
    );

    expect(sessionFolderIsLocal(profile), isTrue);
  });

  test('a WebSocket agent works in a folder we cannot see', () {
    final profile = ConnectionProfile.webSocket(
      id: 'remote',
      label: 'Remote',
      uri: Uri.parse('wss://devbox:7420/acp'),
    );

    expect(sessionFolderIsLocal(profile), isFalse);
  });
}
