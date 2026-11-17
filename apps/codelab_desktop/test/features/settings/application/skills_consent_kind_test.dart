// Вид строки согласия по элементу `skills.extra_roots` (ревью итерации 5
// change `add-app-skills-page`): одно правило для Cubit (`root_kind` события)
// и страницы (ключ и подпись строки) рядом с `skillsRefusalText`.
//
// Красный до правки: `consentKindOf` и `SkillsConsentKind` ещё нет.
// Ожидаемый API: `consentKindOf(String entry)` → `SkillsConsentKind.home`
// для элемента с `~` в начале, иначе `SkillsConsentKind.project`;
// `kind.key` — `home|project` (суффикс ключей `skills-consent-<key>`),
// `kind.rootKind` — `home|project_relative` (поле события `root_consent`).

import 'package:codelab_desktop/features/settings/application/skills_settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a home element is "home" and a project-relative one is "project"', () {
    expect(consentKindOf('~/.claude/skills'), SkillsConsentKind.home);
    expect(consentKindOf('.claude/skills'), SkillsConsentKind.project);
    expect(SkillsConsentKind.home.key, 'home');
    expect(SkillsConsentKind.project.key, 'project');
    expect(SkillsConsentKind.home.rootKind, 'home');
    expect(SkillsConsentKind.project.rootKind, 'project_relative');
  });
}
