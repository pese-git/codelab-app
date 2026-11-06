import 'package:codelab_setup/codelab_setup.dart';

import '../input/terminal.dart';
import 'prompt_line.dart';
import 'prompt_reader.dart';
import 'provider_wizard.dart';

/// Итог первого запуска: что делать `run.dart` дальше.
///
/// Почему enum: решений два и они взаимоисключающие — продолжить обычный
/// старт или выйти с кодом `130` (Ctrl+C или отмена мастера).
enum FirstRunResult { proceed, cancelled }

/// Первый запуск CLI: готовность провайдера и мастер (U-17, design.md change
/// `add-provider-setup-ui`, D16, решение Q12; §12.4.3).
///
/// Почему отдельная функция: `composition_root.dart` не видит
/// `codelab_setup/io.dart` (сторож), поэтому снимок, порт ключей и фабрику
/// мастера собирает `run.dart` и отдаёт сюда; ветвление живёт здесь и
/// проверяется на фейках.
///
/// Для чего: до запуска встроенного агента вычисляет `checkProviderReadiness`:
/// - `ProviderReady` и `ConfigBroken` — молча обычный старт (сломанный конфиг
///   покажет открытие агента кодом `64`);
/// - `NoProviderConfigured` — текст `CliSetup` и полный мастер ([newWizard]:
///   `entry: firstRun`, `forceDefault`, цель `user`);
/// - `ProviderKeyMissing` — мастер не запускается, конфиг не меняется: вопрос
///   про ключ и запись только секрета, либо подсказка (бэкенд только для
///   чтения, ключ из переменной).
/// Сбой [loadSnapshot] или [openKeys] — обычный старт без вывода: проблему
/// покажет открытие агента.
///
/// Как использовать: вызывать только если stdin и stdout — терминал, режим не
/// `-p` и агент встроенный (SETUP-7). Все строки — в `Terminal.output`; ввод
/// читается из `Terminal.input` и по завершении отдаётся обратно (подписка
/// отменяется, терминал восстанавливается), чтобы REPL или TUI читали тот же
/// поток (один владелец stdin на процесс, D16).
Future<FirstRunResult> runFirstRun({
  required Future<AgentConfigSnapshot> Function() loadSnapshot,
  required Future<ProviderKeys> Function() openKeys,
  required Map<String, String> environment,
  required Terminal terminal,
  required ProviderSetupFlow Function() newWizard,
}) async {
  final AgentConfigSnapshot snapshot;
  final ProviderKeys keys;
  final ProviderReadiness readiness;
  try {
    snapshot = await loadSnapshot();
    keys = await openKeys();
    readiness = await checkProviderReadiness(snapshot, keys, environment);
  } on Object {
    return FirstRunResult.proceed;
  }
  switch (readiness) {
    case ProviderReady() || ConfigBroken():
      return FirstRunResult.proceed;
    case NoProviderConfigured():
      return _setup(snapshot, terminal, newWizard);
    case final ProviderKeyMissing missing:
      return _keyMissing(missing, keys, terminal);
  }
}

Future<FirstRunResult> _setup(
  AgentConfigSnapshot snapshot,
  Terminal terminal,
  ProviderSetupFlow Function() newWizard,
) async {
  terminal.output
    ..writeln('No model provider is configured for the embedded agent.')
    ..writeln(
      'Let\'s set one up. Press Ctrl+C to quit; run "codelab provider add" '
      'later to change it.',
    );
  final result = await runProviderWizard(
    flow: newWizard(),
    terminal: terminal,
    pathOf: (target) => snapshot.layers[target.layer]?.path ?? '',
  );
  switch (result) {
    case ProviderWizardSaved(:final providerId):
      terminal.output.writeln(
        'Saved provider "$providerId". Starting the embedded agent…',
      );
      return FirstRunResult.proceed;
    case ProviderWizardCancelled():
      return FirstRunResult.cancelled;
    case ProviderWizardFailed(:final message) ||
        ProviderWizardRefused(:final message):
      terminal.output.writeln('codelab: provider setup failed: $message');
      return FirstRunResult.proceed;
  }
}

Future<FirstRunResult> _keyMissing(
  ProviderKeyMissing missing,
  ProviderKeys keys,
  Terminal terminal,
) async {
  final out = terminal.output;
  final id = missing.providerId;
  final backend = missing.backend;
  if (missing.reference.startsWith('env ')) {
    final variable = missing.reference.substring(4);
    out.writeln(
      'The key for "$id" is read from $variable, which is not set. Set it '
      'and restart codelab.',
    );
    return FirstRunResult.proceed;
  }
  final name = missing.reference.substring('secret '.length);
  if (!backend.writable) {
    out.writeln(
      'No writable secret store '
      '(${backend.unavailableReason ?? '${backend.id} is read-only'}). Set '
      '${SecretNames.envOverride(name)} or the provider\'s api_key_env '
      'variable.',
    );
    return FirstRunResult.proceed;
  }
  final reader = PromptReader(terminal);
  try {
    bool? store;
    while (store == null) {
      final answer = await reader.read(
        'Store a key for "$id" in ${backend.id}? [Y/n] ',
      );
      if (answer == null) {
        return FirstRunResult.cancelled;
      }
      store = switch (answer.trim().toLowerCase()) {
        '' || 'y' || 'yes' => true,
        'n' || 'no' => false,
        _ => null,
      };
    }
    if (!store) {
      out.writeln(
        'Starting without a key for "$id". Store it later with: codelab '
        'secret set $name',
      );
      return FirstRunResult.proceed;
    }
    String? value;
    while (value == null || value.isEmpty) {
      try {
        value = await reader.read('? API key › ', hidden: true);
      } on KeyInputRejected {
        out.writeln(keyRejectedLine);
        continue;
      }
      if (value == null) {
        return FirstRunResult.cancelled;
      }
      if (value.isEmpty) {
        out.writeln('Enter the API key.');
      }
    }
    switch (await keys.write(name, SecretValue(value))) {
      case ProviderKeyCreated() || ProviderKeyReplaced():
        out.writeln(
          'Saved the key as "$name" in ${backend.id}. Starting the embedded '
          'agent…',
        );
      case ProviderKeyRefused(:final reason):
        out.writeln('Could not store the key: $reason');
    }
    return FirstRunResult.proceed;
  } finally {
    await reader.close();
  }
}
