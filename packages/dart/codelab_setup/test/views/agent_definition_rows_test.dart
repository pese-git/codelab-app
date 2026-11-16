import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        AgentDefinition,
        AgentScope,
        DiagnosticLevel,
        ExtensionDiagnostic,
        ModeId,
        ModelRef,
        ProviderApi;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// Строки таблицы определений агентов в мосте (client-agent-setup «Строки
/// определений агентов в мосте»; design.md change `add-settings-agents-modes`,
/// D7, Q6, Q7, Q12): порядок, статусы, замена встроенного типа, выключенные
/// субагенты и отсутствие тел файлов и имён неизвестных ключей.
///
/// Красные до задачи 2.4: `agentDefinitionRowsOf` — заглушка.
void main() {
  const home = '/h/.codelab';

  AgentDefinition builtin(String name, {List<String>? tools}) =>
      AgentDefinition(
        name: name,
        description: 'Built-in $name',
        prompt: 'BUILTIN-BODY',
        source: 'builtin:$name',
        tools: tools,
        mode: ModeId.plan,
      );

  final builtins = [
    builtin('general'),
    builtin('explore', tools: const ['read', 'ls', 'search']),
    builtin('review', tools: const ['read', 'ls', 'search', 'exec']),
    builtin('plan', tools: const ['read', 'ls', 'search']),
  ];

  AgentDefinition file(
    String name, {
    String dir = '$home/agents',
    AgentScope scope = AgentScope.both,
    List<String>? tools,
    ModelRef? model,
  }) => AgentDefinition(
    name: name,
    description: 'Agent $name',
    prompt: 'SECRET-BODY of $name',
    source: '$dir/$name.md',
    scope: scope,
    tools: tools,
    model: model,
  );

  ExtensionDiagnostic diagnostic(
    String path,
    String code, {
    DiagnosticLevel level = DiagnosticLevel.error,
    int? line,
    String message = 'fixed text',
  }) => ExtensionDiagnostic(
    path: path,
    level: level,
    code: code,
    message: message,
    line: line,
  );

  List<AgentDefinitionRowView> rows({
    List<AgentDefinition> definitions = const [],
    List<ExtensionDiagnostic> diagnostics = const [],
    bool subagentsEnabled = true,
  }) => agentDefinitionRowsOf(
    definitions: definitions,
    diagnostics: diagnostics,
    builtins: builtins,
    subagentsEnabled: subagentsEnabled,
  );

  AgentDefinitionRowView rowOf(
    List<AgentDefinitionRowView> all,
    String name, {
    String? path,
  }) => all.singleWhere((r) => r.name == name && r.path == path);

  group('порядок и встроенные строки', () {
    test('default, встроенные типы, затем файлы по имени', () {
      final all = rows(definitions: [file('zeta'), file('alpha')]);

      expect(
        [for (final r in all) r.name],
        ['default', 'general', 'explore', 'review', 'plan', 'alpha', 'zeta'],
      );
    });

    test('default: built-in, session, все инструменты, модель сессии', () {
      final row = rows().first;

      expect(row.name, 'default');
      expect(row.path, isNull);
      expect(row.availableIn, AgentRowScope.session);
      expect(row.tools, isNull);
      expect(row.model, isNull);
      expect(row.status, AgentRowStatus.available);
    });

    test('встроенные типы: subagent, инструменты из определения', () {
      final all = rows();

      final explore = rowOf(all, 'explore');
      expect(explore.availableIn, AgentRowScope.subagent);
      expect(explore.tools, ['read', 'ls', 'search']);
      expect(explore.status, AgentRowStatus.available);
      expect(rowOf(all, 'general').tools, isNull);
    });
  });

  group('файлы, прошедшие проверку', () {
    test('область, инструменты, модель и описание', () {
      final model = ModelRef(
        provider: 'p',
        id: 'm',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('http://localhost/v1'),
        contextWindow: 1000,
        maxOutputTokens: 100,
      );
      final all = rows(
        definitions: [
          file(
            'worker',
            scope: AgentScope.subagent,
            tools: const ['read'],
            model: model,
          ),
        ],
      );

      final row = rowOf(all, 'worker', path: '$home/agents/worker.md');
      expect(row.availableIn, AgentRowScope.subagent);
      expect(row.tools, ['read']);
      expect(row.model, 'p/m');
      expect(row.description, 'Agent worker');
      expect(row.status, AgentRowStatus.available);
    });
  });

  group('статусы отклонённых файлов (Q7)', () {
    test('диагностика model — Model not configured, имя без .md', () {
      final all = rows(
        diagnostics: [diagnostic('$home/agents/broken.md', 'model', line: 3)],
      );

      final row = rowOf(all, 'broken', path: '$home/agents/broken.md');
      expect(row.status, AgentRowStatus.modelNotConfigured);
      expect(row.availableIn, isNull);
    });

    test('другая error — Error со строкой и фиксированным текстом', () {
      final all = rows(
        diagnostics: [
          diagnostic(
            '$home/agents/reviewer.md',
            'unknown_key',
            line: 4,
            message: 'unknown frontmatter key; allowed: name, description',
          ),
        ],
      );

      final row = rowOf(all, 'reviewer', path: '$home/agents/reviewer.md');
      expect(row.status, AgentRowStatus.error);
      expect(row.errorLine, 4);
      expect(row.errorMessage, contains('unknown frontmatter key'));
      expect(row.errorMessage, isNot(contains('color')));
    });

    test('error без позиции — без номера строки', () {
      final all = rows(
        diagnostics: [diagnostic('$home/agents/x.md', 'not_utf8')],
      );

      expect(rowOf(all, 'x', path: '$home/agents/x.md').errorLine, isNull);
    });

    test('duplicate — Not loaded: duplicate name', () {
      final all = rows(
        diagnostics: [diagnostic('$home/agents/dup.md', 'duplicate')],
      );

      expect(
        rowOf(all, 'dup', path: '$home/agents/dup.md').status,
        AgentRowStatus.duplicate,
      );
    });

    test('shadowed пользовательского файла — Shadowed by project', () {
      final all = rows(
        diagnostics: [
          diagnostic(
            '$home/agents/same.md',
            'shadowed',
            level: DiagnosticLevel.info,
          ),
        ],
      );

      expect(
        rowOf(all, 'same', path: '$home/agents/same.md').status,
        AgentRowStatus.shadowed,
      );
    });

    test('untrusted_project (info) строк не добавляет', () {
      final all = rows(
        diagnostics: [
          diagnostic(
            '/p/.codelab/agents',
            'untrusted_project',
            level: DiagnosticLevel.info,
          ),
        ],
      );

      expect(all, hasLength(5));
    });
  });

  group('определение заменяет встроенный тип', () {
    test(
      'review.md со scope both: встроенный — Overridden, файл — Available',
      () {
        final all = rows(definitions: [file('review')]);

        final builtinRow = rowOf(all, 'review');
        expect(builtinRow.status, AgentRowStatus.overridden);
        expect(builtinRow.overriddenBy, '$home/agents/review.md');
        final fileRow = rowOf(all, 'review', path: '$home/agents/review.md');
        expect(fileRow.status, AgentRowStatus.available);
        expect(fileRow.availableIn, AgentRowScope.both);
      },
    );

    test('определение только для session встроенный тип не заменяет', () {
      final all = rows(
        definitions: [file('review', scope: AgentScope.session)],
      );

      expect(rowOf(all, 'review').status, AgentRowStatus.available);
    });
  });

  group('выключенные субагенты (Q12)', () {
    test('встроенные типы остаются со статусом Subagents off', () {
      final all = rows(subagentsEnabled: false);

      for (final name in ['general', 'explore', 'review', 'plan']) {
        expect(rowOf(all, name).status, AgentRowStatus.subagentsOff);
      }
      expect(rowOf(all, 'default').status, AgentRowStatus.available);
    });
  });

  group('что не попадает в строки', () {
    test('ни тела файла, ни имени неизвестного ключа', () {
      final all = rows(
        definitions: [file('worker')],
        diagnostics: [
          diagnostic(
            '$home/agents/reviewer.md',
            'unknown_key',
            line: 4,
            message: 'unknown frontmatter key; allowed: name, description',
          ),
        ],
      );

      final text = [
        for (final r in all)
          [
            r.name,
            r.description,
            r.path,
            r.model,
            r.overriddenBy,
            r.errorMessage,
            ...?r.tools,
          ].join('|'),
      ].join('\n');
      expect(text, isNot(contains('SECRET-BODY')));
      expect(text, isNot(contains('BUILTIN-BODY')));
      expect(text, isNot(contains('color')));
    });
  });
}
