import 'package:freezed_annotation/freezed_annotation.dart';

import '../session/session_views.dart';

part 'command_catalog.freezed.dart';

/// Команда хоста для палитры: что хост умеет делать сам, без агента.
///
/// Почему: набор команд у каждого хоста свой (у app — `/logs`, у CLI —
/// свои), поэтому kit их не знает, а получает от хоста (design D2 change
/// `add-command-palette-agent-commands`).
///
/// Для чего: вход [CommandCatalog]. [name] — без `/`; [isAvailable] `false` —
/// заглушка «coming soon», которую вытесняет одноимённая команда агента
/// (D3). Иконки — забота хоста: он сопоставляет команду по [id].
@freezed
abstract class HostCommand with _$HostCommand {
  const factory HostCommand({
    required String id,
    required String name,
    required String label,
    required String description,
    @Default(true) bool isAvailable,
  }) = _HostCommand;
}

/// Команда каталога: команда хоста или команда агента активной сессии.
///
/// Как использовать: хост разбирает её `switch` по [HostCatalogCommand] и
/// [AgentCatalogCommand] и строит строку палитры.
@freezed
sealed class CatalogCommand with _$CatalogCommand {
  const CatalogCommand._();

  const factory CatalogCommand.host(HostCommand command) = HostCatalogCommand;

  const factory CatalogCommand.agent(AgentCommandView command) =
      AgentCatalogCommand;

  /// Имя команды без `/`, как его объявил хост или агент.
  String get name => switch (this) {
    HostCatalogCommand(:final command) => command.name,
    AgentCatalogCommand(:final command) => command.name,
  };

  /// Название для поиска: `label` у хоста, имя — у агента (своего названия
  /// у команды ACP нет).
  String get _label => switch (this) {
    HostCatalogCommand(:final command) => command.label,
    AgentCatalogCommand(:final command) => command.name,
  };

  String get _description => switch (this) {
    HostCatalogCommand(:final command) => command.description,
    AgentCatalogCommand(:final command) => command.description,
  };
}

/// Каталог команд палитры: команды хоста и агента вместе, с разрешёнными
/// конфликтами имён и нечётким поиском.
///
/// Почему: раньше список склеивал app, а отбирал виджет `codelab_ui`
/// подстрокой — логика жила в UI, а заглушка клиента `/compact` стояла рядом
/// с рабочей командой агента (change `add-command-palette-agent-commands`).
///
/// Для чего: единственное место правил палитры для app и CLI (D2–D4). Каталог
/// неизменяем; хост строит его заново, когда меняется
/// `SessionView.agentCommands` активной сессии.
///
/// Как использовать: `CommandCatalog(host: hostCommands, agent:
/// view.agentCommands)`, затем [commands] для полного списка и [search] для
/// запроса пользователя.
final class CommandCatalog {
  factory CommandCatalog({
    required List<HostCommand> host,
    required List<AgentCommandView> agent,
  }) {
    // D3: повтор имени у агента — одна команда, первая.
    final agentCommands = <String, AgentCommandView>{};
    for (final command in agent) {
      agentCommands.putIfAbsent(command.name, () => command);
    }
    return CommandCatalog._([
      for (final command in host)
        // D3: заглушку вытесняет рабочая команда агента; доступная команда
        // хоста остаётся рядом с одноимённой командой агента.
        if (command.isAvailable || !agentCommands.containsKey(command.name))
          CatalogCommand.host(command),
      for (final command in agentCommands.values) CatalogCommand.agent(command),
    ]);
  }

  CommandCatalog._(List<CatalogCommand> commands)
    : commands = List.unmodifiable(commands);

  /// Команды хоста в его порядке, затем команды агента в порядке
  /// `available_commands_update`.
  final List<CatalogCommand> commands;

  /// Команды, подходящие под [query], лучшие — первыми (D4).
  ///
  /// Пробелы по краям и ведущий `/` снимаются, регистр не учитывается;
  /// пустой запрос — все [commands]. Правила по убыванию: префикс имени,
  /// подстрока имени, подпоследовательность имени, подстрока названия или
  /// описания; внутри правила — порядок [commands]. Подпоследовательность
  /// только по имени: по описанию она находила бы почти всё.
  List<CatalogCommand> search(String query) {
    var normalized = query.trim().toLowerCase();
    if (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    if (normalized.isEmpty) {
      return commands;
    }
    final ranked = <int, List<CatalogCommand>>{};
    for (final command in commands) {
      final rank = _rank(command, normalized);
      if (rank != null) {
        (ranked[rank] ??= []).add(command);
      }
    }
    return List.unmodifiable([
      for (final rank in ranked.keys.toList()..sort()) ...ranked[rank]!,
    ]);
  }

  static int? _rank(CatalogCommand command, String query) {
    final name = command.name.toLowerCase();
    if (name.startsWith(query)) {
      return 0;
    }
    if (name.contains(query)) {
      return 1;
    }
    if (_isSubsequence(query, name)) {
      return 2;
    }
    if (command._label.toLowerCase().contains(query) ||
        command._description.toLowerCase().contains(query)) {
      return 3;
    }
    return null;
  }

  static bool _isSubsequence(String query, String text) {
    var position = 0;
    for (final unit in text.codeUnits) {
      if (position < query.length && query.codeUnitAt(position) == unit) {
        position += 1;
      }
    }
    return position == query.length;
  }
}
