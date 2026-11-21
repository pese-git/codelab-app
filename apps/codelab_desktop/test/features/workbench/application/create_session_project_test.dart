// «New session» без проекта (задача A1.4 change `require-project-folder`;
// spec agent-workbench-ui «New session без проекта открывает выбор папки»;
// design.md D5).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

final class _RecordingPicker implements ProjectFolderPicker {
  _RecordingPicker(this.answer);

  final String? answer;
  var picks = 0;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async {
    picks++;
    return answer;
  }
}

/// Выбор папки, который завершает тест: пока [complete] не вызван, диалог
/// «открыт».
final class _GatedPicker implements ProjectFolderPicker {
  var picks = 0;
  Completer<String?>? _open;

  @override
  Future<String?> pickFolder({String? initialDirectory}) {
    picks++;
    return (_open = Completer<String?>()).future;
  }

  void complete(String? path) => _open!.complete(path);
}

void main() {
  test('without a project New session opens the folder picker, creates no '
      'session and sends nothing to the agent', () async {
    final picker = _RecordingPicker('/work/app');
    final started = <StdioAcpTransportConfig>[];
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      projectFolderPicker: picker,
      stdioTransportFactory: (config) {
        started.add(config);
        return agent;
      },
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.createSession();

    await pumpEventQueue();

    expect(picker.picks, 1);
    // Выбранная папка — триггер старта агента (D13), но сессии нет: её
    // создаёт повторное «New session».
    expect(started.single.cwd, '/work/app');
    expect(
      agent.sentMessages.whereType<JsonRpcRequest>().map((r) => r.method),
      isNot(contains(sessionNewMethod)),
    );
    expect(cubit.state.selectedProjectPath, '/work/app');
    expect(cubit.state.sessions, isEmpty);
    // Проект проверяется раньше соединения: подсказка «Connect an ACP agent»
    // здесь неуместна — пользователю нужна папка.
    final entries = binding.scope.resolve<LogBuffer>().entries.value.where(
      (entry) =>
          entry['event'] ==
          'Open a project to start a session: '
              'choose a folder.',
    );
    expect(entries, hasLength(1));
    expect(entries.single['source'], 'session');
    expect(entries.single['level'], 'info');
    final events = binding.scope.resolve<LogBuffer>().entries.value.map(
      (entry) => entry['event'],
    );
    expect(
      events,
      isNot(contains('Connect an ACP agent before creating a session.')),
    );
  });

  test('a closed picker changes nothing', () async {
    final picker = _RecordingPicker(null);
    final binding = CodeLabTestBinding(projectFolderPicker: picker);
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    await cubit.createSession();

    expect(picker.picks, 1);
    expect(cubit.state.selectedProjectPath, isNull);
    expect(cubit.state.sessions, isEmpty);
  });

  // Задача 3.5 change `add-empty-project-screen` (spec «Второй запрос при
  // открытом диалоге»; design.md D7): с Ctrl+O появился третий путь к выбору
  // папки, и повторный запрос при открытом системном диалоге не должен
  // открывать второй диалог.
  test('while the folder dialog is open, a second request and New session do '
      'not open another dialog; all see the chosen project', () async {
    final picker = _GatedPicker();
    final binding = CodeLabTestBinding(projectFolderPicker: picker);
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    final first = cubit.browseForProject();
    final second = cubit.browseForProject();
    final third = cubit.createSession();
    await pumpEventQueue();
    expect(picker.picks, 1);

    picker.complete('/work/app');
    await Future.wait([first, second, third]);

    expect(picker.picks, 1);
    expect(cubit.state.selectedProjectPath, '/work/app');
  });

  test('after the dialog is closed without a choice, the next request opens '
      'a new dialog', () async {
    final picker = _GatedPicker();
    final binding = CodeLabTestBinding(projectFolderPicker: picker);
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;

    final first = cubit.browseForProject();
    await pumpEventQueue();
    picker.complete(null);
    await first;
    final second = cubit.browseForProject();
    await pumpEventQueue();

    expect(picker.picks, 2);
    picker.complete(null);
    await second;
  });
}
