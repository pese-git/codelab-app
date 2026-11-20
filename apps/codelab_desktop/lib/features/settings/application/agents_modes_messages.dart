import 'package:codelab_setup/codelab_setup.dart'
    show ConfigLayer, ConfigSourceKind;

/// Когда запись вступит в силу для новых сессий (D5, «Уточнение итерации 5»).
enum AgentsApplyWhen {
  /// Сразу.
  now,

  /// После `Restart agent`.
  afterRestart,

  /// Когда агент запустится.
  whenAgentStarts,
}

/// Что записано: режим или уровень рассуждения.
enum AgentsModesSetting { mode, effort }

/// Разовое сообщение баннера страницы «Agents & modes»
/// (`agents-modes-banner`).
///
/// Почему закрытая иерархия и целые фразы: прежний `_savedBanner` склеивал
/// основу и хвост (`'.'`, `' after Restart agent.'`), что ломает перевод
/// (правило 7 D5). Теперь три вида баннера записи, а «когда применится» —
/// аргумент [AgentsApplyWhen], по которому ICU `select` выбирает целое
/// предложение. Подпись режима (`ask (edits and commands blocked by plan)`)
/// строит presentation по [blocksWriteAndExec].
///
sealed class AgentsModesMessage {
  const AgentsModesMessage();
}

/// `Saved. New sessions use <value>…` — действующее значение равно записанному.
final class AgentsSavedMessage extends AgentsModesMessage {
  const AgentsSavedMessage({
    required this.setting,
    required this.value,
    required this.when,
    this.blocksWriteAndExec = false,
  });

  final AgentsModesSetting setting;
  final String value;
  final AgentsApplyWhen when;
  final bool blocksWriteAndExec;

  // Равенство по значению: тесты сравнивают сообщение целиком.
  @override
  bool operator ==(Object other) =>
      other is AgentsSavedMessage &&
      other.setting == setting &&
      other.value == value &&
      other.when == when &&
      other.blocksWriteAndExec == blocksWriteAndExec;

  @override
  int get hashCode => Object.hash(setting, value, when, blocksWriteAndExec);

  @override
  String toString() =>
      'AgentsSavedMessage(${setting.name}, $value, ${when.name})';
}

/// `Saved to <target>; <source> overrides it: new sessions use <value>…` —
/// значение перекрыто другим слоем ([source]); `null` — по умолчанию.
final class AgentsSavedOverriddenMessage extends AgentsModesMessage {
  const AgentsSavedOverriddenMessage({
    required this.setting,
    required this.target,
    required this.source,
    required this.value,
    required this.when,
    this.blocksWriteAndExec = false,
  });

  final AgentsModesSetting setting;
  final ConfigLayer target;
  final ConfigSourceKind? source;
  final String value;
  final AgentsApplyWhen when;
  final bool blocksWriteAndExec;
}

/// `Saved to <target>; the untrusted project overrides it: …` — режим сужен
/// недоверенным проектом.
final class AgentsSavedNarrowedMessage extends AgentsModesMessage {
  const AgentsSavedNarrowedMessage({
    required this.target,
    required this.value,
    required this.when,
    this.blocksWriteAndExec = false,
  });

  final ConfigLayer target;
  final String value;
  final AgentsApplyWhen when;
  final bool blocksWriteAndExec;
}

/// `Saved to <target>.` — запись состоялась, перечитывание не удалось (D16).
final class AgentsSavedOnlyMessage extends AgentsModesMessage {
  const AgentsSavedOnlyMessage(this.target);

  final ConfigLayer target;
}

/// `Settings changed while the dialog was open; bypass was not saved.`
final class AgentsBypassStaleMessage extends AgentsModesMessage {
  const AgentsBypassStaleMessage();
}

/// `The config changed on disk, so nothing was saved. …`
final class AgentsConflictMessage extends AgentsModesMessage {
  const AgentsConflictMessage();
}

/// `Cannot save: the target config file is not available.` — слой цели не
/// прочитан, запись не начиналась.
final class AgentsTargetUnavailableMessage extends AgentsModesMessage {
  const AgentsTargetUnavailableMessage();
}

/// `The config was not saved.`
final class AgentsNotSavedMessage extends AgentsModesMessage {
  const AgentsNotSavedMessage();
}
