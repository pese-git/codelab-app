// Красные тесты задачи 4.1 change `add-desktop-localization`: подпись профиля
// встроенного агента в шапке рабочего места (design.md D6, «Подпись профиля
// встроенного агента (`EmbeddedProfile.label`) переводится в итерации 4»;
// spec app-settings «Локализация интерфейса app»; глоссарий §3: «embedded
// agent — встроенный агент»).
//
// Почему отдельный тест. В итерации 3 переведена только подпись типа
// соединения (`WindowConnectionState.transportLabel`, `workbenchTransportEmbedded`).
// Подпись самого профиля — `embeddedConnectionProfile.label` — оставалась
// английской `Embedded agent`: она попадает в подсказку бейджа соединения
// (`connectionTooltipOf`), в текст «Starting <profile>…» стартового экрана и в
// `CodeLabShellState.profileLabel`. Производный текст пересобирается при смене
// языка (D5): профиль и его `id` не меняются, меняется только подпись.
//
// Заглушка задачи 4.1: подпись не переводится, поэтому проверки на `ru`
// красные на `expect`, а проверки «на en прежняя подпись» и «профиль не
// меняется» зелёные.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart'
    show connectionTooltipOf;
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';

final class _NoPicker implements ProjectFolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory}) async => null;
}

final class _NoRecentProjects implements RecentProjectsStore {
  @override
  Future<List<RecentProject>> load() async => const [];

  @override
  Future<void> record(String path) async {}
}

/// Части рабочего места на управляемом порте языка; агент не подключён:
/// подпись берётся у выбранного профиля.
CodeLabShellParts _parts(TestAppStrings strings) {
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
    recentProjectsStore: _NoRecentProjects(),
    directoryExists: (_) async => true,
    strings: strings,
  );
  addTearDown(() async {
    await parts.close();
    await workspace.dispose();
    await application.dispose();
  });
  return parts;
}

void main() {
  late TestAppStrings strings;

  setUp(() {
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  test('на en подпись профиля встроенного агента прежняя', () {
    final parts = _parts(strings);

    expect(parts.connection.state.selectedProfileLabel, 'Embedded agent');
    expect(parts.connection.state.transportLabel, 'Embedded agent');
  });

  test('на ru подпись профиля и подсказка бейджа называют встроенного '
      'агента по-русски', () {
    strings = TestAppStrings(AppLocalizationsRu());
    final parts = _parts(strings);
    final state = parts.connection.state;

    expect(state.selectedProfileLabel, 'Встроенный агент');
    expect(
      connectionTooltipOf(
        profileLabel: state.selectedProfileLabel,
        transportLabel: state.transportLabel,
        connectionDetail: state.selectedConnectionDetail,
      ),
      // Деталь — пакет и профиль хоста, это идентификаторы (D7).
      'Встроенный агент · Встроенный агент · '
      'codelab_embedded (embedded-app-desktop)',
    );
  });

  test(
    'смена языка пересобирает подпись, профиль и его id не меняются',
    () async {
      final parts = _parts(strings);
      final profile = parts.connection.state.profile;
      expect(parts.connection.state.selectedProfileLabel, 'Embedded agent');

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(parts.connection.state.selectedProfileLabel, 'Встроенный агент');
      expect(parts.connection.state.profile, profile);
      expect(parts.connection.state.profile.id, embeddedProfileId);

      strings.emit(AppLocalizationsEn());
      await pumpEventQueue();
      expect(parts.connection.state.selectedProfileLabel, 'Embedded agent');
    },
  );

  test('профиль пользователя переводить нельзя: подпись `Dev` одинакова на '
      'обоих языках', () async {
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: const [],
    );
    const dev = ConnectionProfile.stdio(
      id: 'dev',
      label: 'Dev',
      command: 'codelab-agent',
    );
    final parts = CodeLabShellParts.build(
      initialProfile: dev,
      application: application,
      workspace: workspace,
      projectFolderPicker: _NoPicker(),
      usageCsvSaver: FakeUsageCsvSaver(),
      recentProjectsStore: _NoRecentProjects(),
      directoryExists: (_) async => true,
      strings: strings,
    );
    addTearDown(() async {
      await parts.close();
      await workspace.dispose();
      await application.dispose();
    });
    expect(parts.connection.state.selectedProfileLabel, 'Dev');

    strings.emit(AppLocalizationsRu());
    await pumpEventQueue();

    expect(parts.connection.state.selectedProfileLabel, 'Dev');
  });
}
