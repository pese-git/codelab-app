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
    show EmbeddedAgent, EmbeddedAgentConfigException;
import 'package:flutter_test/flutter_test.dart';

final class _FakeAgent implements EmbeddedAgent {
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
}
