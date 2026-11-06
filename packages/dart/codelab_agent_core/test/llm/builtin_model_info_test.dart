import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Публичный поиск во встроенном каталоге моделей (change
/// `add-provider-setup-ui`, D7 «Окно контекста»; tasks 3.0a).
///
/// Правило поиска одно — то же, что у `StaticModelCatalog`; прежние тесты
/// каталога остаются без изменений.
void main() {
  test('точное имя', () {
    final info = builtinModelInfo('claude-sonnet-5-5');
    expect(info, isNotNull);
    expect(info!.contextWindow, isNotNull);
  });

  test('префикс до «-»: датированный id находит базовую запись', () {
    expect(
      builtinModelInfo('claude-sonnet-5-5-20260101'),
      same(builtinModelInfo('claude-sonnet-5-5')),
    );
  });

  test('часть после «/»: id шлюза находит запись', () {
    expect(
      builtinModelInfo('anthropic/claude-sonnet-5-5'),
      same(builtinModelInfo('claude-sonnet-5-5')),
    );
  });

  test('префикс без «-» или конца строки не совпадает', () {
    expect(builtinModelInfo('claude-sonnet-5-50'), isNull);
  });

  test('неизвестная модель — null', () {
    expect(builtinModelInfo('my-model'), isNull);
    expect(builtinModelInfo(''), isNull);
  });

  test('безопасное окно по умолчанию — 32000', () {
    expect(safeDefaultContextWindow, 32000);
  });
}
