// Красные тесты моста нативного меню (ручная проверка macOS, change
// `add-app-keyboard-page`/`add-app-appearance-page`): пункт «Настройки…»
// главного меню macOS (⌘,) шлёт `openSettings` в канал `codelab/app_menu`, а app
// открывает настройки тем же путём, что сочетание `open-settings`
// (`SettingsOpenSource.shortcut`).
//
// Нативное меню перехватывает ⌘, раньше Flutter: пункт без действия не
// запускал ничего, а сочетание Dart-стороны до него не доходило. Нативную
// сторону проверяют вручную; здесь — Dart-обработчик канала и проводка в app.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/app_destination.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/core/platform/app_menu_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app_scope.dart';

/// Вызов метода канала со стороны платформы.
Future<ByteData?> _platformCall(String method) {
  const codec = StandardMethodCodec();
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        kAppMenuChannelName,
        codec.encodeMethodCall(MethodCall(method)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('канал называется codelab/app_menu', () {
    expect(kAppMenuChannelName, 'codelab/app_menu');
  });

  group('AppMenuBridge', () {
    test('openSettings из канала зовёт обработчик', () async {
      var opened = 0;
      final bridge = AppMenuBridge(onOpenSettings: () => opened++)..attach();
      addTearDown(bridge.dispose);

      await _platformCall('openSettings');

      expect(opened, 1);
    });

    test('после dispose обработчик не вызывается', () async {
      var opened = 0;
      AppMenuBridge(onOpenSettings: () => opened++)
        ..attach()
        ..dispose();

      await _platformCall('openSettings');

      expect(opened, 0);
    });

    test('неизвестный метод — MissingPluginException, обработчик не '
        'вызывается', () async {
      var opened = 0;
      final bridge = AppMenuBridge(onOpenSettings: () => opened++)..attach();
      addTearDown(bridge.dispose);

      await _platformCall('somethingElse');

      expect(opened, 0);
    });
  });

  testWidgets('пункт меню «Настройки…» открывает настройки как сочетание '
      '(SettingsOpenSource.shortcut)', (tester) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    final navigation = binding.scope.resolve<NavigationCubit>();
    expect(navigation.state, isA<WorkbenchDestination>());

    await tester.runAsync(() => _platformCall('openSettings'));
    await tester.pumpAndSettle();

    expect(navigation.state, isA<SettingsDestination>());
  });
}
