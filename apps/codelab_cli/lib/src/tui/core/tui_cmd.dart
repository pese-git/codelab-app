/// Команда ядра экрана — описание действия, которое исполняет адаптер.
///
/// Почему: команды-данные сравниваются в тестах `reduce` по значению, а
/// анализатор находит пропущенную ветку их исполнения; замыкания `Cmd`
/// `dart_tui` так не умеют (§12.2.7, §12.2.12; design.md change
/// `add-cli-tui`, D5).
///
/// Как использовать: `reduce` возвращает список команд, `TuiEffects`
/// переводит каждую в `Cmd` пакета. Новая команда — новый подкласс и ветка в
/// `TuiEffects`.
sealed class TuiCmd {
  const TuiCmd();
}

/// Отправить промпт; во время хода kit ставит его в очередь (U-15).
final class SubmitCmd extends TuiCmd {
  const SubmitCmd(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is SubmitCmd && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'SubmitCmd($text)';
}

/// Отменить идущий ход (`session/cancel`).
final class CancelTurnCmd extends TuiCmd {
  const CancelTurnCmd();

  @override
  bool operator ==(Object other) => other is CancelTurnCmd;

  @override
  int get hashCode => (CancelTurnCmd).hashCode;

  @override
  String toString() => 'CancelTurnCmd()';
}

/// Строка с `/`: клиентская команда или команда агента.
final class RunCommandCmd extends TuiCmd {
  const RunCommandCmd(this.line);

  final String line;

  @override
  bool operator ==(Object other) =>
      other is RunCommandCmd && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'RunCommandCmd($line)';
}

/// Выйти из TUI с кодом [code].
final class QuitCmd extends TuiCmd {
  const QuitCmd(this.code);

  final int code;

  @override
  bool operator ==(Object other) => other is QuitCmd && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'QuitCmd($code)';
}

/// Записать историю ввода (`$CODELAB_HOME/cli_history`, общую с REPL).
final class SaveHistoryCmd extends TuiCmd {
  const SaveHistoryCmd(this.entries);

  final List<String> entries;

  @override
  bool operator ==(Object other) =>
      other is SaveHistoryCmd &&
      other.entries.length == entries.length &&
      [
        for (var i = 0; i < entries.length; i++) other.entries[i] == entries[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'SaveHistoryCmd($entries)';
}
