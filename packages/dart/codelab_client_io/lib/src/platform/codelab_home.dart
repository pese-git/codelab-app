import 'package:path/path.dart' as p;

/// Ошибка вычисления `$CODELAB_HOME`: значение переменной нельзя превратить в
/// путь.
///
/// Почему: общая функция не знает о `UsageError` CLI или о странице настроек
/// app; хост сам выбирает, как показать причину (CLI — код `64`, app — текст
/// на странице). [message] — готовый текст без секретов.
final class CodelabHomeException implements Exception {
  const CodelabHomeException(this.message);

  final String message;

  @override
  String toString() => 'CodelabHomeException: $message';
}

/// Вычисляет `$CODELAB_HOME` — каталог, общий для CLI, app и агента.
///
/// Почему: `profiles.json` общий у CLI и app (design.md change
/// `add-app-settings-shell`, D7), поэтому правило пути обязано быть одним:
/// три копии расходились (app не знал про ошибки `~user`).
///
/// Для чего: единственная реализация правила в клиентском слое; CLI
/// (`CodelabHome.resolve`) и app вызывают её. Агент (`codelabHomeOf` в
/// `codelab_agent_io`) остаётся отдельным: клиенты не импортируют
/// `codelab_agent_*`.
///
/// Как использовать: `resolveCodelabHome(Platform.environment)`. Правило:
/// * `CODELAB_HOME` непуст — берётся он; `~` и `~/…` раскрываются через
///   `HOME`, затем `USERPROFILE` (оболочка не раскрывает тильду в кавычках);
/// * `CODELAB_HOME` пуст или не задан — `<HOME|USERPROFILE>/.codelab`.
///
/// Ошибка [CodelabHomeException]: любое значение на `~`, кроме `~` и `~/…`
/// (`~user/…`); `~` без домашнего каталога; нет ни `CODELAB_HOME`, ни
/// домашнего каталога.
String resolveCodelabHome(Map<String, String> environment) {
  final userHome = [
    environment['HOME'],
    environment['USERPROFILE'],
  ].firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
  final explicit = environment['CODELAB_HOME'];
  if (explicit != null && explicit.isNotEmpty) {
    if (explicit.length > 1 && explicit.startsWith('~') && explicit[1] != '/') {
      throw const CodelabHomeException(
        'CODELAB_HOME: ~user is not supported, use an absolute path',
      );
    }
    if (explicit == '~' || explicit.startsWith('~/')) {
      if (userHome == null) {
        throw const CodelabHomeException(
          'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an '
          'absolute path',
        );
      }
      return explicit == '~'
          ? userHome
          : p.join(userHome, explicit.substring(2));
    }
    return explicit;
  }
  if (userHome == null) {
    throw const CodelabHomeException(
      'Cannot find the home folder: set CODELAB_HOME or HOME.',
    );
  }
  return p.join(userHome, '.codelab');
}
