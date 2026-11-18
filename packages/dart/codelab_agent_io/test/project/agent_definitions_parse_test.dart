import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/src/project/agent_definitions_parse.dart';
import 'package:test/test.dart';

/// Одна внутренняя функция «каталог моделей из конфига + разбор определений»
/// для `config check` и `loadAgentDefinitions` (design.md change
/// `add-settings-agents-modes`, D20.2; SETUP-8). Красный до реализации: файла
/// `agent_definitions_parse.dart` нет.
void main() {
  CoreConfig config() => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'model-1',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:8080/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
  );

  MarkdownFile file(Map<String, Object?> values) => MarkdownFile(
    path: '/h/agents/a.md',
    scope: ExtensionScope.user,
    body: 'Body',
    bodyLine: 5,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '/h/agents/a.md',
      values: values,
    ),
  );

  test('принятое определение попадает в результат', () {
    final result = parseAgentDefinitionsOf(config(), [
      file({'name': 'a', 'description': 'A'}),
    ]);

    expect([for (final d in result.agents) d.name], ['a']);
  });

  test('модель вне каталога конфига — диагностика ядра', () {
    final result = parseAgentDefinitionsOf(config(), [
      file({'name': 'a', 'description': 'A', 'model': 'nope/x'}),
    ]);

    expect(result.agents, isEmpty);
    expect(
      result.diagnostics.single.message,
      agentDefinitionModelNotInCatalogMessage,
    );
  });
}
