import 'dart:async';

import '../cancel/cancel_token.dart';
import '../config/core_config.dart' show CoreConfig;
import '../secrets/secret_lookup.dart';
import '../secrets/secret_names.dart';
import '../secrets/secret_resolver.dart';
import '../secrets/secret_template.dart';
import '../util/logger.dart';
import 'decorators/fallback.dart';
import 'decorators/retry.dart';
import 'decorators/watchdog.dart';
import 'errors.dart';
import 'event_stream.dart';
import 'model_catalog.dart' show EnvKeyRef, ProviderKeyRef, SecretKeyRef;
import 'model_ref.dart';
import 'provider_config.dart';
import 'providers/anthropic.dart';
import 'providers/openai_compatible.dart';
import 'stream_function.dart';
import 'stream_state.dart';

/// The only way for a host to get a model function (PKG-5,
/// `agent-core-architecture` §2.10): the adapter of [config] wrapped, from
/// the inside out, by `withWatchdogs` with the provider timeouts,
/// `withTransientRetry` with its policy and `withFallback` over the
/// requested model (design.md, D4). A chain of several models — the
/// `ModelRoleResolver` of stage 8 — wraps the same functions.
StreamFunction createStreamFunction(
  ProviderConfig config,
  CoreLlmServices services,
) {
  final adapter = switch (config.api) {
    ProviderApi.openaiChat => openAiCompatibleStreamFunction(config, services),
    ProviderApi.anthropicMessages => anthropicStreamFunction(config, services),
    ProviderApi.gemini => _unsupported(config, services),
  };
  final watched = withWatchdogs(
    adapter,
    connect: config.timeouts.connect,
    idle: config.timeouts.idle,
    idleReasoning: config.timeouts.idleReasoning,
    clock: services.clock,
  );
  final retried = withTransientRetry(
    watched,
    config.retry,
    clock: services.clock,
    random: services.random,
    logger: services.logger,
  );
  return (model, context, {cancel}) => withFallback(
    [model],
    (_) => retried,
    onNotice: (_) {},
  )(model, context, cancel: cancel);
}

/// A provider api without an adapter yet (Gemini — after MVP, §17.10.3).
StreamFunction _unsupported(ProviderConfig config, CoreLlmServices services) =>
    (model, context, {cancel}) => runProvider(
      model,
      cancel,
      services.clock,
      (state) async => state.fail(
        LlmErrorClass.badRequest,
        '${config.name}: provider api ${config.api.name} is not supported yet',
      ),
    );

/// Функция модели по провайдерам загруженной конфигурации.
///
/// Почему в ядре: `codelab-agent` и встроенный агент (`codelab_embedded`)
/// обязаны проецировать `CoreConfig` в [createRoutedStreamFunction] одинаково
/// (ключи, шаблоны заголовков, проблемы провайдеров). Две копии проводки
/// расходились бы молча (design.md change `add-embedded-agent-mode`, D1).
///
/// Для чего: берёт из [config] провайдеров (`CatalogProvider.config`),
/// `providerProblems` как `unavailable`, ключи (`CatalogProvider.key`) и
/// шаблоны заголовков, остальное делает [createRoutedStreamFunction].
///
/// Как использовать: хост передаёт [config] — результат загрузчика, [services]
/// — порты LLM (HTTP-клиент, часы, `Random`, логгер от хоста, PKG-6) и тот же
/// [secrets], что кладёт в `AgentCoreServices.secrets`. Результат отдаёт в
/// `buildAgentCore(streamFunction: …)`. Значения секретов хост не читает.
StreamFunction createConfiguredStreamFunction(
  CoreConfig config,
  CoreLlmServices services, {
  SecretResolver? secrets,
}) => createRoutedStreamFunction(
  [for (final provider in config.providers) provider.config],
  services,
  unavailable: config.providerProblems,
  keys: {
    for (final provider in config.providers)
      provider.config.name: ?provider.key,
  },
  headerTemplates: {
    for (final provider in config.providers)
      if (provider.headerTemplates.isNotEmpty)
        provider.config.name: provider.headerTemplates,
  },
  secrets: secrets,
);

/// Функция модели для нескольких провайдеров конфигурации (design.md change
/// `add-agent-configuration`, D11; `agent-core-architecture` §2.10).
///
/// Почему в ядре: `ModelRef.provider` уже называет провайдера (§2.12.2), а
/// конфиг даёт их несколько. Маршрут держит ядро, а не каждый хост, поэтому
/// бинарь и встроенный хост этапа 7 не повторяют его; адаптеры остаются
/// закрытыми (PKG-5).
///
/// Для чего: по одной цепочке [createStreamFunction] на провайдера, которая
/// создаётся лениво при первом запросе. Маршрут — по `model.provider`.
/// Провайдер из [unavailable] (id → причина: незаданная переменная ключа,
/// D4) отвечает ошибкой класса `auth` с текстом причины БЕЗ HTTP-запроса;
/// провайдер вне списка — `badRequest` `unknown provider <id>`.
///
/// Ключ и заголовки со ссылками на секреты разрешаются здесь, при первом
/// запросе, а не при загрузке конфига (design.md change
/// `add-agent-secret-store`, D4): загрузка — чистая функция и секреты не
/// читает. [keys] — ссылка на ключ по id провайдера (`api_key_env`,
/// `api_key_secret`), [headerTemplates] — шаблоны заголовков со
/// `${secret:…}`. Значения читает [secrets]; найденные идут в
/// `ProviderConfig` (`apiKey`, `headers`), а значит в вычистку текстов ошибок
/// провайдера. Секрет не задан или хранилище недоступно — ошибка `auth` без
/// HTTP-запроса; следующий запрос разрешает ссылку заново, цепочка
/// кэшируется только при успехе. Без [secrets] ссылка недоступна: хост
/// резолвер не передал, а окружение ядро само не читает (текст отказа:
/// `the host has no secret resolver`). Ожидание секрета идёт
/// внутри потока: отмена хода завершает его `aborted` сразу, не дожидаясь
/// хранилища (его результат всё равно наполнит кэш резолвера, D3).
///
/// Как использовать: хост передаёт `[for (final p in config.providers)
/// p.config]`, `config.providerProblems`, а `keys` и `headerTemplates` — из
/// `CatalogProvider.key` и `CatalogProvider.headerTemplates`; результат
/// отдаёт в `buildAgentCore(streamFunction: …)`. Значения секретов хост не
/// читает.
///
/// Предупреждение: если [keys] опустить, запросы пойдут без ключа (как у
/// локального сервера) — ключ из `ProviderConfig.apiKey` берётся только у
/// записи, собранной хостом вручную. Для провайдеров конфига всегда
/// передавайте `keys` из `CatalogProvider.key`.
StreamFunction createRoutedStreamFunction(
  List<ProviderConfig> providers,
  CoreLlmServices services, {
  Map<String, String> unavailable = const {},
  Map<String, ProviderKeyRef> keys = const {},
  Map<String, Map<String, SecretTemplate>> headerTemplates = const {},
  SecretResolver? secrets,
}) {
  final configs = {for (final provider in providers) provider.name: provider};
  final chains = <String, StreamFunction>{};

  // Отказ без обращения к сети: поток с одной терминальной ошибкой.
  StreamFunction fail(LlmErrorClass errorClass, String message) =>
      (model, context, {cancel}) => runProvider(
        model,
        cancel,
        services.clock,
        (state) async => state
          ..start()
          ..fail(errorClass, message),
      );

  // Отменённый токен: `runProvider` сам завершает поток `aborted` (LLM-7).
  final aborted = fail(LlmErrorClass.aborted, 'Request was aborted');

  Future<StreamFunction> target(ModelRef model, CancelToken? cancel) async {
    final name = model.provider;
    if (unavailable[name] case final reason?) {
      return fail(LlmErrorClass.auth, reason);
    }
    final config = configs[name];
    if (config == null) {
      return fail(LlmErrorClass.badRequest, 'unknown provider $name');
    }
    if (chains[name] case final chain?) {
      return chain;
    }
    final key = keys[name];
    final templates = headerTemplates[name] ?? const {};
    if (key == null && templates.isEmpty) {
      return chains[name] = createStreamFunction(config, services);
    }
    final pending = _resolveSecrets(config, key, templates, secrets);
    // Первым из двух: значения секретов или отмена хода (D4).
    final resolved = cancel == null
        ? await pending
        : await Future.any<_ResolvedProvider?>([
            pending,
            cancel.onCancel.then((_) => null),
          ]);
    if (resolved == null) {
      return aborted;
    }
    if (resolved.failure case final message?) {
      return fail(LlmErrorClass.auth, message);
    }
    // Два одновременных первых запроса получили значения из одного
    // обращения (single-flight резолвера); цепочку строит первый, второй её
    // берёт.
    return chains.putIfAbsent(
      name,
      () => createStreamFunction(resolved.config!, services),
    );
  }

  return (model, context, {cancel}) {
    final out = AssistantMessageEventStream();
    scheduleMicrotask(() async {
      try {
        final chain = await target(model, cancel);
        await for (final event in chain(model, context, cancel: cancel)) {
          out.push(event);
        }
      } on Object catch (error) {
        // Сбой самого маршрутизатора (не провайдера): без терминального
        // события потребитель хода увидел бы `StateError` вместо причины.
        // В текст идёт только тип: сообщение исключения могло нести
        // значение секрета.
        services.logger.log(
          LogLevel.error,
          'llm.stream.failed',
          fields: {
            'provider': model.provider,
            'error_type': '${error.runtimeType}',
          },
        );
        await for (final event in fail(
          LlmErrorClass.unknown,
          '${model.provider}: ${error.runtimeType}',
        )(model, context)) {
          out.push(event);
        }
      } finally {
        out.end();
      }
    });
    return out;
  };
}

/// Итог разрешения ссылок провайдера: готовая конфигурация или текст отказа.
final class _ResolvedProvider {
  const _ResolvedProvider.ok(ProviderConfig this.config) : failure = null;
  const _ResolvedProvider.failed(String this.failure) : config = null;

  final ProviderConfig? config;
  final String? failure;
}

/// Читает ключ и значения заголовков через [secrets]; не бросает исключений.
///
/// Тексты отказов: секрет не задан — команда `codelab secret set`;
/// хранилище недоступно — бэкенд, причина и переменная переопределения
/// (agent-secrets «Ключ провайдера при запросе»). Значения в них не попадают.
Future<_ResolvedProvider> _resolveSecrets(
  ProviderConfig config,
  ProviderKeyRef? key,
  Map<String, SecretTemplate> templates,
  SecretResolver? secrets,
) async {
  const noResolver = 'the host has no secret resolver';
  final id = config.name;
  String? apiKey;
  final rawValues = <String>[];
  switch (key) {
    case null:
      break;
    case EnvKeyRef(:final variable):
      if (secrets == null) {
        return _ResolvedProvider.failed(
          'API key variable $variable cannot be read: $noResolver',
        );
      }
      final lookup = secrets.env(
        variable,
        purpose: 'providers.$id.api_key_env',
      );
      switch (lookup) {
        case SecretFound(:final value):
          apiKey = value;
        case SecretMissing():
          return _ResolvedProvider.failed(
            'API key variable $variable is not set',
          );
        case SecretUnavailable(:final backend, :final reason):
          return _ResolvedProvider.failed(
            'API key variable $variable cannot be read: $backend is '
            'unavailable ($reason)',
          );
      }
    case SecretKeyRef(:final name):
      if (secrets == null) {
        return _ResolvedProvider.failed(
          'API key secret $name cannot be read: $noResolver',
        );
      }
      final lookup = await secrets.secret(
        name,
        purpose: 'providers.$id.api_key_secret',
      );
      switch (lookup) {
        case SecretFound(:final value):
          apiKey = value;
        case SecretMissing():
          return _ResolvedProvider.failed(
            'API key secret $name is not set. Run: codelab secret set $name',
          );
        case SecretUnavailable(:final backend, :final reason):
          return _ResolvedProvider.failed(
            'API key secret $name cannot be read: $backend is unavailable '
            '($reason). Set ${SecretNames.envOverride(name)} or fix the '
            'secret store',
          );
      }
  }
  final headers = {...config.headers};
  for (final MapEntry(key: header, value: template) in templates.entries) {
    final values = <String, String>{};
    for (final name in template.names) {
      final path = 'providers.$id.headers.$header';
      if (secrets == null) {
        return _ResolvedProvider.failed(
          'secret $name cannot be read ($path): $noResolver',
        );
      }
      final lookup = await secrets.secret(name, purpose: path);
      switch (lookup) {
        case SecretFound(:final value):
          values[name] = value;
          rawValues.add(value);
        case SecretMissing():
          return _ResolvedProvider.failed(
            'secret $name is not set ($path). Run: codelab secret set $name',
          );
        case SecretUnavailable(:final backend, :final reason):
          return _ResolvedProvider.failed(
            'secret $name cannot be read ($path): $backend is unavailable '
            '($reason). Set ${SecretNames.envOverride(name)} or fix the '
            'secret store',
          );
      }
    }
    headers[header] = template.render(values);
  }
  return _ResolvedProvider.ok(
    config.copyWith(apiKey: apiKey, headers: headers, extraSecrets: rawValues),
  );
}
