// Общая настройка e2e-тестов app: Flutter подхватывает этот файл для каждого
// теста в `integration_test/`.

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Перед каждым тестом подменяет `SharedPreferences` пустым хранилищем в памяти.
///
/// Почему: e2e-тесты запускают тот же бандл, что и настоящее app, и на macOS
/// делят с ним `NSUserDefaults`. Без подмены тесты дописывали временные папки
/// в список недавних проектов пользователя, а снимок рабочего пространства
/// прошлого теста выбирал бы его проект и восстанавливал его сессии (design D8
/// change `add-session-list-and-reload`).
///
/// Для чего: каждый тест начинает с чистых настроек и не трогает настройки
/// пользователя. Хранилище в памяти живёт до следующего `setUp`, поэтому тест
/// перезапуска, пересобирающий `Scope` внутри одного теста, по-прежнему
/// проверяет, что данные переживают `Scope`.
///
/// Ещё перед каждым тестом задаёт логический размер окна [e2eWindowSize].
/// Почему: окно app по умолчанию — 800×600 (`MainMenu.xib`), это класс
/// `narrow`, где сайдбар уходит в выдвижное меню (`CodeLabLayoutClass`,
/// порог `mediumMinWidth`), и тесты, которые нажимают кнопки сайдбара и
/// дока, зависели бы от размера окна на машине разработчика. Размер
/// задаётся у вида теста и после теста сбрасывается.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = e2eWindowSize * view.devicePixelRatio;
    addTearDown(view.resetPhysicalSize);
  });
  await testMain();
}

/// Логический размер окна e2e-тестов: класс `wide` (от 1280), сайдбар и док
/// стоят колонками, как на типичном экране ноутбука.
const e2eWindowSize = Size(1440, 900);
