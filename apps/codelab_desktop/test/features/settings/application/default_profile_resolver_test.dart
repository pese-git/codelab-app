// `DefaultProfileResolver`: события D17 (находка L4 ревью итерации 2,
// задача 2.16.8 change `add-app-settings-shell`).
//
// Резолвер не бросает исключений, но не должен и молчать: потеря выбора
// пользователя или нечитаемый файл попадают в журнал (AGENTS.md §16).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/default_profile_resolver.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/recording_logger.dart';

const _dev = ConnectionProfile.stdio(id: 'dev', label: 'Dev', command: 'x');

void main() {
  late RecordingLogger logger;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'codelab.connection.default_profile': 'gone',
    });
    logger = RecordingLogger();
  });

  DefaultProfileResolver build(InMemoryProfileStore store) =>
      DefaultProfileResolver(
        store: store,
        preferences: const SharedPreferencesConnectionPreferences(),
        logger: logger,
      );

  test('a saved id that disappeared is reset: info default_reset, the key '
      'is dropped, the embedded agent is chosen', () async {
    final resolved = await build(InMemoryProfileStore([_dev])).resolve();

    expect(resolved, embeddedConnectionProfile);
    final event = logger.entries.singleWhere(
      (e) => e['event'] == 'connection_profile.default_reset',
    );
    expect(event['level'], 'info');
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'codelab.connection.default_profile',
      ),
      isFalse,
    );
  });

  test('an unreadable file gives warning default_unresolved with the error '
      'type only, and the saved id is kept', () async {
    final store = InMemoryProfileStore([_dev])..failLoad = true;

    final resolved = await build(store).resolve();

    expect(resolved, embeddedConnectionProfile);
    final event = logger.entries.singleWhere(
      (e) => e['event'] == 'connection_profile.default_unresolved',
    );
    expect(event['level'], 'warning');
    expect(event['error_type'], 'FormatException');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'codelab.connection.default_profile',
      ),
      'gone',
    );
  });

  test('no events without a saved choice', () async {
    SharedPreferences.setMockInitialValues({});

    await build(InMemoryProfileStore([_dev])).resolve();

    expect(logger.entries, isEmpty);
  });
}
