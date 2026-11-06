import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';

import '../cli_args.dart';
import '../exit_codes.dart';
import '../input/terminal.dart';
import 'prompt_reader.dart';
import 'wizard_steps.dart';
import 'setup_commands.dart';

/// Значения флагов `codelab provider add`, с которыми работает автомат
/// (design.md change `add-provider-setup-ui`, D15).
final class ProviderAddFlags {
  const ProviderAddFlags({
    this.id,
    this.preset,
    this.kind,
    this.baseUrl,
    this.model,
    this.contextWindow,
    this.apiKeySecret,
    this.apiKeyEnv,
    this.apiKeyStdin = false,
    this.makeDefault = false,
    this.project = false,
    this.local = false,
    this.skipCheck = false,
    this.yes = false,
  });

  final String? id, preset, kind, baseUrl, model, contextWindow;
  final String? apiKeySecret, apiKeyEnv;
  final bool apiKeyStdin, makeDefault, project, local, skipCheck, yes;
}

/// Автомат мастера, собранный `run.dart`: [flow] (`entry: flags`), хранилище
/// секретов [backend] и путь файла слоя для сводки.
final class ProviderAddKit {
  const ProviderAddKit({
    required this.flow,
    required this.backend,
    required this.pathOf,
  });

  final ProviderSetupFlow flow;
  final String backend;
  final String Function(ConfigTarget target) pathOf;
}

const _clientFlags = '--preset, --yes or --skip-check';

/// `codelab provider add` с клиентскими флагами: те же события мастера, что
/// у человека, но из флагов ядра и без вопросов (D15, «Автомат по флагам»).
///
/// Почему автомат, а не `ProviderCommands.add`: проверка `/models` до записи
/// (SETUP-4), подтверждение `http://` (SETUP-10) и защита существующего
/// секрета (SETUP-5) живут в `ProviderSetupFlow`; флаговая форма ядра их не
/// знает и остаётся нетронутой для вызовов без клиентских флагов.
///
/// Как использовать: сначала разбор флагов и офлайн-ошибки — они бросают
/// `UsageError` (код `64`, справка `provider`, присланные значения не
/// цитируются, CFG-10); сеть — последней. Возвращает код и строки; `130` —
/// ответ `n` на сводку. [readKey] читает ключ `--api-key-stdin`;
/// [interactive] — есть терминал для вопроса `? Save? [Y/n]`.
Future<SetupCommandResult> runProviderAddByFlags({
  required ProviderAddFlags flags,
  required Future<ProviderAddKit> Function() openKit,
  required Future<String?> Function() readKey,
  required bool interactive,
  required Terminal terminal,
  required String cwd,
}) async {
  Never usage(String message) =>
      throw UsageError(message, usage: providerUsage());

  if (flags.project) {
    usage(
      '--project is not supported with $_clientFlags; use --local or the '
      'user config',
    );
  }
  if (flags.apiKeySecret != null) {
    usage(
      '--api-key-secret is not supported with $_clientFlags; use '
      '--api-key-stdin or --api-key-env',
    );
  }
  if (flags.kind == 'gemini') {
    usage(
      '--kind gemini is not supported with $_clientFlags; use the core '
      'flags only',
    );
  }
  final preset = _presetOf(flags, usage);
  final missing = [
    if (preset.isCustom && flags.baseUrl == null) '--base-url',
    if (flags.model == null) '--model',
  ];
  if (missing.isNotEmpty) {
    usage('missing required options: ${missing.join(', ')}');
  }

  final kit = await openKit();
  final flow = kit.flow;
  try {
    flow.dispatch(PresetChosen(preset.id));
    flow.dispatch(BaseUrlSubmitted(flags.baseUrl ?? preset.baseUrl!));
    switch (flow.current) {
      case EnteringBaseUrl(:final insecureHost?):
        usage(
          '--base-url sends the key unencrypted to $insecureHost; use '
          'https, or run "codelab provider add" on a terminal to confirm',
        );
      case EnteringBaseUrl(:final error?):
        usage('--base-url: $error');
      case _:
        break;
    }
    if (!flags.yes && !interactive) {
      usage('provider add needs --yes without a terminal');
    }

    // Ключ: переменная, stdin или без ключа (`--api-key-secret` отклонён).
    await _settle(flow, (s) => s is ChoosingKey && s.ready);
    final KeyChoice choice;
    if (flags.apiKeyEnv case final name?) {
      choice = UseEnvVar(name);
    } else if (flags.apiKeyStdin) {
      final key = await readKey();
      if (key == null) {
        // Ctrl+C или конец ввода в поле ключа.
        return const SetupCommandResult(exitCode: sigintExit);
      }
      choice = StoreSecret(SecretValue(key));
    } else {
      choice = const NoKey();
    }
    flow.dispatch(KeySubmitted(choice));
    final checked = await _settle(
      flow,
      (s) =>
          s is CheckFailed ||
          s is ChoosingModel ||
          (s is ChoosingKey && s.error != null),
    );
    if (checked is ChoosingKey) {
      return _failed(checked.error!);
    }
    var next = checked;
    if (next is CheckFailed) {
      final kind = next.failure.kind;
      final skippable =
          kind == ProviderCheckFailureKind.unreachable ||
          kind == ProviderCheckFailureKind.timeout;
      if (!(flags.skipCheck && next.canSkip && skippable)) {
        final origin = _origin(next.probeUrl);
        return SetupCommandResult(
          exitCode: failureExit,
          stderr: ['codelab: provider check failed: ${kind.name} ($origin)'],
        );
      }
      flow.dispatch(const SkipCheck(confirmed: true));
      next = await _settle(flow, (s) => s is ChoosingModel);
    }

    // Модель из списка ответа или ручной ввод.
    final model = flags.model!;
    final models = (next as ChoosingModel).models;
    flow.dispatch(
      models.any((m) => m.id == model)
          ? ModelChosen(model)
          : ModelEnteredManually(model),
    );
    if (flow.current is EnteringModelDetails) {
      final raw = flags.contextWindow;
      if (raw == null) {
        usage('missing required options: --context-window');
      }
      final window = int.tryParse(raw);
      if (window == null || window <= 0) {
        usage('--context-window: expected a positive whole number');
      }
      flow.dispatch(ModelDetailsSubmitted(contextWindow: window));
    }
    if (flow.current is! Reviewing) {
      return _failed('the model is not accepted');
    }
    flow.dispatch(
      ReviewEdited(
        providerId: flags.id,
        makeDefault: flags.makeDefault,
        target: flags.local ? ConfigTarget.projectLocal(cwd) : null,
      ),
    );
    final review = flow.current;
    if (review is! Reviewing || review.error != null) {
      return _failed(
        review is Reviewing ? review.error! : 'the plan is not accepted',
      );
    }
    if (!flags.yes) {
      terminal.output.writeAll([
        for (final line in reviewSummary(
          review.plan,
          backend: kit.backend,
          path: kit.pathOf(review.plan.target),
        ))
          '$line\n',
      ]);
      final reader = PromptReader(terminal);
      final String? answer;
      try {
        answer = await reader.read('? Save? [Y/n] ');
      } finally {
        await reader.close();
      }
      final yes = switch (answer?.trim().toLowerCase()) {
        '' || 'y' || 'yes' => true,
        _ => false,
      };
      if (!yes) {
        return const SetupCommandResult(exitCode: sigintExit);
      }
    }
    flow.dispatch(const ConfirmSave());
    final saved = await _settle(
      flow,
      (s) =>
          s is Done ||
          s is SaveFailed ||
          (s is Reviewing && s.error != null) ||
          // ProviderKeyAppeared и ProviderKeyNotStored возвращают на шаг
          // ключа с ошибкой (D9): ждём и его, иначе команда зависла бы.
          (s is ChoosingKey && s.error != null),
    );
    return switch (saved) {
      ChoosingKey(:final error?) => _failed(error),
      Done(:final plan) => SetupCommandResult(
        exitCode: okExit,
        stdout: [
          'Saved provider "${plan.providerId}". Models are available in '
              '/model.',
        ],
      ),
      SaveFailed(:final failure) => _failed(saveFailureText(failure)),
      Reviewing(:final error) => _failed(error!),
      _ => _failed('the provider is not saved'),
    };
  } on _WizardStopped catch (stopped) {
    return _failed(stopped.reason);
  } on TimeoutException {
    return _failed('the provider did not answer in time');
  } finally {
    await flow.dispose();
  }
}

/// Автомат остановился там, где команда ждала следующий шаг: ошибка с
/// понятной строкой, а не `StateError` в пользовательском выводе.
final class _WizardStopped implements Exception {
  const _WizardStopped(this.reason);

  final String reason;
}

ProviderPreset _presetOf(ProviderAddFlags flags, Never Function(String) usage) {
  final byId = {for (final p in ProviderPresets.all) p.id: p};
  if (flags.preset case final id?) {
    final preset = byId[id];
    if (preset == null) {
      usage(
        'unknown --preset; use openai, anthropic, openrouter, ollama, '
        'custom-openai or custom-anthropic',
      );
    }
    if (flags.kind != null && flags.kind != preset.kind) {
      usage('--kind does not match --preset');
    }
    return preset;
  }
  return switch (flags.kind) {
    'openai-compatible' => byId['custom-openai']!,
    'anthropic' => byId['custom-anthropic']!,
    null => usage('missing required options: --preset'),
    _ => usage('unknown --kind; use openai-compatible or anthropic'),
  };
}

SetupCommandResult _failed(String reason) => SetupCommandResult(
  exitCode: failureExit,
  stderr: ['codelab: provider add failed: $reason'],
);

/// `scheme://host:port` без пути, query и userinfo (CFG-10).
String _origin(Uri uri) =>
    '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

/// Состояние автомата, удовлетворяющее [accept]: текущее или следующее.
///
/// Страховка от зависания: `Cancelled`, закрытие потока и тишина дольше
/// минуты — не молчаливое ожидание, а ошибка (код `1` через `run.dart`).
Future<ProviderSetupState> _settle(
  ProviderSetupFlow flow,
  bool Function(ProviderSetupState state) accept,
) async {
  if (accept(flow.current)) {
    return flow.current;
  }
  final state = await flow.states
      .firstWhere(
        (s) => accept(s) || s is Cancelled,
        orElse: () =>
            throw const _WizardStopped('the setup stopped unexpectedly'),
      )
      .timeout(const Duration(minutes: 1));
  if (state is Cancelled) {
    throw const _WizardStopped('the setup was cancelled');
  }
  return state;
}
