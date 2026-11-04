import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;

/// Узкий интерфейс подключения для страницы «Connection».
///
/// Почему: страница настроек должна подключать окно, но не знать ни номера
/// попытки, ни проверки папки проекта, ни текстов диагностики — они уже есть в
/// `ConnectionCubit` feature `workbench`, и дублировать их нельзя (design.md
/// change `add-app-settings-shell`, D4; `layers-and-dependencies.md` §27:
/// связь между features — через application API, а не через внутренности).
///
/// Для чего: единственная точка входа `ConnectionSettingsCubit` в подключение.
/// Реализует `ConnectionCubit`; в тестах подменяется записывающим фейком.
///
/// Цель перезапуска ([restartTarget]) — единственный источник ответа «какой
/// профиль у окна»: страница берёт из неё «Current», бейдж, подпись
/// Restart/Reconnect и доступность «Restart agent». `WorkspaceState.profile`
/// для этого не годится: workspace публикует профиль уже в начале попытки, и
/// после неудачного Connect он указывал бы на профиль, который не
/// подключился, а «Restart agent» переподключил бы совсем другой (D6, D9).
///
/// Как использовать: [connect] подключает окно к [profile] и не меняет
/// профиль по умолчанию (D5); [reconnect] — тот же профиль заново, как
/// «Restart agent» (D9). Исход подключения Cubit страницы читает из
/// `WorkspaceState`, а не из возвращаемого значения.
abstract interface class ConnectionCommands {
  /// Профиль последнего принятого подключения, а до первого принятого —
  /// последний выбранный; `null` — окно ещё ни к чему не подключалось.
  ConnectionProfile? get restartTarget;

  /// Новое значение [restartTarget] при каждой его смене.
  Stream<ConnectionProfile?> get restartTargets;

  Future<void> connect(ConnectionProfile profile);

  Future<void> reconnect();
}
