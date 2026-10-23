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
