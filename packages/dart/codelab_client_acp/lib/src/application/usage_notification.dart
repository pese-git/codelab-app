import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

/// Имя метода уведомления `_codelab/session/usage` (расширение CodeLab,
/// change `add-usage-extension`, D1, D8).
const usageNotificationMethod = '_codelab/session/usage';

/// Снимок расхода сессии, принятый от агента, в сыром виде.
///
/// Почему: разбор формы `_codelab/session/usage` принадлежит одной реализации
/// в ядре клиента (`UsageDecoder` в `codelab_client_core`, D8), а этот слой
/// только маршрутизирует кадр и ничего в нём не интерпретирует; поэтому
/// [params] остаются сырыми.
///
/// Для чего: запись публикует `AcpClientApplication.usageNotifications`.
/// [generation] — поколение соединения, по которому пришёл кадр: потребитель
/// сбрасывает свёртку по смене поколения, а не по началу своего `reconnect`
/// (D21 Т2: снимок старого агента может прийти в окне между ними).
///
/// Как использовать: подписаться на `usageNotifications` до `connect`;
/// запись не содержит id запроса — на уведомление ответа нет.
final class UsageNotification {
  const UsageNotification({
    required this.sessionId,
    required this.params,
    required this.generation,
  });

  /// Сессия из строкового `params.sessionId`.
  final SessionId sessionId;

  /// Параметры уведомления целиком, без разбора значений.
  final Map<String, Object?> params;

  /// Поколение соединения на момент приёма кадра.
  final int generation;
}
