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
