import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Исход попытки открыть каталог в файловом менеджере ОС.
///
/// [opened] — платформа приняла каталог; [missing] — пути нет на диске или это
/// не каталог (платформа не вызывалась); [failed] — путь не абсолютный
/// (платформа не вызывалась), платформа отказала или бросила исключение.
enum FolderOpenOutcome { opened, failed, missing }

/// Порт открытия каталога в файловом менеджере ОС.
///
/// Почему: открытие папки — platform concern (`AGENTS.md` §11,
/// `platform-integration.md`): Cubit страницы «Skills & extensions» не вызывает
/// плагин напрямую, а тест подставляет двойник (образец — `ExternalLinkOpener`;
/// change `add-app-skills-page`, D8).
///
/// Для чего: единственная точка, откуда путь, показанный страницей, попадает в
/// систему. Принимает только абсолютный путь существующего каталога: файлы НЕ
/// открываются и не запускаются — у `.md` обработчиком ОС может оказаться что
/// угодно, у исполняемых файлов — запуск (приоритет 1).
///
/// Как использовать: привязан в `app_scope.dart`
/// (`createCodeLabRootScope(localFolderOpener:)`); вызывает
/// `SkillsSettingsCubit` по нажатию пользователя.
abstract interface class LocalFolderOpener {
  Future<FolderOpenOutcome> open(String directory);
}

/// Реализация на `url_launcher` (единственное место его вызова для каталогов).
///
/// Почему не просто «каталог существует»: на macOS каталоги `.app`,
/// `.workflow`, `.pkg`, `.prefPane` `launchUrl` ЗАПУСКАЕТ, а не показывает, на
/// Windows `name.{GUID}` — объект оболочки. Путь приходит из файлов проекта и
/// пользователя (имя каталога навыка, симлинк `.codelab → x.app`), то есть
/// недоверен (ревью итерации 4 change `add-app-skills-page`, приоритет 1).
///
/// Что делает: (1) разрешает симлинки (`resolveSymbolicLinks`), (2) отказывает
/// [FolderOpenOutcome.failed], если у имени разрешённого каталога есть
/// расширение (`.codelab` и `.agents` — не расширение) или `{…}`-суффикс,
/// (3) передаёт платформе уже РАЗРЕШЁННЫЙ путь, а не исходный. Проверку
/// абсолютности и существования делает сама: вторая линия защиты на случай
/// ошибки вызывающего. Исключение платформы даёт [FolderOpenOutcome.failed]
/// без текста: он может содержать путь целиком (`AGENTS.md` §16).
///
/// Остаточный риск: гонка TOCTOU. Если между проверкой и запуском кто-то
/// подменит САМ реальный каталог (переименует, заменит на пакет), проверка
/// этого не заметит; закрыть это в Dart без дескрипторов ОС нельзя.
final class UrlLauncherLocalFolderOpener implements LocalFolderOpener {
  const UrlLauncherLocalFolderOpener({Future<bool> Function(Uri uri)? launch})
    : _launch = launch;

  /// Шов тестов; по умолчанию внешнее приложение ОС.
  final Future<bool> Function(Uri uri)? _launch;

  /// Суффикс `{…}` имени: объект оболочки Windows (`name.{GUID}`).
  static final _shellObject = RegExp(r'\{[^{}]*\}$');

  @override
  Future<FolderOpenOutcome> open(String directory) async {
    if (directory.isEmpty || !p.isAbsolute(directory)) {
      return FolderOpenOutcome.failed;
    }
    try {
      final String resolved;
      try {
        resolved = await Directory(directory).resolveSymbolicLinks();
      } on FileSystemException {
        return FolderOpenOutcome.missing;
      }
      // Симлинк на файл разрешается в файл: каталогом он не является.
      if (!await Directory(resolved).exists()) {
        return FolderOpenOutcome.missing;
      }
      final name = p.basename(resolved);
      if (p.extension(name).isNotEmpty || _shellObject.hasMatch(name)) {
        return FolderOpenOutcome.failed;
      }
      // `file://` со слэшем в конце: ОС открывает именно каталог.
      final uri = Uri.directory(resolved).replace(scheme: 'file');
      final launch =
          _launch ??
          (Uri target) =>
              launchUrl(target, mode: LaunchMode.externalApplication);
      return await launch(uri)
          ? FolderOpenOutcome.opened
          : FolderOpenOutcome.failed;
    } on Object {
      return FolderOpenOutcome.failed;
    }
  }
}
