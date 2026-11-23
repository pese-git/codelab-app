// Общая настройка e2e-тестов app: Flutter подхватывает этот файл для каждого
// теста в `integration_test/`.

import 'dart:async';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Перед каждым тестом подменяет `SharedPreferences` пустым хранилищем в памяти.
///
/// Почему: e2e-тесты запускают тот же бандл, что и настоящее app, и на macOS
/// делят с ним `NSUserDefaults`. Без подмены снимок рабочего пространства
/// прошлого теста выбирал бы его проект и восстанавливал его сессии (design D8
/// change `add-session-list-and-reload`). Недавние проекты в `NSUserDefaults`
/// больше не живут: они в `recent_projects.json` временного `CODELAB_HOME`
/// теста (change `share-recent-projects-store`, D7).
///
/// Для чего: каждый тест начинает с чистых настроек и не трогает настройки
/// пользователя. Хранилище в памяти живёт до следующего `setUp`, поэтому тест
/// перезапуска, пересобирающий `Scope` внутри одного теста, по-прежнему
/// проверяет, что данные переживают `Scope`.
///
/// Ещё перед каждым тестом задаёт окну логический размер [e2eWindowSize].
/// Почему: окно app по умолчанию — 800×600 (`MainMenu.xib`), это класс
/// `narrow`, где сайдбар уходит в выдвижное меню (`CodeLabLayoutClass`,
/// порог `mediumMinWidth`), и тесты, которые нажимают кнопки сайдбара и
/// дока, зависели бы от размера окна на машине разработчика. Размер меняется
/// у настоящего окна через канал `codelab/e2e_window` (`MainFlutterWindow`,
/// только debug), а не подменой `physicalSize` вида: подмена расходилась с
/// поверхностью окна, и на macOS окно было чёрным весь тест.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() async {
    // Язык `en` задан явно: приёмка не зависит от языка машины
    // (add-desktop-localization, D9).
    SharedPreferences.setMockInitialValues({'codelab.app.language': 'en'});
    await _resizeWindow(e2eWindowSize);
  });
  // Закрывает корневой scope Cherrypick после каждого теста, в том числе
  // упавшего до своего `closeCodeLabRootScope()`. Почему: `CodeLabBootstrap`
  // с готовым `scope` при размонтировании освобождает только его, а
  // статический корень `CherryPick` остаётся; следующий тест файла получал
  // этот уже отработавший корень и падал вторичной ошибкой «Can't resolve
  // dependency `CodeLabRootLifecycle`», маскируя исходное падение. Повторное
  // закрытие после теста, закрывшего корень сам, безопасно.
  tearDown(() async {
    await closeCodeLabRootScope();
  });
  await testMain();
}

/// Логический размер окна e2e-тестов: класс `wide` (от 1280), сайдбар и док
/// стоят колонками, как на типичном экране ноутбука.
const e2eWindowSize = Size(1440, 900);

const _windowChannel = MethodChannel('codelab/e2e_window');

/// Просит платформу поменять размер окна и ждёт, пока Flutter получит новые
/// метрики вида (не дольше 5 с). Если экран меньше [size], macOS ужмёт окно,
/// и тест упадёт на ожидании с понятной причиной, а не на поиске кнопки.
Future<void> _resizeWindow(Size size) async {
  await _windowChannel.invokeMethod<void>('setContentSize', {
    'width': size.width,
    'height': size.height,
  });
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  Size logical() => view.physicalSize / view.devicePixelRatio;
  while (logical() != size && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (logical() != size) {
    throw StateError(
      'e2e window is ${logical()}, expected $size: the screen may be too small',
    );
  }
}
