import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Текст диагностики «модель вне каталога» — публичная константа ядра
/// (design.md change `add-settings-agents-modes`, D7): мост `codelab_setup`
/// отличает по ней такую диагностику от прочих `invalid_value` и не копирует
/// строку. Красный до реализации: константы нет, файл не компилируется.
void main() {
  test('диагностика неизвестной модели несёт текст константы', () {
    final result = parseAgentDefinitions([
      MarkdownFile(
        path: '/h/agents/broken.md',
        scope: ExtensionScope.user,
        body: 'Body',
        bodyLine: 5,
        frontmatter: ConfigTree(
          kind: ConfigLayerKind.user,
          source: '/h/agents/broken.md',
          values: const {
            'name': 'broken',
            'description': 'Broken',
            'model': 'nope/missing',
          },
        ),
      ),
    ], models: FixedModelCatalog(const []));

    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, 'invalid_value');
    expect(diagnostic.message, agentDefinitionModelNotInCatalogMessage);
  });
}
