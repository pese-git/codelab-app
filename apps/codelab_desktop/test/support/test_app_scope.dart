import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:cherrypick/cherrypick.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart'
    show TestWidgetsFlutterBinding, addTearDown;
import 'package:shared_preferences/shared_preferences.dart';

final class CodeLabTestBinding {
  CodeLabTestBinding({
    FakeAcpTransport? transport,
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    Map<String, Object> preferences = const {},
    DirectoryExists? directoryExists,
  }) : transport = transport ?? FakeAcpTransport() {
    // Корневой scope собирает настоящий `SharedPreferencesRecentProjectsStore`,
    // а у плагина в тестах нет реализации канала: без моков каждая загрузка
    // недавних проектов падает `MissingPluginException`. Cubit её
    // перехватывает, но статический completer плагина может отдать ошибку в
    // зону уже завершившегося теста, и раннер засчитает её как сбой («failed
    // after test completion»). Пустое хранилище убирает обращение к каналу.
    // [preferences] — сохранённое прошлым запуском (недавние проекты,
    // снимок рабочего пространства).
    SharedPreferences.setMockInitialValues(preferences);
    scope = createCodeLabRootScope(
      transportFactory: () => this.transport,
      stdioTransportFactory: stdioTransportFactory,
      webSocketTransportFactory: webSocketTransportFactory,
      // Тесты работают с вымышленными путями вроде `/work/app`; по
      // умолчанию любая папка считается существующей.
      directoryExists: directoryExists ?? (_) async => true,
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
