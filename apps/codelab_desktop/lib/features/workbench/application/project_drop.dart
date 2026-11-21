import 'package:path/path.dart' as p;

final _uriScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]+://');

/// Брошенная строка — абсолютный локальный путь.
///
/// Почему: `desktop_drop` на Linux отдаёт не-файловые URI как есть
/// (`https://user:token@host/…`, `smb://…`), а относительный путь разрешался
/// бы от папки процесса app. Строка не должна попасть ни в состояние, ни в
/// журналы (корневой `AGENTS.md` §10, §16; design.md change
/// `add-empty-project-screen`, D4).
///
/// Для чего: единственное правило «это путь» для `openDroppedPaths`. Строка
/// со схемой URI из двух и более символов (`scheme://`) путём не считается:
/// одна буква перед `:` — диск Windows. В стиле `posix` путь абсолютен, если
/// начинается с `/`. В стиле `windows` нужен корень с диском (`C:\`, `C:/`)
/// или UNC (`\\server\share`, `\\?\C:\`): `\x` и `/x` — путь от корня
/// текущего диска, то есть неявная папка, `C:x` — относительный путь на диске.
///
/// Как использовать: `isLocalAbsolutePath(path)` — стиль хоста;
/// [context] подменяют тесты, чтобы проверить оба стиля на любом хосте.
bool isLocalAbsolutePath(String path, {p.Context? context}) {
  final style = context ?? p.context;
  if (_uriScheme.hasMatch(path)) {
    return false;
  }
  return style.style == p.Style.windows
      ? style.rootPrefix(path).length > 1
      : style.isAbsolute(path);
}

/// Причина, по которой брошенные в окно элементы не стали проектом.
///
/// Почему закрытая иерархия, а не текст: сообщение разовое и живёт в
/// `SettingsState`, а текст на языке интерфейса строит presentation
/// (`apps/codelab_desktop/AGENTS.md`, «Локализация», вид 3; design.md change
/// `add-empty-project-screen`, D4).
///
/// Для чего: `SettingsCubit.openDroppedPaths` кладёт её в
/// `SettingsState.dropRejection`; экран «проект не выбран» показывает текст
/// в зоне перетаскивания. Как использовать: `switch` по подтипам без
/// `default`.
sealed class ProjectDropRejection {
  const ProjectDropRejection();
}

/// Брошен обычный файл (`not_a_folder`).
final class DropNotAFolder extends ProjectDropRejection {
  const DropNotAFolder(this.path);
  final String path;
}

/// Брошено больше одного элемента (`multiple`), даже если все — папки.
final class DropMultiple extends ProjectDropRejection {
  const DropMultiple(this.count);
  final int count;
}

/// Пути уже нет на диске (`missing`).
final class DropMissing extends ProjectDropRejection {
  const DropMissing(this.path);
  final String path;
}

/// У элемента нет локального пути, вид пути другой или проверка вида
/// завершилась ошибкой (`unsupported`); [path] — `null`, если пути нет.
final class DropUnsupported extends ProjectDropRejection {
  const DropUnsupported(this.path);
  final String? path;
}
