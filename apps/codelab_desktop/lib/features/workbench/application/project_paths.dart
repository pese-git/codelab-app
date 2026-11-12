import 'package:path/path.dart' as p;

/// Корень файловой системы в любом из стилей путей: `/`, `C:\`, а также
/// неканонические записи (`//`, `/.`, `/tmp/..`).
///
/// Почему: версии до change `require-project-folder` подставляли папку
/// процесса вместо невыбранного проекта, и приложение, запущенное из
/// Finder, записывало в снимок рабочего пространства проект `/`. Такой
/// «проект» нельзя восстанавливать, а сессию в корне нельзя открывать без
/// подтверждения: агент получил бы весь диск (D10, D24). Сравнение строк
/// `== '/'` пропустило бы `/tmp/..`, поэтому путь сначала нормализуется.
/// Оба стиля (`p.posix` и `p.windows`) проверяются на любом хосте: `cwd`
/// сессии удалённого агента может быть путём другой ОС (D24).
///
/// Для чего: чистая проверка для `SettingsCubit._restoreProject` и
/// подтверждения D24 в `SessionsCubit`; явный выбор корня через
/// «Open folder…» она не ограничивает.
///
/// Как использовать: `isFilesystemRoot(path)`. Для показа пользователю есть
/// [normalizedPath].
bool isFilesystemRoot(String path) =>
    _isRootIn(p.posix, path) || _isRootIn(p.windows, path);

bool _isRootIn(p.Context style, String path) {
  final normalized = style.normalize(path);
  final root = style.rootPrefix(normalized);
  return root.isNotEmpty && root == normalized;
}

/// Нормализованная запись [path] для сообщений пользователю (`/tmp/..` →
/// `/`); стиль — хоста.
String normalizedPath(String path) => p.context.normalize(path);
