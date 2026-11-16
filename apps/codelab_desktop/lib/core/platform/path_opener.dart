import 'dart:io';

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
/// Почему отдельный порт, а не `ExternalLinkOpener`: у того политика ссылок из
/// ответа агента (DSK-7), а путь из настроек — другой источник; общая политика
/// ослабила бы первую.
///
/// Для чего: единственная точка, откуда путь страницы «Agents & modes» уходит
/// в платформу. Какие пути допустимы, решает вызывающий Cubit (только файл
/// строки состояния и каталоги определений); порт лишь открывает и, если его
/// попросили, создаёт каталог.
///
/// Как использовать: привязан в `app_scope.dart`; ошибки платформы не
/// бросаются, а превращаются в [PathOpenOutcome.failed].
abstract interface class PathOpener {
  /// Открывает файл [path].
  Future<PathOpenOutcome> open(String path);

  /// Открывает каталог [path]; с [create] недостающий каталог (с родителями)
  /// сначала создаётся. Без [create] отсутствующий каталог не создаётся и
  /// даёт [PathOpenOutcome.failed].
  Future<PathOpenOutcome> openDirectory(String path, {bool create = false});
}

/// Реализация на `url_launcher`: `launchUrl(Uri.file(path))` (D8).
///
/// Как использовать: composition root создаёт один экземпляр; `launch` — шов
/// для тестов (по умолчанию `launchUrl`). Текст исключения платформы может
/// содержать путь целиком, поэтому наружу идёт только исход (`AGENTS.md` §16).
final class UrlLauncherPathOpener implements PathOpener {
  UrlLauncherPathOpener({Future<bool> Function(Uri uri)? launch})
    : _launch = launch ?? ((uri) => launchUrl(uri));

  final Future<bool> Function(Uri uri) _launch;

  @override
  Future<PathOpenOutcome> open(String path) async {
    // Файл определения — обычный `.md`; символьная ссылка, каталог и прочее
    // (`/etc/passwd` по ссылке) в платформу не уходят (D8).
    if (!path.endsWith('.md') ||
        await _typeOf(path) != FileSystemEntityType.file) {
      return PathOpenOutcome.notAllowed;
    }
    return await _launchPath(path)
        ? PathOpenOutcome.opened
        : PathOpenOutcome.failed;
  }

  @override
  Future<PathOpenOutcome> openDirectory(
    String path, {
    bool create = false,
  }) async {
    var created = false;
    switch (await _typeOf(path)) {
      case FileSystemEntityType.directory:
        break;
      case FileSystemEntityType.notFound:
        if (!create) {
          // Без разрешения создавать отсутствующий каталог не появляется (Q11).
          return PathOpenOutcome.failed;
        }
        try {
          await Directory(path).create(recursive: true);
        } on Object {
          return PathOpenOutcome.failed;
        }
        created = true;
      default:
        // Символьная ссылка и файл на месте каталога не открываются (D8).
        return PathOpenOutcome.notAllowed;
    }
    if (!await _launchPath(path)) {
      return PathOpenOutcome.failed;
    }
    return created ? PathOpenOutcome.created : PathOpenOutcome.opened;
  }

  /// Вид записи без разыменования ссылок: ссылка остаётся ссылкой.
  Future<FileSystemEntityType> _typeOf(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false);
    } on Object {
      return FileSystemEntityType.notFound;
    }
  }

  Future<bool> _launchPath(String path) async {
    try {
      return await _launch(Uri.file(path));
    } on Object {
      return false;
    }
  }
}
