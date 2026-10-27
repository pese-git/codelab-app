import 'package:codelab_client_core/codelab_client_core.dart';

import 'repl_command.dart';

/// Куда уходит введённая строка.
sealed class CommandRoute {
  const CommandRoute();
}

/// Обычный промпт: строка не начинается с `/`.
final class PromptRoute extends CommandRoute {
  const PromptRoute(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is PromptRoute && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'PromptRoute($text)';
}

/// Команда агента: уходит промптом [text] (`/<имя> аргументы`).
final class AgentPromptRoute extends CommandRoute {
  const AgentPromptRoute(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is AgentPromptRoute && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'AgentPromptRoute($text)';
}

final class ClientCommandRoute extends CommandRoute {
  const ClientCommandRoute(this.command, this.args);

  final ReplCommand command;
  final List<String> args;
}

/// Ни клиент, ни агент такой команды не знают; запроса нет.
final class UnknownCommandRoute extends CommandRoute {
  const UnknownCommandRoute(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      other is UnknownCommandRoute && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'UnknownCommandRoute($name)';
}

/// Итог Tab: [replacement] — новая строка ввода (`null` — не менять),
/// [candidates] — список для показа, если кандидатов несколько.
final class Completion {
  const Completion(this.replacement, this.candidates);

  static const none = Completion(null, []);

  final String? replacement;
  final List<CompletionCandidate> candidates;
}

/// Кандидат дополнения: [label] — что вставится (`/plan` или
/// `/agent:plan`), [fromAgent] — команда агента.
final class CompletionCandidate {
  const CompletionCandidate(
    this.label,
    this.description, {
    this.fromAgent = false,
  });

  final String label;
  final String description;
  final bool fromAgent;
}

/// Разбор `/команд` и Tab-дополнение поверх `CommandCatalog` kit.
///
/// Почему: команды клиента и агента делят одно пространство имён; правило
/// «клиентская сильнее, агентская доступна как `/agent:<имя>`» должно быть
/// одним для ввода и для подсказок (spec codelab-cli «Slash-меню и
/// клиентские команды»; U-03; design.md change `add-codelab-cli`, D7).
///
/// Как использовать: REPL вызывает [route] на каждую отправленную строку и
/// [complete] на Tab, передавая команды агента из текущего `SessionView` —
/// новое `available_commands_update` действует сразу.
final class CommandRouter {
  CommandRouter(List<ReplCommand> commands)
    : commands = List.unmodifiable(commands),
      _byName = {for (final command in commands) command.name: command};

  final List<ReplCommand> commands;
  final Map<String, ReplCommand> _byName;

  static const _agentPrefix = 'agent:';

  CommandRoute route(
    String line, {
    required List<AgentCommandView> agentCommands,
  }) {
    if (!line.startsWith('/')) {
      return PromptRoute(line);
    }
    final match = RegExp(r'^/(\S*)\s*(.*)$', dotAll: true).firstMatch(line)!;
    final name = match.group(1)!;
    final rest = match.group(2)!.trim();
    bool agentKnows(String name) => agentCommands.any((c) => c.name == name);

    if (name.startsWith(_agentPrefix)) {
      final agentName = name.substring(_agentPrefix.length);
      return agentKnows(agentName)
          ? AgentPromptRoute(rest.isEmpty ? '/$agentName' : '/$agentName $rest')
          : UnknownCommandRoute(name);
    }
    if (_byName[name] case final command?) {
      return ClientCommandRoute(
        command,
        rest.isEmpty ? const [] : rest.split(RegExp(r'\s+')),
      );
    }
    if (agentKnows(name)) {
      return AgentPromptRoute(line.trimRight());
    }
    return UnknownCommandRoute(name);
  }

  Completion complete(
    String line, {
    required List<AgentCommandView> agentCommands,
  }) {
    if (!line.startsWith('/') || line.contains(RegExp(r'\s'))) {
      return Completion.none;
    }
    final query = line.substring(1);
    final catalog = CommandCatalog(
      host: [
        for (final command in commands)
          HostCommand(
            id: command.name,
            name: command.name,
            label: '/${command.name}',
            description: command.description,
          ),
      ],
      agent: agentCommands,
    );
    final candidates = [
      for (final command in catalog.search(query))
        if (command.name.startsWith(query))
          switch (command) {
            HostCatalogCommand(:final command) => CompletionCandidate(
              '/${command.name}',
              command.description,
            ),
            AgentCatalogCommand(:final command) => CompletionCandidate(
              _byName.containsKey(command.name)
                  ? '/$_agentPrefix${command.name}'
                  : '/${command.name}',
              command.description,
              fromAgent: true,
            ),
          },
    ];
    if (candidates.isEmpty) {
      return Completion.none;
    }
    if (candidates.length == 1) {
      return Completion('${candidates.single.label} ', const []);
    }
    final prefix = _commonPrefix([for (final c in candidates) c.label]);
    return Completion(prefix.length > line.length ? prefix : null, candidates);
  }

  static String _commonPrefix(List<String> values) {
    var prefix = values.first;
    for (final value in values.skip(1)) {
      var i = 0;
      while (i < prefix.length && i < value.length && prefix[i] == value[i]) {
        i++;
      }
      prefix = prefix.substring(0, i);
    }
    return prefix;
  }
}
