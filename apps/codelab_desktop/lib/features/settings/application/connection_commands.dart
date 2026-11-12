import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;

/// Узкий интерфейс подключения для страницы «Connection».
///
/// Почему: страница настроек должна выбирать профиль и перезапускать агента,
/// но не знать ни номера попытки, ни проверки папки проекта, ни текстов
/// диагностики — они уже есть в `ConnectionCubit` feature `workbench`, и
/// дублировать их нельзя (design.md change `add-app-settings-shell`, D4;
/// `layers-and-dependencies.md` §27: связь между features — через application
/// API, а не через внутренности).
///
/// Для чего: единственная точка входа `ConnectionSettingsCubit` в соединение.
/// Реализует `ConnectionCubit`; в тестах подменяется записывающим фейком.
/// Ручного подключения и «Disconnect» нет: агент стартует по триггерам, а
/// «Use» только выбирает профиль для следующего старта (design.md change
/// `require-project-folder`, D13, D18).
///
/// Два профиля окна раздельно (D18): [restartTarget] — выбранный («Selected»),
/// [runningProfile] — профиль работающего агента («Current»).
/// `WorkspaceState.profile` для этого не годится: workspace публикует профиль
/// уже в начале попытки, и после неудачной попытки он указывал бы на профиль,
/// который не подключился.
///
/// Как использовать: [use] выбирает профиль и не трогает агента и профиль по
/// умолчанию (D5); [restart] — единственный перезапуск «Restart agent» с
/// подтверждением при работе (D22). Исход читается из `WorkspaceState`, а не
/// из возвращаемого значения.
abstract interface class ConnectionCommands {
  /// Выбранный профиль окна («Selected»): профиль следующего старта и
  /// перезапуска.
  ConnectionProfile? get restartTarget;

  /// Профиль работающего агента («Current»); `null` — агент ещё не стартовал.
  ConnectionProfile? get runningProfile;

  /// Корень процесса для «Restart agent» (D18, Q27); `null` — перезапускать
  /// некуда: нет ни проекта, ни прежнего корня.
  String? get restartDirectory;

  /// Сигнал смены выбранного или работающего профиля.
  Stream<ConnectionProfile?> get restartTargets;

  /// «Use»: выбрать [profile] для следующего старта.
  Future<void> use(ConnectionProfile profile);

  /// «Restart agent» / «Reconnect» (D22).
  Future<void> restart();
}
