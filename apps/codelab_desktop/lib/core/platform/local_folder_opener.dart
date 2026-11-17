import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Исход попытки открыть каталог в файловом менеджере ОС.
///
/// [opened] — платформа приняла каталог; [missing] — пути нет на диске или это
/// не каталог (платформа не вызывалась); [failed] — путь не абсолютный
/// (платформа не вызывалась), платформа отказала или бросила исключение;
/// [created] — каталога не было, его создали (`create: true`) и открыли
/// (change `add-settings-agents-modes`, D8, D21).
enum FolderOpenOutcome { opened, created, failed, missing }

/// Порт открытия каталога в файловом менеджере ОС.
///
/// Почему: открытие папки — platform concern (`AGENTS.md` §11,
/// `platform-integration.md`): Cubit-ы страниц не вызывают плагин напрямую, а
/// тест подставляет двойник (образец — `ExternalLinkOpener`; change
/// `add-app-skills-page`, D8; change `add-settings-agents-modes`, D8, D20.3,
/// D21).
///
/// Для чего: единственная точка, откуда путь, показанный страницей, попадает в
/// систему. Два потребителя: `SkillsSettingsCubit` («Skills & extensions») и
/// `AgentsModesCubit` («Agents & modes»: «Open folder» шапки и кнопка InfoBar
/// ошибки определения, которая открывает каталог файла). Принимает только
/// абсолютный путь каталога: файлы НЕ открываются и не запускаются — у `.md`
/// обработчиком ОС может оказаться что угодно, у исполняемых — запуск
/// (приоритет 1). Отсутствующий каталог по умолчанию не создаётся; с
/// `create: true` порт создаёт его (с родителями) — так страница определений
/// готовит `$CODELAB_HOME/agents` (Q11 (а)), и только если по пути нет никакой
/// записи, даже битой ссылки (D21). Страница навыков `create` не передаёт.
///
/// Как использовать: привязан в `app_scope.dart`
/// (`createCodeLabRootScope(localFolderOpener:)`); вызывается по нажатию
/// пользователя. Какие каталоги допустимы, решает вызывающий Cubit (путь из
/// своего состояния); порт сам отклоняет каталоги-пакеты и раскрывает ссылки.
abstract interface class LocalFolderOpener {
  /// Открывает [directory]. С [create] отсутствующий каталог (с родителями)
  /// сначала создаётся — только если по пути нет НИКАКОЙ записи: битая ссылка
  /// или файл по пути дают [FolderOpenOutcome.missing] без создания.
  Future<FolderOpenOutcome> open(String directory, {bool create = false});
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
  Future<FolderOpenOutcome> open(
    String directory, {
    bool create = false,
  }) async {
    if (directory.isEmpty || !p.isAbsolute(directory)) {
      return FolderOpenOutcome.failed;
    }
    try {
      var created = false;
      // `followLinks: false`: битая ссылка — это запись, поверх неё не создаём.
      if (create &&
          await FileSystemEntity.type(directory, followLinks: false) ==
              FileSystemEntityType.notFound) {
        try {
          await Directory(directory).create(recursive: true);
          created = true;
        } on FileSystemException {
          return FolderOpenOutcome.failed;
        }
      }
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
      if (!await launch(uri)) {
        return FolderOpenOutcome.failed;
      }
      return created ? FolderOpenOutcome.created : FolderOpenOutcome.opened;
    } on Object {
      return FolderOpenOutcome.failed;
    }
  }
}
