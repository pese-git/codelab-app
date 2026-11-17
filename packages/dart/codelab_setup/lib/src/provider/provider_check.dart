/// Порт проверки провайдера: список моделей `/models` (`dart-agent-and-clients`
/// §12.4.4, шаг 4; design.md change `add-provider-setup-ui`, D8).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show CancelToken;

import '../secret/secret_value.dart';

/// Умеет ли [HttpProviderCheck] проверять провайдера вида [kind].
///
/// Почему в мосте: список видов и их запросов знает `HttpProviderCheck`, а app
/// и CLI не должны дублировать его (SETUP-8). `false` у `gemini` и неизвестных
/// видов — страница делает Check неактивным с подсказкой, а не показывает
/// ложный отказ.
bool supportsProviderCheck(String kind) =>
    kind == 'openai-compatible' || kind == 'anthropic';

/// Адрес API по умолчанию для вида [kind], когда в конфиге нет `base_url`.
///
/// Почему: ядро подставляет его само (`resolve.dart`: `anthropic` и `gemini`),
/// и Check строки без `base_url` должен идти на тот же адрес, что агент. У
/// `openai-compatible` умолчания нет (`base_url` обязателен) — `null`, как и
/// у неизвестного вида. Значения — общеизвестные адреса API, а не чужой код.
Uri? defaultProviderBaseUrl(String kind) => switch (kind) {
  'anthropic' => Uri.parse('https://api.anthropic.com'),
  'gemini' => Uri.parse('https://generativelanguage.googleapis.com'),
  _ => null,
};

/// Время ожидания проверки по умолчанию (§12.4.4, шаг 4).
const defaultProviderCheckTimeout = Duration(seconds: 10);

/// Запрашивает у провайдера список моделей.
///
/// Почему порт: мастер и страница Providers тестируются на фейке, а сетевая
/// реализация — [HttpProviderCheck] поверх `http.Client` (IO-фабрика —
/// `ioProviderCheck()` в `lib/io.dart`).
///
/// Для чего: проверка «адрес живой, ключ подходит» до записи провайдера и по
/// кнопке «Check». Результат — значение, а не исключение: отказ — обычный
/// исход.
///
/// Как использовать: [key] — `SecretValue` (значение не логируется и не попадает
/// в результат); `null` — запрос без авторизации (локальные серверы). Вид
/// [kind] — значение `providers.<id>.kind` реестра: `openai-compatible` или
/// `anthropic`.
///
/// [cancel] — отмена владельцем (закрытие страницы, «Retry», «Cancel» мастера):
/// сработавший токен обрывает запрос, соединение закрывается, результат —
/// [CheckCancelled]. Отмена после результата ни на что не влияет.
abstract interface class ProviderCheck {
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  });
}

/// Итог проверки.
sealed class ProviderCheckResult {
  const ProviderCheckResult();
}

/// Запрос удался: провайдер ответил списком моделей.
final class CheckOk extends ProviderCheckResult {
  const CheckOk(this.models);

  final List<RemoteModel> models;

  @override
  String toString() => 'CheckOk(${models.length} models)';
}

/// Запрос не удался; [failure] — вид и статус без тела ответа.
final class CheckFailure extends ProviderCheckResult {
  const CheckFailure(this.failure);

  final ProviderCheckFailure failure;

  @override
  String toString() => 'CheckFailure(${failure.kind.name})';
}

/// Проверку отменил владелец ([ProviderCheck.listModels] получил сработавший
/// `cancel`).
///
/// Почему отдельный исход, а не `null` или исключение: это не отказ провайдера
/// и не ошибка, а решение вызывающего. Исход виден в `switch` без `default`, и
/// поздний результат отменённой проверки нельзя принять за ответ провайдера;
/// Cubit молча отбрасывает его (D21).
final class CheckCancelled extends ProviderCheckResult {
  const CheckCancelled();

  @override
  String toString() => 'CheckCancelled';
}

/// Модель из ответа провайдера: id и окно контекста, если провайдер его назвал.
final class RemoteModel {
  const RemoteModel(this.id, {this.contextWindow});

  final String id;
  final int? contextWindow;

  @override
  String toString() => 'RemoteModel($id)';
}

/// Вид отказа проверки (§12.4.4, шаг 4).
enum ProviderCheckFailureKind {
  /// `401` или `403`: ключ не подошёл.
  unauthorized,

  /// `404`: сервер не умеет список моделей, но адрес жив.
  notFound,

  /// Ошибка соединения: хост недоступен, порт закрыт.
  unreachable,

  /// Ответ не пришёл за отведённое время.
  timeout,

  /// Ошибка TLS: сертификат или рукопожатие.
  tlsError,

  /// Любой другой ответ: `3xx` (редирект не выполняется), `5xx`, не JSON.
  badResponse,
}

/// Отказ проверки: вид, статус HTTP и короткий текст.
///
/// Почему без тела ответа: тело ошибки может цитировать ключ или внутренности
/// провайдера; наружу идут только [kind], [statusCode] и наш фиксированный
/// [message] (SETUP-1).
final class ProviderCheckFailure {
  const ProviderCheckFailure({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final ProviderCheckFailureKind kind;

  /// Статус HTTP, если ответ получен.
  final int? statusCode;

  /// Фиксированный английский текст без значений и без тела ответа.
  final String message;

  @override
  String toString() => 'ProviderCheckFailure(${kind.name}, $message)';
}
