import 'package:url_launcher/url_launcher.dart';

/// Исход открытия пути в приложении ОС.
///
/// [created] — каталога не было, его создали и открыли (только
/// `openDirectory(create: true)`); [notAllowed] — путь не прошёл проверку
/// вызывающего (Cubit) и платформа не вызывалась.
enum PathOpenOutcome { opened, created, failed, notAllowed }

/// Порт открытия файла или каталога в приложении ОС (design.md change
/// `add-settings-agents-modes`, D8, Q8 (б), Q11).
///
/// ЗАГЛУШКА итерации 2, задача 2.1: сигнатуры зафиксированы красными тестами,
/// логики нет. Реализация — задача 2.5.
///
/// Почему отдельный порт, а не `ExternalLinkOpener`: у того политика ссылок из
/// ответа агента (DSK-7), а путь из настроек — другой источник; общая политика
/// ослабила бы первую.
abstract interface class PathOpener {
  /// Открывает файл [path].
  Future<PathOpenOutcome> open(String path);

  /// Открывает каталог [path]; с [create] недостающий каталог (с родителями)
  /// сначала создаётся. Без [create] отсутствующий каталог не создаётся.
  Future<PathOpenOutcome> openDirectory(String path, {bool create = false});
}

/// Реализация на `url_launcher`: `launchUrl(Uri.file(path))`.
///
/// Как использовать: composition root создаёт один экземпляр; `launch` — шов
/// для тестов (по умолчанию `launchUrl`). Заглушка итерации 2, задача 2.1.
final class UrlLauncherPathOpener implements PathOpener {
  UrlLauncherPathOpener({Future<bool> Function(Uri uri)? launch})
    : _launch = launch ?? ((uri) => launchUrl(uri));

  // ignore: unused_field
  final Future<bool> Function(Uri uri) _launch;

  @override
  Future<PathOpenOutcome> open(String path) =>
      throw UnimplementedError('UrlLauncherPathOpener.open: задача 2.5');

  @override
  Future<PathOpenOutcome> openDirectory(String path, {bool create = false}) =>
      throw UnimplementedError(
        'UrlLauncherPathOpener.openDirectory: задача 2.5',
      );
}
