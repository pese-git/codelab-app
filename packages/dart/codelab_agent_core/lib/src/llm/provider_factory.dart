import 'decorators/fallback.dart';
import 'decorators/retry.dart';
import 'decorators/watchdog.dart';
import 'errors.dart';
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
/// Провайдер из [unavailable] (id → причина: ключ не задан, секрет не
/// читается, D8) отвечает ошибкой класса `auth` с текстом причины БЕЗ
/// HTTP-запроса; провайдер вне списка — `badRequest` `unknown provider <id>`.
///
/// Как использовать: хост передаёт `[for (final p in config.providers)
/// p.config]` и `config.providerProblems`, а результат отдаёт в
/// `buildAgentCore(streamFunction: …)`. Ключ `api_key_env` уже разрешён в
/// `ProviderConfig.apiKey` при загрузке конфига, хосту его читать не нужно.
StreamFunction createRoutedStreamFunction(
  List<ProviderConfig> providers,
  CoreLlmServices services, {
  Map<String, String> unavailable = const {},
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

  return (model, context, {cancel}) {
    final name = model.provider;
    if (unavailable[name] case final reason?) {
      return fail(LlmErrorClass.auth, reason)(model, context, cancel: cancel);
    }
    final config = configs[name];
    if (config == null) {
      return fail(LlmErrorClass.badRequest, 'unknown provider $name')(
        model,
        context,
        cancel: cancel,
      );
    }
    final chain = chains.putIfAbsent(
      name,
      () => createStreamFunction(config, services),
    );
    return chain(model, context, cancel: cancel);
  };
}
