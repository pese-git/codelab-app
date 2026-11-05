import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/connection_cubit.dart'
    show stdioConnectionProfileOf;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show codelabAgentStdioProfile;
import 'package:codelab_client_core/codelab_client_core.dart' show ProfileStore;
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:cherrypick/cherrypick.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentOpener;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart'
    show TestWidgetsFlutterBinding, addTearDown;
import 'package:shared_preferences/shared_preferences.dart';

import 'in_memory_profile_store.dart';

/// stdio-профиль, который тестовая сборка делает профилем по умолчанию.
///
/// Почему: до change `add-app-settings-shell` форма подключения стартовала с
/// `codelabAgentStdioProfile`, и сотни проверок подключения опираются на «Connect
/// запускает stdio-агента через `stdioTransportFactory`». Теперь профиль по
/// умолчанию — встроенный агент (D5), поэтому тестовая сборка явно хранит
/// выбор этого профиля, как это делает пользователь радиокнопкой
/// (`codelab.connection.default_profile`). Тесты правила «нет выбора —
/// встроенный агент» передают `stdioDefault: false`.
final testStdioProfile = stdioConnectionProfileOf(codelabAgentStdioProfile);

/// Открыватель встроенного агента по умолчанию в тестах: сразу падает.
///
/// Почему: настоящий `localEmbeddedAgentOpener` без заданного окружения читает
/// реальный `~/.codelab` разработчика, и исход теста зависел бы от машины.
/// Для чего: тесты, которым встроенный агент не нужен, получают
/// предсказуемый `ConnectionFailed` без ввода-вывода и таймеров.
/// Как использовать: подставляется `CodeLabTestBinding`, если не переданы
/// ни `embeddedOpener`, ни `environment`.
Future<EmbeddedAgent> _embeddedAgentNotInThisTest({
  required String cwd,
  required String hostProfile,
}) async => throw StateError('the embedded agent is not part of this test');

final class CodeLabTestBinding {
  CodeLabTestBinding({
    FakeAcpTransport? transport,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    Map<String, Object> preferences = const {},
    DirectoryExists? directoryExists,
    EmbeddedAgentOpener? embeddedOpener,
    Map<String, String>? environment,
    SettingsPages? settingsPages,
    ProfileStore? profileStore,
    bool stdioDefault = true,
  }) : transport = transport ?? FakeAcpTransport() {
    // Корневой scope собирает настоящий `SharedPreferencesRecentProjectsStore`,
    // а у плагина в тестах нет реализации канала: без моков каждая загрузка
    // недавних проектов падает `MissingPluginException`. Cubit её
    // перехватывает, но статический completer плагина может отдать ошибку в
    // зону уже завершившегося теста, и раннер засчитает её как сбой («failed
    // after test completion»). Пустое хранилище убирает обращение к каналу.
    // [preferences] — сохранённое прошлым запуском (недавние проекты,
    // снимок рабочего пространства).
    SharedPreferences.setMockInitialValues({
      if (stdioDefault)
        'codelab.connection.default_profile': testStdioProfile.id,
      ...preferences,
    });
    scope = createCodeLabRootScope(
      transportFactory: () => this.transport,
      stdioTransportFactory: stdioTransportFactory,
      webSocketTransportFactory: webSocketTransportFactory,
      // Тесты работают с вымышленными путями вроде `/work/app`; по
      // умолчанию любая папка считается существующей.
      directoryExists: directoryExists ?? (_) async => true,
      // Без своего окружения настоящий открыватель читал бы реальный
      // `~/.codelab/config.yaml` разработчика: исход теста зависел бы от
      // машины, а открытый агент оставлял бы таймер опроса конфига
      // (`ConfigWatcher`) в fake-async зоне. Поэтому по умолчанию встроенный
      // агент не открывается; тест с временным `CODELAB_HOME` передаёт
      // `environment:` и получает настоящий открыватель на изолированной
      // папке.
      embeddedOpener:
          embeddedOpener ??
          (environment == null ? _embeddedAgentNotInThisTest : null),
      environment: environment,
      settingsPages: settingsPages,
      // Файл профилей в `testWidgets` зависал бы в fake-async зоне: тесты
      // работают с хранилищем в памяти, а настоящий файл проверяет
      // `app_scope_profiles_test.dart`.
      profileStore:
          profileStore ??
          InMemoryProfileStore([if (stdioDefault) testStdioProfile]),
    );
    // `CherryPick.openRootScope()` is a process-global singleton that
    // silently REUSES an unclosed scope, so a test that fails before its own
    // `closeCodeLabRootScope()` would corrupt every later test. Close it
    // here regardless.
    addTearDown(closeCodeLabRootScopeInTest);
  }

  final FakeAcpTransport transport;
  late final Scope scope;

  Widget bootstrap({required Widget child}) =>
      CodeLabBootstrap(scope: scope, child: child);
}

/// Closes the root scope from teardown, where a plain `await` can hang.
///
/// The scope is built inside the test's fake-async zone, so the file log
/// outputs' write queues (`AsyncRotatingFileOutput.flushed`) are fake-zone
/// futures that are resumed by *real* file I/O. `flutter_test` flushes the
/// fake microtask queue only inside `pump`/`idle`, so once the test body
/// has ended (or threw) nothing resumes them and `await flushed` never
/// completes. Alternate real event-loop turns with explicit flushes until
/// the scope is closed.
Future<void> closeCodeLabRootScopeInTest() async {
  final TestWidgetsFlutterBinding binding;
  try {
    binding = TestWidgetsFlutterBinding.instance;
  } on FlutterError {
    // A plain `test()` has no widget binding, hence no fake zone to flush.
    await closeCodeLabRootScope();
    return;
  }
  var closed = false;
  final closing = closeCodeLabRootScope().whenComplete(() => closed = true);
  while (!closed && binding.inTest) {
    await binding.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (binding.inTest) {
      await binding.idle();
    }
  }
  await closing;
}
