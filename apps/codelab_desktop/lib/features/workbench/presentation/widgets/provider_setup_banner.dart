import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/app_scope.dart';
import '../../../settings/presentation/provider_wizard_dialog.dart';
import '../../application/shell_cubit.dart';

/// Текст баннера соединения, когда встроенному агенту не настроен провайдер
/// (spec agent-workbench-ui «Встроенный агент без провайдера»; design.md change
/// `add-provider-setup-ui`, D26). Тот же текст, что первая строка мастера CLI.
const noProviderMessage =
    'No model provider is configured for the embedded agent.';

/// Кнопка «Add provider» баннера соединения (ключ
/// `connection-banner-add-provider`).
///
/// Почему отдельная функция: действие нужно и экрану подключения, и баннеру
/// над лентой; оба показывают одну кнопку (D26).
///
/// Для чего: только вызывает [addProviderFromBanner]; признак «нужен
/// провайдер» уже решили мост и `ConnectionCubit` (метка [notice]), виджет
/// опасность действий не определяет (AGENTS.md §10).
Widget providerSetupAction(
  BuildContext context,
  CodeLabShellCubit cubit,
  ProviderSetupNotice notice,
) => CodeLabButton(
  key: const ValueKey('connection-banner-add-provider'),
  label: 'Add provider',
  icon: FluentIcons.add,
  emphasis: CodeLabButtonEmphasis.primary,
  onPressed: () => unawaited(
    cubit.runProviderSetup(() => addProviderFromBanner(context, cubit, notice)),
  ),
);

/// Открывает мастер провайдера для встроенного агента и после записи просит
/// `ConnectionCubit` переподключить его (D26).
///
/// Почему переподключение через метку: пока мастер открыт, окно могло
/// начать другую попытку (триггер старта, «Restart agent», переподключение kit); тогда
/// `connectAfterProviderSetup` ничего не делает и пишет
/// `provider_wizard.reconnect_skipped` (D21). Отмена мастера оставляет баннер
/// как есть.
///
/// Как использовать: вызывается нажатием «Add provider»; Cubit мастера
/// создаёт composition root (`CodeLabDependencies.openEmbeddedWizard`), а эта
/// функция его закрывает после диалога — закрытие отменяет проверку и сбрасывает
/// ключ.
Future<void> addProviderFromBanner(
  BuildContext context,
  CodeLabShellCubit cubit,
  ProviderSetupNotice notice,
) async {
  final open = codeLabDependenciesOf(context).openEmbeddedWizard;
  final wizard = await open(cwd: notice.cwd);
  if (wizard == null || !context.mounted) {
    await wizard?.close();
    return;
  }
  await showProviderWizardDialog(context, wizard);
  final saved = wizard.savedBanner != null;
  await wizard.close();
  if (saved) {
    await cubit.connectAfterProviderSetup(notice);
  }
}
