import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:path/path.dart' as p;

import 'cli_args.dart';
import 'input/history.dart';

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
  ///
  /// Правило общее с app и живёт в `resolveCodelabHome` (`codelab_client_io`,
  /// design.md change `add-app-settings-shell`, D7): CLI лишь переводит
  /// [CodelabHomeException] в [UsageError] с тем же текстом (код `64`).
  /// Агентский `codelabHomeOf` (D17) даёт тот же результат; CLI не импортирует
  /// `codelab_agent_*`.
  factory CodelabHome.resolve(Map<String, String> environment) {
    try {
      return CodelabHome._(resolveCodelabHome(environment));
    } on CodelabHomeException catch (error) {
      throw UsageError(error.message);
    }
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

/// История ввода REPL в файле `$CODELAB_HOME/cli_history` (U-07).
///
/// Почему: промпты пользователя могут содержать то, что не должны читать
/// другие пользователи машины, поэтому файл создаётся с правами `0600` до
/// записи содержимого (design.md change `add-codelab-cli`, D4).
///
/// Как использовать: `HistoryFile(home.historyFile)`; REPL загружает историю
/// при старте и сохраняет после каждой отправки. Формат — `encodeHistory`.
final class HistoryFile implements HistoryStore {
  const HistoryFile(this.path);

  final String path;

  @override
  Future<List<String>> load() async {
    final file = File(path);
    if (!await file.exists()) {
      return const [];
    }
    return decodeHistory(await file.readAsString());
  }

  @override
  Future<void> save(List<String> entries) async {
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', path]);
        if (result.exitCode != 0) {
          throw FileSystemException('chmod 600 failed: ${result.stderr}', path);
        }
      }
    }
    await file.writeAsString(encodeHistory(entries), flush: true);
  }
}
