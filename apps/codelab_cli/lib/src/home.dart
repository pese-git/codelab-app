import 'dart:io';

import 'package:path/path.dart' as p;

import 'cli_args.dart';

/// Домашний каталог CodeLab на стороне CLI.
///
/// Почему: профили подключения и история ввода CLI живут между запусками в
/// том же `$CODELAB_HOME`, что журналы сессий `codelab-agent`; у kit
/// соглашения о путях нет — хранилища получают путь явно (design.md change
/// `add-codelab-cli`, D4).
///
/// Для чего: единственное место путей CLI — `profiles.json` и
/// `cli_history`.
///
/// Как использовать: `CodelabHome.resolve(environment)`; перед записью —
/// [ensureExists]. Нет ни `CODELAB_HOME`, ни домашней папки — [UsageError].
final class CodelabHome {
  const CodelabHome._(this.path);

  /// `CODELAB_HOME`, иначе `$HOME/.codelab` (`%USERPROFILE%\.codelab` на
  /// Windows).
  factory CodelabHome.resolve(Map<String, String> environment) {
    final explicit = environment['CODELAB_HOME'];
    if (explicit != null && explicit.isNotEmpty) {
      return CodelabHome._(explicit);
    }
    final userHome = environment['HOME'] ?? environment['USERPROFILE'];
    if (userHome == null || userHome.isEmpty) {
      throw const UsageError(
        'Cannot find the home folder: set CODELAB_HOME or HOME.',
      );
    }
    return CodelabHome._(p.join(userHome, '.codelab'));
  }

  final String path;

  String get profilesFile => p.join(path, 'profiles.json');

  String get historyFile => p.join(path, 'cli_history');

  /// Создаёт каталог с правами `0700`: в нём история промптов пользователя
  /// (design.md, D4). В `dart:io` нет API прав доступа, поэтому — `chmod`
  /// ОС; на Windows права не меняются.
  Future<void> ensureExists() async {
    final directory = Directory(path);
    if (await directory.exists()) {
      return;
    }
    await directory.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['700', path]);
      if (result.exitCode != 0) {
        throw FileSystemException('chmod 700 failed: ${result.stderr}', path);
      }
    }
  }
}
