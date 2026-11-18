// Английский эталон кита без контекста (задача 2.2 change
// `add-desktop-localization`; design.md D3, D4).
//
// Почему: `CodeLabApprovalPrompt.noSuchOption` и `CodeLabApprovalRisk.label`
// остались публичными константой и геттером, на которые ссылаются
// спецификации и тесты, а текст на экране идёт из каталога. Тест фиксирует,
// что английский каталог и эталон не разошлись: иначе тест, сверяющий текст по
// константе, проверял бы не то, что видит пользователь.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_ui/src/l10n/codelab_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = CodeLabLocalizationsEn();

  test('noSuchOption совпадает с английским каталогом', () {
    expect(CodeLabApprovalPrompt.noSuchOption, en.codeLabApprovalNoSuchOption);
  });

  test('CodeLabApprovalRisk.label совпадает с английским каталогом', () {
    expect(
      {for (final risk in CodeLabApprovalRisk.values) risk: risk.label},
      {
        CodeLabApprovalRisk.readOnly: en.codeLabRiskReadOnly,
        CodeLabApprovalRisk.unknown: en.codeLabRiskUnknown,
        CodeLabApprovalRisk.localWrite: en.codeLabRiskLocalWrite,
        CodeLabApprovalRisk.network: en.codeLabRiskNetwork,
        CodeLabApprovalRisk.shell: en.codeLabRiskShell,
        CodeLabApprovalRisk.destructive: en.codeLabRiskDestructive,
      },
    );
  });
}
