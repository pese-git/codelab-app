// Красные тесты адаптера системного акцента (задача 4.9 change
// `add-app-appearance-page`; design.md D7; spec app-settings «Системный
// акцент»: «Плагин не отдал цвет», «Платформа без системного акцента»).
//
// Адаптер `SystemThemeAccentSource` — единственное место импорта пакета
// `system_theme` (правило сторожа D1). Тест подменяет каналы плагина
// (`MethodChannel('system_theme')` и событийный канал
// `system_theme_events/switch_callback`) на `TestDefaultBinaryMessenger` и не
// импортирует сам пакет.
//
// Особенности пакета 3.3.0, которые закрывает адаптер: при отсутствии плагина
// `load()` молча оставляет запасной цвет (адаптер заводит маркер
// `Color(0x00000000)`); статический `SystemTheme.accentColor` грузится без
// `await` (исключение потерялось бы); `load()` сам подписывается на
// `onChange` и не отписывается.

import 'dart:async';

import 'package:codelab_desktop/core/platform/system_accent_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _method = MethodChannel('system_theme');
const _events = EventChannel('system_theme_events/switch_callback');

Map<String, Object?> _color(int r, int g, int b) => {
  'accent': {'A': 255, 'R': r, 'G': g, 'B': b},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Событийный канал: [onListen] получает приёмник событий.
  void mockEvents({void Function(MockStreamHandlerEventSink sink)? onListen}) {
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => onListen?.call(sink),
      ),
    );
  }

  void mockColor(Object? Function() answer) {
    messenger.setMockMethodCallHandler(_method, (call) async {
      expect(call.method, 'SystemTheme.accentColor');
      return answer();
    });
  }

  setUp(() => mockEvents());

  tearDown(() {
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_events, null);
  });

  group('SystemThemeAccentSource', () {
    test('цвет канала — ARGB, поддержка есть', () async {
      mockColor(() => _color(0xff, 0x2d, 0x55));

      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );

      expect(source.supported, isTrue);
      expect(await source.read(), 0xFFFF2D55);
    });

    test('read() перечитывает канал: новое значение после смены', () async {
      var color = _color(0x11, 0x22, 0x33);
      mockColor(() => color);
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.linux,
      );
      expect(await source.read(), 0xFF112233);

      color = _color(0xaa, 0xbb, 0xcc);

      expect(await source.read(), 0xFFAABBCC);
    });

    test('«Плагин не отдал цвет»: ответ без цвета — маркер остаётся, read() '
        'даёт null, supported ложно', () async {
      mockColor(() => null);

      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );

      expect(source.supported, isFalse);
      expect(await source.read(), isNull);
    });

    test('MissingPluginException при старте: supported ложно, read() даёт '
        'null, запасной цвет пакета не просачивается', () async {
      // Обработчика метода нет: вызов канала бросает MissingPluginException.
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );

      expect(source.supported, isFalse);
      expect(await source.read(), isNull);
      expect(await source.read(), isNot(0xFF00B7C3));
    });

    test('исключение канала при старте не теряется и не падает: supported '
        'ложно', () async {
      mockColor(() => throw PlatformException(code: 'boom'));

      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );

      expect(source.supported, isFalse);
    });

    test('исключение канала после старта — ошибка read(), а не необработанное '
        'асинхронное исключение', () async {
      var fail = false;
      mockColor(() {
        if (fail) throw PlatformException(code: 'boom');
        return _color(1, 2, 3);
      });
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );
      fail = true;

      await expectLater(source.read(), throwsA(isA<PlatformException>()));
    });

    test('платформа вне списка пакета: supported ложно без обращения к '
        'каналу', () async {
      var calls = 0;
      mockColor(() {
        calls++;
        return _color(1, 2, 3);
      });

      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.fuchsia,
      );

      expect(source.supported, isFalse);
      expect(calls, 0);
    });

    test('первое чтение ограничено временем: зависший канал — supported '
        'ложно', () async {
      messenger.setMockMethodCallHandler(
        _method,
        (call) => Completer<Object?>().future,
      );

      final source = await SystemThemeAccentSource.start(
        timeout: const Duration(milliseconds: 50),
        platform: TargetPlatform.macOS,
      );

      expect(source.supported, isFalse);
    });

    test('на macOS changes отображает события onChange в ARGB', () async {
      MockStreamHandlerEventSink? sink;
      mockColor(() => _color(1, 2, 3));
      mockEvents(onListen: (s) => sink = s);
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.macOS,
      );
      final received = <int?>[];
      final sub = source.changes.listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      sink!.success(_color(0xff, 0x2d, 0x55));
      await Future<void>.delayed(Duration.zero);

      expect(received, contains(0xFFFF2D55));
    });

    test('на Windows changes отображает события onChange', () async {
      MockStreamHandlerEventSink? sink;
      mockColor(() => _color(1, 2, 3));
      mockEvents(onListen: (s) => sink = s);
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.windows,
      );
      final received = <int?>[];
      final sub = source.changes.listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      sink!.success(_color(9, 8, 7));
      await Future<void>.delayed(Duration.zero);

      expect(received, contains(0xFF090807));
    });

    test('на Linux changes — пустой поток: пакет выдал бы одно текущее '
        'значение', () async {
      mockColor(() => _color(1, 2, 3));
      final source = await SystemThemeAccentSource.start(
        platform: TargetPlatform.linux,
      );

      expect(source.supported, isTrue);
      await expectLater(source.changes, emitsDone);
    });
  });

  group('UnsupportedSystemAccentSource', () {
    test('supported ложно, read() даёт null, changes пуст', () async {
      const source = UnsupportedSystemAccentSource();

      expect(source.supported, isFalse);
      expect(await source.read(), isNull);
      await expectLater(source.changes, emitsDone);
    });
  });
}
