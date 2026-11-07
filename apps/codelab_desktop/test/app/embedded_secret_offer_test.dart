// Предложение переноса секретов и порт переноса в composition root (задача
// 4.3 change `add-config-literal-secrets-and-migrate`; agent-workbench-ui
// «Перенос секретов встроенного агента», сценарии «Окружение движка
// совпадает с агентом» и «Ошибка без текста исключения»; design.md D8).
//
// Порт проверяется на настоящем `SecretMigrator` и временных файлах:
// `CODELAB_HOME` и `CODELAB_CONFIG` задаются явно, чтобы тест не коснулся
// настоящего `~/.codelab`.

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/embedded_secret_migration_runner.dart';
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/app/secret_migration_offer.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_runner.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentOpener, McpStatusPort;
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_logger.dart';
import '../support/test_app_scope.dart';

final class _FakeAgent implements EmbeddedAgent {
  // Статус MCP в этом тесте не нужен: фейк сессий не открывает.
  @override
  McpStatusPort? mcpStatus(String sessionId) => null;

  _FakeAgent({required this.secretsInConfig});

  @override
  final bool secretsInConfig;

  final _closed = Completer<void>();

  @override
  AcpTransport get clientTransport => FakeAcpTransport();

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> dispose() async {
    if (!_closed.isCompleted) _closed.complete();
  }
}

final _profile = ConnectionProfile.embedded(
  id: 'embedded',
  label: 'Embedded agent',
  hostProfile: 'embedded-app-desktop',
);

final class _ThrowingRunner implements SecretMigrationRunner {
  @override
  Future<SecretMigrationOutcome> plan(String cwd) =>
      Future.error(_Leaky('sk-test-leak-0123456789'));

  @override
  Future<SecretMigrationOutcome> apply(String cwd) =>
      Future.error(_Leaky('sk-test-leak-0123456789'));
}

final class _Leaky implements Exception {
  _Leaky(this.secret);
  final String secret;

  @override
  String toString() => 'yaml error near $secret';
}

void main() {
  group('SecretMigrationOffer и резолвер', () {
    test('признак агента передаётся в предложение после открытия', () async {
      final offer = SecretMigrationOffer();
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: true),
        offer: offer,
      );
      expect(offer.value, isFalse);

      await resolver.open(_profile, projectDirectory: '/work/app');

      expect(offer.value, isTrue);
      await resolver.close();
    });

    test(
      'watch: смена в момент получения первого события не теряется',
      () async {
        final offer = SecretMigrationOffer()..set('/a');
        final seen = <String?>[];
        final sub = offer.watch().listen((value) {
          seen.add(value);
          // Агент закрылся/сменился сразу после снимка текущего значения.
          if (seen.length == 1) offer.set('/b');
        });
        await pumpEventQueue();

        expect(seen.first, '/a');
        expect(seen.last, '/b');
        await sub.cancel();
      },
    );

    test('предложение несёт cwd, с которым открыт агент', () async {
      final offer = SecretMigrationOffer();
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: true),
        offer: offer,
      );

      await resolver.open(_profile, projectDirectory: '/work/agent');

      expect(offer.cwd, '/work/agent');
      await resolver.close();
    });

    test('агент без секретов в файле: предложения нет', () async {
      final offer = SecretMigrationOffer();
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: false),
        offer: offer,
      );

      await resolver.open(_profile, projectDirectory: '/work/app');

      expect(offer.value, isFalse);
      await resolver.close();
    });

    test('закрытие резолвера сбрасывает признак', () async {
      final offer = SecretMigrationOffer();
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: true),
        offer: offer,
      );
      await resolver.open(_profile, projectDirectory: '/work/app');

      await resolver.close();

      expect(offer.value, isFalse);
    });

    test('закрытие самого агента сбрасывает признак', () async {
      final offer = SecretMigrationOffer();
      final agent = _FakeAgent(secretsInConfig: true);
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async => agent,
        offer: offer,
      );
      await resolver.open(_profile, projectDirectory: '/work/app');

      await agent.dispose();
      await pumpEventQueue();

      expect(offer.value, isFalse);
      await resolver.close();
    });

    test('повторное открытие даёт цикл null -> cwd: предупреждение, '
        'закрытое крестиком, вернётся', () async {
      final offer = SecretMigrationOffer();
      final changes = <String?>[];
      offer.changes.listen(changes.add);
      final resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: true),
        offer: offer,
      );

      await resolver.open(_profile, projectDirectory: '/work/app');
      await resolver.open(_profile, projectDirectory: '/work/app');
      await pumpEventQueue();

      expect(changes, ['/work/app', null, '/work/app']);
      await resolver.close();
    });

    test('вытесненное открытие признак не выставляет', () async {
      final offer = SecretMigrationOffer();
      final gate = Completer<void>();
      var calls = 0;
      final resolver = EmbeddedTransportResolver(({
        required cwd,
        required hostProfile,
      }) async {
        if (++calls == 1) await gate.future;
        return _FakeAgent(secretsInConfig: calls == 1);
      }, offer: offer);

      final first = resolver.open(_profile, projectDirectory: '/work/app');
      final firstResult = first.then<Object?>((v) => v, onError: (e) => e);
      // Первое открытие должно дойти до открывателя и встать на воротах.
      await pumpEventQueue();
      final second = resolver.open(_profile, projectDirectory: '/work/app');
      gate.complete();
      expect(await firstResult, isA<EmbeddedOpenCancelledException>());
      await second;

      expect(offer.value, isFalse);
      await resolver.close();
    });
  });

  group('порт переноса (EmbeddedSecretMigrationRunner)', () {
    late Directory root;
    late String home;
    late String cwd;
    final sk = 'sk-${'a1b2c3d4e5' * 3}';

    setUp(() {
      root = Directory.systemTemp.createTempSync('embedded_secret_offer_test');
      home = '${root.path}/home';
      cwd = '${root.path}/proj';
      Directory(home).createSync();
      Directory(cwd).createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    String config({bool fileBackend = true, String? key}) =>
        '''
${fileBackend ? 'secrets:\n  backend: file\n' : ''}providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
${key == null ? '' : '    api_key: $key\n'}    models:
      m: {}
agent:
  default_model: lm/m
''';

    EmbeddedSecretMigrationRunner runner({
      Map<String, String> extra = const {},
      String platform = 'macos',
    }) => EmbeddedSecretMigrationRunner(
      environment: {'CODELAB_HOME': home, ...extra},
      platform: platform,
    );

    test(
      'план читает файлы по CODELAB_HOME, не меняет их и без значений',
      () async {
        File('$home/config.yaml').writeAsStringSync(config(key: sk));
        final before = File('$home/config.yaml').readAsStringSync();

        final outcome = await runner().plan(cwd);

        expect(outcome.problem, isNull);
        expect(outcome.canApply, isTrue);
        expect(outcome.items, hasLength(1));
        expect(outcome.items.single, contains('providers.lm.api_key'));
        expect(outcome.items.join(), isNot(contains(sk)));
        expect(File('$home/config.yaml').readAsStringSync(), before);
      },
    );

    test('перенос пишет в те же файлы и хранилище под CODELAB_HOME', () async {
      File('$home/config.yaml').writeAsStringSync(config(key: sk));

      final outcome = await runner().apply(cwd);

      expect(outcome.problem, isNull);
      final text = File('$home/config.yaml').readAsStringSync();
      expect(text, contains('api_key_secret'));
      expect(text, isNot(contains(sk)));
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
    });

    test('бэкенд env: только чтение, подсказка с <home>', () async {
      File(
        '$home/config.yaml',
      ).writeAsStringSync(config(fileBackend: false, key: sk));

      final outcome = await runner().plan(cwd);

      expect(outcome.readOnlyBackend, isTrue);
      expect(outcome.canApply, isFalse);
      expect(outcome.problem, isNull);
      expect(
        outcome.detail,
        'Secrets cannot be stored: the env backend is read-only. '
        'Add secrets.backend: file to $home/config.yaml, or set '
        'CODELAB_SECRET_* variables.',
      );
    });

    test(
      'Windows: подсказка без secrets.backend: file (ветка secret set)',
      () async {
        File(
          '$home/config.yaml',
        ).writeAsStringSync(config(fileBackend: false, key: sk));

        final outcome = await runner(platform: 'windows').plan(cwd);

        expect(outcome.readOnlyBackend, isTrue);
        expect(
          outcome.detail,
          'Secrets cannot be stored: the env backend is read-only. '
          'Set CODELAB_SECRET_* variables.',
        );
      },
    );

    test('находки только в CODELAB_CONFIG: переносить нечего', () async {
      File('$home/config.yaml').writeAsStringSync(config());
      final extra = '${root.path}/extra.yaml';
      File(extra).writeAsStringSync('providers:\n  lm:\n    api_key: $sk\n');

      final outcome = await runner(extra: {'CODELAB_CONFIG': extra}).plan(cwd);

      expect(outcome.onlyExtraLayerFindings, isTrue);
      expect(outcome.canApply, isFalse);
      expect(outcome.items.join(), isNot(contains(sk)));
      expect(File(extra).readAsStringSync(), contains(sk));
    });

    test('проблема загрузки конфига: problem без значений секретов', () async {
      File('$home/config.yaml').writeAsStringSync('providers: [unclosed');

      final outcome = await runner().plan(cwd);

      expect(outcome.problem, isNotNull);
      expect(outcome.canApply, isFalse);
    });
  });

  group('тексты ошибок и лог без toString() исключения', () {
    test(
      'planFailed и applyFailed показывают имя типа, лог — error_class',
      () async {
        final logger = RecordingLogger();
        final cubit = SecretMigrationCubit(
          runner: _ThrowingRunner(),
          turnActivity: const Stream<bool>.empty(),
          logger: logger,
        );
        addTearDown(cubit.close);
        cubit.setOffered('/work/app');

        cubit.openPlan();
        await pumpEventQueue();
        final planFailed = cubit.state as SecretMigrationPlanFailed;
        expect(planFailed.message, contains('_Leaky'));
        expect(planFailed.message, isNot(contains('sk-test-leak-0123456789')));

        cubit.closeDialog();
        // Перенос возможен только из применимого плана; для текста ошибки
        // переноса подставляем исправный план через второго исполнителя.
        final applying = SecretMigrationCubit(
          runner: _PlanOkApplyThrows(),
          turnActivity: const Stream<bool>.empty(),
          logger: logger,
        );
        addTearDown(applying.close);
        applying.setOffered('/work/app');
        applying.openPlan();
        await pumpEventQueue();
        applying.migrate();
        await pumpEventQueue();
        final applyFailed = applying.state as SecretMigrationApplyFailed;
        expect(applyFailed.message, contains('_Leaky'));
        expect(applyFailed.message, isNot(contains('sk-test-leak-0123456789')));

        final failures = logger.entries.where((e) => e['level'] == 'warning');
        expect(failures, hasLength(2));
        expect(failures.map((e) => e['error_class']), everyElement('_Leaky'));
        expect(logger.entries.toString(), isNot(contains('sk-test-leak')));
      },
    );
  });

  group('composition root', () {
    testWidgets('порт и открыватель берут одни CODELAB_HOME и CODELAB_CONFIG '
        'из environment корневого scope', (tester) async {
      final root = Directory.systemTemp.createTempSync('embedded_secret_scope');
      addTearDown(() => root.deleteSync(recursive: true));
      final home = '${root.path}/home';
      final project = '${root.path}/proj';
      Directory(home).createSync();
      Directory(project).createSync();
      File('$home/config.yaml').writeAsStringSync(
        'secrets:\n  backend: file\nproviders:\n  lm:\n'
        '    kind: openai-compatible\n    base_url: https://llm.test/v1\n'
        "    headers:\n      X-Gateway-Key: ghp_${'abcdef0123' * 3}abcdef\n"
        '    models:\n      m: {}\n'
        'agent:\n  default_model: lm/m\n',
      );
      final extra = '${root.path}/extra.yaml';
      File(extra).writeAsStringSync(
        "providers:\n  lm:\n    api_key: sk-${'f1e2d3c4b5' * 3}\n",
      );
      final binding = CodeLabTestBinding(
        environment: {'CODELAB_HOME': home, 'CODELAB_CONFIG': extra},
      );

      final outcome = await tester.runAsync(
        () => binding.scope.resolve<SecretMigrationRunner>().plan(project),
      );

      expect(outcome!.problem, isNull);
      expect(
        outcome.items,
        contains(startsWith('not migrated: $extra')),
        reason: 'порт видит CODELAB_CONFIG из того же environment',
      );
      expect(outcome.items.join('\n'), contains('X-Gateway-Key'));

      // Открыватель из того же scope читает тот же `CODELAB_HOME`.
      final opener = binding.scope.resolve<EmbeddedAgentOpener>();
      final agent = await tester.runAsync(
        () => opener(cwd: project, hostProfile: 'embedded-app-desktop'),
      );
      expect(agent!.secretsInConfig, isTrue);
      await tester.runAsync(agent.dispose);
    });

    testWidgets('открытие агента с секретами показывает предложение в Cubit, '
        'закрытие скрывает', (tester) async {
      final binding = CodeLabTestBinding(
        embeddedOpener: ({required cwd, required hostProfile}) async =>
            _FakeAgent(secretsInConfig: true),
      );
      final cubit = binding.scope.resolve<SecretMigrationCubit>();
      expect(cubit.state, isA<SecretMigrationHidden>());

      final resolver = binding.scope.resolve<EmbeddedTransportResolver>();
      await resolver.open(_profile, projectDirectory: '/work/app');
      expect(cubit.state, isA<SecretMigrationOffered>());

      await resolver.close();
      expect(cubit.state, isA<SecretMigrationHidden>());
    });
  });
}

final class _PlanOkApplyThrows implements SecretMigrationRunner {
  @override
  Future<SecretMigrationOutcome> plan(String cwd) async =>
      const SecretMigrationOutcome(items: ['x'], canApply: true);

  @override
  Future<SecretMigrationOutcome> apply(String cwd) =>
      Future.error(_Leaky('sk-test-leak-0123456789'));
}
