import 'package:codelab_desktop/core/platform/local_folder_opener.dart';

/// Двойник порта [LocalFolderOpener] для тестов app.
///
/// Почему: настоящий `url_launcher` открыл бы файловый менеджер разработчика, а
/// тесты страницы «Skills & extensions» проверяют только то, КАКОЙ каталог и
/// СКОЛЬКО раз страница передала порту (change `add-app-skills-page`, D8).
///
/// Для чего: журнал [opened] всех вызовов `open` и настраиваемый [outcome];
/// [outcomes] — очередь исходов по вызовам (сначала берётся она, потом
/// [outcome]), чтобы проверить запасной каталог при `missing`.
///
/// Как использовать: `createCodeLabRootScope(localFolderOpener: fake)` или
/// `SkillsSettingsCubit(folderOpener: fake)`; после жеста пользователя
/// проверять `fake.opened`.
final class FakeLocalFolderOpener implements LocalFolderOpener {
  FakeLocalFolderOpener({this.outcome = FolderOpenOutcome.opened});

  /// Исход вызова, когда очередь [outcomes] пуста.
  FolderOpenOutcome outcome;

  /// Исходы ближайших вызовов по порядку.
  final List<FolderOpenOutcome> outcomes = [];

  /// Каталоги всех вызовов `open` в порядке вызова.
  final List<String> opened = [];

  @override
  Future<FolderOpenOutcome> open(String directory) async {
    opened.add(directory);
    return outcomes.isEmpty ? outcome : outcomes.removeAt(0);
  }
}
