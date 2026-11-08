// `EmbeddedTransportResolver` и признак «нужен провайдер» (задача 3.12 change
// `add-provider-setup-ui`; agent-workbench-ui «Встроенный агент без
// провайдера»; design.md D26).
//
// Резолвер при `EmbeddedAgentConfigException` спрашивает функцию composition
// root «нужен ли провайдер» (она читает снимок конфига) и записывает ответ в
// `ProviderSetupOffer` ДО исключения: `ConnectionCubit` читает порт синхронно
// в обработчике сбоя. Исключение наружу прежнее.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspaceException, ConnectionProfile;
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/app/provider_setup_offer.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentConfigException, McpStatusPort;
import 'package:flutter_test/flutter_test.dart';

final class _FakeAgent implements EmbeddedAgent {
  // Статус MCP в этом тесте не нужен: фейк сессий не открывает.
  @override
  McpStatusPort? mcpStatus(String sessionId) => null;

  @override
  bool get secretsInConfig => false;

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

EmbeddedAgentConfigException _broken() =>
    EmbeddedAgentConfigException(const [], home: '/h');

void main() {
  late ProviderSetupOffer offer;
  late List<String> probed;
  var needed = true;
  var failOpen = true;
  Object? probeError;

  EmbeddedTransportResolver make() => EmbeddedTransportResolver(
    ({required cwd, required hostProfile}) async =>
        failOpen ? throw _broken() : _FakeAgent(),
    setupOffer: offer,
    providerSetupNeeded: (cwd) async {
      probed.add(cwd);
      if (probeError != null) {
        throw probeError!;
      }
      return needed;
    },
  );

  setUp(() {
    offer = ProviderSetupOffer();
    probed = [];
    needed = true;
    failOpen = true;
    probeError = null;
  });

  test('a true snapshot flag sets the offer with the cwd before the '
      'exception; the exception is the same as before', () async {
    final resolver = make();
    ProviderSetupNeeded? seenWhenThrown;

    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app').catchError((
        Object e,
      ) {
        seenWhenThrown = offer.value;
        throw e;
      }),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(seenWhenThrown?.cwd, '/work/app');
    expect(offer.value?.cwd, '/work/app');
    expect(probed, ['/work/app']);
    await resolver.close();
  });

  test('a false flag leaves the offer empty', () async {
    needed = false;
    final resolver = make();

    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(offer.value, isNull);
    await resolver.close();
  });

  test('a failure of the snapshot is "no" and the exception stays', () async {
    probeError = StateError('cannot read');
    final resolver = make();

    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(offer.value, isNull);
    await resolver.close();
  });

  test('the value is reset at the start of the next open', () async {
    final resolver = make();
    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );
    expect(offer.value, isNotNull);

    needed = false;
    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(offer.value, isNull);
    await resolver.close();
  });

  test('a successful open resets the value', () async {
    final resolver = make();
    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );
    expect(offer.value, isNotNull);

    failOpen = false;
    await resolver.open(_profile, projectDirectory: '/work/app');

    expect(offer.value, isNull);
    await resolver.close();
  });

  test('without a probe nothing is set (the app without setup)', () async {
    final resolver = EmbeddedTransportResolver(
      ({required cwd, required hostProfile}) async => throw _broken(),
      setupOffer: offer,
    );

    await expectLater(
      resolver.open(_profile, projectDirectory: '/work/app'),
      throwsA(isA<ClientWorkspaceException>()),
    );

    expect(offer.value, isNull);
    await resolver.close();
  });

  // Задача 5.4 change `add-provider-setup-ui` (design.md D12 «Механизм в
  // коде»): страница «MCP servers» берёт порт состояния MCP у агента
  // текущего соединения через `currentAgent`. Красные до задачи 5.10.
  group('currentAgent (D12)', () {
    test('is null before open, the agent after a successful open and null '
        'after close()', () async {
      failOpen = false;
      final resolver = make();
      expect(resolver.currentAgent, isNull);

      await resolver.open(_profile, projectDirectory: '/work/app');

      expect(resolver.currentAgent, isA<_FakeAgent>());

      await resolver.close();

      expect(resolver.currentAgent, isNull);
    });

    test('a failed open leaves no current agent', () async {
      final resolver = make();

      await expectLater(
        resolver.open(_profile, projectDirectory: '/work/app'),
        throwsA(isA<ClientWorkspaceException>()),
      );

      expect(resolver.currentAgent, isNull);
      await resolver.close();
    });

    test('an open that was superseded never becomes current; the newer '
        'agent does', () async {
      final agents = <_FakeAgent>[];
      final gate = Completer<void>();
      final resolver = EmbeddedTransportResolver(({
        required cwd,
        required hostProfile,
      }) async {
        final agent = _FakeAgent();
        agents.add(agent);
        if (agents.length == 1) {
          await gate.future;
        }
        return agent;
      }, setupOffer: offer);

      final first = resolver.open(_profile, projectDirectory: '/work/app');
      final firstResult = expectLater(
        first,
        throwsA(isA<EmbeddedOpenCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(resolver.currentAgent, isNull);
      final second = resolver.open(_profile, projectDirectory: '/work/app');
      gate.complete();
      await firstResult;
      await second;

      expect(agents, hasLength(2));
      expect(resolver.currentAgent, same(agents[1]));
      await resolver.close();
    });
  });
}
