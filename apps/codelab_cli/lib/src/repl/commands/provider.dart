import 'package:codelab_setup/codelab_setup.dart' show EditableSettings;

import '../../cli_args.dart';
import '../../setup/provider_wizard.dart';
import '../../setup/settings_access.dart';
import '../../setup/setup_commands.dart';
import '../repl_command.dart';

/// `/provider add|list|remove [<id>] [--local]` — провайдеры модели.
///
/// Почему: те же обработчики, что у подкоманд `codelab provider …`, нужны
/// без выхода из REPL (spec codelab-cli «Команды /provider и /settings»;
/// design.md change `add-provider-setup-ui`, D17).
///
/// Для чего: сначала решает, чьи это настройки (`settingsAccessOf` профиля
/// подключения): удалённому и стороннему агенту — строка только для чтения
/// без вызова порта (SETUP-2). `add` ведёт построчный мастер через
/// `ReplContext.runWizard` — клавиши идут из подписки REPL, а во время хода
/// или без терминала мастер не открывается (решение Q14).
final class ProviderCommand implements ReplCommand {
  const ProviderCommand();

  @override
  String get name => 'provider';

  @override
  String get usage => '/provider add|list|remove [<id>] [--local]';

  @override
  String get description => 'add, list or remove model providers';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final setup = context.setup;
    if (setup == null) {
      context.say('Provider settings are not available here.');
      return;
    }
    final sub = args.isEmpty ? '' : args.first;
    final rest = [
      for (final a in args.skip(1))
        if (!a.startsWith('--')) a,
    ];
    if (sub != 'add' && sub != 'list' && sub != 'remove') {
      throw UsageError('Usage: $usage');
    }
    final access = settingsAccessOf(
      context.profile,
      cwd: context.cwd,
      codelabHome: setup.codelabHome,
    );
    if (readOnlyLineOf(access) case final line?) {
      context.say(line);
      return;
    }
    final editable = access as EditableSettings;
    final scope = settingsScopeOf(context.profile, editable, cwd: context.cwd);
    final local = args.contains('--local');
    if (local && sub != 'list' && projectLocalTargetOf(editable) == null) {
      context.say(noProjectLocalLine);
      return;
    }
    switch (sub) {
      case 'list':
        _print(context, await setup.listProviders(scope));
      case 'remove':
        if (rest.isEmpty) {
          throw UsageError('Usage: /provider remove <id> [--local]');
        }
        _print(
          context,
          await setup.removeProvider(rest.first, scope, local: local),
        );
      case _:
        await _add(context, setup, editable, scope, rest, local: local);
    }
  }

  Future<void> _add(
    ReplContext context,
    SetupCommands setup,
    EditableSettings access,
    SetupScope scope,
    List<String> rest, {
    required bool local,
  }) async {
    if (context.turnRunning) {
      context.say(
        'Finish or cancel the current turn first (Ctrl+C), then run '
        '/provider add.',
      );
      return;
    }
    if (!context.hasTerminal) {
      context.say(
        '/provider add needs a terminal; run "codelab provider add" with '
        'flags instead.',
      );
      return;
    }
    final store = await setup.configStore(scope);
    final snapshot = await store.snapshot(cwd: scope.cwd);
    final flow = await setup.newProviderFlow(scope);
    final result = await context.runWizard(
      flow,
      providerId: rest.isEmpty ? null : rest.first,
      target: local ? projectLocalTargetOf(access) : null,
      pathOf: (target) => snapshot.layers[target.layer]?.path ?? '',
    );
    switch (result) {
      case ProviderWizardSaved(:final providerId):
        context.say(
          'Saved provider "$providerId". Models are available in /model.',
        );
      case ProviderWizardCancelled():
        context.say('Provider setup cancelled.');
      case ProviderWizardRefused(:final message):
        context.say(message);
      case ProviderWizardFailed(:final message):
        context.say('codelab: provider add failed: $message');
    }
  }

  void _print(ReplContext context, SetupCommandResult result) {
    result.stdout.forEach(context.say);
    result.stderr.forEach(context.say);
  }
}
