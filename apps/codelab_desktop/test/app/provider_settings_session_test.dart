// Адаптер Check страницы «Providers» (задача 2.6 change
// `add-provider-setup-ui`; D4, SETUP-1): ключ читается в `lib/app/` и сразу
// уходит `ProviderCheck`; наружу значение не возвращается.
//
// Секрет приходит через `CODELAB_SECRET_*` (переменная побеждает бэкенд, как у
// резолвера агента), поэтому файлов секретов в тесте нет; `CODELAB_HOME` —
// временная папка.

import 'dart:io';

import 'package:codelab_desktop/app/provider_settings_session.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider_settings.dart';

final class _CapturingCheck implements ProviderCheck {
  final seen = <SecretValue?>[];
  final tokens = <CancelToken?>[];

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) async {
    seen.add(key);
    tokens.add(cancel);
    return const CheckOk([RemoteModel('m')]);
  }
}

void main() {
  late Directory home;
  late _CapturingCheck check;

  setUp(() {
    home = Directory.systemTemp.createTempSync('codelab_providers_');
    addTearDown(() => home.deleteSync(recursive: true));
    check = _CapturingCheck();
  });

  Future<ProviderSettingsSession> open(Map<String, String> env) async {
    final environment = {'CODELAB_HOME': home.path, ...env};
    return openProviderSettingsSession(
      EditableSettings(ConfigPaths(codelabHome: home.path)),
      environment,
      check: check,
      logger: const _Silent(),
    );
  }

  test('hands a stored key straight to the check', () async {
    final session = await open({
      SecretNames.envOverride('codelab/anthropic'): leakMarker,
    });

    final result = await session.checkProvider(
      kind: 'anthropic',
      baseUrl: Uri.parse('https://api.anthropic.com'),
      key: const KeyInSecretStore(name: 'codelab/anthropic', backendId: 'env'),
    );

    expect(result, isA<CheckOk>());
    expect(check.seen.single?.reveal(), leakMarker);
    expect(check.seen.single.toString(), isNot(contains(leakMarker)));
    expect(result.toString(), isNot(contains(leakMarker)));
  });

  test(
    'hands an environment key to the check and nothing for no key',
    () async {
      final session = await open({'OPENAI_API_KEY': leakMarker});

      await session.checkProvider(
        kind: 'openai-compatible',
        baseUrl: Uri.parse('https://h/v1'),
        key: const KeyFromEnv(name: 'OPENAI_API_KEY', isSet: true),
      );
      await session.checkProvider(
        kind: 'openai-compatible',
        baseUrl: Uri.parse('https://h/v1'),
        key: const KeyNone(),
      );

      expect(check.seen.first?.reveal(), leakMarker);
      expect(check.seen.last, isNull);
    },
  );

  test('passes the cancel token to the check', () async {
    final session = await open({});
    final source = CancelTokenSource();

    await session.checkProvider(
      kind: 'openai-compatible',
      baseUrl: Uri.parse('https://h/v1'),
      key: const KeyNone(),
      cancel: source.token,
    );

    expect(check.tokens.single, same(source.token));
  });

  test('isSecretSet answers without reading the value', () async {
    final session = await open({
      SecretNames.envOverride('codelab/anthropic'): leakMarker,
    });

    expect(await session.isSecretSet('codelab/anthropic'), isTrue);
    expect(await session.isSecretSet('codelab/other'), isFalse);
    expect(session.backend.id, 'env');
  });
}

final class _Silent implements setup.Logger {
  const _Silent();

  @override
  bool isEnabled(setup.LogLevel level) => false;

  @override
  void log(
    setup.LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
