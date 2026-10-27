import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection_view.freezed.dart';

/// Состояние соединения рабочего пространства — явный конечный автомат.
///
/// Почему: набор флагов `isConnected`/`isConnecting`/`hasError` допускает
/// невозможные сочетания (`AGENTS.md` §8); закрытая иерархия заставляет UI
/// и CLI разобрать каждое состояние (spec acp-client-kit «Явный автомат
/// соединения»).
///
/// Для чего: поле `WorkspaceState.connection`. Переходы:
/// `Disconnected` → `Connecting` → `Connected` | `ConnectionFailed`;
/// `reconnect()` → `Reconnecting` → `Connected` | `ConnectionFailed`;
/// неожиданный сбой транспорта в `Connected` → `ConnectionLost`, откуда
/// `reconnect()` идёт так же, как из `ConnectionFailed`.
///
/// Как использовать: `switch (state.connection)` в отображении; сравнение
/// по значению (`==`) — так подписчик отличает новое состояние от повтора.
@freezed
sealed class ConnectionView with _$ConnectionView {
  const ConnectionView._();

  const factory ConnectionView.disconnected() = Disconnected;

  const factory ConnectionView.connecting() = Connecting;

  const factory ConnectionView.connected() = Connected;

  /// Идёт переподключение; [attempt] начинается с 1. Сейчас попытка одна,
  /// повторы с паузами — change `add-session-list-and-reload` (design D4).
  const factory ConnectionView.reconnecting({required int attempt}) =
      Reconnecting;

  /// Установленное соединение оборвалось без вызова `connect()` или
  /// `reconnect()` — например, процесс агента завершился.
  ///
  /// Отдельный вариант, а не флаг в [ConnectionView.failed]: пользователь
  /// работал в ленте, и UI показывает над ней баннер с Reconnect, а не
  /// результат только что нажатой кнопки (design D1 change
  /// `add-connection-and-error-states`). [message] — причина от транспорта.
  const factory ConnectionView.lost({
    required ConnectionFailureReason reason,
    required String message,
  }) = ConnectionLost;

  /// Попытка `connect()` или `reconnect()` не удалась; [message] — текст
  /// для пользователя от ядра клиента или kit.
  const factory ConnectionView.failed({
    required ConnectionFailureReason reason,
    required String message,
  }) = ConnectionFailed;
}
