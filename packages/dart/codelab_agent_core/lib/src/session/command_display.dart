/// Показ развёрнутой команды в проекциях журнала (design.md change
/// `add-agent-skills`, D8, D18; agent-sessions «Поле записи command»).
///
/// Почему здесь, а не в `CommandRef`: `CommandRef` экспортируется в барель, а
/// правило «какие источники показываются тем, что набрал пользователь» нужно
/// только реплею и заголовку; публичным оно не должно становиться.
///
/// Как использовать: `record.command?.showsTyped` в `projections.dart` и
/// `summary.dart`.
library;

import '../commands/expand_command.dart';
import '../commands/slash_command.dart';

extension CommandRefDisplay on CommandRef {
  /// Известный источник (шаблон, навык) показывается как `displayText`;
  /// неизвестный из более нового журнала — текстом сообщения, потому что
  /// развёртку знает только его автор.
  bool get showsTyped =>
      source == SlashCommandSource.template.wire ||
      source == SlashCommandSource.skill.wire;
}
