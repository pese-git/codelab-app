// Закрытие `CodeLabRootLifecycle`: параллельные ветки, изоляция шагов,
// идемпотентность (change `add-client-process-shutdown-on-exit`, задача 3.1;
// спецификация `agent-workbench-ui` «Выход из приложения завершает процессы
// клиента»; задачи 5.9, 5.11; design.md D2, D5, D6, D10 (`pendingSteps` —
// и не начатые шаги), D11 (две параллельные подветви после `workspace`)).
//
// Настоящий scope даёт Cubit-ы, резолвер встроенного агента и ядро клиента;
// подменяются только владельцы, поведением которых управляет тест:
// вкладки Terminal, рабочее пространство и транспорт.
import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show AcpClientApplication, AcpTransport;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    as agent
    show EmbeddedAgent, LogLevel, Logger;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/app/secret_migration_offer.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/secret_migration_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_client_workspace.dart';
import '../support/fake_external_link_opener.dart';
import '../support/fake_user_shell_launcher.dart';
import '../support/recording_logger.dart';
import '../support/test_app_scope.dart';

/// Транспорт, запоминающий предел, с которым его закрыли.
///
/// `FakeAcpTransport` — `final`, поэтому обёртка делегирует ему все вызовы.
final class _SpyTransport implements AcpTransport {
  final _inner = FakeAcpTransport();
  final closeTimeouts = <Duration?>[];

  @override
  Stream<JsonRpcMessage> get inbound => _inner.inbound;

  @override
  Stream<AcpTransportEvent> get events => _inner.events;

  @override
  AcpTransportState get state => _inner.state;

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> send(JsonRpcMessage message) => _inner.send(message);

  @override
  Future<void> close({Duration? timeout}) {
    closeTimeouts.add(timeout);
    return _inner.close(timeout: timeout);
  }
}

/// Вкладки, у которых `closeAll()` не завершается, пока тест не откроет ворота.
final class _HangingTabs extends TerminalTabsCubit {
  _HangingTabs({
    required super.workspace,
    required super.launcher,
    required super.directoryExists,
    required super.logger,
    required super.externalLinkOpener,
  });

  final gate = Completer<void>();
  var closeAllCalls = 0;

  @override
  Future<void> closeAll() {
    closeAllCalls++;
    return gate.future;
  }
}

/// Рабочее пространство, у которого `dispose` считается и может бросать.
final class _SpyWorkspace extends Fake implements ClientWorkspace {
  Object? disposeError;
  var disposeCalls = 0;

  /// Если задан, `dispose` не завершается, пока тест не завершит `Completer`.
  Completer<void>? disposeGate;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate?.future;
    final error = disposeError;
    if (error != null) {
      throw error;
    }
  }
}

/// Логгер встроенного агента, запоминающий имена событий.
final class _AgentLog implements agent.Logger {
  final events = <String>[];

  @override
  bool isEnabled(agent.LogLevel level) => true;

  @override
  void log(
    agent.LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) => events.add(event);
}

const _embeddedProfile = EmbeddedProfile(
  id: 'e',
  label: 'E',
  hostProfile: 'default',
);

void main() {
  late _SpyTransport transport;
  late CodeLabTestBinding binding;
  late RecordingLogger logger;
  late _HangingTabs tabs;
  late _SpyWorkspace workspace;
  late CodeLabRootLifecycle lifecycle;
  late AcpClientApplication lifecycleApplication;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    transport = _SpyTransport();
    binding = CodeLabTestBinding();
    logger = RecordingLogger();
    final scope = binding.scope;
    tabs = _HangingTabs(
      workspace: FakeClientWorkspace(),
      launcher: FakeUserShellLauncher(),
      directoryExists: (_) async => true,
      logger: logger,
      externalLinkOpener: FakeExternalLinkOpener(),
    );
    workspace = _SpyWorkspace();
    lifecycleApplication = AcpClientApplication(transport: transport);
    lifecycle = CodeLabRootLifecycle(
      application: lifecycleApplication,
      transport: transport,
      workspace: workspace,
      embedded: scope.resolve<EmbeddedTransportResolver>(),
      embeddedCloseSettings: scope.resolve<EmbeddedCloseSettings>(),
      shellCubit: scope.resolve<CodeLabShellCubit>(),
      secretMigrationCubit: scope.resolve<SecretMigrationCubit>(),
      secretMigrationOffer: scope.resolve<SecretMigrationOffer>(),
      navigationCubit: scope.resolve<NavigationCubit>(),
      terminalTabsCubit: tabs,
      logger: logger,
    );
  });

  tearDown(() async {
    if (!tabs.gate.isCompleted) {
      tabs.gate.complete();
    }
    await tabs.close();
    // Верхнеуровневый `lifecycle` тоже владеет ядром клиента: освобождаем.
    await lifecycle.dispose();
  });

  test(
    'зависший closeAll() вкладок не задерживает закрытие ядра клиента',
    () async {
      final disposing = lifecycle.dispose();

      await pumpEventQueue();
      expect(transport.state, AcpTransportState.closed);
      expect(tabs.closeAllCalls, 1);
      expect(workspace.disposeCalls, 1);
      expect(lifecycle.pendingSteps, ['terminal']);

      tabs.gate.complete();
      await disposing.timeout(const Duration(seconds: 5));
      expect(lifecycle.pendingSteps, isEmpty);
    },
  );

  test('ядро клиента закрывается с пределом транспорта 2 с', () async {
    tabs.gate.complete();

    await lifecycle.dispose();

    expect(transport.closeTimeouts, contains(transportCloseTimeout));
  });

  test('сбой ClientWorkspace.dispose: событие без текста ошибки, остальные '
      'шаги выполнены', () async {
    tabs.gate.complete();
    workspace.disposeError = StateError('secret /home/user/path');

    await lifecycle.dispose();

    final event = logger.entries.singleWhere(
      (e) => e['event'] == 'app.shutdown_step_failed',
    );
    expect(event['step'], 'workspace');
    expect(event['error_type'], 'StateError');
    expect(event['level'], 'error');
    expect(event.toString(), isNot(contains('secret')));
    expect(event.keys.toSet(), {'event', 'level', 'step', 'error_type'});
    // Резолвер встроенного агента закрыт: новое открытие отменяется.
    await expectLater(
      binding.scope.resolve<EmbeddedTransportResolver>().open(
        const EmbeddedProfile(id: 'e', label: 'E', hostProfile: 'default'),
        projectDirectory: '/work/a',
      ),
      throwsA(isA<EmbeddedOpenCancelledException>()),
    );
    // Ядро клиента закрыто: его закрытие не пропущено сбоем предыдущего шага.
    expect(transport.closeTimeouts, contains(transportCloseTimeout));
    expect(transport.state, AcpTransportState.closed);
  });

  test('повторный dispose() возвращает тот же Future, владельцы вызваны '
      'один раз', () async {
    final first = lifecycle.dispose();
    final second = lifecycle.dispose();

    expect(identical(first, second), isTrue);
    tabs.gate.complete();
    await first;
    expect(identical(lifecycle.dispose(), first), isTrue);
    expect(tabs.closeAllCalls, 1);
    expect(workspace.disposeCalls, 1);
    expect(
      transport.closeTimeouts.where((t) => t == transportCloseTimeout),
      hasLength(1),
    );
  });

  // Задачи 5.9 и 5.11 change `add-client-process-shutdown-on-exit`
  // (design.md D10, D11): `pendingSteps` перечисляет и не начатые шаги;
  // клиентская ветка после `workspace` делится на агентскую и ACP-подветви.
  group('pendingSteps — все незавершённые шаги (D10)', () {
    const fullSet = [
      'terminal',
      'cubits',
      'workspace',
      'embedded',
      'migration_offer',
      'transport',
      'client',
    ];

    test('до dispose() пуст, сразу после — весь закрытый набор по порядку', () {
      expect(lifecycle.pendingSteps, isEmpty);

      final disposing = lifecycle.dispose();

      // Синхронно, до первого `await`: не начатые шаги тоже «не завершены».
      expect(lifecycle.pendingSteps, fullSet);
      tabs.gate.complete();
      return disposing;
    });

    test('зависший workspace: после Cubit-ов остаются workspace и хвост, '
        'после прохода список пуст', () async {
      workspace.disposeGate = Completer<void>();

      final disposing = lifecycle.dispose();
      await pumpEventQueue();

      expect(lifecycle.pendingSteps, [
        'terminal',
        'workspace',
        'embedded',
        'migration_offer',
        'transport',
        'client',
      ]);

      tabs.gate.complete();
      workspace.disposeGate!.complete();
      await disposing;
      expect(lifecycle.pendingSteps, isEmpty);
    });

    test('сбой шага убирает его имя из pendingSteps', () async {
      workspace.disposeError = StateError('boom');

      final disposing = lifecycle.dispose();
      await pumpEventQueue();

      // `terminal` ещё висит, `workspace` упал, остальное закрыто.
      expect(lifecycle.pendingSteps, ['terminal']);
      tabs.gate.complete();
      await disposing;
      expect(lifecycle.pendingSteps, isEmpty);
    });
  });

  group('две параллельные подветви после workspace (D11)', () {
    late Completer<agent.EmbeddedAgent> opening;
    late EmbeddedTransportResolver resolver;
    late SecretMigrationOffer offer;
    late _AgentLog agentLog;
    late CodeLabRootLifecycle hanging;
    late bool offerClosed;

    CodeLabRootLifecycle build({
      Duration timeout = const Duration(seconds: 10),
    }) {
      final scope = binding.scope;
      return CodeLabRootLifecycle(
        application: AcpClientApplication(transport: transport),
        transport: transport,
        workspace: workspace,
        embedded: resolver,
        embeddedCloseSettings: EmbeddedCloseSettings(
          timeout: timeout,
          logger: agentLog,
        ),
        shellCubit: scope.resolve<CodeLabShellCubit>(),
        secretMigrationCubit: scope.resolve<SecretMigrationCubit>(),
        secretMigrationOffer: offer,
        navigationCubit: scope.resolve<NavigationCubit>(),
        terminalTabsCubit: tabs,
        logger: logger,
      );
    }

    /// Начинает открытие, которое висит на `opening`: `close()` резолвера
    /// ждёт его через `_tail`.
    Future<void> startHangingOpen() async {
      unawaited(
        resolver
            .open(_embeddedProfile, projectDirectory: '/work/a')
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await pumpEventQueue();
    }

    setUp(() {
      opening = Completer<agent.EmbeddedAgent>();
      offer = SecretMigrationOffer();
      offerClosed = false;
      offer.changes.listen((_) {}, onDone: () => offerClosed = true);
      agentLog = _AgentLog();
      // Неиспользованное открытие не должно давать необработанную ошибку.
      opening.future.ignore();
      resolver = EmbeddedTransportResolver(
        ({required cwd, required hostProfile}) => opening.future,
        offer: offer,
      );
      hanging = build();
      tabs.gate.complete();
    });

    tearDown(() async {
      if (!opening.isCompleted) {
        opening.completeError(StateError('teardown'));
      }
      await hanging.dispose();
    });

    test('зависший резолвер не задерживает транспорт и ядро клиента', () async {
      await startHangingOpen();

      final disposing = hanging.dispose();
      await pumpEventQueue();

      expect(transport.closeTimeouts, contains(transportCloseTimeout));
      expect(transport.closeTimeouts, contains(null));
      expect(transport.state, AcpTransportState.closed);
      // Агентская подветвь ещё стоит на `embedded`, ACP-подветвь завершена.
      expect(hanging.pendingSteps, ['embedded', 'migration_offer']);
      expect(offerClosed, isFalse);

      opening.completeError(StateError('open failed'));
      await disposing;
      expect(hanging.pendingSteps, isEmpty);
    });

    test('источник предложения закрывается только после close() резолвера, '
        'эта подветвь не закрывает ядро раньше', () async {
      await startHangingOpen();

      final disposing = hanging.dispose();
      await pumpEventQueue();
      expect(offerClosed, isFalse);

      opening.completeError(StateError('open failed'));
      await pumpEventQueue();

      expect(offerClosed, isTrue);
      await disposing;
    });

    test('embedded и client начинаются после завершения workspace', () async {
      workspace.disposeGate = Completer<void>();

      final disposing = hanging.dispose();
      await pumpEventQueue();

      expect(transport.closeTimeouts, isEmpty);
      expect(offerClosed, isFalse);
      // Резолвер ещё не закрыт: открытие принимается (в очередь не ставим —
      // проверяем по состоянию транспорта и списку шагов).
      expect(hanging.pendingSteps, contains('embedded'));

      workspace.disposeGate!.complete();
      await disposing;

      expect(transport.closeTimeouts, contains(transportCloseTimeout));
      expect(offerClosed, isTrue);
      await expectLater(
        resolver.open(_embeddedProfile, projectDirectory: '/work/a'),
        throwsA(isA<EmbeddedOpenCancelledException>()),
      );
    });

    test('embedded.close_timeout пишется по истечении предела, закрытие '
        'идёт дальше', () async {
      // Предел укорочен ради скорости теста: значение 10 с задаёт
      // `CodeLabEmbeddedAgentModule` (по умолчанию 10 с); здесь
      // важно поведение при его истечении (без опроса: `dispose()` сам
      // завершается по таймауту, пока открытие висит).
      // Первый `hanging` из setUp в тесте не используется; tearDown группы
      // видит уже новый, поэтому прежний освобождаем отдельно.
      addTearDown(hanging.dispose);
      hanging = build(timeout: const Duration(milliseconds: 20));
      await startHangingOpen();

      await hanging.dispose();

      expect(agentLog.events, ['embedded.close_timeout']);
      expect(transport.closeTimeouts, contains(transportCloseTimeout));
      expect(offerClosed, isTrue);
      expect(hanging.pendingSteps, isEmpty);
    });
  });
}
