// Мастер провайдера из onboarding (задача 3.5 change `add-app-onboarding`;
// design.md D8, D11; spec app-onboarding «Шаг «Choose a model» и мастер
// провайдера», сценарии «Провайдер с ключом в файле» и «Отмена мастера»).
//
// Красный по причине компиляции: `OnboardingWizardOpener` и его привязка в
// `app_scope.dart` появляются в задаче 3.6.
//
// Только временный `CODELAB_HOME` с `secrets.backend: file`; сервер `/models`
// заменён двойником `ProviderCheck` (сетевая проверка адреса — предмет
// тестов моста). Файлы конфига и секретов — настоящие: проверяется то, что
// ключ уходит в хранилище, а конфиг получает ссылку, и что ни одно значение
// ключа не попадает в журнал и состояние.
//
// Контракт открывателя (принят при реализации 3.6):
// `OnboardingWizardOpener = Future<ProviderWizardCubit?> Function({required
// String presetId})`; он собирает мастер встроенного профиля с целью `user`,
// `forceDefault: true`, `entry: ProviderWizardEntry.onboarding` и сам
// отправляет автомату `PresetChosen(presetId)`, поэтому диалог начинается с
// «Base URL». Закрывает Cubit владелец (экран после диалога).

import 'dart:async';
import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/app/provider_settings_session.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_wizard_opener.dart';
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../support/fake_provider_settings.dart' show leakMarker;
import '../../../support/recording_logger.dart';
import '../../../support/test_app_scope.dart';

/// Проверка адреса и список моделей: сети нет.
final class _ModelsCheck implements ProviderCheck {
  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) async => const CheckOk([RemoteModel('m1', contextWindow: 8000)]);
}

void main() {
  late Directory home;
  late RecordingLogger log;
  late OnboardingWizardOpener open;

  setUp(() {
    home = Directory.systemTemp.createTempSync('codelab-onboarding-wizard-');
    addTearDown(() => home.deleteSync(recursive: true));
    // Бэкенду `file` нужны права 0700 на дом (как в тестах сессии настроек).
    Process.runSync('/bin/chmod', ['700', home.path]);
    File(
      p.join(home.path, 'config.yaml'),
    ).writeAsStringSync('secrets:\n  backend: file\n');
    log = RecordingLogger();
    final environment = {'CODELAB_HOME': home.path, 'HOME': home.path};
    final binding = CodeLabTestBinding(
      environment: environment,
      providerSettingsOpener: (access, env) => openProviderSettingsSession(
        access,
        env,
        check: _ModelsCheck(),
        logger: CodeLabEmbeddedLogger(logger: log),
      ),
    );
    addTearDown(binding.scope.dispose);
    open = binding.scope.resolve<OnboardingWizardOpener>();
  });

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 300 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ok(), isTrue, reason: 'автомат не дошёл до нужного состояния');
  }

  String config() => File(p.join(home.path, 'config.yaml')).readAsStringSync();

  test(
    'диалог начинается с «Base URL»; ключ уходит в хранилище, конфиг '
    'получает ссылку и модель по умолчанию; значения ключа нигде нет',
    () async {
      final wizard = (await open(presetId: 'custom-openai'))!;
      addTearDown(wizard.close);

      // PresetChosen отправлен открывателем: «API type» пропущен (D8).
      await until(() => wizard.state.setup is EnteringBaseUrl);
      expect(
        wizard.forceDefault,
        isTrue,
        reason: '«Make default» не снимается',
      );

      wizard.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await until(() => wizard.state.setup is ChoosingKey);
      wizard.dispatch(KeySubmitted(StoreSecret(SecretValue(leakMarker))));
      await until(() => wizard.state.setup is ChoosingModel);
      wizard.dispatch(const ModelChosen('m1'));
      await until(() => wizard.state.setup is Reviewing);
      wizard.dispatch(const ConfirmSave());
      await until(() => wizard.state.setup is Done);

      final done = wizard.state.setup as Done;
      expect(done.plan.target.layer, ConfigLayer.user, reason: 'цель user');
      expect(done.plan.makeDefault, isTrue);
      expect(done.plan.providerId, 'llm-example');
      expect(config(), contains('api_key_secret: codelab/llm-example'));
      expect(config(), contains('default_model: llm-example/m1'));
      expect(config(), isNot(contains(leakMarker)));
      final secrets = File(
        p.join(home.path, 'secrets.yaml'),
      ).readAsStringSync();
      expect(secrets, contains('codelab/llm-example'));

      final started = log.entries.firstWhere(
        (e) => e['event'] == 'provider_wizard.started',
      );
      expect(started['entry'], 'onboarding');
      expect(log.entries.toString(), isNot(contains(leakMarker)));
      expect(wizard.state.toString(), isNot(contains(leakMarker)));
      expect(done.toString(), isNot(contains(leakMarker)));
    },
  );

  test('отмена мастера: ничего не записано', () async {
    final before = config();
    final wizard = (await open(presetId: 'anthropic'))!;
    addTearDown(wizard.close);
    await until(() => wizard.state.setup is EnteringBaseUrl);

    wizard.cancel();
    await until(() => wizard.state.setup is Cancelled);

    expect(config(), before);
    expect(File(p.join(home.path, 'secrets.yaml')).existsSync(), isFalse);
  });
}
