/// Проверка `/models` поверх `http.Client` (`dart-agent-and-clients` §12.4.4,
/// шаг 4; design.md change `add-provider-setup-ui`, D8; SETUP-10, SETUP-23).
library;

import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show CancelToken, CancelledException, LogLevel, Logger, raceCancel;
import 'package:http/http.dart' as http;

import '../secret/secret_value.dart';
import 'provider_check.dart';

/// Предел тела успешного ответа: список моделей агрегаторов не больше нескольких
/// сотен килобайт, а бесконечный ответ не должен занять память.
const _maxBodyBytes = 8 * 1024 * 1024;

/// Версия API Anthropic для заголовка `anthropic-version` (та же, что у
/// провайдера ядра по умолчанию).
const _anthropicVersion = '2023-06-01';

/// Проверка списка моделей по HTTP.
///
/// Почему поверх `http.Client`, а не `dart:io`: класс живёт в основном бареле
/// моста и остаётся web-безопасным (`melos run web-compile`); `IOClient`
/// подставляет только `lib/io.dart` (`ioProviderCheck`). Клиент создаётся на
/// КАЖДУЮ проверку и закрывается по её окончании, поэтому таймаут и отмена
/// закрывают соединение, а не просто перестают его ждать.
///
/// Для чего: единственная сетевая проверка мастера и страницы Providers.
/// Безопасность (SETUP-10, SETUP-23, SETUP-1):
/// - запрос идёт только на введённый адрес и НЕ следует редиректам: ответ `3xx`
///   даёт `badResponse` со статусом, иначе заголовок `Authorization` или
///   `x-api-key` ушёл бы на другой хост;
/// - ключ уходит только в заголовке авторизации и не попадает ни в результат,
///   ни в журнал; тело ответа об ошибке не читается и не попадает в результат;
/// - в журнале — только `scheme://host:port`, без пути, query и userinfo.
///
/// Как использовать: `HttpProviderCheck(() => http.Client(...))` в тестах
/// (`MockClient`) и `ioProviderCheck()` в composition root; `listModels` не
/// бросает исключений для сетевых отказов — они становятся [CheckFailure].
final class HttpProviderCheck implements ProviderCheck {
  HttpProviderCheck(
    this._clientFactory, {
    Logger? logger,
    ProviderCheckFailureKind? Function(Object error)? classifier,
  }) : _logger = logger,
       _classifier = classifier;

  final http.Client Function() _clientFactory;

  /// Вид отказа по типу ошибки клиента; `null` — не распознана. Типы
  /// `dart:io` основной барель назвать не может, поэтому классификатор
  /// приходит из `io.dart` (`ioProviderCheck`); текст ошибки не разбирается.
  final ProviderCheckFailureKind? Function(Object error)? _classifier;
  final Logger? _logger;

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) async {
    final origin = _originOf(baseUrl);
    if (cancel != null && cancel.isCancelled) {
      return _done(origin, kind, const CheckCancelled());
    }
    final request = _requestFor(kind, baseUrl, key);
    if (request == null) {
      return _done(
        origin,
        kind,
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.badResponse,
            message:
                'the model list check is not supported for this '
                'provider kind',
          ),
        ),
      );
    }
    final client = _clientFactory();
    try {
      final work = _fetch(client, request).timeout(timeout);
      // `raceCancel` отбрасывает поздний итог `work`; соединение закрывает
      // `finally` ниже, поэтому запрос не висит до таймаута.
      final result = cancel == null
          ? await work
          : await raceCancel(work, cancel);
      return _done(origin, kind, result);
    } on CancelledException {
      return _done(origin, kind, const CheckCancelled());
    } on TimeoutException {
      return _done(
        origin,
        kind,
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.timeout,
            message: 'no response in time',
          ),
        ),
      );
    } on Object catch (error) {
      // Текст исключения не используется: `ClientException` цитирует адрес, а
      // чужие исключения — что угодно. Вид даёт только классификатор по типу.
      final failureKind =
          _classifier?.call(error) ?? ProviderCheckFailureKind.unreachable;
      return _done(
        origin,
        kind,
        CheckFailure(
          ProviderCheckFailure(
            kind: failureKind,
            message: switch (failureKind) {
              ProviderCheckFailureKind.tlsError => 'TLS handshake failed',
              _ => 'cannot connect',
            },
          ),
        ),
      );
    } finally {
      // Закрытие обрывает и незавершённый запрос после таймаута: соединение не
      // остаётся висеть до сборки мусора.
      client.close();
    }
  }

  /// `null` — вид без поддерживаемой проверки.
  http.Request? _requestFor(String kind, Uri baseUrl, SecretValue? key) {
    final String suffix;
    final headers = <String, String>{'accept': 'application/json'};
    switch (kind) {
      case 'openai-compatible':
        suffix = 'models';
        if (key != null && !key.isEmpty) {
          headers['Authorization'] = 'Bearer ${key.reveal()}';
        }
      case 'anthropic':
        suffix = 'v1/models';
        if (key != null && !key.isEmpty) {
          headers['x-api-key'] = key.reveal();
        }
        headers['anthropic-version'] = _anthropicVersion;
      default:
        return null;
    }
    final trimmed = baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    final url = baseUrl.replace(path: '$trimmed/$suffix').removeFragment();
    return http.Request('GET', url)
      ..headers.addAll(headers)
      // SETUP-23: ключ не должен уйти на адрес из `Location`.
      ..followRedirects = false
      ..maxRedirects = 0;
  }

  Future<ProviderCheckResult> _fetch(
    http.Client client,
    http.Request request,
  ) async {
    final response = await client.send(request);
    final status = response.statusCode;
    if (status != 200) {
      // Тело не читается: оно может цитировать ключ (SETUP-1).
      return CheckFailure(_failureFor(status));
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBodyBytes) {
        return const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.badResponse,
            statusCode: 200,
            message: 'the response is too large',
          ),
        );
      }
    }
    final models = _parseModels(bytes);
    if (models == null) {
      return const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.badResponse,
          statusCode: 200,
          message: 'the response is not a model list',
        ),
      );
    }
    return CheckOk(models);
  }

  ProviderCheckFailure _failureFor(int status) => switch (status) {
    401 || 403 => ProviderCheckFailure(
      kind: ProviderCheckFailureKind.unauthorized,
      statusCode: status,
      message: 'the provider rejected the key (HTTP $status)',
    ),
    404 => ProviderCheckFailure(
      kind: ProviderCheckFailureKind.notFound,
      statusCode: status,
      message: 'the provider has no model list at this address (HTTP 404)',
    ),
    >= 300 && < 400 => ProviderCheckFailure(
      kind: ProviderCheckFailureKind.badResponse,
      statusCode: status,
      message:
          'the address redirects (HTTP $status); redirects are not '
          'followed',
    ),
    _ => ProviderCheckFailure(
      kind: ProviderCheckFailureKind.badResponse,
      statusCode: status,
      message: 'unexpected response (HTTP $status)',
    ),
  };

  /// `data[].id` с окном контекста; `null` — ответ не похож на список.
  List<RemoteModel>? _parseModels(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final data = decoded['data'];
    if (data is! List<Object?>) {
      return null;
    }
    final models = <RemoteModel>[];
    for (final item in data) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final id = item['id'];
      if (id is! String || id.isEmpty) {
        continue;
      }
      models.add(RemoteModel(id, contextWindow: _contextWindow(item)));
    }
    return models;
  }

  int? _contextWindow(Map<String, Object?> item) {
    for (final name in const [
      'context_length',
      'context_window',
      'max_context_length',
    ]) {
      final value = item[name];
      if (value is int && value > 0) {
        return value;
      }
    }
    return null;
  }

  ProviderCheckResult _done(
    String origin,
    String kind,
    ProviderCheckResult result,
  ) {
    _logger?.log(
      LogLevel.info,
      'provider_check.result',
      fields: {
        'origin': origin,
        'kind': kind,
        'outcome': switch (result) {
          CheckOk() => 'ok',
          CheckCancelled() => 'cancelled',
          CheckFailure(:final failure) => failure.kind.name,
        },
        if (result is CheckFailure && result.failure.statusCode != null)
          'status': result.failure.statusCode,
        if (result is CheckOk) 'models': result.models.length,
      },
    );
    return result;
  }

  /// `scheme://host:port` без userinfo, пути и query (D8).
  String _originOf(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';
}
