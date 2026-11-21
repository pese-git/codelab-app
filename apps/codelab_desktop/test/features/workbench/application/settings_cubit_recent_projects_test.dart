// Тест задачи 2.4 change `share-recent-projects-store`: нечитаемый файл
// недавних проектов не мешает выбору проекта и не перезаписывается
// (spec agent-workbench-ui, сценарий «An unreadable recents file is kept» —
// часть app без переноса; design.md D2).
//
// Настоящий `JsonFileRecentProjectsStore` на временном файле `{not json}`:
// файловый ввод-вывод идёт в обычном `test()` (в `testWidgets` он зависал бы
// в fake-async зоне). Части рабочего места собираются так же, как в
// `embedded_profile_label_l10n_test.dart`, поэтому тест не зависит от шва
// `createCodeLabRootScope(recentProjectsStore:)` (задача 2.2).
//
// Cubit уже ловит ошибки хранилища (`try/catch` в `selectProject` и
// `_loadRecentProjects`), поэтому тест может оказаться сразу зелёным: тогда
// он остаётся стражем, а задача 2.5 закрывается без кода.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileRecentProjectsStore;
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codelab_desktop/l10n/app_localizations_en.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/recording_logger.dart';

final class _NoPicker implements ProjectFolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory}) async => null;
}

void main() {
  test('an unreadable recents file: the project is selected, recents are '
      'empty, a warning is in diagnostics, the file bytes are kept', () async {
    final dir = await Directory.systemTemp.createTemp('codelab_recents_cubit_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/recent_projects.json');
    await file.writeAsString('{not json}');
    final bytesBefore = await file.readAsBytes();

    final logger = RecordingLogger();
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: const [],
    );
    final parts = CodeLabShellParts.build(
      initialProfile: embeddedConnectionProfile,
      application: application,
      workspace: workspace,
      projectFolderPicker: _NoPicker(),
      usageCsvSaver: FakeUsageCsvSaver(),
      recentProjectsStore: JsonFileRecentProjectsStore(file.path),
      directoryExists: (_) async => true,
      strings: TestAppStrings(AppLocalizationsEn()),
      logger: logger,
    );
    addTearDown(() async {
      await parts.close();
      await workspace.dispose();
      await application.dispose();
    });

    await parts.settings.selectProject('/work/app');

    expect(parts.settings.state.selectedProjectPath, '/work/app');
    expect(parts.settings.state.recentProjects, isEmpty);
    final warnings = [
      for (final e in logger.entries)
        if (e['level'] == 'warning') '${e['event']}',
    ];
    expect(
      warnings,
      contains(allOf(contains('recent project'), contains('FormatException'))),
    );
    expect(await file.readAsBytes(), bytesBefore);
  });
}
