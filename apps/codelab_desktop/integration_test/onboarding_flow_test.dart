// Onboarding первого запуска на устройстве (задача 4.1 change
// `add-app-onboarding`; spec app-onboarding «Показ onboarding при первом
// запуске», «Шаг «Choose a model» и мастер провайдера», «Завершение
// onboarding и старт рабочего места», «События журнала onboarding без
// секретов и путей» — «Полный проход без утечек»; design.md D3, D5, D8, D13).
//
// Сценарий: пустой временный `CODELAB_HOME` с бэкендом секретов `file` →
// onboarding на первом шаге, рабочего места нет → «Next», «Next» → пресет
// «Custom OpenAI-compatible» → мастер на тестовом сервере `/models`, ключ в
// хранилище → «Next» → «Privacy» → «Next» → шаг «Open a project»: выбор папки
// тестовым портом выбора папки (системный диалог из теста не закрыть) →
// рабочее место; встроенный агент стартует один раз в выбранной папке уже
// после перехода, без баннера «Add provider»; журнал onboarding не содержит
// ключа и путей (change `add-onboarding-project-step`, D1, D2, D5, задача
// 4.1).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` скриптом
// `test:e2e:app:onboarding` (AGENTS.md §21; веха M4, design.md D17). Настоящие
// `~/.codelab` и хранилище ОС не затрагиваются. Встроенному агенту нужен
// настоящий открыватель на временном `CODELAB_HOME`, поэтому в режиме
// `CODELAB_E2E_AGENT=embedded` (сценарий модели) тест пропускается.

import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show CherryPick;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:codelab_desktop/features/workbench/presentation/workbench_shell.dart';
import 'package:codelab_setup/io.dart' show ClientSecretAccess;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabConnectionStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import 'support/e2e_agent.dart';

/// Значение ключа, которое не должно выйти из хранилища ни в журнал, ни на
/// экран.
const _marker = 'sk-test-leak-0123456789';

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets, reason: 'did not appear in $timeout');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await _pumpUntil(tester, _key(key));
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Системный выбор папки, который сразу возвращает [path].
final class _FixedFolderPicker implements ProjectFolderPicker {
  _FixedFolderPicker(this.path);

  final String path;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async => path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first run: wizard saves the provider, the Open a project step opens the '
    'workbench, the agent starts once in the chosen folder without the Add '
    'provider banner, the log has no key and no paths',
    (tester) async {
      // Пустые `shared_preferences`: флага нет, onboarding должен показаться.
      SharedPreferences.setMockInitialValues({});
      final load = await const SharedPreferencesOnboardingPreferences().load();
      expect(load.done, isFalse);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"data":[{"id":"m1"}]}');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final project = await Directory.systemTemp.createTemp(
        'codelab_onboarding_project_',
      );
      addTearDown(() => project.delete(recursive: true));

      final secrets = await E2eAgent.current.openFileSecrets();
      final home = File(E2eAgent.current.profilesPath).parent.path;

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(
          profileSecrets: secrets,
          onboarding: OnboardingStart.fromLoad(load),
          projectFolderPicker: _FixedFolderPicker(project.path),
        ),
      );
      await tester.pumpAndSettle();

      // Первый кадр — onboarding, рабочего места нет (D3, D5).
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(CodeLabShell), findsNothing);
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;

      await _tapKey(tester, 'onboarding-next');
      await _tapKey(tester, 'onboarding-next');
      await _pumpUntil(tester, _key('onboarding-step-model'));

      // Мастер: диалог начинается с «Base URL», ключ уходит в хранилище.
      await _tapKey(tester, 'onboarding-preset-custom-openai');
      await _tapKey(tester, 'onboarding-model-setup');
      await _pumpUntil(tester, _key('provider-wizard-base-url-field'));
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'http://127.0.0.1:${server.port}/v1',
      );
      await _tapKey(tester, 'provider-wizard-next');
      await _tapKey(tester, 'provider-wizard-key-store');
      await tester.enterText(_key('provider-wizard-key-field'), _marker);
      await _tapKey(tester, 'provider-wizard-next');
      await _tapKey(tester, 'provider-wizard-model-m1');
      // `/models` без окна контекста: мастер спрашивает его (подсказка 32000).
      await _tapKey(tester, 'provider-wizard-next');
      await _pumpUntil(tester, _key('provider-wizard-review'));
      await tester.tap(_key('provider-wizard-save'));
      await _pumpUntil(tester, _key('onboarding-model-connected'));
      expect(find.textContaining(_marker), findsNothing);

      final config = File('$home/config.yaml').readAsStringSync();
      expect(config, contains('api_key_secret: codelab/'));
      expect(config, contains('default_model:'));
      expect(config, isNot(contains(_marker)));
      final access = await ClientSecretAccess.open(
        codelabHome: home,
        environment: {...Platform.environment, 'CODELAB_HOME': home},
        logger: CodeLabEmbeddedLogger(),
      );
      expect(await access.isSet('codelab/local-${server.port}'), isTrue);

      // Шаг «Privacy» и конец onboarding: флаг записан, рабочее место.
      await _tapKey(tester, 'onboarding-next');
      await _pumpUntil(tester, _key('onboarding-step-privacy'));
      expect(find.textContaining('secrets.yaml'), findsWidgets);

      // Документ внутри onboarding (D10, редакция 2026-11-21): политика
      // открывается поверх шага настоящим ресурсом `assets/legal/PRIVACY.md`,
      // «Back to setup» возвращает на «Privacy» с прежним состоянием.
      await _tapKey(tester, 'onboarding-privacy-policy');
      await _pumpUntil(tester, _key('onboarding-document'));
      await _pumpUntil(tester, _key('settings-legal'));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await _tapKey(tester, 'onboarding-document-back');
      await _pumpUntil(tester, _key('onboarding-step-privacy'));
      expect(_key('onboarding-document'), findsNothing);

      // «Next» ведёт на шаг «Open a project» (D1); «Start using CodeLab» нет.
      expect(_key('onboarding-finish'), findsNothing);
      await _tapKey(tester, 'onboarding-next');
      await _pumpUntil(tester, _key('onboarding-step-project'));
      expect(shellCubit.state.selectedProjectPath, isNull);
      expect(
        (await SharedPreferences.getInstance()).getBool(kOnboardingDoneKey),
        isNot(isTrue),
      );

      // Выбор папки: флаг пишется после принятого выбора, агент ждёт перехода
      // на рабочее место (D2, D5).
      await _tapKey(tester, 'start-open-project');
      await _pumpUntil(tester, find.byType(CodeLabShell));
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(kOnboardingDoneKey),
        isTrue,
      );

      // Агент стартует один раз в выбранной папке и находит провайдера:
      // баннера нет.
      expect(shellCubit.state.selectedProjectPath, project.path);
      for (
        var i = 0;
        i < 200 &&
            shellCubit.state.connectionStatus !=
                CodeLabConnectionStatus.connected;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        shellCubit.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      expect(_key('connection-banner-add-provider'), findsNothing);

      // Журнал onboarding: события D13 есть, ключа и пути дома в них нет.
      final entries = CherryPick.openRootScope()
          .resolve<LogBuffer>()
          .entries
          .value
          .where((e) => '${e['event']}'.startsWith('onboarding.'))
          .toList();
      final events = entries.map((e) => e['event']).toList();
      expect(events, contains('onboarding.shown'));
      expect(events, contains('onboarding.model_saved'));
      expect(events, contains('onboarding.document_opened'));
      expect(events, contains('onboarding.document_closed'));
      final completed = entries.singleWhere(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed['model_step'], 'saved');
      expect('$entries', isNot(contains(_marker)));
      expect(completed['project'], 'picker');
      expect('$entries', isNot(contains(home)));
      expect('$entries', isNot(contains(project.path)));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    skip: E2eAgent.current.kind == E2eAgentKind.embedded,
  );
}
