/// Вид отказа проверки `/models` по типу ошибки `dart:io` (design.md change
/// `add-provider-setup-ui`, D8).
library;

import 'dart:io';

import '../provider/provider_check.dart';

/// Классифицирует ошибку клиента по ТИПУ, не по тексту.
///
/// Почему здесь: `TlsException` и `SocketException` — типы `dart:io`, а
/// основной барель web-безопасен и их не видит. Разбор текста запрещён (правило D12
/// change `add-app-settings-shell`): текст зависит от
/// ОС и SDK и может нести адрес.
///
/// Для чего: `ioProviderCheck` передаёт её в `HttpProviderCheck`. В `http` 1.x
/// `IOClient` оборачивает `SocketException` в `ClientException`, который сам
/// реализует `SocketException` (тип сохраняется), а `TlsException`
/// (`HandshakeException`, `CertificateException`) пробрасывается как есть.
/// Распознаётся: `TlsException` → `tlsError`; `SocketException` (отказ в
/// соединении, неразрешённое имя — различать их для вида отказа не нужно, оба
/// `unreachable`, поэтому таблица errno не требуется) → `unreachable`.
/// Остальное — `null`, и `HttpProviderCheck` берёт `unreachable` по умолчанию.
ProviderCheckFailureKind? classifyProviderCheckError(Object error) {
  if (error is TlsException) {
    return ProviderCheckFailureKind.tlsError;
  }
  if (error is SocketException) {
    return ProviderCheckFailureKind.unreachable;
  }
  return null;
}
