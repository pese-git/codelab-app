import 'package:codelab_client_io/codelab_client_io.dart'
    show CodelabHomeException, resolveCodelabHome;
import 'package:path/path.dart' as p;

/// Окружение app для профилей подключения: переменные процесса и путь к
/// `profiles.json`.
///
/// Почему: `profiles.json` общий с CLI и лежит в `$CODELAB_HOME` (design.md
/// change `add-app-settings-shell`, D7), а переменные окружения читаются и
/// для токена профиля (`ProfileSecretSource`, D15). Оба берутся из одного
/// окружения composition root — шва `createCodeLabRootScope(environment:)`, —
/// чтобы тест подставлял свой дом без правки настоящих переменных. Правило
/// пути одно на CLI и app: `resolveCodelabHome` из `codelab_client_io`
/// (находка ревью итерации 2: собственная копия не знала про ошибки `~user`).
///
/// Для чего: единственный держатель окружения для Cubit-ов настроек и
/// резолвера транспорта; виджеты окружения не видят. Встроенный агент берёт
/// путь к дому по своему правилу и этого класса не использует.
///
/// Как использовать: `ConnectionEnvironment.of(environment)`. Недопустимый
/// `CODELAB_HOME` не бросает: [profilesPath] тогда `null`, а [homeProblem] —
/// причина; composition root подставляет `UnavailableProfileStore`.
final class ConnectionEnvironment {
  const ConnectionEnvironment({
    required this.variables,
    this.profilesPath,
    this.homeProblem,
  });

  factory ConnectionEnvironment.of(Map<String, String> environment) {
    try {
      return ConnectionEnvironment(
        variables: environment,
        profilesPath: p.join(resolveCodelabHome(environment), 'profiles.json'),
      );
    } on CodelabHomeException catch (error) {
      return ConnectionEnvironment(
        variables: environment,
        homeProblem: error.message,
      );
    }
  }

  final Map<String, String> variables;

  /// Путь к `profiles.json`; `null` — [homeProblem].
  final String? profilesPath;

  /// Почему `CODELAB_HOME` недопустим; `null` — путь определён.
  final String? homeProblem;
}
