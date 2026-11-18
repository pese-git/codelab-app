import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/language/app_language_start.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/io.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';

import 'support/test_app_scope.dart';

void main() {
  tearDown(StructlogConfiguration.reset);

  // Задача 1.6 change `add-desktop-localization` (D13): события о языке пишет
  // composition root после настройки журнала, а не `main` до неё, иначе в
  // release они терялись бы.
  group('диагностика чтения языка (D13)', () {
    List<Map<String, Object?>> languageEvents(CodeLabTestBinding binding) => [
      for (final entry in binding.scope.resolve<LogBuffer>().entries.value)
        if ('${entry['event']}'.startsWith('app.')) entry,
    ];

    test(
      'fr в хранилище даёт app.language_preference_invalid в LogBuffer',
      () async {
        SharedPreferences.setMockInitialValues({kAppLanguageKey: 'fr'});
        final load = await const SharedPreferencesAppLanguagePreferences()
            .load();
        final binding = CodeLabTestBinding(
          languageStart: AppLanguageStart.fromLoad(load, const []),
        );
        addTearDown(binding.scope.dispose);

        final invalid = languageEvents(
          binding,
        ).singleWhere((e) => e['event'] == 'app.language_preference_invalid');
        expect(invalid['level'], 'warning');
        expect(invalid['component'], 'app');
        expect('$invalid', isNot(contains('fr')));
      },
    );

    test('сбой чтения хранилища: app стартует как при System, warning без '
        'текста ошибки', () async {
      final load = await SharedPreferencesAppLanguagePreferences(
        open: () => Future.error(const FormatException('/secret/path')),
      ).load();
      final binding = CodeLabTestBinding(
        languageStart: AppLanguageStart.fromLoad(load, const [Locale('ru')]),
      );
      addTearDown(binding.scope.dispose);

      final cubit = binding.scope.resolve<AppLanguageCubit>();
      expect(cubit.state.preference, AppLanguagePreference.system);
      expect(cubit.state.locale, const Locale('en'));
      final failed = languageEvents(
        binding,
      ).singleWhere((e) => e['event'] == 'app.language_preference_read_failed');
      expect(failed['level'], 'warning');
      expect(failed['error_class'], 'FormatException');
      expect('$failed', isNot(contains('secret')));
    });

    test('допустимое значение предупреждений не даёт', () {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);

      expect(languageEvents(binding).map((e) => e['event']), [
        'app.locale_resolved',
      ]);
    });
  });

  test(
    'LogBuffer resolves from the root scope and captures application-level '
    'events (replace-debug-log-panel-with-fluent/design.md, Decision 3)',
    () async {
      final binding = CodeLabTestBinding();
      addTearDown(binding.scope.dispose);

      final buffer = binding.scope.resolve<LogBuffer>();
      // При сборке scope пишутся запись о языке интерфейса (change
      // `add-desktop-localization`, D13) и о бэкенде хранилища секретов
      // (change `add-provider-setup-ui`, D18); событий соединения ещё нет.
      expect(
        [for (final entry in buffer.entries.value) entry['event']],
        ['app.locale_resolved', 'secrets.client.backend'],
      );

      binding.transport.emitDiagnostic(
        message: 'stderr line',
        source: 'stderr',
      );

      expect(buffer.entries.value, isNotEmpty);
      expect(
        buffer.entries.value.every((e) => e['category'] == 'application'),
        isTrue,
      );
    },
  );

  test('CodeLabLoggingLifecycle.dispose() awaits pending writes on both sinks '
      '(design.md Decision 8 — graceful shutdown)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'codelab-logging-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final applicationOutput = AsyncFileOutput(
      '${tempDir.path}/application.log',
    );
    final protocolTraceOutput = AsyncRotatingFileOutput(
      '${tempDir.path}/protocol.log',
    );
    final lifecycle = CodeLabLoggingLifecycle(
      applicationOutput: applicationOutput,
      protocolTraceOutput: protocolTraceOutput,
    );

    applicationOutput({'event': 'queued'}, LogLevel.info);
    protocolTraceOutput({'event': 'queued'}, LogLevel.trace);

    await lifecycle.dispose();

    expect(File('${tempDir.path}/application.log').existsSync(), isTrue);
    expect(File('${tempDir.path}/protocol.log').existsSync(), isTrue);
  });

  test('CodeLabLoggingLifecycle.dispose() works when the application sink is '
      'console-only (debug build, no AsyncFileOutput)', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'codelab-logging-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final protocolTraceOutput = AsyncRotatingFileOutput(
      '${tempDir.path}/protocol.log',
    );
    final lifecycle = CodeLabLoggingLifecycle(
      applicationOutput: null,
      protocolTraceOutput: protocolTraceOutput,
    );

    await expectLater(lifecycle.dispose(), completes);
  });

  test('CodeLabLoggingLifecycle.dispose() also closes the local-dev-only '
      'RemoteSyncLogOutput when one was configured', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'codelab-logging-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final protocolTraceOutput = AsyncRotatingFileOutput(
      '${tempDir.path}/protocol.log',
    );
    var delivered = <Map<String, dynamic>>[];
    final httpOutput = RemoteSyncLogOutput(
      serverUrl: 'http://localhost:0',
      projectSecretKey: 'test-key',
      sender: (entries) async {
        delivered = entries;
        return const BatchResult.delivered();
      },
    );
    final lifecycle = CodeLabLoggingLifecycle(
      applicationOutput: null,
      protocolTraceOutput: protocolTraceOutput,
      httpOutput: httpOutput,
    );

    httpOutput({'event': 'queued'}, LogLevel.info);
    await lifecycle.dispose();

    expect(delivered, isNotEmpty);
  });
}
