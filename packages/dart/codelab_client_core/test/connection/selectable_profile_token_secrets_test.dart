// Фильтр «Use stored secret» (ревью итерации 1 change
// `add-provider-setup-ui`; решение пользователя): в списке выбора — только
// секреты `codelab/profiles/*` с именами, которые принимает kit.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  test('keeps only codelab/profiles/* names accepted by the kit, sorted', () {
    final selectable = selectableProfileTokenSecrets([
      'codelab/profiles/b/token',
      'codelab/profiles/a/token',
      'codelab/profiles/shared-ws',
      // Ключи провайдеров и секреты MCP — не токены профилей.
      'codelab/openai',
      'codelab/mcp/github/token',
      'codelab/profiles',
      'codelab/profiles/',
      // Имена, которые kit не принимает.
      'codelab/profiles/a//token',
      'codelab/profiles/a..b/token',
      'codelab/profiles/Upper/token',
      'codelab/profiles/with space',
      'Codelab/profiles/a/token',
      'codelab/profiles/trailing/',
      'other/codelab/profiles/x',
    ]);

    expect(selectable, [
      'codelab/profiles/a/token',
      'codelab/profiles/b/token',
      'codelab/profiles/shared-ws',
    ]);
  });

  test('a manual secret: reference outside the filter is still readable', () {
    // Фильтр касается только выбора в UI, не разбора ссылки.
    expect(
      ProfileTokenRef.parse('secret:codelab/openai'),
      const SecretTokenRef('codelab/openai'),
    );
  });
}
