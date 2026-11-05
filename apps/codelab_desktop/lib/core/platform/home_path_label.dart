import 'package:path/path.dart' as p;

/// Путь [path] для показа пользователю: домашний каталог сокращён до `~`.
///
/// Почему одна функция: подзаголовок диалога «Add connection profile»
/// («Saved to ~/.codelab/profiles.json …») и подсказка хранилища секретов
/// только для чтения («… to ~/.codelab/config.yaml …») должны называть пути
/// одинаково, а не один сокращённо, другой полностью.
///
/// Для чего: сокращает по `HOME` (или `USERPROFILE`) из [environment] и
/// правилам разделителя ОС (`package:path`): на Windows это `\`, и простое
/// `startsWith('$home/')` не сработало бы. Путь вне домашнего каталога или без
/// `HOME` возвращается как есть.
///
/// Как использовать: `homePathLabel(path, environment)`; [environment] — то
/// же окружение composition root, что у `ConnectionEnvironment`.
String homePathLabel(String path, Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (home != null && home.isNotEmpty && p.isWithin(home, path)) {
    return '~${p.separator}${p.relative(path, from: home)}';
  }
  return path;
}
