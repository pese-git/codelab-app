// `NavigationCubit` (задача 1.1 change `add-app-settings-shell`; spec
// app-settings «Переход в настройки и обратно»; design.md D1, D2, D17).
//
// Тесты идут на фейке порта `SettingsPageStore`: проверяются выбор страницы,
// возврат и поведение при сбое хранилища, а не `shared_preferences`.

import 'dart:async';

import 'package:codelab_desktop/app/navigation/app_destination.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/app/navigation/settings_page_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_logger.dart';

/// Хранилище, чьё чтение ждёт [complete]: моделирует `last_page` в полёте.
final class _GatedStore implements SettingsPageStore {
  final _gate = Completer<String?>();

  void complete(String? value) => _gate.complete(value);

  @override
  Future<String?> load() => _gate.future;

  @override
  Future<void> save(String page) async {}
}

/// Фейк порта: хранит строку в памяти, сбои включаются флагами.
final class _FakeStore implements SettingsPageStore {
  String? saved;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<String?> load() async {
    if (failLoad) {
      throw StateError('load failed: secret-looking-detail');
    }
    return saved;
  }

  @override
  Future<void> save(String page) async {
    if (failSave) {
      throw StateError('save failed: secret-looking-detail');
    }
    saved = page;
  }
}

void main() {
  const pages = SettingsPages(
    available: {
      SettingsPage.connection,
      SettingsPage.general,
      SettingsPage.keyboard,
    },
  );

  late _FakeStore store;
  late RecordingLogger logger;
  String? activeSession;

  final selected = <String>[];
  var openSessions = <String>{'B', 'C'};

  NavigationCubit build({
    SettingsPages? withPages,
    SettingsPageStore? withStore,
  }) => NavigationCubit(
    store: withStore ?? store,
    pages: withPages ?? pages,
    activeSessionId: () => activeSession,
    selectSessionIfOpen: (id) {
      if (!openSessions.contains(id)) {
        return false;
      }
      selected.add(id);
      return true;
    },
    logger: logger,
  );

  /// Открытие настроек с обязательным источником (D2, D17).
  Future<void> open(NavigationCubit cubit, [SettingsPage? page]) =>
      cubit.openSettings(page: page, source: SettingsOpenSource.sidebar);

  setUp(() {
    store = _FakeStore();
    logger = RecordingLogger();
    activeSession = 'B';
    selected.clear();
    openSessions = {'B', 'C'};
  });

  test('starts on the workbench', () {
    expect(build().state, const WorkbenchDestination());
  });

  test('openSettings without a saved page opens Connection and remembers '
      'the active session', () async {
    final cubit = build();

    await open(cubit);

    expect(
      cubit.state,
      const SettingsDestination(SettingsPage.connection, returnTo: 'B'),
    );
    await cubit.close();
  });

  test('openSettings opens the saved visible page', () async {
    store.saved = 'general';
    final cubit = build();

    await open(cubit);

    expect(cubit.state, isA<SettingsDestination>());
    expect((cubit.state as SettingsDestination).page, SettingsPage.general);
    await cubit.close();
  });

  test('a saved page that is hidden in this build opens Connection', () async {
    store.saved = 'providers';
    final cubit = build();

    await open(cubit);

    expect((cubit.state as SettingsDestination).page, SettingsPage.connection);
    await cubit.close();
  });

  test('an unknown saved value opens Connection', () async {
    store.saved = 'no-such-page';
    final cubit = build();

    await open(cubit);

    expect((cubit.state as SettingsDestination).page, SettingsPage.connection);
    await cubit.close();
  });

  test('openSettings with an explicit page opens it and saves it', () async {
    final cubit = build();

    await open(cubit, SettingsPage.keyboard);

    expect((cubit.state as SettingsDestination).page, SettingsPage.keyboard);
    expect(store.saved, 'keyboard');
    await cubit.close();
  });

  test('selectSettingsPage switches the page, keeps returnTo and saves the '
      'choice', () async {
    final cubit = build();
    await open(cubit);

    await cubit.selectSettingsPage(SettingsPage.general);

    expect(
      cubit.state,
      const SettingsDestination(SettingsPage.general, returnTo: 'B'),
    );
    expect(store.saved, 'general');
    await cubit.close();
  });

  test('selectSettingsPage ignores a hidden page', () async {
    final cubit = build();
    await open(cubit);

    await cubit.selectSettingsPage(SettingsPage.providers);

    expect((cubit.state as SettingsDestination).page, SettingsPage.connection);
    expect(store.saved, isNull);
    await cubit.close();
  });

  test('back returns to the workbench', () async {
    final cubit = build();
    await open(cubit);

    cubit.back();

    expect(cubit.state, const WorkbenchDestination());
    await cubit.close();
  });

  test(
    'back and openSettings on the destination already shown do nothing',
    () async {
      final cubit = build();
      cubit.back();
      expect(cubit.state, const WorkbenchDestination());

      await open(cubit, SettingsPage.general);
      activeSession = 'C';
      await open(cubit, SettingsPage.keyboard);

      // Повторный Cmd/Ctrl+, на экране настроек ничего не делает (D2).
      expect(
        cubit.state,
        const SettingsDestination(SettingsPage.general, returnTo: 'B'),
      );
      await cubit.close();
    },
  );

  test('a store read failure logs a warning without the error text and '
      'opens Connection', () async {
    store.failLoad = true;
    final cubit = build();

    await open(cubit);

    expect((cubit.state as SettingsDestination).page, SettingsPage.connection);
    final warning = logger.entries.singleWhere((e) => e['level'] == 'warning');
    expect(warning['event'], 'settings.last_page_load_failed');
    expect(warning['error_type'], 'StateError');
    expect(warning.toString(), isNot(contains('secret-looking-detail')));
    await cubit.close();
  });

  test(
    'a store write failure logs a warning and keeps the page switched',
    () async {
      store.failSave = true;
      final cubit = build();
      await open(cubit);

      await cubit.selectSettingsPage(SettingsPage.general);

      expect((cubit.state as SettingsDestination).page, SettingsPage.general);
      final warning = logger.entries.singleWhere(
        (e) => e['level'] == 'warning',
      );
      expect(warning['event'], 'settings.last_page_save_failed');
      expect(warning['error_type'], 'StateError');
      await cubit.close();
    },
  );

  test('logs settings.opened with page and source, then page_selected and '
      'closed', () async {
    final cubit = build();

    await cubit.openSettings(source: SettingsOpenSource.shortcut);
    await cubit.selectSettingsPage(SettingsPage.general);
    cubit.back();

    final events = [for (final e in logger.entries) e['event']];
    expect(events, [
      'settings.opened',
      'settings.page_selected',
      'settings.closed',
    ]);
    expect(logger.entries[0]['page'], 'connection');
    expect(logger.entries[0]['source'], 'shortcut');
    expect(logger.entries[1]['page'], 'general');
    expect(logger.entries[2]['page'], 'general');
    await cubit.close();
  });

  test('back selects the session returnTo when it is still open', () async {
    final cubit = build();
    await open(cubit);
    activeSession = 'C';

    cubit.back();

    expect(selected, ['B']);
    expect(cubit.state, const WorkbenchDestination());
    await cubit.close();
  });

  test('back leaves the current session when returnTo is closed', () async {
    openSessions = {'C'};
    final cubit = build();
    await open(cubit);

    cubit.back();

    expect(selected, isEmpty);
    expect(cubit.state, const WorkbenchDestination());
    await cubit.close();
  });

  test('back(toSession) activates the session with the approval request and '
      'logs back_to_approval without ids', () async {
    final cubit = build();
    await open(cubit);

    cubit.back(toSession: 'C');

    expect(selected, ['C']);
    expect(cubit.state, const WorkbenchDestination());
    final entry = logger.entries.singleWhere(
      (e) => e['event'] == 'settings.back_to_approval',
    );
    expect(entry['level'], 'info');
    expect(entry.keys, unorderedEquals(['event', 'level']));
    await cubit.close();
  });

  test('openSettings while settings are open keeps returnTo', () async {
    final cubit = build();
    await open(cubit);
    activeSession = 'C';

    await open(cubit);

    expect((cubit.state as SettingsDestination).returnTo, 'B');
    await cubit.close();
  });

  test('an unknown saved slug behaves like no saved value; the enum name '
      'is not a slug', () async {
    store.saved = 'mcpServers';
    final cubit = build(
      withPages: const SettingsPages(
        available: {SettingsPage.connection, SettingsPage.mcpServers},
      ),
    );

    await open(cubit);

    expect((cubit.state as SettingsDestination).page, SettingsPage.connection);
    await cubit.close();
  });

  test('back without a remembered session selects nothing', () async {
    activeSession = null;
    final cubit = build();
    await open(cubit);

    cubit.back();

    expect(selected, isEmpty);
    await cubit.close();
  });

  test('two openSettings calls without a page while the read is pending '
      'give one screen and one settings.opened', () async {
    final gate = _GatedStore();
    final cubit = build(withStore: gate);
    final states = <AppDestination>[];
    final sub = cubit.stream.listen(states.add);

    final first = open(cubit);
    final second = open(cubit);
    gate.complete('general');
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);

    expect(states, hasLength(1));
    expect(
      logger.entries.where((e) => e['event'] == 'settings.opened'),
      hasLength(1),
    );
    await sub.cancel();
    await cubit.close();
  });

  test('an explicit page overrides a last_page read still in flight', () async {
    final gate = _GatedStore();
    final cubit = build(withStore: gate);

    final pending = open(cubit);
    await open(cubit, SettingsPage.keyboard);
    gate.complete('general');
    await pending;

    expect((cubit.state as SettingsDestination).page, SettingsPage.keyboard);
    expect(
      logger.entries.where((e) => e['event'] == 'settings.opened'),
      hasLength(1),
    );
    await cubit.close();
  });

  test('opens the first visible page when Connection is not visible', () async {
    final cubit = build(
      withPages: const SettingsPages(
        available: {SettingsPage.keyboard, SettingsPage.general},
      ),
    );

    await open(cubit);

    expect((cubit.state as SettingsDestination).page, SettingsPage.general);
    await cubit.close();
  });

  test(
    'with no visible pages openSettings does nothing and logs at debug',
    () async {
      final cubit = build(withPages: const SettingsPages(available: {}));

      await open(cubit);

      expect(cubit.state, const WorkbenchDestination());
      final entry = logger.entries.single;
      expect(entry['level'], 'debug');
      expect(entry['event'], 'settings.open_skipped');
      await cubit.close();
    },
  );

  test('selectSettingsPage on the page already shown does nothing', () async {
    final cubit = build();
    await open(cubit);
    logger.entries.clear();

    await cubit.selectSettingsPage(SettingsPage.connection);

    expect(store.saved, isNull);
    expect(logger.entries, isEmpty);
    await cubit.close();
  });

  test('pendingApprovalShown logs the session count without ids', () async {
    final cubit = build();

    cubit.pendingApprovalShown(sessions: 2);

    final entry = logger.entries.single;
    expect(entry['level'], 'info');
    expect(entry['event'], 'settings.pending_approval_shown');
    expect(entry['sessions'], 2);
    expect(entry.keys, unorderedEquals(['event', 'level', 'sessions']));
    await cubit.close();
  });

  group('SharedPreferencesSettingsPageStore', () {
    test('save writes codelab.settings.last_page', () async {
      SharedPreferences.setMockInitialValues({});
      await const SharedPreferencesSettingsPageStore().save('mcp-servers');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('codelab.settings.last_page'), 'mcp-servers');
    });

    test('load reads the initial value and null when absent', () async {
      SharedPreferences.setMockInitialValues({
        'codelab.settings.last_page': 'general',
      });
      expect(
        await const SharedPreferencesSettingsPageStore().load(),
        'general',
      );

      SharedPreferences.setMockInitialValues({});
      expect(await const SharedPreferencesSettingsPageStore().load(), isNull);
    });
  });

  group('SettingsPages', () {
    test('lists visible pages in the fixed section order whatever the '
        'registration order', () {
      const registered = SettingsPages(
        available: {
          SettingsPage.keyboard,
          SettingsPage.connection,
          SettingsPage.general,
        },
      );

      expect(registered.visible, [
        SettingsPage.connection,
        SettingsPage.general,
        SettingsPage.keyboard,
      ]);
    });

    test('keys are kebab-case', () {
      expect(SettingsPage.connection.navKey, 'settings-nav-connection');
      expect(SettingsPage.mcpServers.navKey, 'settings-nav-mcp-servers');
      expect(
        SettingsPage.skillsAndExtensions.navKey,
        'settings-nav-skills-and-extensions',
      );
    });

    test('has the eleven pages of section 12.4.9 in two groups', () {
      expect(SettingsPage.values, hasLength(11));
      expect(
        SettingsPage.values.where((p) => p.group == SettingsGroup.agent),
        hasLength(8),
      );
      expect(
        SettingsPage.values.where((p) => p.group == SettingsGroup.app),
        hasLength(3),
      );
    });
  });
}
