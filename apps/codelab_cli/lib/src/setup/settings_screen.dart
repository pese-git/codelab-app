import 'package:codelab_setup/codelab_setup.dart';

import 'setup_commands.dart';

/// Данные экрана `/settings`: чьи настройки, откуда читать и куда писать.
///
/// Почему отдельный тип: REPL печатает из него список, TUI открывает по нему
/// оверлей `SettingsOverlay`, и различие выносится узким членом
/// `ReplContext.showSettings` (D17, как `pick` и `showPlan`).
///
/// Для чего: [access] — результат `resolveSettingsAccess`; для
/// `RemoteReadOnly`/`NotManaged` остальные поля `null` (локальный конфиг не
/// принадлежит чужому агенту, SETUP-2). [scope] и [store] — порт записи,
/// [snapshot] — снимок на момент открытия.
final class SettingsScreen {
  const SettingsScreen({
    required this.access,
    this.scope,
    this.store,
    this.snapshot,
  });

  final SettingsAccess access;
  final SetupScope? scope;
  final AgentConfigStore? store;
  final AgentConfigSnapshot? snapshot;
}
