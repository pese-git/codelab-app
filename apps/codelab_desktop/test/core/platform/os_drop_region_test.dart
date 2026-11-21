// Красный тест адаптера приёма перетаскивания из ОС (задача 5.3 change
// `add-empty-project-screen`; design.md D3; spec workspace-architecture
// «Плагин перетаскивания из ОС только в адаптере платформы»).
//
// Адаптер `OsDropRegion` — единственное место, где разрешён
// `package:desktop_drop/` (правило сторожа). Тест подаёт события плагина тем
// же путём, каким их шлёт нативная часть: вызовами метода канала
// `desktop_drop` (`entered`, `exited`, `performOperation`) через
// `TestDefaultBinaryMessenger`, и сам пакет не импортирует. Проверяется
// только перевод событий в колбэки; решения «что можно открыть» в адаптере
// нет (D4).
//
// Красный до задачи 5.4: пакета `desktop_drop` нет в `pubspec.yaml` и файла
// `lib/core/platform/os_drop_region.dart` нет, поэтому тест не
// компилируется.

import 'package:codelab_desktop/core/platform/os_drop_region.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('desktop_drop');

void main() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Событие нативной части плагина: вызов Dart-стороны канала.
  Future<void> native(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
    await TestWidgetsFlutterBinding.instance.pump();
  }

  Future<void> pumpRegion(
    WidgetTester tester, {
    VoidCallback? onEntered,
    VoidCallback? onExited,
    required ValueChanged<List<String?>> onDropped,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: OsDropRegion(
        onEntered: onEntered,
        onExited: onExited,
        onDropped: onDropped,
        child: const SizedBox(width: 400, height: 300),
      ),
    ),
  );

  testWidgets('вход и выход перетаскивания вызывают onEntered и onExited', (
    tester,
  ) async {
    var entered = 0;
    var exited = 0;
    await pumpRegion(
      tester,
      onEntered: () => entered++,
      onExited: () => exited++,
      onDropped: (_) {},
    );

    await native('entered', [10.0, 10.0]);
    expect((entered, exited), (1, 0));

    await native('exited');
    expect((entered, exited), (1, 1));
  });

  testWidgets('бросок: onDropped получает пути в порядке плагина', (
    tester,
  ) async {
    final dropped = <List<String?>>[];
    await pumpRegion(tester, onDropped: dropped.add);

    await native('entered', [10.0, 10.0]);
    await native('performOperation', ['/work/app']);

    expect(dropped, [
      ['/work/app'],
    ]);
  });

  testWidgets('элемент с пустым путём передаётся как null', (tester) async {
    final dropped = <List<String?>>[];
    await pumpRegion(tester, onDropped: dropped.add);

    await native('entered', [10.0, 10.0]);
    await native('performOperation', ['/work/app', '']);

    expect(dropped, [
      ['/work/app', null],
    ]);
  });

  testWidgets('после броска повторный вход снова вызывает onEntered', (
    tester,
  ) async {
    var entered = 0;
    await pumpRegion(tester, onEntered: () => entered++, onDropped: (_) {});

    await native('entered', [10.0, 10.0]);
    await native('performOperation', ['/work/app']);
    await native('entered', [10.0, 10.0]);

    expect(entered, 2);
  });
}
