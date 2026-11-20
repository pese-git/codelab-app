// Выбор цели возврата фокуса после ухода полосы одобрения (задача 3.2 change
// `fix-approval-focus`; design.md D5): композер, рабочее место или ничего.

import 'package:codelab_desktop/features/workbench/application/approval_focus_return.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('композер есть и включён — фокус в композер', () {
    expect(
      approvalFocusReturnOf(
        hasComposer: true,
        composerEnabled: true,
        focusTaken: false,
      ),
      ApprovalFocusReturn.composer,
    );
  });

  test('композера нет — фокус на рабочее место', () {
    expect(
      approvalFocusReturnOf(
        hasComposer: false,
        composerEnabled: true,
        focusTaken: false,
      ),
      ApprovalFocusReturn.workbench,
    );
  });

  test('композер выключен — фокус на рабочее место', () {
    expect(
      approvalFocusReturnOf(
        hasComposer: true,
        composerEnabled: false,
        focusTaken: false,
      ),
      ApprovalFocusReturn.workbench,
    );
  });

  test('фокус уже занят другим — ничего не делать, при любом композере', () {
    for (final hasComposer in const [true, false]) {
      for (final enabled in const [true, false]) {
        expect(
          approvalFocusReturnOf(
            hasComposer: hasComposer,
            composerEnabled: enabled,
            focusTaken: true,
          ),
          ApprovalFocusReturn.none,
          reason: 'composer=$hasComposer enabled=$enabled',
        );
      }
    }
  });
}
